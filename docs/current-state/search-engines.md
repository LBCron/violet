# Search Engines

How Google and Bing see `ontariomenopauseclinic.ca`: which properties exist,
how they are verified, and which of the findings they report are expected for
this site, and why. The procedure for checking them is
[Reviewing Search Engine Indexing](../runbooks/reviewing-search-indexing.md).

Unlike Cloudflare and GitHub, this is state the site produces and the search
engines observe, not configuration set in a dashboard. There is no export yet:
the facts below were read from each tool by hand.
[#221](https://github.com/timgladwell/violet/issues/221) tracks read-only API
access, which would provide one.

## Properties

| Tool | Property | Verified by | Sitemap |
|---|---|---|---|
| Google Search Console | Domain property `ontariomenopauseclinic.ca` (covers the apex, `www` and every other host) | DNS TXT record `google-site-verification=…` on the apex, in `cloudflare-export/dns.json` | `https://ontariomenopauseclinic.ca/sitemap.xml`, submitted and last read 2026-07-25, status Success |
| Bing Webmaster Tools | `https://ontariomenopauseclinic.ca/` | DNS CNAME record `4c2a2c0a2413e7ec9186152562a7c3d7` → `verify.bing.com`, DNS only (not proxied), in `cloudflare-export/dns.json` | `https://ontariomenopauseclinic.ca/sitemap.xml`, last crawled 2026-07-25, status Success |

**Don't remove either verification record**: the `google-site-verification` TXT
or the Bing CNAME. Both tools re-check them, and a property loses its
verification if its record is gone. Both are listed in
[Cloudflare configuration](cloudflare-config.md)'s DNS table, because their
names and values don't say what they are.

## Google: expected "not indexed" reasons

Search Console's *Indexing → Pages* lists every URL Google knows about. These
rows are expected:

| Reason | URLs | Why it's expected | It's a real problem if |
|---|---|---|---|
| Page with redirect | `https://www.ontariomenopauseclinic.ca/…` | `www` 301-redirects to the apex: the *www to apex redirect* rule in [Cloudflare configuration](cloudflare-config.md#redirect-rules), from [#124](https://github.com/timgladwell/violet/issues/124). Google lists the redirecting URL and indexes its target. | An apex URL is listed, or a `www` URL doesn't 301 to the same path on the apex. |
| Excluded by 'noindex' tag | `/quiz/` and `/quiz`, on the apex and `www` | The quiz has `noindex: true` (`site/content/quiz.md`) and is left out of the sitemap. Why it is `noindex` isn't recorded. The slashless `/quiz` comes from the site's own quiz links, which Cloudflare Pages 308-redirects to `/quiz/`. | Any other page is listed. `baseof.html` also adds `noindex` on staging and in maintenance mode, so a production page here may mean either leaked into a production build. |
| Alternate page with proper canonical tag | `https://www.ontariomenopauseclinic.ca/book/` | Last crawled 2026-07-25, before the `www` redirect existed. Its canonical tag already named the apex. It moves to *Page with redirect* when Google next crawls it. | An apex URL is listed, or a `www` URL crawled after 2026-07-28. |

A reason not in this table, such as *Crawled – currently not indexed*,
*Duplicate without user-selected canonical*, *Not found (404)*, *Soft 404* or
*Server error (5xx)*, is never expected.

Pressing *Validate fix* on an expected row can only fail, because the reason
still applies. A validation of *Page with redirect* started 2026-08-24 and
failed on 2026-09-05 for exactly this reason. It needs no action.

## Bing: expected recommendations

| Recommendation | Pages | Why it's expected | It's a real problem if |
|---|---|---|---|
| The `<img>` tag does not have an ALT attribute defined | `/` | Every image has an `alt` attribute. The logo and the footer link icons have `alt=""` on purpose: the clinic name and the link text sit right beside them, so text `alt` would make screen readers read the same words twice (WCAG 2.1 AA). Bing appears to count an empty `alt` as missing, or the finding predates a fix. | An image that carries meaning (Andrea's headshot, any photo or chart) has no `alt`, or `alt=""`. Check with an HTML parser, not `grep`: the headshot's `alt` is on a later line of its tag. |
| Meta descriptions on many of your pages are too short | `/book/` | Stale: `/book/`'s description was lengthened on 2026-08-23 and is about 150 characters. | The page's current description is under 150 characters. `/privacy/` (90) and `/medical-disclaimer/` (100) genuinely are short today; [#224](https://github.com/timgladwell/violet/pull/224) lengthens them. |

Any other recommendation is not expected.

Bing is worth the same attention as Google even though it sends less traffic:
its index also serves DuckDuckGo and the web search behind ChatGPT and
Copilot, which matters for discoverability by LLMs.
