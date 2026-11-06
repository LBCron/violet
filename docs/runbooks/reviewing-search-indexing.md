# Reviewing Search Engine Indexing

Checks that every page meant for search is indexed by Google and Bing, and that
every finding either tool reports is expected or has an issue open.

Which findings are expected for this site, why, and what would make each one a
real problem is in [Search Engines](../current-state/search-engines.md). This
runbook is the procedure for checking the tools against it.

Run it monthly, and after any release that adds, removes or renames a page or
changes a Cloudflare redirect rule.

## Pre-checks

1. **You can open both tools** for `ontariomenopauseclinic.ca`: Google Search
   Console and Bing Webmaster Tools.
2. **You have the current page list.** The production sitemap is the list of
   pages meant for search:

   ```sh
   curl -s https://ontariomenopauseclinic.ca/sitemap.xml | grep -o '<loc>[^<]*' | cut -c6-
   ```

## Steps

### Google Search Console

1. **Sitemap.** Open *Sitemaps*. The sitemap's *Last read* should be recent,
   and its discovered-page count should match the sitemap. If it was last
   read before the latest release that changed the page list, resubmit it.
2. **Indexed pages.** Open *Indexing → Pages → View data about indexed pages*.
   The URLs listed should be exactly the sitemap's.
   - A sitemap URL missing from the list: inspect it (*URL inspection*) and
     open an issue.
   - A URL that isn't in the sitemap: find out why Google indexed it, and open
     an issue.
3. **Pages that aren't indexed.** For each row under *Why pages aren't
   indexed*, open it and compare its URLs with
   [Google's expected reasons](../current-state/search-engines.md#google-expected-not-indexed-reasons).
   *Export* (top right of a row) gives the full URL list when there are more
   than a few.
   - **Matches:** nothing to do.
   - **Matches a reason, but a URL breaks the pattern, or the row is new:**
     open an issue with the export attached.
4. **Don't press "Validate fix" on an expected row.** It can only fail.

### Bing Webmaster Tools

1. **Sitemap.** Open *Sitemaps* and check the same as for Google: read
   recently, and the page count matches.
2. **Recommendations.** Open *Recommendations* and compare each row with
   [Bing's expected recommendations](../current-state/search-engines.md#bing-expected-recommendations).
   Bing's findings can be older than the page, so check the page as it is now
   before acting:

   ```sh
   curl -s https://ontariomenopauseclinic.ca/<page>/ | grep -o '<meta name="description"[^>]*>'
   ```

## Post-checks

1. Every sitemap URL is indexed by Google, and both tools read the sitemap
   after the latest release that changed the page list.
2. Every Google *not indexed* row and every Bing recommendation is expected,
   or has an issue open.
3. If the review found a new expected finding,
   [Search Engines](../current-state/search-engines.md) records it, with why
   it is expected and what would make it a real problem.
