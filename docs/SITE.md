# TalkType for Mac — the shop site

Lives in `site/`. Plain HTML, one stylesheet, one small script, one Netlify
function. No build step, no framework, no tracker.

```
index.html    the main page: hero, product stage, how it works, engines, pricing, FAQ
buy.html      order summary → POST /api/checkout → Square payment link
thanks.html   post-payment download + install steps + confetti (noindex)
netlify.toml  static publish + the /api/checkout redirect + headers
netlify/functions/checkout.mjs   the only server code: mints a Square link
support.html  install/permission help, refunds, contact
privacy.html  what leaves the Mac, in plain words
styles.css    cream paper, warm ink, one peach gradient — the app's own palette
app.js        HUD line cycle, version stamp, soft reveal
assets/       ghost.svg, app icon PNGs, og-card.png
version.json  version stamp; the footer reads it
```

## Preview

```bash
cd site && python3 -m http.server 8898
# http://127.0.0.1:8898
```

## Price

**A$29 for the launch month** (about US$19), A$39 after 4 December. Two places must agree:

- `netlify/functions/checkout.mjs` → `PRODUCT.amountCents: 2900`
- the visible copy: `index.html` (pricing card, CTA, meta) and `buy.html`
  (order lines, total). The OG card is baked, so regenerate it if the number moves.

## Square checkout

`POST /api/checkout` → `netlify/functions/checkout.mjs` → Square
`/v2/online-checkout/payment-links` → buyer pays on Square → redirect to
`/thanks.html?checkout_id=…` (confetti + download). No card field is ever served
from this site.

Environment (set in Netlify, never in the repo):

| var | value |
|---|---|
| `SQUARE_ACCESS_TOKEN` | production token from the Square developer dashboard |
| `SQUARE_LOCATION_ID` | `LS821EYMQCANH` (AU production location) |
| `SQUARE_ENVIRONMENT` | `production` — anything else stays sandbox |
| `SQUARE_API_VERSION` | optional, defaults to `2026-01-22` |
| `SITE_URL` | optional; the origin used for the post-payment redirect |

Without a token the function answers 503 and `buy.html` shows its inline error
with a mailto fallback. Nothing charges.

An AU seller location charges AUD; the function asks Square for the location
currency rather than assuming it.

## Before it goes live

1. **Canonical / OG URLs** — `index.html`, `buy.html` `<head>`, currently
   `https://talktype.app/mac/`. Update all three if the host changes.
2. **DMG URLs** — `thanks.html`, `index.html` (pricing card) and the FAQ point at
   `https://talktype.app/downloads/TalkType.dmg`. Keep that file in sync with the
   build this site sells.
3. **Square dashboard** — rename the merchant business from `pabloandres` to
   **Made by Pablo**, and update the old A$29 Square Online item (left over as a
   manual fallback) to A$59 or archive it.

## Hosting (live)

Netlify project **talktype-mac** → **https://mac.talktype.app**
(team `pibulus`, project id `cd23d988-989e-422b-ae02-1a88a371be37`).
The `talktype-mac.netlify.app` host still answers; `mac.talktype.app` is the
canonical one, with a Let's Encrypt certificate provisioned 2026-11-04.

It is deployed as a plain static publish plus one function; no build step.

```bash
cd site
netlify deploy --dir . --functions netlify/functions --prod
```

`site/` is linked to that project locally (`.netlify/state.json`, gitignored).

**Current environment:** `SQUARE_ENVIRONMENT=sandbox`, sandbox token and location.
`SITE_URL` is deliberately unset — the function uses the request origin, so the
post-payment redirect stays on whichever host sold the app (`mac.talktype.app`
in production, a review deploy if testing elsewhere). Fallback is
`https://mac.talktype.app`.

The whole flow is live and testable now — Buy → Square's sandbox testing panel →
back to `/thanks.html` with confetti.

**To take real money:** replace the site env with the production token and set
`SQUARE_ENVIRONMENT=production` + `SQUARE_LOCATION_ID=LS821EYMQCANH`, then redeploy
(nothing else changes).

## Domain — done

- Cloudflare: `CNAME mac → talktype-mac.netlify.app`, **DNS only** (grey cloud;
  Netlify issues the certificate, and a proxied record would double-TLS).
- Netlify: `custom_domain = mac.talktype.app`, certificate issued, `http` 301s
  to `https`.
- Canonical and `og:url` in `index.html` + `buy.html` point at
  `https://mac.talktype.app/`.

### `talktype.app/mac` is NOT redirected yet — on purpose

The old SvelteKit page still sells A$29 through a working Square order. The new
shop's checkout is still **sandbox**, so it cannot take money. Until a production
token is live on this site, 301-ing `/mac` would remove the only purchase path.

When production payments are verified, add to the talktype.app repo's
`netlify.toml` and deploy:

```toml
[[redirects]]
  from = "/mac"
  to = "https://mac.talktype.app/"
  status = 301
  force = true

[[redirects]]
  from = "/mac/*"
  to = "https://mac.talktype.app/:splat"
  status = 301
  force = true
```

### App Store Connect URLs

| field | value |
|---|---|
| Support URL | `https://mac.talktype.app/appstore-support` |
| Marketing URL | *(leave blank in App Store Connect — avoids Guideline 3.1.1 cross-link)* |
| Privacy policy URL | `https://mac.talktype.app/appstore-privacy` |

### Sandbox token note

The Netlify CLI echoed the sandbox `SQUARE_ACCESS_TOKEN` into terminal output
while it was being set. It is a sandbox credential only; the production token
should be set from the Square dashboard without passing through a shell command
that echoes it (`netlify env:import` from a local file, or the Netlify UI).

## Notes

- The product art on the hero is an HTML reconstruction of the real popover
  (346 × 440, same metrics, palette and copy as `TalkType.swift`). It stays crisp
  at every size and animates without a video. Swap in real captures only if they
  are clean — the current App Store screenshot is not.
- The palette is duplicated from the app on purpose. If the app's palette moves,
  update `:root` in `styles.css` and the ghost gradient in `assets/ghost.svg`.
- `version.json` is the machine-readable stamp; bump it with the app version.
