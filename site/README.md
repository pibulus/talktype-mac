# site/ — TalkType for Mac

The shop page. Plain HTML, one stylesheet, one small script. No build step, no
framework, no tracker.

```
index.html    the main page: hero, product stage, how it works, engines, pricing, FAQ
buy.html      order summary → Square hosted checkout
thanks.html   post-payment download + install steps (noindex)
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

## Before it goes live

Three constants are placeholders. Change them in the HTML, nowhere else:

1. **Canonical / OG URLs** — `index.html`, `buy.html` `<head>`, currently
   `https://talktype.app/mac/`. If the site lands on its own domain (or at
   `talktype.app/download`), update those plus the `og:url`.
2. **Square checkout link** — `buy.html`, the `#checkout` anchor. It currently
   points at the live "TalkType for Mac (Lifetime) — A$29.00" order:
   `checkout.square.site/merchant/ML5YMRAT9Q14P/order/...`. Replace it if a new
   Square item is created.
3. **DMG URLs** — `thanks.html`, `index.html` (pricing card) and the FAQ point at
   `https://talktype.app/downloads/TalkType.dmg`. Keep that file in sync with the
   build this site sells.

Also worth doing once, in Square: rename the store from `pabloandres` to
`TalkType`, and set the checkout confirmation to send buyers to `/thanks.html`
when Square's link settings allow a return URL.

## Deploy

Any static host works, because there is no server:

- **Netlify drop** — drag the `site/` folder onto app.netlify.com/drop, then point
  the domain. No build command, publish directory `site/`.
- **The box** — copy `site/` into the nginx root for a `talktype-mac` vhost and
  reverse-proxy `/downloads/` at the DMG, mirroring the other fleet apps.
- **Deno Deploy** — serve the folder with `deno serve` or the existing static
  handler; no config needed.

Keep `thanks.html` reachable at the same path the Square receipt links to.

## Notes

- The product art on the hero is an HTML reconstruction of the real popover
  (346 × 440, same metrics, palette and copy as `TalkType.swift`). It stays crisp
  at every size and animates without a video. Swap in real captures only if they
  are clean — the current App Store screenshot is not.
- The palette is duplicated from the app on purpose. If the app's palette moves,
  update `:root` in `styles.css` and the ghost gradient in `assets/ghost.svg`.
- `version.json` is the machine-readable stamp; bump it with the app version.
