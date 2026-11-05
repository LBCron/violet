# Testing Changes Before Release

Shows that a change does what it should on a real deployment, and nothing
else, before [Cutting a Release](cutting-a-release.md) asks you to confirm
`verified_on_staging`.

Staging exists to verify what production will do, so it mirrors production in
everything except the staging banner and the index-blocking signals
("Staging mirrors production" in [CLAUDE.md](../../CLAUDE.md#principles)). The final check before a release is on the default, in-zone
slot; [Deploying to Staging](deploying-to-staging.md) explains the slots.

## Pre-checks

1. **`./validate.sh` passes** on the branch: build, environment checks, lint and
   accessibility. CI runs the same checks on the PR.

## Steps

1. **Deploy** the branch to the default slot and confirm it is serving your
   commit, following [Deploying to Staging](deploying-to-staging.md).

2. **Compare against production:**

   ```sh
   npm run compare
   ```

   This loads every page (the a11y suite's list, plus a 404) at desktop and
   phone widths, and the quiz modal, on production and on staging. For every
   element except the staging banner it compares box size and the computed
   properties listed in `scripts/compare-sites.mjs`, then prints each distinct
   difference with where it appears. Screenshots of every state land in
   `test-results/compare/`.

   **Every difference must be explained by the change.** A change meant to be
   visually a no-op should report none. A "structure diverges" or
   "element count" line means the markup changed; expected when templates
   change, a red flag when only CSS did.

   Production is the last release, so for a release check the differences are
   everything merged since. To isolate one PR, compare it against `main`
   deployed to a numbered slot instead:

   ```sh
   git switch main && ./deploy-staging.sh 9
   git switch <branch> && ./deploy-staging.sh
   npm run compare -- https://staging9.violet-6qt.pages.dev https://staging.ontariomenopauseclinic.ca
   ```

3. **If the change touches the maintenance page** — `baseof.html`, or tokens it
   uses in `main.css` — compare it too. It renders only in a production build
   with maintenance mode on, which no staging slot shows, so build both sides
   locally through `site/build.sh` and serve them:

   ```sh
   git worktree add /tmp/violet-main main
   for side in /tmp/violet-main "$PWD"; do
     (cd "$side/site" && env -u CF_PAGES_BRANCH bash build.sh >/dev/null)
   done
   python3 -m http.server 8701 -d /tmp/violet-main/site/public 2>/dev/null & before=$!
   python3 -m http.server 8702 -d site/public 2>/dev/null & after=$!
   npm run compare -- http://localhost:8701 http://localhost:8702
   kill $before $after; git worktree remove --force /tmp/violet-main
   ```

   Every route shows the placeholder, so the per-page results repeat. Check the
   page width at each viewport too: the heading is held on one line, so padding
   changes can make it scroll sideways on phones (#158).

4. **Check on real browsers** for anything layout, font or booking related. The
   comparison runs Chromium only. At minimum: Safari on an iPhone, Safari and
   Firefox on a desktop. The booking iframe is cross-origin, so its contents
   are not compared — open `/book/` and confirm the calendar loads.

## Post-checks

1. **Every difference the comparison reported is intended.** Anything else is
   fixed on the branch, or filed as an issue if it already exists on
   production.
2. **The staging slot holds the commit you are releasing**, so the
   `verified_on_staging` confirmation in Cut Release is true.

What this does not cover, and what does: structured data, metadata and crawler
directives are asserted per environment by `./check-environments.sh`; zone
configuration is checked against `docs/current-state/cloudflare-export/` by
`./export-cloudflare.sh`.
