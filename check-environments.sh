#!/usr/bin/env bash
# check-environments.sh
#
# Builds each environment the way it's actually built in real life — staging
# and production through site/build.sh (the Cloudflare Pages entry point,
# simulating CF_PAGES_BRANCH), development directly via hugo — and asserts
# each one produces the expected output (staging banner/noindex/disallow,
# production maintenance placeholder/noindex, development with none of the
# above, no RSS feed anywhere). The development build is also checked for
# internal links without a trailing slash, which cost a redirect hop and show
# up in Search Console as extra URLs.
#
# Building through build.sh means a typo'd --environment value or branch
# pattern inside it fails this check, instead of silently falling back to
# Hugo's untouched defaults and shipping wrong.
#
# USAGE:
#   ./check-environments.sh

set -euo pipefail

# Placeholders from .env.local.example are enough to build and test (as in CI),
# so a fresh worktree without .env.local still works.
ENV_FILE=.env.local; [ -f "$ENV_FILE" ] || ENV_FILE=.env.local.example
# shellcheck disable=SC1091
set -a && source "$ENV_FILE" && set +a

PASS=0
FAIL=0

check() {
  local desc="$1" cond="$2"
  if eval "$cond"; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc"
    FAIL=$((FAIL + 1))
  fi
}

build_via_buildsh() {
  rm -rf site/public
  (cd site && CF_PAGES_BRANCH="${1:-}" bash build.sh >/dev/null)
}

build_direct() {
  rm -rf site/public
  hugo build site --source site --environment "$1" --logLevel warn >/dev/null
}

# Internal page links (href="/x" or JS location.href = '/x') that end in
# neither "/" nor a file extension. Cloudflare Pages 308s them to the slashed
# URL, so each is a wasted hop and a second URL for crawlers to report.
slashless_links() {
  grep -rhoE "(href=\"|location\.href = ')/[A-Za-z0-9/_.-]*" site/public --include='*.html' \
    | sed -E 's|^[^/]*||' | grep -vE '/$|\.[A-Za-z0-9]+$' | sort -u || true
}

echo "── development"
build_direct development
check "no staging banner"   "! grep -q staging-banner site/public/index.html"
check "no noindex"          "! grep -q noindex site/public/index.html"
check "robots.txt allows"   "grep -q 'Allow: /' site/public/robots.txt"
check "llms.txt lists pages" "grep -q '^- \[' site/public/llms.txt"
check "JSON-LD present"     "grep -q 'application/ld+json' site/public/index.html"
check "no RSS feed"         "[ ! -f site/public/index.xml ]"
check "internal links end in /" "[ -z \"\$(slashless_links)\" ]"
slashless_links | sed 's/^/      slashless: /'

echo "── staging (via build.sh, CF_PAGES_BRANCH=staging)"
build_via_buildsh staging
check "staging banner present" "grep -q staging-banner site/public/index.html"
check "noindex present"        "grep -q noindex site/public/index.html"
check "robots.txt disallows"   "grep -q 'Disallow: /' site/public/robots.txt"
check "llms.txt notes preview" "grep -q 'preview environment' site/public/llms.txt"
check "JSON-LD present (must mirror prod)" "grep -q 'application/ld+json' site/public/index.html"
check "no RSS feed"            "[ ! -f site/public/index.xml ]"

echo "── production (via build.sh, no CF_PAGES_BRANCH)"
build_via_buildsh ""
check "no staging banner"                     "! grep -q staging-banner site/public/index.html"
check "noindex present (maintenance default)" "grep -q noindex site/public/index.html"
check "maintenance placeholder shown"         "grep -q 'class=\"maintenance\"' site/public/index.html"
check "robots.txt disallows (maintenance default)" "grep -q 'Disallow: /' site/public/robots.txt"
check "no JSON-LD (maintenance default)"      "! grep -q 'application/ld+json' site/public/index.html"
check "llms.txt notes unavailable (maintenance default)" "grep -q 'temporarily unavailable' site/public/llms.txt"
check "no RSS feed"                           "[ ! -f site/public/index.xml ]"

rm -rf site/public

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "Result: $FAIL check(s) failed, $PASS passed"
  exit 1
else
  echo "Result: all $PASS checks passed"
fi
