#!/usr/bin/env bash
# dev-server.sh
#
# Starts the Hugo development server on http://localhost:1313.
#
# Ownership: a background server this script starts records its PID in
# .dev-server.lock (output in .dev-server.log). --stop only kills that PID, so
# it never kills a server someone else started. A server already answering on
# the port is left alone and reused.
#
# USAGE:
#   ./dev-server.sh        — run the server in this terminal (Ctrl-C stops it)
#   ./dev-server.sh --ci   — ensure a server is running in the background
#   ./dev-server.sh --stop — stop the background server, if this script started it

set -euo pipefail

MODE="interactive"
case "${1:-}" in
  --ci) MODE="ci" ;;
  --stop) MODE="stop" ;;
esac

PORT=1313
URL="http://localhost:${PORT}"
LOCK=".dev-server.lock"
LOG=".dev-server.log"

# Load env so it's inherited by the hugo server process
# Placeholders from .env.local.example are enough to build and test (as in CI),
# so a fresh worktree without .env.local still works.
ENV_FILE=.env.local; [ -f "$ENV_FILE" ] || ENV_FILE=.env.local.example
# shellcheck disable=SC1091
set -a && source "$ENV_FILE" && set +a

if [ -f .tool-versions ] && command -v hugo >/dev/null 2>&1; then
  # .tool-versions pins "extended_X.Y.Z" (Cloudflare's asdf preset name), but
  # `hugo version` reports a bare "X.Y.Z" - strip the prefix before comparing.
  PINNED=$(grep '^hugo ' .tool-versions | awk '{print $2}' | sed 's/^extended_//')
  INSTALLED=$(hugo version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d v)
  if [ -n "$PINNED" ] && [ "$PINNED" != "$INSTALLED" ]; then
    echo "Warning: installed Hugo is $INSTALLED, .tool-versions pins $PINNED" >&2
  fi
fi

serving() { curl -s --max-time 1 "$URL" > /dev/null 2>&1; }

if [ "$MODE" = "stop" ]; then
  if [ ! -f "$LOCK" ]; then
    echo "No server started by this script here."
    exit 0
  fi
  PID=$(cat "$LOCK")
  # Check the PID is still hugo, in case it exited and the number was reused.
  if ps -p "$PID" -o comm= 2>/dev/null | grep -q hugo; then
    kill "$PID"
    echo "Stopped dev server (pid $PID)."
  else
    echo "Dev server (pid $PID) had already exited."
  fi
  rm -f "$LOCK"
  exit 0
fi

if serving; then
  echo "A server is already running at $URL; using it."
  exit 0
fi

HUGO_CMD=(hugo server --source site --environment development --logLevel debug --port "$PORT" --disableFastRender)

if [ "$MODE" = "ci" ]; then
  nohup "${HUGO_CMD[@]}" > "$LOG" 2>&1 &
  echo $! > "$LOCK"
  echo "Waiting for server at $URL..."
  for _ in $(seq 1 30); do
    serving && echo "Server ready." && exit 0
    kill -0 "$(cat "$LOCK")" 2>/dev/null || break
    sleep 1
  done
  echo "Error: server did not start; last lines of $LOG:" >&2
  tail -n 10 "$LOG" >&2
  rm -f "$LOCK"
  exit 1
fi

echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "URL:    $URL"
echo ""
(sleep 2 && open "$URL") &
exec "${HUGO_CMD[@]}"
