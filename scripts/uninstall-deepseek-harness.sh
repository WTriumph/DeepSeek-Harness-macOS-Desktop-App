#!/bin/bash
set -euo pipefail

DRY_RUN=0
ASSUME_YES=0
KEEP_APP=0
MODE=standard
TARGET_HOME=${HOME:-}
APP_PATH=""
WORKSPACES=()

usage() {
  cat <<'EOF'
Usage: uninstall-deepseek-harness.sh [options]

Options:
  --mode app-only|standard|complete
  --workspace <absolute-path>   Add an exact workspace to complete uninstall
  --dry-run                     Print exact targets without deleting anything
  --yes                         Skip the typed confirmation
  --keep-app                    Remove selected data but keep the App
  --home <absolute-home>
  --app <absolute-app-path>
  --help

Modes / 卸载模式:
  app-only  Move only the App to Trash; preserve all data.
            仅将 App 移到废纸篓，保留全部数据。
  standard  Remove App and Desktop-owned data; preserve ~/.dsh, ~/.agents,
            and user workspaces.
            删除 App 与桌面版专属数据，保留 ~/.dsh、~/.agents 和工作区。
  complete  Also permanently remove ~/.dsh, ~/.agents, and workspaces recorded
            by Harness or supplied with --workspace.
            同时永久删除 ~/.dsh、~/.agents，以及 Harness 记录或明确指定的工作区。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      MODE=$2
      shift 2
      ;;
    --workspace)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      WORKSPACES+=("$2")
      shift 2
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --keep-app) KEEP_APP=1; shift ;;
    --home)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      TARGET_HOME=$2
      shift 2
      ;;
    --app)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      APP_PATH=$2
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in
  app-only|standard|complete) ;;
  *) printf 'Unknown uninstall mode: %s\n' "$MODE" >&2; exit 2 ;;
esac

[[ "$TARGET_HOME" == /* && "$TARGET_HOME" != "/" ]] || {
  printf 'Unsafe home: %s\n' "$TARGET_HOME" >&2
  exit 2
}
[[ -d "$TARGET_HOME" ]] || { printf 'Home does not exist: %s\n' "$TARGET_HOME" >&2; exit 2; }
TARGET_HOME=$(cd "$TARGET_HOME" && pwd -P)

if [[ -z "$APP_PATH" ]]; then
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
  if [[ -d "$SCRIPT_DIR/DeepSeek Harness.app" ]]; then
    APP_PATH="$SCRIPT_DIR/DeepSeek Harness.app"
  elif [[ -d "/Applications/DeepSeek Harness.app" ]]; then
    APP_PATH="/Applications/DeepSeek Harness.app"
  elif [[ -d "$TARGET_HOME/Applications/DeepSeek Harness.app" ]]; then
    APP_PATH="$TARGET_HOME/Applications/DeepSeek Harness.app"
  fi
fi

if [[ -n "$APP_PATH" ]]; then
  [[ "$APP_PATH" == /* && "$APP_PATH" == *.app && "$APP_PATH" != "/" ]] || {
    printf 'Unsafe App path: %s\n' "$APP_PATH" >&2
    exit 2
  }
fi

append_workspace() {
  local raw=$1
  local parent

  [[ "$raw" == /* ]] || {
    printf 'Unsafe workspace: %s\n' "$raw" >&2
    exit 2
  }
  while [[ "$raw" != "/" && "$raw" == */ ]]; do
    raw=${raw%/}
  done
  case "$raw" in
    *//*|*/./*|*/../*|*/.|*/..)
      printf 'Unsafe workspace: %s\n' "$raw" >&2
      exit 2
      ;;
  esac
  [[ -d "$raw" || -L "$raw" ]] || return 0
  [[ "$raw" != "/" && "$raw" != "$TARGET_HOME" ]] || {
    printf 'Unsafe workspace: %s\n' "$raw" >&2
    exit 2
  }
  case "$raw" in
    "$TARGET_HOME/Library"|"$TARGET_HOME/Library/"*|"$TARGET_HOME/Applications"|"$TARGET_HOME/Applications/"*|"$TARGET_HOME/.Trash"|"$TARGET_HOME/.Trash/"*|"$TARGET_HOME/.dsh"|"$TARGET_HOME/.dsh/"*|"$TARGET_HOME/.agents"|"$TARGET_HOME/.agents/"*)
      printf 'Unsafe workspace: %s\n' "$raw" >&2
      exit 2
      ;;
    "$TARGET_HOME/"*) ;;
    /Volumes/*/*) ;;
    *) printf 'Unsafe workspace: %s\n' "$raw" >&2; exit 2 ;;
  esac

  # Preserve symbolic-link targets. A final workspace symlink is removed as a
  # link, while symlinks in parent components are rejected because rm would
  # otherwise operate inside their targets.
  parent=$(/usr/bin/dirname "$raw")
  while [[ "$parent" != "/" ]]; do
    [[ ! -L "$parent" ]] || {
      printf 'Unsafe workspace parent symlink: %s\n' "$parent" >&2
      exit 2
    }
    parent=$(/usr/bin/dirname "$parent")
  done

  local existing
  if [[ ${#VALIDATED_WORKSPACES[@]} -gt 0 ]]; then
    for existing in "${VALIDATED_WORKSPACES[@]}"; do
      [[ "$existing" == "$raw" ]] && return 0
    done
  fi
  VALIDATED_WORKSPACES+=("$raw")
}

discover_workspaces() {
  [[ "$MODE" == "complete" ]] || return 0
  local embedded_node=""
  if [[ -n "$APP_PATH" && -x "$APP_PATH/Contents/Resources/runtime/node" ]]; then
    embedded_node="$APP_PATH/Contents/Resources/runtime/node"
  fi
  [[ -n "$embedded_node" ]] || return 0

  local files=()
  local file
  for file in \
    "$TARGET_HOME/Library/Application Support/DeepSeek Harness/Harness/storages/workspace.json" \
    "$TARGET_HOME/Library/Application Support/DeepSeek Harness/Harness/storages/session_projcache.json" \
    "$TARGET_HOME/.dsh/storages/workspace.json" \
    "$TARGET_HOME/.dsh/storages/session_projcache.json"
  do
    [[ -f "$file" ]] && files+=("$file")
  done
  [[ ${#files[@]} -gt 0 ]] || return 0

  while IFS= read -r -d '' file; do
    append_workspace "$file"
  done < <("$embedded_node" -e '
    const fs = require("fs");
    const paths = new Set();
    for (const file of process.argv.slice(1)) {
      const root = JSON.parse(fs.readFileSync(file, "utf8"));
      const tables = root && root.tables ? root.tables : {};
      for (const record of Object.values(tables.workspaces || {})) {
        if (record && typeof record.path === "string") paths.add(record.path);
      }
      for (const record of Object.values(tables.sessions || {})) {
        const cwd = record && record.identity && record.identity.cwd;
        if (typeof cwd === "string") paths.add(cwd);
      }
    }
    for (const path of paths) {
      if (path.startsWith("/") && path !== "/") process.stdout.write(path + "\0");
    }
  ' "${files[@]}")
}

VALIDATED_WORKSPACES=()
if [[ "$MODE" == "complete" ]]; then
  discover_workspaces
  if [[ ${#WORKSPACES[@]} -gt 0 ]]; then
    for workspace in "${WORKSPACES[@]}"; do
      append_workspace "$workspace"
    done
  fi
elif [[ ${#WORKSPACES[@]} -gt 0 ]]; then
  printf '%s\n' '--workspace is valid only with --mode complete.' >&2
  exit 2
fi

OWNED_PATHS=(
  "$TARGET_HOME/Library/Application Support/DeepSeek Harness"
  "$TARGET_HOME/Library/Caches/com.deepseek.harness.desktop"
  "$TARGET_HOME/Library/Logs/DeepSeek Harness"
  "$TARGET_HOME/Library/Preferences/com.deepseek.harness.desktop.plist"
  "$TARGET_HOME/Library/Saved Application State/com.deepseek.harness.desktop.savedState"
  "$TARGET_HOME/Library/WebKit/com.deepseek.harness.desktop"
  "$TARGET_HOME/Library/HTTPStorages/com.deepseek.harness.desktop"
  "$TARGET_HOME/Library/Cookies/com.deepseek.harness.desktop.binarycookies"
)

PATHS=()
if [[ "$MODE" == "standard" || "$MODE" == "complete" ]]; then
  PATHS+=("${OWNED_PATHS[@]}")
fi
if [[ "$MODE" == "complete" ]]; then
  PATHS+=("$TARGET_HOME/.dsh" "$TARGET_HOME/.agents")
  if [[ ${#VALIDATED_WORKSPACES[@]} -gt 0 ]]; then
    PATHS+=("${VALIDATED_WORKSPACES[@]}")
  fi
fi

printf 'Uninstall mode / 卸载模式: %s\n' "$MODE"
if [[ ${#PATHS[@]} -gt 0 ]]; then
  printf 'Permanent removal targets / 永久删除目标:\n'
  printf '  %s\n' "${PATHS[@]}"
else
  printf 'No data will be deleted / 不会删除数据。\n'
fi
if [[ -n "$APP_PATH" && "$KEEP_APP" -eq 0 ]]; then
  printf 'Move App to Trash / 将 App 移到废纸篓: %s\n' "$APP_PATH"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
  case "$MODE" in
    app-only) expected='REMOVE APP' ;;
    standard) expected='DELETE' ;;
    complete) expected='DELETE ALL' ;;
  esac
  printf '\nType %s to continue / 输入 %s 继续: ' "$expected" "$expected"
  read -r answer
  [[ "$answer" == "$expected" ]] || { printf 'Cancelled / 已取消。\n'; exit 1; }
fi

if [[ "$TARGET_HOME" == "$(cd "${HOME:-/}" 2>/dev/null && pwd -P)" ]]; then
  /usr/bin/osascript -e 'tell application id "com.deepseek.harness.desktop" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6; do
    /usr/bin/pgrep -x "DeepSeek Harness" >/dev/null 2>&1 || break
    /bin/sleep 1
  done
  if /usr/bin/pgrep -x "DeepSeek Harness" >/dev/null 2>&1; then
    printf 'DeepSeek Harness is still running; nothing was removed.\n' >&2
    exit 1
  fi
fi

for path in "${PATHS[@]}"; do
  if [[ -L "$path" || -f "$path" ]]; then
    /bin/rm -f -- "$path"
  elif [[ -d "$path" ]]; then
    /bin/rm -rf -- "$path"
  fi
done

if [[ -n "$APP_PATH" && "$KEEP_APP" -eq 0 && -e "$APP_PATH" ]]; then
  TRASH_DIR="$TARGET_HOME/.Trash"
  /bin/mkdir -p "$TRASH_DIR"
  TRASH_PATH="$TRASH_DIR/DeepSeek Harness uninstalled $(/bin/date +%Y%m%d-%H%M%S).app"
  /bin/mv -- "$APP_PATH" "$TRASH_PATH"
  printf 'Moved App to Trash / App 已移到废纸篓: %s\n' "$TRASH_PATH"
fi

printf 'Uninstall completed / 卸载完成。\n'
