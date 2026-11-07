# TYPE-SPEC — two plates, one grid, no excuses

*lights cigarette* Look, kid. Two viewport plates is not a mood, it's arithmetic. Either the
numbers add up on a 1280×800 laptop or they don't, and no amount of "text-wrap: balance" will
save an h1 that's 92px wide-bodied in a 544px column. Here are the numbers.

## 0. The grid, before anything

- `.wrap`: `max-width: 1240px`, `padding-inline: 48px` → **content 1144px, always**, at 1280, 1440 and 1920. The grid stops growing at 1336px viewport and never breathes again.
- Hero/plate split: `grid-template-columns: minmax(0, 1fr) minmax(0, 1fr)`, `gap: 56px` → **two 544px columns**.
- Plate 2 split: `minmax(0, 1.26fr) minmax(0, 1fr)` with `gap: 64px` → **604px / 476px**.
- Sticky bar: `height: 74px` exactly (`min-height: 74px`, no padding growth). Usable plate height = `calc(100svh - 74px)`. **`svh`, not `vh`** — desktop browser chrome and iOS Safari both lie about `vh`.
- Law for every clamp below: **the vw coefficient = cap ÷ 14.4** (cap is reached at 1440) and **the vh coefficient = cap ÷ 9** (cap is reached at 900 tall). Any new size derives itself from that and stays honest.

## 1. Type scale

| Role | px @1440×900 | `clamp()` | line-height | letter-spacing | weight | notes |
|---|---|---|---|---|---|---|
| h1 two-line lockup | 80 | `clamp(44px, min(5.6vw, 8.9vh), 80px)` | 0.93 | **-0.028em** | 800 | 1440→80, 1920→80, 1280×800→71.2 |
| lede | 20 | `clamp(17px, min(1.4vw, 2.25vh), 20px)` | 1.5 | -0.004em | 500 | ink-soft, max-width 40ch |
| beat title | 27 | `clamp(22px, min(1.9vw, 3vh), 27px)` | 1.12 | -0.018em | 700 | 2 lines max |
| beat line | 17 | `clamp(15.5px, min(1.2vw, 1.9vh), 17px)` | 1.55 | 0 | 400 | ink-soft, max 44ch |
| beat number | 12 | fixed | 1 | 0.16em | 600 | mono, ink-mute, "01" |
| ticket title | 40 | `clamp(30px, min(2.8vw, 4.5vh), 40px)` | 1.0 | -0.03em | 800 | forced 2-line break |
| price numerals | 88 | `clamp(64px, min(6.1vw, 9.8vh), 88px)` | 0.85 | -0.02em | 800 | tabular, see §3 |
| price currency "A$" | 0.31em ≈ 27 | `font-size: 0.31em` | 1 | **+0.01em** | 600 | ink-mute, tabular |
| proof bullets | 15.5 | fixed | 1.45 | 0 | 500 | 4 items, 22px row pitch |
| mono chips / eyebrow | 11.5 | fixed | 1.2 | 0.14em | 600 | uppercase, mono |
| spec rail | 12 | `clamp(11px, 0.85vw, 12px)` | 1.4 | 0.08em | 500 | mono, ink-mute |
| tab labels | 14 | fixed | 1 | -0.005em | 600 | 44px hit area |
| nav brand | 17 | fixed | 1 | -0.025em | 800 | `for Mac` tag: 11.5 mono |
| capsule transcript | 15.5 | `clamp(14px, 1.1vw, 15.5px)` | 1.3 | -0.008em | 500 | single line, ellipsis |
| mono hint (under card) | 12.5 | fixed | 1.4 | 0.02em | 500 | opacity .52, never below |

System stack only (`--sans` / `--mono`). **No weights between 400/500/600/700/800** — SF snaps
`650` to something you didn't ask for and Segoe/Roboto fake it. Cap heights land within 1.5% of
each other across the fallback stack at these sizes; they don't at 92px, which is why the h1 cap
is 80 and not 93.

## 2. The h1, and the break that has to be a decision

- Markup: `Talk faster than<br>you type.` — a real `<br>`. `text-wrap: balance` is **banned** here; it re-ragged a two-line lockup into three on the current file.
- `text-wrap: initial` (or `wrap`); `white-space: normal`. Do not use `nowrap`.
- Hard cap: `max-width: 552px` (safety only — 8px of give). At 80px that is ≈ **12.6ch**; state it in px, because `ch` moves when the font-size moves and then the break silently changes at 1280.
- Tracking **-0.028em** (2.24px at 80px). The current -0.05em (−4.6px per pair at 92px) closes the `T`/`a` and `t`/`h` ink traps into a smear. Do not go below -0.03em.
- Measured at 80px, weight 800, −0.028em: **"Talk faster than" = 486px** (544 col, 58px of rag), **"you type." = 322px**. Both fit at 1440 *and* at 1920, because the column is 544px at both. If the brief wants it bigger at 1920, the max-width has to grow — it isn't allowed to grow here.
- At 1280×800 the h1 is 71.2px → lines measure 433px and 287px, still one lockup, still left-aligned, never centred.

## 3. The price lockup (this is not a typo, it's a hierarchy)

```
.price        { display: flex; align-items: baseline; gap: 0; }
.price .cur   { font-size: 0.31em; letter-spacing: +0.01em; margin-right: 0.055em;
                color: var(--ink-mute); font-weight: 600; }
.price .amount{ font-size: clamp(64px, min(6.1vw, 9.8vh), 88px); font-weight: 800;
                letter-spacing: -0.02em; line-height: 0.85; color: var(--ink); }
.price .cur, .price .amount { font-variant-numeric: tabular-nums lining-nums;
                              font-feature-settings: "tnum" 1, "lnum" 1; }
```

- **Ratio 0.31**, so at 88px the A$ is 27px — big enough to read as currency, small enough to never compete. At 64px (smallest) it's 20px, so it never falls below the proof-bullet size and never looks like a footnote.
- `align-items: baseline` **and nothing else**. No flex centring, no `translateY` hacks: baseline is the only alignment that survives the clamp changing size mid-window.
- Horizontal air is `0.055em` (≈4.8px at 88px), **not** `gap: 8px`. A fixed 8px gap is correct at exactly one size and wrong at every other size in the clamp.
- Tabular figures on both parts. `29` in proportional figures has a 9 that hangs past the 2 and the lockup goes visibly lopsided at 88px.
- Colour: numerals full `--ink`, A$ `--ink-mute`. Two-tone is the whole trick — the eye reads "29" first and "Australian dollars" second, which is the truth of the offer.
- Wrap the pair in `aria-label="A$29"` with the visual spans `aria-hidden` so a screen reader doesn't say "A dollar 29".

## 4. Plate 2 vertical rhythm

| Block | Value |
|---|---|
| plate height | `calc(100svh - 74px)`, `grid-template-rows: 1fr auto` |
| beat rows | 3 × `minmax(150px, 1fr)` inside the 1fr track — they absorb every spare pixel, the ticket does not |
| beat row internal | `padding: 26px 0 30px`; hairline `1px solid var(--line)` on `border-top`; number 12px, `margin-bottom: 14px`; title→line gap 12px |
| column gap (plate 2) | 64px |
| ticket height | **591px fixed content** (see below) |
| rail | `72px` = 1px hairline + 20px top pad + 17px line + 28px bottom pad, `align-self: end` |

Ticket internals, top to bottom (sums to 591):

`40` pad · `76` title (2 × 38 at lh 1.0) · `24` · `71` price (88 × 0.85 line box) · `16` ·
`48` statement (2 × 24) · `24` · `136` bullets (4 × 22 + 3 × 16 gaps) · `28` ·
`56` CTA pill · `14` · `18` mono "Already purchased" · `40` pad.

**Does it fit 826?** Yes: tallest column is the ticket at 591 + rail 72 = **663px**, so 826 leaves
**163px spare**, and at a 1280×800 window (726 usable) it leaves **63px spare**. Nothing clips;
nothing scrolls. Any padding you add to the plate comes out of that 63px, so add none.
Set `@media (max-height: 780px)` to drop beat row padding to `18px 0 22px` and the statement to
one line — that buys back 60px for the 720p-laptop crowd.

## 5. The ghost sticker

- 112 × 112, `position: absolute` inside the copy column, `left: -20px`, `top: -136px`, measured from the h1's box top.
- `transform: rotate(-8deg)`. Rotating a 112 square grows its bounds to 126.5 in both axes, hence the −136 offset: **8px of guaranteed clearance above the cap line at every size**, including when the h1 drops to 71.2px.
- Bloom: `filter: drop-shadow(0 18px 28px rgba(255, 96, 224, 0.22))` plus one radial behind it — `radial-gradient(closest-side, rgba(255,130,202,.20), transparent 72%)`, 180px, blurred 26px. One bloom. Not three.
- It hangs **left into the 48px gutter and up above the column**. It never sits beside the first line, never under the `T`, never overlaps the lede. The copy block gets `padding-top: 132px` to reserve the row, so the sticker is optically a sticker and structurally invisible.
- Below 1100px: `position: static; margin: 0 0 20px; transform: rotate(-6deg)` so it stacks and can't collide with anything.
- `animation: hover 6s` stays, but the transform must be written as `rotate(-8deg) translateY(...)` on a wrapper, or the keyframes will overwrite the rotation. Reduced-motion kills the float and keeps the rotation.
- `z-index: 1`, well under the sticky bar's `50`. Never `pointer-events` on the art.

## 6. Spacing scale and where hairlines go

Scale: **4 · 8 · 12 · 16 · 24 · 32 · 48 · 64 · 96 · 132**. Nothing else. No 22, no 34, no 71.

- Gutters 48. Column gaps 56 (plate 1) / 64 (plate 2). Section padding: **none** — the plates own their height, padding inside them is `48px 0`.
- Hairlines exist in exactly three places: the sticky bar's `border-bottom` (`--line-soft`, 0.07), the two beat-row separators + the row above the rail (`--line`, 0.10), and the ticket's own `1px solid var(--line)` edge.
- **No hairline** between the beat group and the ticket (they're columns, the whitespace is the divider), none above plate 1 (the bar already drew it), none around the ticket's inner halves, and none under the pill.
- The ticket is a paper object: `background: var(--card)`, `border-radius: 24px`, `border: 1px solid var(--line)`, `box-shadow: var(--shadow-soft)`. **Drop the pink radial wash and the `backdrop-filter: blur(22px)`** — it's blurring cream onto cream and paying compositor tax for a gradient nobody can see. Screaming at a 1.5px candy border to do the work of a shadow is a failure of nerve.
- Warm only: `--cream`, `--card`, `--paper`, `--ink`, `--ink-soft`, `--ink-mute`. No `#fff`, no `#000`, at any opacity that resolves to them.

## 7. Three things in the current `styles.css` that are wrong

1. **Lines 272–281 — the h1.** `font-size: clamp(3.6rem, 5.4vw, 5.8rem)` caps at **92.8px**, but the column is 544px and "Talk faster than" at 92.8px measures ~610px. It wraps to three ragged lines, and then `text-wrap: balance` (line 280) re-balances the wreck into a wider mess. `letter-spacing: -0.05em` (line 276) at that size is −4.6px per pair — the `Talk` ink traps close. Fix: 80px cap, −0.028em, `<br>`, `text-wrap: initial`.
2. **Lines 619–634 — the price lockup.** `gap: 8px` (line 622) is a fixed gap between a 28px and a 92px glyph, so the air is wrong at every size but one; `0.055em` margins are the fix. `letter-spacing: -0.055em` (line 633) over `29` in proportional figures — the 9 crowds the 2 and it reads like a typo, which is precisely the complaint. And `.cur` at a flat `28px` is a magic number with no relationship to `.amount`. Fix: 0.31em ratio, tabular figures, baseline.
3. **Lines 239–244 — `min-height: calc(100vh - 74px)`.** `vh` is the wrong unit (use `svh`), `min-height` lets plate 1 grow so the hero is *at least* a viewport and then keeps going on a 1280×800 window with the current content, and `align-items: center` with asymmetric `32px / 48px` padding means the optical centre drifts as the copy grows. Compounding it, **no clamp anywhere in the file has a `vh` term** (274, 286, 544, 570, 578, 613, 631) — so a short window shrinks nothing. Then line 697 `margin-top: 96px` on the footer guarantees the two-plate lock breaks. Fix: `height: calc(100svh - 74px)`, vh terms in every clamp, footer inside the rail.

One more, for free: line 140 `font-weight: 650`. The system stack has no 650. It renders as 700 on SF and as synthetic on Segoe. Use 600 or 700 and stop gambling.

## 8. Contract for the implementer

- `prefers-reduced-motion: reduce` → every `animation` and `transform` goes to `0.01ms`; the ghost keeps its rotation, the capsule stops sliding, the bloom stops breathing. Already handled at lines 959–966, keep it and keep it last in the file.
- No webfonts. No `@font-face`. `--sans` and `--mono` only.
- Verify by resizing, not by reading: **1280×800, 1440×900, 1920×1080, 1024×768**. The h1 stays two lines, the lede three, plate 2's rail sits on the fold with nothing below it.

*pours another glass* The page isn't far off, kid. It's just been sizing type off the viewport when it should have been sizing it off the column. Fix the column relationship and the rest of it behaves.
