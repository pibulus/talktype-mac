# TalkType for Mac — the shop site

Lives in `site/`. Plain HTML, one stylesheet, one small script, one Netlify
function. No build step, no framework, no tracker.

```
index.html    the main page: two plates. Plate 01 is the instrument (three
              scenes on one stage), plate 02 is the three beats, the ticket
              and the rail. Exactly 200svh on desktop.
buy.html      order summary → POST /api/checkout → Square payment link
thanks.html   post-payment download + install steps + confetti (noindex)
netlify.toml  static publish + the /api/checkout redirect + headers
netlify/functions/checkout.mjs   the only server code: mints a Square link
support.html  install/permission help, refunds, contact
privacy.html  what leaves the Mac, in plain words
styles.css    cream paper, warm ink, one peach gradient — the app's own palette
app.js        the three scenes, the prompt deck, the live demo, the version stamp
assets/       ghost.svg, app icon PNGs, og-card.png
version.json  version stamp; the footer reads it
```

## The demo, and the microphone header

`app.js` carries `DEMO_ENGINE`, defaulting to `browser`. That lane uses the
browser's own `SpeechRecognition`, needs no key and no server, and stores
nothing. If it is missing or the mic is blocked, the scene plays its scripted
take and the hint says so plainly.

`netlify.toml` MUST keep `Permissions-Policy: microphone=(self)`. With the old
`microphone=()` the whole origin lost the mic and every "live" demo silently
fell through to the scripted take — it looked like it worked, so nothing
reported it.

The `proxy` lane is written but not armed. Turning it on means a Netlify
function that forwards audio to Deepgram, which contradicts the "no TalkType
server receives audio" promise on `privacy.html` unless that page and the demo
both disclose it. Netlify functions are HTTP-only, so word-by-word streaming on
that lane needs Deno Deploy, not this host.

## Preview

```bash
cd site && python3 -m http.server 8898
# http://127.0.0.1:8898
```

## Price

**A$29 one time** (about US$19). Two places must agree:

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

## Already verified (do not re-do)

1. **Canonical / OG URLs** — every page points at `https://mac.talktype.app/`.
   Verified 2026-11-05. `/buy` is canonical as the clean route, not `/buy.html`.
2. **DMG URL** — the shop serves its own artifact at
   `https://mac.talktype.app/downloads/TalkType.dmg` (committed at
   `site/downloads/`). Re-verify a release with
   `shasum -a 256 site/downloads/TalkType.dmg dist/direct/TalkType-1.0.dmg`;
   the two must match.
3. **Square dashboard** — still open: rename the merchant business from
   `pabloandres` to **Made by Pablo** so buyers see the right name at checkout,
   and archive the old A$29 Square Online item.

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

**Current environment:** `SQUARE_ENVIRONMENT=production`, production token and
location `LS821EYMQCANH` (AUD, AU). `SITE_URL` is deliberately unset — the
function uses the request origin, so the post-payment redirect stays on whichever
host sold the app. Fallback is `https://mac.talktype.app`.

Verified 2026-11-05: `curl -sX POST -d '{}' https://mac.talktype.app/api/checkout`
returns `"environment":"production"`, `AUD 2900`, and a `checkout.square.site`
link. The flow is Buy → Square → back to `/thanks` with confetti.

**To go back to sandbox:** set `SQUARE_ENVIRONMENT=sandbox`, the sandbox token,
and `SQUARE_LOCATION_ID=L41AKRW3ZPD1B`, then redeploy.

## Domain — done

- Cloudflare: `CNAME mac → talktype-mac.netlify.app`, **DNS only** (grey cloud;
  Netlify issues the certificate, and a proxied record would double-TLS).
- Netlify: `custom_domain = mac.talktype.app`, certificate issued, `http` 301s
  to `https`.
- Canonical and `og:url` in `index.html` + `buy.html` point at
  `https://mac.talktype.app/`.

### `talktype.app/mac` — ready to redirect

The blocker is gone: this shop's checkout is production. The 301 can land
whenever the old SvelteKit page is retired. Note that `talktype.app/downloads/`
still serves a 27 October build from the other repo (`pibulus/talktype`), so
retire or repoint those links at the same time.

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
