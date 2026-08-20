# TalkType for Mac

Menu-bar dictation. Click the ghost (or hold ⌥ Right Option anywhere), talk, and the
text pastes into whatever app has focus. On-device via Apple's `SFSpeechRecognizer` —
no API key, no network, no cost.

## Build

```bash
./build.sh          # compiles + signs -> build/TalkType.app
open build/TalkType.app
```

Install with `ditto build/TalkType.app /Applications/TalkType.app`.

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

Hardened runtime (`--options runtime`) is deliberately NOT enabled: it requires a
`com.apple.security.device.audio-input` entitlement and silently kills the mic without
one. Add both together when notarizing.

## Permissions

Microphone and Speech Recognition prompt on first launch. Accessibility must be granted
by hand in System Settings → Privacy & Security → Accessibility — it covers both the
⌥ push-to-talk global monitor and the Cmd+V paste.

## Design

Palette is shared with talktype.app and the browser extension, sourced from
`talktype/src/app.css` and `ghost/gradients.js`. Cream `#fff6e6` paper, warm ink
`#1e1714`, peach ghost gradient. Dark mode inverts to warm near-black — never `#000`.
Ghost assets in `Assets/` are rendered from `talktype/static/talktype-icon.svg`.
