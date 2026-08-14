#!/bin/bash
set -euo pipefail

RUNTIME_DIR=${1:?usage: smoke-test-runtime.sh RUNTIME_DIR}
NODE="$RUNTIME_DIR/node"
DSH="$RUNTIME_DIR/dsh/lib/bin.js"

[[ -x "$NODE" ]] || { echo "runtime smoke: missing Node executable" >&2; exit 1; }
[[ -f "$DSH" ]] || { echo "runtime smoke: missing dsh entry point" >&2; exit 1; }

SMOKE_ROOT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/deepseek-harness-runtime.XXXXXX")
SMOKE_HOME="$SMOKE_ROOT/home"
SMOKE_WORKSPACE="$SMOKE_ROOT/workspace"
SMOKE_LOG="$SMOKE_ROOT/dsh.log"
/bin/mkdir -p "$SMOKE_HOME/.agents" "$SMOKE_HOME/Harness" "$SMOKE_WORKSPACE"

child_pid=''
cleanup() {
  if [[ -n "$child_pid" ]] && /bin/kill -0 "$child_pid" 2>/dev/null; then
    /bin/kill -TERM "$child_pid" 2>/dev/null || true
    /bin/sleep 1
    /bin/kill -KILL "$child_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

(
  cd "$SMOKE_WORKSPACE"
  exec /usr/bin/env -i \
    HOME="$SMOKE_HOME" \
    DSH_HOME="$SMOKE_HOME/Harness" \
    DSH_AGENTS_HOME="$SMOKE_HOME/.agents" \
    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8" \
    "$NODE" "$DSH" web --host 127.0.0.1 --port 0
) >"$SMOKE_LOG" 2>&1 &
child_pid=$!

base_url=''
for _ in {1..120}; do
  if ! /bin/kill -0 "$child_pid" 2>/dev/null; then
    echo "runtime smoke: dsh exited before readiness" >&2
    /usr/bin/tail -100 "$SMOKE_LOG" >&2
    exit 1
  fi
  base_url=$(/usr/bin/sed -nE 's|^.*dsh web: (http://127\.0\.0\.1:[0-9]+).*$|\1|p' "$SMOKE_LOG" | /usr/bin/tail -1)
  [[ -n "$base_url" ]] && break
  /bin/sleep 0.25
done

if [[ ! "$base_url" =~ ^http://127\.0\.0\.1:([0-9]{1,5})$ ]] \
  || (( BASH_REMATCH[1] < 1 || BASH_REMATCH[1] > 65535 )); then
  echo "runtime smoke: no valid loopback readiness URL" >&2
  /usr/bin/tail -100 "$SMOKE_LOG" >&2
  exit 1
fi

homepage="$SMOKE_ROOT/index.html"
/usr/bin/curl --noproxy '*' --fail --silent --show-error "$base_url/" -o "$homepage"
/usr/bin/grep -Fq 'window.__DSH_BOOT__' "$homepage" \
  || { echo "runtime smoke: boot manifest missing" >&2; exit 1; }

api_response=$(/usr/bin/curl --noproxy '*' --fail --silent --show-error \
  -H 'content-type: application/json' \
  --data '{"id":"desktop-runtime-smoke","method":"settings.describe","payload":{}}' \
  "$base_url/api/settings.describe")
[[ "$api_response" == *'"result"'* ]] \
  || { echo "runtime smoke: API response malformed" >&2; exit 1; }

"$NODE" -e '
const url = process.argv[1].replace(/^http:/, "ws:") + "/api/events.mux";
const timer = setTimeout(() => { console.error("WebSocket timeout"); process.exit(1) }, 5000);
const socket = new WebSocket(url);
socket.addEventListener("open", () => { clearTimeout(timer); socket.close(); });
socket.addEventListener("close", () => process.exit(0));
socket.addEventListener("error", (event) => { console.error(event.message || "WebSocket error"); process.exit(1) });
' "$base_url"

/bin/kill -TERM "$child_pid"
for _ in {1..24}; do
  /bin/kill -0 "$child_pid" 2>/dev/null || break
  /bin/sleep 0.25
done
if /bin/kill -0 "$child_pid" 2>/dev/null; then
  echo "runtime smoke: dsh ignored SIGTERM" >&2
  /bin/kill -KILL "$child_pid" 2>/dev/null || true
  exit 1
fi
wait "$child_pid"
child_pid=''
trap - EXIT INT TERM

echo "runtime smoke: homepage, API, WebSocket, and SIGTERM passed at $base_url"
