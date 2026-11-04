# TalkType — App Store Connect field sheet

Paste-ready. Everything here matches the **MAS build** (`⌃⌥ Space`, popover click-to-start / click-again-to-finish, `Escape` to cancel, clipboard delivery, zero Accessibility), not the direct DMG. If a field here disagrees with the app, the app wins and this file gets fixed.

State: paid download, no trial, no StoreKit, no account, zero external purchase links.

---

## Fields

| Field | Value |
|---|---|
| Name (30 max) | `TalkType: Voice to Text` |
| Subtitle (30 max) | `Say it messy. Get it clean.` |
| Category | Productivity (secondary: Utilities) |
| Keywords (100 max) | `dictation,voice to text,speech to text,transcribe,voice typing,notes,memo,microphone,writing` |
| Support URL | `https://mac.talktype.app/appstore-support` |
| Marketing URL | *(leave blank in App Store Connect — avoids Guideline 3.1.1 cross-link)* |
| Privacy policy URL | `https://mac.talktype.app/appstore-privacy` |
| Copyright | `2026 Pablo Alvarado` |
| SKU | `talktype-mac` |
| Bundle ID | `com.pibulus.talktype` |
| Price | US$19.99 launch month, then US$29.99 |

**Promotional text** (170 max, editable without a new build)

```
A little ghost in the Mac menu bar turns speech into clean text. Hold ⌃⌥ Space, speak naturally, release, and press ⌘V anywhere.
```

Never put the direct-sale price, `mac.talktype.app/`, or `talktype.app` in any store field: Guideline 3.1.1 treats cross-links to external checkout pages as steering buyers outside the App Store. Leaving **Marketing URL** blank and routing **Support URL** + **Privacy policy URL** to the quarantined `/appstore-support` and `/appstore-privacy` pages keeps App Review clean.

---

## Description

```
A little ghost lives in the Mac menu bar and turns speech into clean text, ready wherever the cursor sits.

Hold ⌃⌥ Space in any app, speak naturally, and let go — or click the ghost in the menu bar popover to talk and click again to finish. Finished words land straight on the clipboard, ready for ⌘V in Mail, Notes, Slack, Terminal, or any text field. Press Escape mid-take to cancel cleanly.

THREE ENGINES, ONE GHOST
- Apple on-device — built in, offline, and private. Audio stays on the Mac.
- Deepgram Nova-3 — optional real-time streaming recognition with a personal API key, great for long takes and multi-speaker notes.
- Gemini prose polish — optional pass with a personal API key that turns rough rambling into tidy paragraphs.

BUILT TO STAY OUT OF THE WAY
- Recent takes saved locally in History (up to 50), ready to copy, export to plain text, or clear
- Custom vocabulary and phonetic replacement rules for names, brands, and jargon
- English and Spanish, with automatic system-language detection or one-click switching
- Optional Launch at Login from the menu bar
- Menu bar only — no Dock icon, no window clutter, no account, no subscription, no telemetry

Optional cloud engines stay off by default and use personal API keys stored in the macOS Keychain. Provider terms and usage charges may apply, and audio or text travels directly from the Mac to that provider.

Made in Melbourne by Pablo.
```

No trial claims, no price comparisons, no `"AI"` buzzwords, no links to external stores.

---

## Review notes

```
TalkType is a menu bar utility (LSUIElement). It has no Dock icon and no main window.

1. Launch TalkType. A ghost icon appears in the macOS menu bar and the popover card opens automatically beneath it.
2. macOS requests Microphone access, plus Speech Recognition access the first time on-device dictation runs. Both are required for the built-in offline engine. Accessibility permission is neither requested nor used.
3. Two ways to dictate:
   a) Keyboard shortcut: Hold ⌃⌥ Space in any app, speak, and release to finish (or quick-tap ⌃⌥ Space to enter hands-free mode, then tap ⌃⌥ Space again to finish).
   b) Popover ghost: Click the ghost inside the popover to start listening, speak, and click the ghost again to finish.
   Press Escape at any time while listening to cancel a take cleanly without copying or saving partial text.
   When finished, the transcript is copied to the clipboard ("Copied to clipboard — Press ⌘V to paste!") and saved in the History tab. Press ⌘V in any app (e.g., Notes or TextEdit) to paste.
4. Right-click the menu bar ghost for settings: Voice Mode, Conversations, Auto-Polish, Custom Vocabulary, Language (English / Español), Left/Right Click behavior, HUD Position, Launch at Login, Setup Guide, Privacy Policy, Clear History…, and Quit.
5. No account, no login, and no server operated by the developer. Optional cloud engines (Deepgram Nova-3, Google Gemini) are off by default and only run after an API key is pasted into the macOS Keychain; requests travel directly from the Mac to that provider.

There is no trial, no purchase flow inside the app, and no external store link.
```

---

## App privacy answers

- **Data collection:** *No, we do not collect data from this app.*
- Nothing reaches a TalkType server (there isn't one), no analytics, no identifiers, no tracking.
- Nuance for internal review notes if asked: optional BYOK cloud engines stay disabled unless the owner enters a personal Deepgram or Google Gemini API key in the macOS Keychain, and requests go directly from the Mac to that provider (`mip_opt_out=true` on Deepgram streams).

---

## Screenshots

Generated deterministically at exact `2880 × 1800` Retina resolution via `swift scripts/generate-mas-screenshots.swift`:

- `screenshots/appstore/01-dictate-anywhere-2880x1800.png` (also copied to `screenshots/appstore-2880x1800.png`) — Live popover card + floating HUD capsule, `⌃⌥ Space`, `"Copied to clipboard — Press ⌘V to paste!"`
- `screenshots/appstore/02-history-and-vocabulary-2880x1800.png` — Local 50-take History tab, one-click Copy pills, and Custom Vocabulary phonetic rules (`doctype -> TalkType`)
- `screenshots/appstore/03-private-on-device-2880x1800.png` — Offline Apple Neural Engine by default, macOS Keychain BYOK options, bilingual EN / ES, zero telemetry

All screenshots use warm Flexoki cream (`#fffef7` / `#fbf1e4`) and warm sepia ink (`#1e1714`), open-eyed ghost art, and 100% MAS-true copy.

---

## Before submitting

1. **Deploy `site/` to Netlify first (`https://mac.talktype.app`)** so the quarantined App Store pages are live before App Review tests them:
   - Verify `curl -sI https://mac.talktype.app/appstore-support` → `200`
   - Verify `curl -sI https://mac.talktype.app/appstore-privacy` → `200`
   - Confirm zero links on either page to `/`, `/buy`, Square, or `.dmg`.
2. **Provisioning profile (`TalkType.provisionprofile`)**:
   - Standard sandbox entitlements (`app-sandbox`, `device.audio-input`, `network.client`) sign cleanly with `Apple Distribution`.
   - **TestFlight for Mac** (and profile-gated App Store Connect checks) requires a **Mac App Store Connect** provisioning profile for `com.pibulus.talktype` saved at `./TalkType.provisionprofile` before building. `build.sh mas` automatically embeds it as `Contents/embedded.provisionprofile` and runs `xattr -cr` before signing so downloaded profiles never trigger `ITMS-91109` (`com.apple.quarantine`).
3. **Build the signed installer `.pkg`** (the Mac App Store counterpart to the direct `.dmg` — Transporter accepts signed flat `.pkg` installers for macOS apps):
   ```bash
   VERSION=1.0 BUILD_NUMBER=2 ./build.sh mas
   pkgutil --check-signature dist/mas/TalkType-1.0.pkg
   ```
   *(Increment `BUILD_NUMBER` on every upload to App Store Connect.)*
4. **Validate & upload**:
   ```bash
   xcrun altool --validate-app -f dist/mas/TalkType-1.0.pkg -t macos --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
   ```
   Or drag `dist/mas/TalkType-1.0.pkg` into **Transporter.app** and click **Deliver**, then paste the fields above into App Store Connect (leaving **Marketing URL** blank).
