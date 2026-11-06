# CLAUDE.md

Guidance for Claude Code in this repository. It holds only what applies
repo-wide; anything tied to specific code is a comment on that code, so read the
file before changing it.

Where every kind of information lives — comments, docs, ADRs, runbooks, issues,
PRs — and how temporary things are tagged:

@CONTRIBUTING.md

## Boundaries

**Claude does not move code toward production.** Never dispatch *Draft
Changelog* or *Cut Release* (`gh workflow run`), push to `release`, or change
Cloudflare Pages settings that affect production builds. Reading state
(`gh run list`, `gh run view`, the exports) is fine. Prepare the step — check
`release` is an ancestor of the target, the changelog entry, staging — then hand
over the exact command or dashboard step. Anything that reaches production has a
human executing it, so a surprise in the process cannot become an incident.

**Claude never calls `op` (1Password) directly.** Credentials are reached only
through the scripts that already handle them (`cloudflare-token.sh`, via the
Cloudflare scripts). If a task needs an API call no script covers, ask for the
script to be extended rather than writing a new `op`-backed one.

## Principles

Ontario Menopause Clinic is a new, one-practitioner business: Andrea, a nurse
practitioner, offering menopause care in Ontario. This site is its marketing
site and the top of its customer funnel, leading visitors to book through
Avaros, the clinic's electronic medical records system.

**The business**

- **Build for now.** Build for the next year at most; anything with a longer
  horizon is YAGNI.
- **Keep costs as low as possible.** Prefer $0 options (open source,
  licence-free assets, free tiers), but never at the cost of a terms-of-service
  breach or a roadblock.
- **Keep day-to-day technical literacy low.** Andrea has no technical support,
  so anything she operates has to be simple.
- **Every service has a defined recovery.** It needs a time to recovery, a
  recovery point, and a statement of how incidents are noticed and resolved.

**The site**

- **Its job is conversion.** It explains the services and why to choose
  Andrea, then funnels visitors into booking. It must be ready to carry paid
  advertising.
- **Works equally well on phone and desktop.**
- **Meets WCAG 2.1 AA** at all times.
- **Single point of definition.** Each partial, style and value is defined once.
- **SEO/GEO always wins.** Discoverability by search engines and LLMs
  (structured data, metadata, crawler access) outranks single-point-of-definition
  and maintenance cost. Where it forces duplication, accept it and leave a
  comment at the duplicate naming what it must stay in sync with.
- **Staging mirrors production.** The only permitted differences are the
  staging banner and the signals that keep it out of indexes: `noindex,
  nofollow`, `site/layouts/robots.txt`'s `Disallow: /`, and the
  `site/layouts/llms.txt` preview notice. Never gate markup on
  `hugo.Environment` to hide it from staging; `./check-environments.sh` asserts
  the structured data is present in every environment. Point anything with external side
  effects (analytics, form posts) elsewhere rather than removing it, so the
  code path is still exercised. Zone-level behaviour can only be verified on
  the in-zone default slot.
- **Andrea's headshot appears only with "About Andrea" content**, never in the
  hero. The hero is about her whole-person approach to care.
- **Andrea's Mount Sinai experience is framed as selection, never training.**
  Never name "Mount Sinai" or "Sinai": its usage guidelines forbid implying
  that Andrea gained from the association. Say a recognised menopause program
  selected or employed her to deliver clinical care, which credits her
  competence, not that she trained in or benefited from it.

Anything in [`docs/legacy/`](docs/legacy/) is frozen and out of date: read it
for background, never as a source of truth.

## Workflow

* Always work in a feature branch or a worktree - do not work directly in the `main` branch
* Open questions and project tasks are tracked as GitHub issues (`gh issue list`), not in a markdown file

## Development scripts

All local development is managed through these scripts. Do not construct raw `hugo` commands.

| Script | Purpose |
|--------|---------|
| `./dev-server.sh` | Run the Hugo dev server on `localhost:1313` in this terminal (Ctrl-C stops it). `--ci` starts it in the background instead; `--stop` stops that. |
| `./validate.sh` | Full validation suite: build + environment checks + markdown lint + a11y. Starts the dev server automatically if needed, stops it when done. |
| `./check-environments.sh` | Builds development/staging/production (staging and production via `site/build.sh`, simulating Cloudflare's `CF_PAGES_BRANCH`) and asserts each produces the expected output. Catches a typo'd `--environment` value before it ships. Runs in CI on every PR (`.github/workflows/check-environments.yml`). |
| `./deploy-staging.sh <slug>` | Push current branch to a staging environment. |
| `./export-cloudflare.sh` | Export the live Cloudflare config to `docs/current-state/cloudflare-export/` (read-only API token required). Cloudflare holds configuration this repo cannot reproduce; the export is the record to rebuild from. Run it after **any** Cloudflare change and commit the diff — `git status` afterwards is the drift check. |
| `./cloudflare-build-log.sh [branch]` | Print the Cloudflare Pages build log for a branch's latest deployment (default `staging`), waiting if it is still building. Same read-only token as the export. |
| `./cloudflare-sweep.sh` | List Cloudflare configuration the export doesn't capture: GETs every zone and account endpoint in Cloudflare's OpenAPI schema (~5 min, same token). Run it when a setting turns out to be missing from the export, then add what matters to `export-cloudflare.sh`. Its raw output is outside the repo and must not be committed. |
| `./export-github.sh` | The same for GitHub (rulesets, merge and Actions settings) into `docs/current-state/github-export/`, using your `gh` login. Run it after **any** change in the repo's Settings. |

* **Before pushing a PR**, run `./validate.sh` and fix any failures.
* **If you start the dev server** (`./dev-server.sh --ci`), stop it before exiting by running `./dev-server.sh --stop`. This is ownership-safe: it only stops a server `dev-server.sh` itself started (its PID is in `.dev-server.lock`), so it will never kill a server someone else already had running.
* **A11y only**: `npm run a11y` (requires dev server running first). One-time setup on a new machine: `npx playwright install chromium`.
* **Markdown lint only**: `npm run lint:md`.
* **Compare two deployments**: `npm run compare` (production vs default staging) or `npm run compare -- <before> <after>`. Element-by-element computed-style diff; see [Testing Changes Before Release](docs/runbooks/testing-changes-before-release.md).
* **CSS lint only**: `npm run lint:css` — stylelint (`stylelint.config.mjs`) over `site/assets/css/main.css` and the `<style>` blocks/attributes in `site/layouts`. Keep Hugo tags inside CSS quoted (`url("{{ ... }}")`) so the parser sees a string.
* Hugo version is pinned in `.tool-versions` and used by CI; `dev-server.sh`/`validate.sh` warn (don't fail) if your local `hugo` doesn't match it.

## Environment variables

* All Hugo site parameters that must not be committed to the repo are managed as environment variables.
* `.env.local.example` (repo root) is the **canonical list** of all required environment variables, with safe placeholder values.
* `.env.local` (repo root, gitignored) holds the real values for local development.
* CI (GitHub Actions) loads `.env.local.example` directly — placeholder values are sufficient for builds and tests.
* Cloudflare Pages holds the real values as environment variables configured in the dashboard (Settings → Environment variables).
  * **Cloudflare Pages has separate env var scopes for Production and Preview (staging).** A variable added under one scope is not available to the other. Whenever a new env var is added to Cloudflare, it must be added under **both** scopes.
* **Whenever a new Hugo parameter is added to `site/hugo.toml` that is sourced from an env var, `.env.local.example` must be updated in the same PR, and the variable must be added to Cloudflare Pages under both Production and Preview scopes.** This keeps CI and all deployment environments in sync.

## Publishing

* Production is `https://ontariomenopauseclinic.ca` (the apex; `www` 301s to it — see [Cloudflare configuration](docs/current-state/cloudflare-config.md)), deployed by Cloudflare Pages from the `release` branch. Only the *Cut Release* workflow moves `release`: [Cutting a Release](docs/runbooks/cutting-a-release.md).
* `main` requires a PR (merge commits only) and signed commits. Claude never signs commits: it commits unsigned (`git -c commit.gpgsign=false commit`), and Tim signs the branch while preparing the PR for merge.
* Staging is any `staging*` branch, pushed with `./deploy-staging.sh [slug]`: [Deploying to Staging](docs/runbooks/deploying-to-staging.md). Use the slug the user gives. Only the default slot (no slug) is in-zone; verify anything zone-dependent there, never on a numbered `pages.dev` slot.

## Decisions

| Decision | ADR |
|---|---|
| Trunk-based development with a human release gate: PRs to `main`, verified on staging, released by fast-forwarding `release` | [0001](docs/adr/0001-releasing-to-production.md) |

## Before changing…

| Change | Follow |
|---|---|
| Anything that will be released | [Testing Changes Before Release](docs/runbooks/testing-changes-before-release.md) — every difference `npm run compare` reports must be intended |
| `site/layouts/_default/baseof.html`, or `site/assets/css/main.css` tokens the maintenance placeholder uses | The maintenance-page step of that runbook; staging never renders the placeholder |
| Any Cloudflare setting | Update [`docs/current-state/cloudflare-config.md`](docs/current-state/cloudflare-config.md) and rerun `./export-cloudflare.sh` in the same PR |
| Any GitHub repository setting, ruleset or Actions permission | Update [`docs/current-state/github-config.md`](docs/current-state/github-config.md) and rerun `./export-github.sh` in the same PR |
| The booking frame's height or breakpoints | [When the Avaros Booking Page Changes Size](docs/runbooks/avaros-booking-page-size.md) |

## Repository Structure

```
assets/                                           # Original asset files for the website - Andrea's headshot, logo file, etc
docs/
  adr/                                            # One target design per product problem (README.md has the format)
  runbooks.md                                     # Index of runbooks, by kind
  runbooks/                                       # One procedure per file (releasing, maintenance mode, ...)
  current-state/                                  # State code does not define: Cloudflare and GitHub, each a *-config.md (why) and *-export/ (generated); search-engines.md (how Google and Bing see the site)
  legacy/                                         # Frozen pre-convention docs (original requirements, decision log, early research, content drafts); reference only
site/                                             # Hugo-based website
```
