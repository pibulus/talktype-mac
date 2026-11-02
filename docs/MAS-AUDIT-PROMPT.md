# Mac App Store readiness audit — the prompt

Paste the block below into a fresh agent session started in
`~/Projects/active/mac/talktype-mac`. It is written to make the auditor prove
things with commands instead of trusting this repo's docs.

---

You are a macOS release engineer and App Review specialist doing a pre-submission
audit of TalkType for Mac.

**Repo:** `~/Projects/active/mac/talktype-mac`
**Shape:** one 226k-line Swift file (`TalkType.swift`), a hand-rolled `build.sh`
with two lanes (`direct` = Developer ID + notarized DMG, `mas` = sandboxed pkg),
SwiftUI regression tests in `Tests/`, a static marketing site in `site/`.
**Bundle:** `com.pibulus.talktype` · **Team:** V433H655PN · **App:** LSUIElement
menu-bar utility, no Dock icon.

## The goal

One source tree, two shippable artifacts:

1. a notarized DMG that Gatekeeper opens cleanly, sold directly; and
2. a Mac App Store `.pkg` that passes App Review on the first submission.

## Ground rules

- **Reality beats docs.** Every claim needs a command and its output. If a doc,
  a README or a comment disagrees with the binary, plist or a `curl`, report the
  binary and flag the doc as wrong.
- **Read-only on Apple systems.** Never upload, submit, create certificates,
  change App Store Connect state, or delete an existing `build/` or `dist/`
  artifact. Build in a copy (`rsync` to a temp dir) if a clean build is needed.
- **Classify every finding:** `BLOCKER` (submission or launch fails),
  `REVIEW RISK` (may be rejected), `HYGIENE` (should fix, will not block).
- **Report before editing.** Then propose the minimal diff per finding. Fix only
  after I say go, except for factual errors in metadata.
- Nothing in `Marketing/`, `APP_STORE_LISTING_DRAFT.md` or old homework files
  counts as evidence. They are months old and at least one is wrong.

## Audit A — artifacts (run these, paste real output)

1. `bash Tests/run-regressions.sh` — list every PASS/FAIL. Note that the suite
   mocks Keychain, signing tools and sockets; say what it therefore cannot prove.
2. In a temp copy:
   - `UNIVERSAL=1 ./build.sh mas` and `UNIVERSAL=1 ./build.sh direct`
   - If a lane cannot run (missing cert, notary profile, Apple agreement),
     report the exact gate that stopped it rather than skipping silently.
3. Inspect both artifacts:
   - `codesign -dv --verbose=4` and `--entitlements -` on app and pkg contents
   - `codesign --verify --deep --strict --verbose=2` (app and DMG)
   - `spctl -a -vvv -t open --context context:primary-signature dist/*.dmg`
   - `xcrun stapler validate` on the app and the DMG
   - `pkgutil --check-signature`, `pkgutil --payload-files`, `pkgutil --expand`
   - `lipo -archs`; `otool -l | grep -A4 LC_BUILD_VERSION` for the min OS
4. Compare the MAS Info.plist key by key against what App Store Connect and
   `altool --validate-app` expect. Call out anything missing, plus any key whose
   value is a lie (wrong SDK, wrong copyright, wrong category).
5. Confirm the sandbox is real, not just declared: install the MAS build, run it,
   and stream `log stream --predicate 'process == "TalkType"'` while exercising
   dictation. Look for sandbox denials. Then confirm the MAS binary contains no
   calls to Accessibility or synthetic-key APIs by grepping the source for
   `AXIsProcessTrusted`, `CGEvent`, `addGlobalMonitorForEvents` and checking each
   hit sits behind `#if !MAS_BUILD`.
6. **Privacy manifest vs actual API use.** Grep for every required-reason API
   (`ProcessInfo.systemUptime`, file timestamps, disk space, active keyboard,
   UserDefaults) and confirm `PrivacyInfo.xcprivacy` declares a valid reason for
   each. Known suspicion: the app measures buffer timing with
   `ProcessInfo.processInfo.systemUptime` but the manifest only declares
   UserDefaults — verify and say whether `NSPrivacyAccessedAPICategorySystemBootTime`
   (reason 35F9.1) is missing.
7. Privacy nutrition label vs real data flow: audio to Apple / Deepgram / Gemini,
   the user's own keys, no telemetry, no account. Say exactly what the label must
   declare and where the app's behaviour makes that answer arguable.
8. MAS review risks, checked against the actual build:
   - any outbound "buy it cheaper outside" link or copy in the MAS binary
     (`strings` the binary; the About/privacy links are allowed, a store link is not)
   - trial/unlock language with no StoreKit
   - private API use, auto-updaters, Sparkle, analytics SDKs
   - whether a menu-bar-only app with no Dock icon still gives a way to quit
   - guideline 4.2 (minimum functionality) — is "three engines + history +
     vocabulary" enough of a product to survive that judgement?
9. Functional smoke test on the MAS build: mic, Speech Recognition, on-device
   availability path, `⌃⌥ Space` registration and conflict handling, clipboard
   delivery, History, quit/relaunch. Separate what a machine can prove from a
   short manual script for the parts that need hands.

## Audit B — store presence

10. Screenshots: current file is `screenshots/appstore-2880x1800.png`. Judge
    whether it is submit-ready — size, text legibility, whether it shows the app
    honestly, and whether the transcript content is appropriate for a store page.
11. Metadata: name, subtitle, category, keywords, description, support URL,
    privacy URL, copyright. `curl -sI` every URL and report the status codes.
    Confirm the description contains no trial claims the build cannot honour.
12. Versioning: confirm `CFBundleVersion` increments for every upload and the
    marketing version matches `version.json` on the site.
13. The direct-sale lane: confirm the DMG on `talktype.app/downloads/` is the
    build this repo produces (`shasum` the downloaded file against a fresh build),
    and that `site/version.json` agrees.

## What to report back

- A table: `ID · severity · what is wrong · file:line or artifact · how it was proven`.
- **GO / NO-GO for each lane**, with the exact blocker list.
- The five highest-value fixes, ordered, each with the smallest diff that closes it.
- A copy-paste "submit day" runbook: the commands in order, what success looks
  like at each step, and where a human must be in the loop (Transporter, App Store
  Connect, the review notes field).
- Anything that could not be verified, and why.

## Context to verify, not to trust

- Both lanes are believed to build today: `Developer ID Application`,
  `Apple Distribution` and `3rd Party Mac Developer Installer` identities are in
  the login keychain, and a `talktype-notary` keychain profile exists.
- The MAS build ships **no provisioning profile**; `build.sh` claims basic
  sandbox entitlements do not require one. Confirm whether Apple agrees, in the
  specific case of an `Apple Distribution`-signed sandboxed app.
- The build uses `swiftc` directly — no Xcode project, no asset catalog, one
  `.icns`. Confirm the pkg structure is acceptable without an Xcode archive.
- The app is compiled with `-target arm64-apple-macos13.0` / `x86_64-apple-macos13.0`
  and hand-written `DTSDK*` / `DTXcode*` keys. Say whether fabricated toolchain
  keys are harmless or a validation risk.
- **Known drift to resolve:** the App Store review notes claim the popover opens
  on launch and re-opens when launched from Finder. Launching
  `build/TalkType.app` twice shows the menu bar ghost but no popover, and
  `grep hasLaunchedBefore TalkType.swift` finds nothing. Decide: fix the app or
  fix the review notes, then say which.
- `PrivacyInfo.xcprivacy` was just extended with
  `NSPrivacyAccessedAPICategorySystemBootTime` (35F9.1) for the
  `ProcessInfo.systemUptime` calls. Confirm that is the correct reason code and
  that no other required-reason API is undeclared.
- `build.sh` deletes `build/` and `dist/` at the start of every run. Do not run
  it in the real checkout without preserving existing artifacts first.
