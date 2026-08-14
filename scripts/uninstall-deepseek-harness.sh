#!/bin/bash
set -euo pipefail

DRY_RUN=0
ASSUME_YES=0
KEEP_APP=0
TARGET_HOME=${HOME:-}
APP_PATH=""

usage() {
    cat <<'EOF'
Usage: uninstall-deepseek-harness.sh [--dry-run] [--yes] [--keep-app]
       [--home <absolute-home>] [--app <absolute-app-path>]

Deletes only DeepSeek Harness Desktop-owned data. It preserves ~/.dsh,
~/.agents, user workspaces, and all external symbolic-link targets.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --yes) ASSUME_YES=1; shift ;;
        --keep-app) KEEP_APP=1; shift ;;
        --home) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; TARGET_HOME=$2; shift 2 ;;
        --app) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; APP_PATH=$2; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ "$TARGET_HOME" == /* && "$TARGET_HOME" != "/" ]] || { printf 'Unsafe home: %s\n' "$TARGET_HOME" >&2; exit 2; }
[[ -d "$TARGET_HOME" ]] || { printf 'Home does not exist: %s\n' "$TARGET_HOME" >&2; exit 2; }
TARGET_HOME=$(cd "$TARGET_HOME" && pwd -P)

PATHS=(
    "$TARGET_HOME/Library/Application Support/DeepSeek Harness"
    "$TARGET_HOME/Library/Caches/com.deepseek.harness.desktop"
    "$TARGET_HOME/Library/Logs/DeepSeek Harness"
    "$TARGET_HOME/Library/Preferences/com.deepseek.harness.desktop.plist"
    "$TARGET_HOME/Library/Saved Application State/com.deepseek.harness.desktop.savedState"
    "$TARGET_HOME/Library/WebKit/com.deepseek.harness.desktop"
    "$TARGET_HOME/Library/HTTPStorages/com.deepseek.harness.desktop"
    "$TARGET_HOME/Library/Cookies/com.deepseek.harness.desktop.binarycookies"
)

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
    [[ "$APP_PATH" == /* && "$APP_PATH" == *.app && "$APP_PATH" != "/" ]] \
        || { printf 'Unsafe App path: %s\n' "$APP_PATH" >&2; exit 2; }
fi

printf 'DeepSeek Harness Desktop-owned paths:\n'
printf '  %s\n' "${PATHS[@]}"
printf '\nPreserved: %s/.dsh, %s/.agents, and all user workspaces.\n' "$TARGET_HOME" "$TARGET_HOME"
if [[ -n "$APP_PATH" && "$KEEP_APP" -eq 0 ]]; then
    printf 'App moved to Trash: %s\n' "$APP_PATH"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
    printf '\nType DELETE to continue: '
    read -r answer
    [[ "$answer" == "DELETE" ]] || { printf 'Cancelled.\n'; exit 1; }
fi

if [[ "$TARGET_HOME" == "$(cd "${HOME:-/}" 2>/dev/null && pwd -P)" ]]; then
    /usr/bin/osascript -e 'tell application id "com.deepseek.harness.desktop" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6; do
        /usr/bin/pgrep -x "DeepSeek Harness" >/dev/null 2>&1 || break
        /bin/sleep 1
    done
fi

for path in "${PATHS[@]}"; do
    [[ "$path" == "$TARGET_HOME/Library/"* ]] || { printf 'Unsafe owned path: %s\n' "$path" >&2; exit 2; }
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
    printf 'Moved App to %s\n' "$TRASH_PATH"
fi

printf 'DeepSeek Harness Desktop data removed. Preserved ~/.dsh, ~/.agents, and user workspaces.\n'
