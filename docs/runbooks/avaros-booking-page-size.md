# When the Avaros Booking Page Changes Size

Keeps the "Book an appointment" button visible when Avaros's booking page
grows.

The booking form on `/book/` (and in the desktop modal) is an iframe of
Avaros's booking page, whose content is edited in Avaros, not here. If that
page grows — longer welcome text, a bigger logo — its button can drop below or
past the frame's edge, where phone visitors won't find it
([#165](https://github.com/timgladwell/violet/issues/165)).

The **Booking Check** workflow (`booking-check.yml`) re-measures the real page
every morning into `a11y/fixtures/avaros-landing.json`, which
`a11y/booking.spec.ts` uses as a stand-in for the iframe on every test run. It
finds the booking URL on production's `/book/`, falling back to staging, and
fails with an error if both are in maintenance mode. On any change it opens, or
updates, an **"Avaros booking page changed size"** PR.

## Pre-checks

1. **Read the PR's verdict.**
   - **✅ still fits** — review the numbers and merge. Nothing else to do.
   - **❌ no longer fits** — the run also fails, which emails you. Continue
     below. Production shows the hidden button until a release ships the fix.

## Steps

1. Check out the PR's branch.
2. Adjust the frame in `site/assets/css/main.css` until the booking tests pass:
   - **The button fell below the bottom edge:** raise the frame's height —
     `.book-page__frame` for `/book/`, `.modal--booking .modal__panel` for the
     modal.
   - **The button overhangs the right edge** (Avaros's minimum width grew): move
     the edge-to-edge breakpoint below it.
3. Run the booking tests (they need the dev server; `./validate.sh` starts it):

   ```sh
   ./validate.sh
   ```

4. **Check the fix on staging.** The tests run against a measured stand-in;
   staging embeds the real Avaros page, so it is the only place the fit can be
   confirmed before release.
   [Deploy the branch](deploying-to-staging.md) to the default slot, then open
   `/book/` and the desktop booking modal on a phone and on desktop. The button
   must be visible without scrolling inside the frame.
5. Merge, then [cut a release](cutting-a-release.md).

## Post-checks

1. **Production's `/book/` shows the button** on a phone without scrolling
   inside the frame.

To re-measure on demand, run the workflow by hand:
`gh workflow run booking-check.yml`. `npm run avaros:measure -- <booking URL>`
works locally for a look, but don't commit its fixture: fonts differ from the
workflow's Ubuntu runner, so text wraps differently at some widths and the next
daily run opens a PR to undo it
([#183](https://github.com/timgladwell/violet/pull/183)).
