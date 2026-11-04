# TalkType — App Store Connect field sheet

Paste-ready. Everything here matches the **MAS build** (`⌃⌥ Space`, clipboard
delivery, no Accessibility), not the direct DMG. If a field here disagrees with
the app, the app wins and this file gets fixed.

State: paid download, no trial, no StoreKit, no account.

---

## Fields

| Field | Value |
|---|---|
| Name (30 max) | `TalkType: Voice to Text` |
| Subtitle (30 max) | `Say it messy. Get it clean.` |
| Category | Productivity (secondary: Utilities) |
| Keywords (100 max) | `dictation,voice to text,speech to text,transcribe,voice typing,notes,memo,microphone,writing` |
| Support URL | `https://mac.talktype.app/support` |
| Marketing URL | `https://mac.talktype.app/` |
| Privacy policy URL | `https://mac.talktype.app/privacy` |
| Copyright | `2026 Pablo Alvarado` |
| SKU | `talktype-mac` |
| Bundle ID | `com.pibulus.talktype` |
| Price | US$19.99 launch month, then US$29.99 |

**Promotional text** (170 max, editable without a new build)

```
Meet the little ghost in your Mac's menu bar. Hold ⌃⌥ Space, say what you mean, get words you can use.
```

Never put the direct-sale price or a link to mac.talktype.app in any store field:
guideline 3.1.1 treats that as steering buyers outside the store. The promo field
is the one place that can change without a new build.

---

## Description

```
A little ghost lives in your Mac's menu bar and turns speech into clean text, right where the cursor is.

Hold ⌃⌥ Space in any app, speak naturally, and let go. The words land in your clipboard, ready for ⌘V — in Mail, Notes, Slack, Terminal, or anything else that takes text.

THREE ENGINES, ONE GHOST
• Apple on-device — free, offline, and private. Audio never leaves your Mac.
• Deepgram Nova-3 — optional streaming recognition with your own key, for long takes.
• Gemini polish — an optional pass that turns rambling into tidy prose.

BUILT TO STAY OUT OF THE WAY
• Recent transcripts in the menu bar, ready to copy or clear
• Custom vocabulary for names, brands and slang
• English and Spanish, with automatic system-language detection
• One keyboard shortcut, no account, no subscription, no telemetry
• Menu bar only — no Dock icon, no windows to manage

Optional cloud engines use your own API keys. Provider terms and usage charges
may apply, and the audio goes straight from your Mac to that provider.

Made in Melbourne by Pablo.
```

No trial claims, no price comparisons, no links to the direct store.

---

## Review notes

```
TalkType is a menu bar utility (LSUIElement). It has no Dock icon and no main window.

1. Launch the app. A ghost appears in the menu bar; the popover card opens on the right of the menu bar.
2. macOS asks for Microphone access, and for Speech Recognition the first time on-device dictation runs. Both are needed for the built-in engine.
3. Click the ghost (or press ⌃⌥ Space) and speak. Release to finish. The transcript is copied to the clipboard and appears in the History tab. Press ⌘V in any app to use it.
4. Right-click the ghost for settings: voice engine, custom vocabulary, language, privacy policy, quit.
5. No account, no login, no server operated by the developer. Cloud engines (Deepgram, Gemini) are off by default and only run after the user pastes their own API key; audio goes from the Mac directly to that provider.

There is no trial, no purchase flow inside the app, and no external store link.
```

---

## App privacy answers

- **Data collection:** *No, we do not collect data from this app.*
- Nothing reaches a TalkType server (there isn't one), no analytics, no
  identifiers, no tracking.
- Add one nuance in the notes if asked: cloud engines are opt-in, run on the
  user's own provider account, and stay off until a key is entered.

---

## Screenshots

One is enough to submit, five is better. `2880 × 1800` (or `1440 × 900`).

**Recipe for a clean one** (this is the current blocker — the checked-in image
is a bug report):

1. Launch the MAS build, click the ghost.
2. Type a friendly, finished-looking sample into the popover — or dictate one.
3. `⌘⇧4`, then press `Space`, then click the popover. macOS saves it to the
   Desktop as a window shot with a soft shadow.
4. Scale to 2880×1800 on the cream background, keep the copy true to the MAS
   build (`⌃⌥ Space`, "copied to clipboard", never "Right ⌥ Option").

---

## Before submitting

1. Download a Mac App Store provisioning profile for `com.pibulus.talktype` and
   drop it at `TalkType.provisionprofile` (the audit's finding M5).
2. `VERSION=1.0 BUILD_NUMBER=2 ./build.sh mas` — the build number must increase
   on every upload.
3. `xcrun altool --validate-app -f dist/TalkType-1.0.pkg -t macos --apiKey … --apiIssuer …`
4. Upload with Transporter, then fill the fields above.
5. Keep `SQUARE`/direct pricing out of the app and out of this listing.
