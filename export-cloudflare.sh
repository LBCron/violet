#!/usr/bin/env bash
# export-cloudflare.sh
#
# Exports the live Cloudflare configuration for ontariomenopauseclinic.ca into
# docs/current-state/cloudflare-export/ so it is committed to the repo.
#
# WHY THIS EXISTS
#   Cloudflare holds configuration that is not reproducible from this repo: DNS
#   records, the www-to-apex redirect rule, zone settings, and the Pages project
#   (custom domains, build config). Losing the account, or rebuilding the site
#   from scratch, means recreating all of it by hand. This export is the record
#   to rebuild from. The configuration is not infrastructure as code, so this
#   script is the continuity plan.
#
#   A previous version of this script was never committed and is gone. That is
#   the reason it now lives here rather than in someone's home directory.
#
# WHAT IT DOES NOT CAPTURE
#   Secret values. Pages environment variable names are exported, but values
#   only for the allowlist in the pages step below; the rest live in 1Password,
#   with placeholders in .env.local.example. The API token itself is never
#   written anywhere.
#
# USAGE
#   ./export-cloudflare.sh   # token from 1Password or a prompt - see cloudflare-token.sh
#
#   Then review and commit the diff. `git status` after a run IS the drift
#   check: if the export changes, Cloudflare changed since the last commit.
#
# TOKEN
#   A READ-ONLY token from the "Read all resources" template. Creating or
#   rotating it: docs/runbooks/cloudflare-read-token.md.

set -uo pipefail

ZONE_ID="${CF_ZONE_ID:-df4711b6c10cf3043898e21d6c23f007}"
API=https://api.cloudflare.com/client/v4
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$REPO_ROOT/docs/current-state/cloudflare-export"

command -v jq >/dev/null || { echo "ERROR: jq is required (brew install jq)" >&2; exit 1; }

. "$REPO_ROOT/cloudflare-token.sh"

auth=(-H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json")
FAILED=0

get() { # get <api-path> <outfile> <label>
  local code
  code=$(curl -s -o "$OUT/$2" -w '%{http_code}' "${auth[@]}" "$API/$1")
  if [[ "$code" == "200" ]] && jq -e '.success == true' "$OUT/$2" >/dev/null 2>&1; then
    # Strip response envelope noise that churns between runs for no reason.
    jq 'del(.result_info, .messages)' "$OUT/$2" > "$OUT/$2.tmp" && mv "$OUT/$2.tmp" "$OUT/$2"
    printf '  ok    %s\n' "$3"
  else
    printf '  FAIL  %-26s (http %s) %s\n' "$3" "$code" \
      "$(jq -r '[.errors[]?.message] | join("; ")' "$OUT/$2" 2>/dev/null)" >&2
    rm -f "$OUT/$2"
    FAILED=1
  fi
}

mkdir -p "$OUT"

echo "== token"
curl -s "${auth[@]}" "$API/user/tokens/verify" \
  | jq -r 'if .success then "  valid" else "  INVALID: " + ([.errors[]?.message]|join("; ")) end'

echo "== zone"
get "zones/$ZONE_ID"                          zone.json     "zone"
get "zones/$ZONE_ID/dns_records?per_page=200" dns.json      "dns records"
get "zones/$ZONE_ID/settings"                 settings.json "zone settings"
# Cloudflare Fonts is missing from the bulk list above; it only answers on its own path.
get "zones/$ZONE_ID/settings/fonts"           settings_fonts.json "zone setting: fonts"
# Same gap for the encryption-mode page: automatic SSL/TLS, automatic key exchange to the origin,
# and its compliance requirements (answers with id "origin_tls_cmpl", not the path name).
# Not cache/origin_post_quantum_encryption: Cloudflare documents that one as a no-op.
get "zones/$ZONE_ID/settings/ssl_automatic_mode"         settings_ssl_automatic_mode.json "zone setting: ssl_automatic_mode"
get "zones/$ZONE_ID/settings/auto_origin_tls_kex"        settings_auto_origin_tls_kex.json "zone setting: auto_origin_tls_kex"
get "zones/$ZONE_ID/settings/origin_tls_compliance_modes" settings_origin_tls_compliance_modes.json "zone setting: origin_tls_compliance_modes"
# DNSSEC is neither a DNS record nor a zone setting; it only answers on its own path.
get "zones/$ZONE_ID/dnssec"                   dnssec.json   "dnssec"
# More settings the bulk list omits, found by ./cloudflare-sweep.sh on 2026-10-19.
# Rerun the sweep to find the next gap rather than guessing at defaults.
# cloudflare-sweep.sh reads this loop's list, so keep it one `for s in` loop.
for s in aegis automatic_platform_optimization binary_ast csam_scanner_third_party h2_prioritization \
         image_resizing nel origin_h2_max_streams origin_max_http_version rum speed_brain \
         transformations_allowed_origins transformations_c2pa transformations_config; do
  get "zones/$ZONE_ID/settings/$s" "settings_$s.json" "zone setting: $s"
done
get "zones/$ZONE_ID/dns_settings"             dns_settings.json    "dns settings (nameservers, SOA, CNAME flattening)"
get "zones/$ZONE_ID/bot_management"           bot_management.json  "bot management (AI crawlers, managed robots.txt)"
get "zones/$ZONE_ID/managed_headers"          managed_headers.json "managed transforms"
get "zones/$ZONE_ID/url_normalization"        url_normalization.json "url normalization"
get "zones/$ZONE_ID/ssl/universal/settings"   ssl_universal.json   "universal ssl"
get "zones/$ZONE_ID/ct/alerting"              ct_alerting.json     "certificate transparency alerting"
get "zones/$ZONE_ID/hold"                     zone_hold.json       "zone hold"
get "zones/$ZONE_ID/argo/tiered_caching"      tiered_caching.json  "tiered caching"
get "zones/$ZONE_ID/cache/tiered_cache_smart_topology_enable" tiered_cache_smart_topology.json "tiered cache topology"

echo "== rulesets"
get "zones/$ZONE_ID/rulesets" rulesets.json "ruleset index"
if [[ -f "$OUT/rulesets.json" ]]; then
  # The index lists rulesets but not their rules; fetch each one that has any.
  rm -f "$OUT/ruleset_"*.json
  for rs in $(jq -r '.result[]? | select(.kind=="zone") | .id' "$OUT/rulesets.json"); do
    phase=$(jq -r --arg id "$rs" '.result[] | select(.id==$id) | .phase' "$OUT/rulesets.json")
    get "zones/$ZONE_ID/rulesets/$rs" "ruleset_${phase}.json" "rules: $phase"
  done
fi

# Optional endpoints: features that may or may not be in use. A 403/404 here is
# information ("not enabled / not permitted"), not an error - so these are
# probed rather than required. This exists because nobody has been tracking what
# was turned on in the dashboard; the point is to discover it, not assume it.
probe() { # probe <api-path> <outfile> <label>
  local code
  code=$(curl -s -o "$OUT/$2" -w '%{http_code}' "${auth[@]}" "$API/$1")
  if [[ "$code" == "200" ]] && jq -e '.success == true' "$OUT/$2" >/dev/null 2>&1; then
    local n in_use
    n=$(jq -r 'if (.result|type)=="array" then (.result|length|tostring) else "present" end' "$OUT/$2")
    # A 200 only means the endpoint answered. Several features respond happily
    # while switched off (email routing returns enabled:false when unconfigured,
    # and ships a disabled catch-all rule), so "responded" is not "in use" -
    # reporting it as found sends you chasing config that does not exist.
    in_use=$(jq -r '
      def live: if type=="object" and has("enabled") then .enabled else true end;
      if (.result|type)=="array"
        then ((.result | map(select(live)) | length) > 0)
        else (.result | live) end' "$OUT/$2")
    if [[ "$n" == "0" || "$in_use" != "true" ]]; then
      # Keep the file when the endpoint answered but the feature is off: knowing
      # it is off is itself worth recording. Just do not list it as in use.
      if [[ "$n" == "0" ]]; then
        rm -f "$OUT/$2"; printf '  none  %s\n' "$3"
      else
        jq 'del(.result_info, .messages)' "$OUT/$2" > "$OUT/$2.tmp" && mv "$OUT/$2.tmp" "$OUT/$2"
        printf '  off   %-30s (present but disabled)\n' "$3"
      fi
    else
      jq 'del(.result_info, .messages)' "$OUT/$2" > "$OUT/$2.tmp" && mv "$OUT/$2.tmp" "$OUT/$2"
      printf '  FOUND %-30s (%s)\n' "$3" "$n"
      DISCOVERED="${DISCOVERED}${3}\n"
    fi
  else
    rm -f "$OUT/$2"
    printf '  n/a   %-30s (http %s)\n' "$3" "$code"
  fi
}
DISCOVERED=""

echo "== mail (non-DNS: routing. SPF/DKIM/DMARC are DNS and are in dns.json)"
probe "zones/$ZONE_ID/email/routing"        email_routing.json       "email routing settings"
probe "zones/$ZONE_ID/email/routing/rules"  email_routing_rules.json "email routing rules"
probe "zones/$ZONE_ID/email/routing/dns"    email_routing_dns.json   "email routing required DNS"

echo "== other zone features (discovery)"
probe "zones/$ZONE_ID/pagerules"            pagerules.json           "page rules (legacy)"
probe "zones/$ZONE_ID/workers/routes"       workers_routes.json      "workers routes"
probe "zones/$ZONE_ID/firewall/access_rules/rules" firewall_access.json "firewall access rules"
probe "zones/$ZONE_ID/ssl/certificate_packs" cert_packs.json         "certificate packs"
probe "zones/$ZONE_ID/custom_certificates"  custom_certs.json        "custom certificates"

# Fields Cloudflare rewrites on its own schedule: Universal SSL renews the cert
# every ~90 days, and the managed DDoS ruleset is versioned by Cloudflare. Left
# in, they make every run show a diff, which defeats `git status` as the drift
# check. Hosts, status and settings stay, so a real change still shows up.
strip() { # strip <outfile> <jq-filter>
  [[ -f "$OUT/$1" ]] || return 0
  jq "$2" "$OUT/$1" > "$OUT/$1.tmp" && mv "$OUT/$1.tmp" "$OUT/$1"
}
strip rulesets.json   '(.result[]? | select(.kind=="managed")) |= del(.version, .last_updated)'
strip cert_packs.json '.result[]? |= (del(.primary_certificate) | .certificates[]? |= del(.id, .uploaded_on, .modified_on, .expires_on))'
# The account name defaults to the owner's email address. The id is kept: the
# pages step reads it.
strip zone.json       'del(.result.account.name)'
# CT alerting lists who receives the emails; record how many, not who.
strip ct_alerting.json '.result |= ((.recipients = ((.emails // []) | length)) | del(.emails))'

echo "== pages"
ACCOUNT_ID=$(jq -r '.result.account.id // empty' "$OUT/zone.json" 2>/dev/null)
if [[ -n "$ACCOUNT_ID" ]]; then
  raw=$(mktemp)
  code=$(curl -s -o "$raw" -w '%{http_code}' "${auth[@]}" "$API/accounts/$ACCOUNT_ID/pages/projects")
  if [[ "$code" == "200" ]] && jq -e '.success == true' "$raw" >/dev/null 2>&1; then
    # Redact before anything touches the working tree: the raw response contains
    # env var VALUES (booking URL, contact addresses). Only allowlisted values are
    # kept; any other var, including new ones, records as "(redacted)".
    # shortcut: hand-kept allowlist; replace if env vars ever move to infrastructure as code.
    jq '{result: [.result[] | {
          name, subdomain, production_branch, created_on,
          build_config,
          domains,
          # The Git connection, including which branches build public previews.
          source,
          deployment_configs: (.deployment_configs | with_entries(.value |= {
            compatibility_date,
            compatibility_flags,
            build_image_major_version,
            env_vars: ((.env_vars // {}) | with_entries(.value =
              if (.key | IN("HUGO_VERSION", "HUGO_PARAMS_MAINTENANCEMODE")) then .value.value else "(redacted)" end))
          }))
        }]}' "$raw" > "$OUT/pages_project.json"
    printf '  ok    pages project (env var values redacted)\n'
  else
    printf '  FAIL  %-26s (http %s) %s\n' "pages project" "$code" \
      "$(jq -r '[.errors[]?.message] | join("; ")' "$raw" 2>/dev/null)" >&2
    printf '        most likely cause: token lacks Account -> Cloudflare Pages -> Read\n' >&2
    FAILED=1
  fi
  rm -f "$raw"

  echo "== account features (discovery)"
  probe "accounts/$ACCOUNT_ID/email/routing/addresses" email_dest_addresses.json "email destination addresses"
  probe "accounts/$ACCOUNT_ID/rules/lists"             rules_lists.json          "bulk redirect / IP lists"
  probe "accounts/$ACCOUNT_ID/rum/site_info/list"      web_analytics.json        "web analytics sites"
  probe "accounts/$ACCOUNT_ID/challenges/widgets"      turnstile.json            "turnstile widgets"
  probe "accounts/$ACCOUNT_ID/access/apps"             access_apps.json          "access applications"
  probe "accounts/$ACCOUNT_ID/access/organizations"    access_organization.json  "access organization"
  probe "accounts/$ACCOUNT_ID/alerting/v3/policies"    alerting_policies.json    "notification policies"
  # Destinations can name people's addresses; which alerts exist is the config.
  strip alerting_policies.json '.result[]? |= del(.mechanisms)'

  echo "== account"
  # The domain is registered through Cloudflare: renewal, lock and expiry live here.
  # registrations, not registrar/domains, which also carries contact details.
  get "accounts/$ACCOUNT_ID/registrar/registrations" registrar.json "registrar (renewal, lock, expiry)"
  # Only the security settings (2FA enforcement and the like). Not the account
  # name, which defaults to the owner's email address; members and billing are
  # personal data too, and are deliberately not exported.
  get "accounts/$ACCOUNT_ID"                          account.json  "account settings"
  strip account.json '{result: {settings: (.result.settings | del(.abuse_contact_email))}, success, errors}'
else
  echo "  SKIP  pages + account features - no account id in zone.json" >&2
  FAILED=1
fi

# ---------------------------------------------------------------- summary
# Facts are generated here so they cannot drift; the reasoning behind them
# stays hand-written in docs/current-state/cloudflare-config.md.
if [[ -f "$OUT/dns.json" ]]; then
  {
    echo "# Cloudflare export"
    echo
    echo "Generated by \`export-cloudflare.sh\`. **Do not hand-edit** - rerun the script."
    echo "Narrative and rationale live in [cloudflare-config.md](../cloudflare-config.md)."
    echo
    echo "Exported: $(date -u +%Y-%m-%d)"
    echo
    echo "## DNS records"
    echo
    echo "| Type | Name | Content | Proxied | TTL |"
    echo "|------|------|---------|---------|-----|"
    jq -r '.result | sort_by(.type, .name)[] |
      "| \(.type) | `\(.name)` | `\(.content)` | \(if .proxied then "**Yes**" else "No" end) | \(if .ttl == 1 then "Auto" else (.ttl|tostring) end) |"' \
      "$OUT/dns.json"
    echo

    if [[ -f "$OUT/dnssec.json" ]]; then
      echo "## DNSSEC"
      echo
      jq -r '.result | "- Status: `\(.status)`\n- DS record (published at the registrar): `\(.ds // "none")`"' "$OUT/dnssec.json"
      echo
    fi

    if [[ -f "$OUT/registrar.json" ]]; then
      echo "## Registrar (Cloudflare Registrar)"
      echo
      jq -r '.result[]? | "- `\(.domain_name)`: status `\(.status)`, expires `\(.expires_at[:10])`, auto-renew `\(.auto_renew)`, locked `\(.locked)`"' "$OUT/registrar.json"
      echo
    fi

    if [[ -f "$OUT/bot_management.json" ]]; then
      echo "## Bots and AI crawlers"
      echo
      jq -r '.result | to_entries[] | select(.key | IN("fight_mode","ai_bots_protection","crawler_protection","ai_training","ai_search","ai_user","is_robots_txt_managed")) | "- `\(.key)`: `\(.value)`"' "$OUT/bot_management.json"
      echo
    fi

    if [[ -f "$OUT/pages_project.json" ]]; then
      echo "## Pages custom domains"
      echo
      jq -r '.result[0].domains[]? | "- `\(.)`"' "$OUT/pages_project.json"
      echo
      echo "## Pages project"
      echo
      jq -r '.result[0] | "- Project: `\(.name)`\n- Subdomain: `\(.subdomain)`\n- Production branch: `\(.production_branch)`\n- Preview deployments: `\(.source.config.preview_deployment_setting // "?")` (include: `\(.source.config.preview_branch_includes // [] | join(", "))`, exclude: `\(.source.config.preview_branch_excludes // [] | join(", "))`)"' "$OUT/pages_project.json"
      echo
      echo "Environment variables (redacted values in 1Password / \`.env.local.example\`):"
      echo
      jq -r '.result[0].deployment_configs | to_entries[] | "- **\(.key)**: " + ((.value.env_vars // {}) | to_entries | map("`" + .key + (if .value == "(redacted)" then "" else "=" + .value end) + "`") | join(", "))' "$OUT/pages_project.json"
      echo
    fi

    if [[ -f "$OUT/email_routing.json" ]]; then
      echo "## Email routing"
      echo
      jq -r '.result | "- enabled: `\(.enabled)`  status: `\(.status // "?")`  name: `\(.name // "?")`"' "$OUT/email_routing.json"
      if [[ -f "$OUT/email_routing_rules.json" ]]; then
        jq -r '.result[]? | "- rule: `\(.name // .tag)` -> " + ((.actions // []) | map((.value // [])|join(",")) | join("; ")) + " (enabled: `\(.enabled)`)"' "$OUT/email_routing_rules.json"
      fi
      echo
    fi

    if [[ -n "$DISCOVERED" ]]; then
      echo "## Other features found"
      echo
      printf '%b' "$DISCOVERED" | sed 's/^/- /' 
      echo
      echo "Raw responses are alongside this file. Anything listed here is in use"
      echo "and must be recreated when rebuilding."
      echo
    fi

    if [[ -f "$OUT/ruleset_http_request_dynamic_redirect.json" ]]; then
      echo "## Redirect rules"
      echo
      jq -r '.result.rules[]? |
        "- **\(.description // "(unnamed)")** — `\(.expression)`\n  - action: `\(.action)`, status: `\(.action_parameters.from_value.status_code // "?")`, preserve query: `\(.action_parameters.from_value.preserve_query_string // false)`\n  - target: `\(.action_parameters.from_value.target_url.expression // .action_parameters.from_value.target_url.value // "?")`\n  - enabled: `\(.enabled)`"' \
        "$OUT/ruleset_http_request_dynamic_redirect.json"
      echo
    fi

    if [[ -f "$OUT/settings.json" ]]; then
      echo "## Zone settings (non-default / notable)"
      echo
      echo "| Setting | Value |"
      echo "|---------|-------|"
      jq -rn '[inputs.result] | flatten | .[] | select(.id | IN("always_use_https","ssl","min_tls_version","email_obfuscation","brotli","http2","browser_cache_ttl","rocket_loader","fonts","automatic_https_rewrites","security_level","ssl_automatic_mode","auto_origin_tls_kex","origin_tls_cmpl","pq_keyex","rum","speed_brain")) |
        "| `\(.id)` | `\(.value // .enabled|tostring)` |"' "$OUT"/settings.json "$OUT"/settings_*.json | sort
      echo
    fi
  } > "$OUT/SUMMARY.md"
  echo "  ok    SUMMARY.md"
fi

# ---------------------------------------------------------------- leak check
echo
echo "== secret check"
LEAKS=$(grep -rlEi 'avaros|@ontariomenopauseclinic\.ca|Bearer ' "$OUT" 2>/dev/null || true)
# Any other email address is personal data (an account name defaults to the
# owner's address). Cloudflare's DMARC reporting address is the one expected.
EMAILS=$(grep -rlE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]+' "$OUT" 2>/dev/null \
  | while read -r f; do grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]+' "$f" \
      | grep -qvE '@dmarc-reports\.cloudflare\.net$' && echo "$f"; done)
LEAKS=$(printf '%s\n%s\n' "$LEAKS" "$EMAILS" | sed '/^$/d' | sort -u)
if [[ -n "$LEAKS" ]]; then
  echo "  REFUSING TO LEAVE THESE IN PLACE - secret-looking content found:" >&2
  echo "$LEAKS" | sed 's/^/    /' >&2
  echo "  Inspect before committing." >&2
  FAILED=1
else
  echo "  clean - no booking URL, contact address, or token in the export"
fi

echo
echo "Wrote $OUT"
ls -1 "$OUT" | sed 's/^/  /'
echo
if [[ "$FAILED" -ne 0 ]]; then
  echo "Completed WITH ERRORS - the export is incomplete, do not treat it as a full backup." >&2
  exit 1
fi
echo "Review with: git diff --stat docs/current-state/cloudflare-export/"
