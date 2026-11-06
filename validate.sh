#!/usr/bin/env bash
# validate.sh
#
# Runs the full local validation suite: build, markdown lint, and accessibility.
# Starts the dev server if it isn't already running, and stops it afterwards.
#
# USAGE:
#   ./validate.sh

set -euo pipefail

PASS=0
FAIL=0

step() {
  local name="$1"
  shift
  echo ""
  echo "── $name"
  if "$@"; then
    echo "   ✓ passed"
    PASS=$((PASS + 1))
  else
    echo "   ✗ failed"
    FAIL=$((FAIL + 1))
  fi
}

echo "Validating site..."

# Placeholders from .env.local.example are enough to build and test (as in CI),
# so a fresh worktree without .env.local still works.
ENV_FILE=.env.local; [ -f "$ENV_FILE" ] || ENV_FILE=.env.local.example
# shellcheck disable=SC1091
set -a && source "$ENV_FILE" && set +a

step "Build"         hugo build site --source site --environment development --logLevel debug
step "Environments"  ./check-environments.sh
step "Markdown lint" npm run lint:md
step "CSS lint"      npm run lint:css

./dev-server.sh --ci
STARTED_SERVER=false
[ -f .dev-server.lock ] && STARTED_SERVER=true

step "Accessibility" npm run a11y

if $STARTED_SERVER; then
  ./dev-server.sh --stop
fi

echo ""
echo "────────────────────────────────"
if [ "$FAIL" -gt 0 ]; then
  echo "Result: $FAIL step(s) failed, $PASS passed"
  exit 1
else
  echo "Result: all $PASS steps passed"
fi
