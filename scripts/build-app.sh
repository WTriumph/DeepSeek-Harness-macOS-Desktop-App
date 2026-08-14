#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/config/build-versions.env"

SOURCE_ZIP="$ROOT_DIR/$HARNESS_ZIP"
BUILD_DIR="$ROOT_DIR/build/macos-arm64"
DOWNLOAD_DIR="$ROOT_DIR/build/downloads"
SOURCE_PARENT="$BUILD_DIR/source"
SOURCE_DIR="$SOURCE_PARENT/deepseek-harness-master"
NODE_ARCHIVE="$DOWNLOAD_DIR/node-v$NODE_VERSION-darwin-arm64.tar.gz"
NODE_URL="https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-arm64.tar.gz"
NODE_DIR="$BUILD_DIR/node-v$NODE_VERSION-darwin-arm64"
PNPM_DIR="$BUILD_DIR/pnpm-$PNPM_VERSION"
RUNTIME_DIR="$BUILD_DIR/runtime"
APP="$ROOT_DIR/dist/DeepSeek Harness.app"
ZIP_OUTPUT="$ROOT_DIR/dist/DeepSeek-Harness-macos-arm64.zip"
INFO_PLIST="$ROOT_DIR/desktop/Resources/Info.plist"
PATCH_SERIES="$ROOT_DIR/patches/harness/series"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  else
    DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
  fi
fi
export DEVELOPER_DIR

log() {
    printf '[build] %s\n' "$*"
}

fail() {
    printf '[build] error: %s\n' "$*" >&2
    exit 1
}

sha256() {
    /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

verify_file() {
  local path=$1
  local expected=$2
  local actual
  [[ -f "$path" ]] || fail "missing file: $path"
  actual=$(sha256 "$path")
  [[ "$actual" == "$expected" ]] || fail "SHA-256 mismatch for $path: $actual"
}

resolve_linked_directory() {
  local path=$1
  [[ -d "$path" ]] || return 1
  (cd "$path" && /bin/pwd -P)
}

safe_recreate_dir() {
    local path=$1
    local stale="${path}.stale.$$"
    [[ "$path" == "$BUILD_DIR" || "$path" == "$BUILD_DIR"/* || "$path" == "$ROOT_DIR/dist" ]] \
        || fail "unsafe build directory: $path"
    if [[ -e "$path" ]]; then
        /bin/mv -- "$path" "$stale"
    fi
    /bin/mkdir -p "$path"
    if [[ -e "$stale" ]]; then
        /bin/rm -rf -- "$stale" || log "Warning: deferred cleanup remains at $stale"
    fi
}

apply_harness_patches() {
    local patch_name
    while IFS= read -r patch_name || [[ -n "$patch_name" ]]; do
        [[ -z "$patch_name" || "$patch_name" == \#* ]] && continue
        [[ "$patch_name" != /* && "$patch_name" != *..* ]] || fail "unsafe patch entry: $patch_name"
        local patch_path="$ROOT_DIR/patches/harness/$patch_name"
        [[ -f "$patch_path" ]] || fail "missing patch: $patch_path"
        log "Applying Harness patch $patch_name"
        (cd "$SOURCE_DIR" && /usr/bin/patch -p1 --forward < "$patch_path")
    done < "$PATCH_SERIES"
}

initialize_test_git_baseline() {
    # The upstream project-doc tests intentionally inspect tracked/ignored files.
    # Release ZIPs do not carry .git, so provide deterministic local metadata.
    (cd "$SOURCE_DIR" && \
        /usr/bin/git init --quiet && \
        /usr/bin/git add -A && \
        GIT_AUTHOR_DATE='2026-08-14T00:00:00Z' \
        GIT_COMMITTER_DATE='2026-08-14T00:00:00Z' \
        /usr/bin/git -c user.name='DeepSeek Harness Desktop Builder' \
            -c user.email='desktop-builder@localhost' \
            commit --quiet --no-gpg-sign -m 'Verified release source baseline')
}

materialize_linked_package() {
  local package_relative=$1
  local package_dir="$SOURCE_DIR/$package_relative"
  local package_key=${package_relative//\//-}
  local staging_dir="$BUILD_DIR/materialized-packages/$package_key"
  local archive="$staging_dir/package.tgz"
  local link
  local resolved
  local count=0

  [[ -f "$package_dir/package.json" ]] || fail "linked package is missing: $package_relative"
  /bin/mkdir -p "$staging_dir/unpacked"
  (cd "$package_dir" && "$PNPM_DIR/bin/pnpm" pack --out "$archive" >/dev/null)
  /usr/bin/tar -xzf "$archive" -C "$staging_dir/unpacked"
  [[ -f "$staging_dir/unpacked/package/package.json" ]] \
    || fail "failed to pack linked package: $package_relative"

  while IFS= read -r -d '' link; do
    resolved=$(resolve_linked_directory "$link" 2>/dev/null) || continue
    if [[ "$resolved" == "$package_dir" ]]; then
      /bin/rm -- "$link"
      /usr/bin/ditto "$staging_dir/unpacked/package" "$link"
      count=$((count + 1))
    fi
  done < <(/usr/bin/find "$RUNTIME_DIR/dsh" -type l -print0)

  [[ "$count" -gt 0 ]] || fail "deployed runtime did not link expected package: $package_relative"
  log "Materialized $count production link(s) for $package_relative"
}

remove_linked_optional_package() {
  local package_relative=$1
  local package_dir="$SOURCE_DIR/$package_relative"
  local link
  local resolved
  local count=0

  while IFS= read -r -d '' link; do
    resolved=$(resolve_linked_directory "$link" 2>/dev/null) || continue
    if [[ "$resolved" == "$package_dir" ]]; then
      /bin/rm -- "$link"
      count=$((count + 1))
    fi
  done < <(/usr/bin/find "$RUNTIME_DIR/dsh" -type l -print0)

  [[ "$count" -gt 0 ]] || fail "deployed runtime did not link expected optional package: $package_relative"
  log "Removed $count unsupported optional production link(s) for $package_relative"
}

assert_contained_symlinks() {
  local root=$1
  local link
  local resolved

  while IFS= read -r -d '' link; do
    resolved=$(resolve_linked_directory "$link" 2>/dev/null) \
      || fail "broken symlink in packaged runtime: $link"
    case "$resolved" in
      "$root"/*) ;;
      *) fail "symlink escapes packaged runtime: $link -> $resolved" ;;
    esac
  done < <(/usr/bin/find "$root" -type l -print0)
}

generate_icon() {
    local icon_work="$BUILD_DIR/icon"
    local source_svg="$icon_work/favicon.svg"
    local icon_svg="$icon_work/AppIcon.svg"
    local rendered="$icon_work/AppIcon.svg.png"
    local iconset="$icon_work/AppIcon.iconset"
    /bin/mkdir -p "$iconset"
    /usr/bin/unzip -p "$SOURCE_ZIP" \
        deepseek-harness-master/apps/web/public/favicon.svg > "$source_svg"
    /usr/bin/sed \
        -e 's/width="50.000000" height="50.000000"/width="1024" height="1024"/' \
        -e 's|<path id="path"|<rect x="1" y="1" width="48" height="48" rx="10" fill="#4D6BFE"/><g transform="translate(5 5) scale(.8)"><path id="path"|' \
        -e 's/fill="#000"/fill="#fff"/' \
        -e 's#</svg>#</g></svg>#' \
        "$source_svg" > "$icon_svg"
    /usr/bin/qlmanage -t -s 1024 -o "$icon_work" "$icon_svg" >/dev/null 2>&1
    [[ -f "$rendered" ]] || fail "failed to render App icon"

    /usr/bin/sips -z 16 16 "$rendered" --out "$iconset/icon_16x16.png" >/dev/null
    /usr/bin/sips -z 32 32 "$rendered" --out "$iconset/icon_16x16@2x.png" >/dev/null
    /usr/bin/sips -z 32 32 "$rendered" --out "$iconset/icon_32x32.png" >/dev/null
    /usr/bin/sips -z 64 64 "$rendered" --out "$iconset/icon_32x32@2x.png" >/dev/null
    /usr/bin/sips -z 128 128 "$rendered" --out "$iconset/icon_128x128.png" >/dev/null
    /usr/bin/sips -z 256 256 "$rendered" --out "$iconset/icon_128x128@2x.png" >/dev/null
    /usr/bin/sips -z 256 256 "$rendered" --out "$iconset/icon_256x256.png" >/dev/null
    /usr/bin/sips -z 512 512 "$rendered" --out "$iconset/icon_256x256@2x.png" >/dev/null
    /usr/bin/sips -z 512 512 "$rendered" --out "$iconset/icon_512x512.png" >/dev/null
    /bin/cp "$rendered" "$iconset/icon_512x512@2x.png"
    /usr/bin/iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns"
}

[[ "$(/usr/bin/uname -m)" == "arm64" ]] || fail "this build is arm64-only"
[[ -d "$DEVELOPER_DIR" ]] || fail "Xcode not found at $DEVELOPER_DIR"
[[ -f "$PATCH_SERIES" ]] || fail "missing patch series"
/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
verify_file "$SOURCE_ZIP" "$HARNESS_ZIP_SHA256"

/bin/mkdir -p "$DOWNLOAD_DIR"
if [[ ! -f "$NODE_ARCHIVE" ]] || [[ "$(sha256 "$NODE_ARCHIVE")" != "$NODE_DARWIN_ARM64_SHA256" ]]; then
    log "Downloading Node.js $NODE_VERSION for darwin-arm64"
    if [[ -s "$NODE_ARCHIVE.part" ]]; then
        if ! /usr/bin/curl --http1.1 -fL --retry 8 --retry-all-errors --retry-delay 2 \
            --continue-at - --output "$NODE_ARCHIVE.part" "$NODE_URL"; then
            log "Server rejected resume; restarting the Node.js download"
            /bin/mv -f "$NODE_ARCHIVE.part" "$NODE_ARCHIVE.part.unresumable"
            /usr/bin/curl --http1.1 -fL --retry 8 --retry-all-errors --retry-delay 2 \
                --output "$NODE_ARCHIVE.part" "$NODE_URL"
        fi
    else
        /usr/bin/curl --http1.1 -fL --retry 8 --retry-all-errors --retry-delay 2 \
            --output "$NODE_ARCHIVE.part" "$NODE_URL"
    fi
    /bin/mv -f "$NODE_ARCHIVE.part" "$NODE_ARCHIVE"
fi
verify_file "$NODE_ARCHIVE" "$NODE_DARWIN_ARM64_SHA256"

safe_recreate_dir "$BUILD_DIR"
/usr/bin/tar -xzf "$NODE_ARCHIVE" -C "$BUILD_DIR"
[[ -x "$NODE_DIR/bin/node" ]] || fail "downloaded Node executable is missing"
[[ "$("$NODE_DIR/bin/node" --version)" == "v$NODE_VERSION" ]] || fail "unexpected Node version"

log "Installing isolated pnpm $PNPM_VERSION"
/bin/mkdir -p "$PNPM_DIR"
PATH="$NODE_DIR/bin:/usr/bin:/bin" "$NODE_DIR/bin/npm" install \
    --global --prefix "$PNPM_DIR" --no-audit --no-fund "pnpm@$PNPM_VERSION"
[[ "$(PATH="$PNPM_DIR/bin:$NODE_DIR/bin:/usr/bin:/bin" "$PNPM_DIR/bin/pnpm" --version)" == "$PNPM_VERSION" ]] \
    || fail "unexpected pnpm version"

log "Extracting verified Harness $HARNESS_VERSION source"
/bin/mkdir -p "$SOURCE_PARENT"
/usr/bin/unzip -q "$SOURCE_ZIP" -d "$SOURCE_PARENT"
[[ -f "$SOURCE_DIR/apps/cli/package.json" ]] || fail "Harness CLI package is missing"
[[ "$(cd "$SOURCE_DIR" && "$NODE_DIR/bin/node" -p "JSON.parse(require('fs').readFileSync('package.json')).version")" == "$HARNESS_VERSION" ]] \
    || fail "unexpected Harness version"
apply_harness_patches
initialize_test_git_baseline

export PATH="$PNPM_DIR/bin:$NODE_DIR/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export CI=1
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export npm_config_update_notifier=false
export NO_UPDATE_NOTIFIER=1

log "Installing locked Harness dependencies"
(cd "$SOURCE_DIR" && "$PNPM_DIR/bin/pnpm" install --frozen-lockfile)
log "Type-checking Harness"
(cd "$SOURCE_DIR" && "$PNPM_DIR/bin/pnpm" run typecheck)
if [[ "${DSH_FAST_BUILD:-0}" == "1" ]]; then
  log "Testing patched Harness production paths (fast build)"
  (cd "$SOURCE_DIR" && NODE_ENV=test "$PNPM_DIR/bin/pnpm" exec vitest run --maxWorkers=4 \
    apps/cli/tests/production-dependencies.spec.ts \
    packages/boot/app-boot/tests/profile.spec.ts \
    packages/bundle/base/tests/production-dependencies.spec.ts)
else
  log "Testing Harness"
  # The caller's shell may leak NODE_ENV=production; React's client suites
  # require a development React for act(), so pin the test environment.
  (cd "$SOURCE_DIR" && NODE_ENV=test "$PNPM_DIR/bin/pnpm" exec vitest run --maxWorkers=4)
fi
log "Building Harness"
(cd "$SOURCE_DIR" && "$PNPM_DIR/bin/pnpm" run build)

log "Deploying production-only dsh runtime"
/bin/mkdir -p "$RUNTIME_DIR"
(cd "$SOURCE_DIR" && "$PNPM_DIR/bin/pnpm" --filter @deepseek-ai/dsh --prod deploy --legacy "$RUNTIME_DIR/dsh")
materialize_linked_package "vendor/schemastery"
materialize_linked_package "vendor/cosmokit"
remove_linked_optional_package "native/landlock-run/packages/linux-x64"
remove_linked_optional_package "native/landlock-run/packages/linux-arm64"
materialize_linked_package "apps/cli"
/bin/cp "$NODE_DIR/bin/node" "$RUNTIME_DIR/node"
/bin/chmod 755 "$RUNTIME_DIR/node"
/usr/bin/find "$RUNTIME_DIR" -name .DS_Store -delete
assert_contained_symlinks "$RUNTIME_DIR"
[[ -f "$RUNTIME_DIR/dsh/lib/bin.js" ]] || fail "deployed dsh entry point is missing"
log "Smoke-testing the isolated production runtime"
/bin/bash "$ROOT_DIR/scripts/smoke-test-runtime.sh" "$RUNTIME_DIR"

log "Testing and building the native desktop shell"
(cd "$ROOT_DIR" && /usr/bin/xcrun swift test --jobs 4)
(cd "$ROOT_DIR" && /usr/bin/xcrun swift build -c release --arch arm64)
SWIFT_BIN_DIR=$(cd "$ROOT_DIR" && /usr/bin/xcrun swift build -c release --arch arm64 --show-bin-path)

safe_recreate_dir "$ROOT_DIR/dist"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/runtime" "$APP/Contents/Resources/Licenses"
/bin/cp "$INFO_PLIST" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$DESKTOP_BUILD" "$APP/Contents/Info.plist"
/bin/cp "$SWIFT_BIN_DIR/DeepSeekHarnessDesktop" "$APP/Contents/MacOS/DeepSeek Harness"
/bin/cp "$SWIFT_BIN_DIR/DeepSeekHarnessUninstaller" "$APP/Contents/MacOS/DeepSeekHarnessUninstaller"
/bin/chmod 755 "$APP/Contents/MacOS/DeepSeek Harness" "$APP/Contents/MacOS/DeepSeekHarnessUninstaller"
/usr/bin/ditto "$RUNTIME_DIR" "$APP/Contents/Resources/runtime"
/usr/bin/unzip -p "$SOURCE_ZIP" deepseek-harness-master/LICENSE > "$APP/Contents/Resources/Licenses/Harness-LICENSE.txt"
/bin/cp "$NODE_DIR/LICENSE" "$APP/Contents/Resources/Licenses/Node.js-LICENSE.txt"
/bin/cp "$ROOT_DIR/desktop/Resources/THIRD-PARTY-NOTICES.txt" "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"
generate_icon

/usr/bin/find "$APP" -name .DS_Store -delete
/usr/bin/xattr -cr "$APP"
assert_contained_symlinks "$APP"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
[[ "$(/usr/bin/lipo -archs "$APP/Contents/MacOS/DeepSeek Harness")" == "arm64" ]] || fail "desktop binary is not arm64"
[[ "$(/usr/bin/lipo -archs "$APP/Contents/Resources/runtime/node")" == "arm64" ]] || fail "embedded Node is not arm64"
[[ ! -e "$APP/Contents/Resources/runtime/npm" && ! -e "$APP/Contents/Resources/runtime/pnpm" ]] \
    || fail "build tools leaked into the runtime root"

log "Creating distributable ZIP"
(cd "$ROOT_DIR/dist" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "DeepSeek Harness.app" "$(basename "$ZIP_OUTPUT")")
verify_file "$SOURCE_ZIP" "$HARNESS_ZIP_SHA256"
log "Created $APP"
log "Created $ZIP_OUTPUT"
