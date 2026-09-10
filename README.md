# TalkType for Mac

Menu-bar dictation with the ghost. Click the ghost (or hold ⌥ Right Option anywhere),
talk, and the text pastes into whatever app has focus.

Three engines, one ghost:

- **Apple on-device** — free, offline, private. No key, no network.
- **Deepgram live** — bring your own key for realtime streaming accuracy.
- **Gemini polish** — optional BYOK pass that rewrites your transcript into clean prose.

English and Spanish, with auto-detect (Deepgram `multi`) or a manual pick.

## Build

```bash
./build.sh direct     # compiles + signs (Developer ID) + builds a notarized-ready DMG
./build.sh mas        # sandboxed App Store target (requires MAS certs)
open build/TalkType.app
```

Install with `ditto build/TalkType.app /Applications/TalkType.app`.

Notarization is wired into `build.sh` (it staples the DMG). It skips gracefully until you
create a notary profile once:

```bash
xcrun notarytool store-credentials "talktype-notary" \
  --apple-id <apple-id-email> --team-id V433H655PN --password <app-specific-password>
```

## Two things that will waste your afternoon if you don't know them

**1. The entry point is explicit, on purpose.** `@main` on an `NSApplicationDelegate`
goes through `NSApplicationMain`, which expects a nib to install the delegate. There is
no nib here, so `applicationDidFinishLaunching` never fires: the app launches, sits
there doing nothing, and shows no menu bar item. `AppDelegate.main()` wires the delegate
by hand instead. Do not "simplify" it back.

**2. Signing is why permissions stick.** TCC remembers an app by its *designated
requirement*. Ad-hoc signing yields `designated => cdhash H"..."` — a hash of the binary
— so every rebuild looks like a brand new app and macOS re-prompts for mic, speech and
accessibility every single time. `build.sh` signs with the Developer ID when it is in
the keychain, giving an identifier + team-ID requirement that survives rebuilds.
Verify with `codesign -d -r- build/TalkType.app`.

Direct distribution uses hardened runtime (`--options runtime`) with the
`com.apple.security.device.audio-input` entitlement — both together, so the mic survives.
The App Store target uses the sandbox entitlements instead.

## Permissions

Microphone and Speech Recognition prompt on first launch. Accessibility must be granted
by hand in System Settings → Privacy & Security → Accessibility — it covers the ⌥
push-to-talk global monitor and the Cmd+V paste. The App Store build compiles that path
out (clipboard-only), since sandboxed apps can't be granted Accessibility.

## Keys & polish

API keys (Deepgram, Gemini) are stored in the Keychain, never in plaintext. A one-time
migration moves any legacy `UserDefaults` key automatically.

## Design

Palette is shared with talktype.app and the browser extension, sourced from
`talktype/src/app.css` and `ghost/gradients.js`. Cream `#fff6e6` paper, warm ink
`#1e1714`, peach ghost gradient. Dark mode inverts to warm near-black — never `#000`.
Ghost assets in `Assets/` are rendered from `talktype/static/talktype-icon.svg`.
