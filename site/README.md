# site/ — TalkType for Mac

The shop page. Plain HTML, one stylesheet, one small script. No build step, no
framework, no tracker.

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

**A$59 once** (about US$39). Two places must agree:

- `netlify/functions/checkout.mjs` → `PRODUCT.amountCents: 5900`
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

## Hosting: what this needs

A static host is not enough any more — the checkout is one serverless function.
Two recipes:

**Netlify (recommended, smallest moving parts)**
```bash
# from the repo root
npx netlify-cli deploy --dir site --functions site/netlify/functions --prod
```
or connect the repo with base `site/`, publish `site/`, functions
`site/netlify/functions` — `site/netlify.toml` already says so. Add the env vars
above in Site settings → Environment.

**Deno Deploy / the box** — serve `site/` statically and route
`POST /api/checkout` at the same module (it is plain `export default (request) =>
Response`; swap `process.env` for `Deno.env` when running under Deno).

**The box** — copy `site/` into an nginx root for a `talktype-mac` vhost, proxy
`POST /api/checkout` at the function module (run it under Deno or Node), and
reverse-proxy `/downloads/` at the DMG.

Keep `thanks.html` reachable at the same path the Square redirect uses.

## Notes

- The product art on the hero is an HTML reconstruction of the real popover
  (346 × 440, same metrics, palette and copy as `TalkType.swift`). It stays crisp
  at every size and animates without a video. Swap in real captures only if they
  are clean — the current App Store screenshot is not.
- The palette is duplicated from the app on purpose. If the app's palette moves,
  update `:root` in `styles.css` and the ghost gradient in `assets/ghost.svg`.
- `version.json` is the machine-readable stamp; bump it with the app version.
