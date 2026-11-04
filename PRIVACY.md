# Privacy Policy for TalkType

*Last updated: November 4, 2026*

TalkType is built on one rule: **software serves humans, never harvests them.**

There is no tracking, no profiling, no analytics SDK, no account system, and no TalkType server. Everything stays on the Mac by default.

---

### 1. Zero Data Collection by Default
- **On-Device by Default**: TalkType uses Apple's native on-device speech recognition framework (`SFSpeechRecognizer`) with `requiresOnDeviceRecognition = true`. Voice audio is processed locally on the Mac's Neural Engine and never leaves the machine.
- **No Analytics or Telemetry**: Zero tracking SDKs, telemetry beacons, crash-reporting third parties, or advertising identifiers.
- **Local History**: Up to 50 recent transcripts, custom vocabulary, and preferences live strictly inside the local macOS application container (`UserDefaults`). History can be exported to plain text or cleared at any time.

---

### 2. Optional Cloud Engines (Bring Own Key)
Optional cloud engines stay disabled by default and run only after a personal API key is saved in the macOS Keychain:

1. **Deepgram Nova-3 (Streaming Recognition)**
   - Audio streams over encrypted WSS directly from the Mac to `api.deepgram.com`.
   - Every session passes `mip_opt_out=true` so audio and transcripts are excluded from model training.
   - Deepgram privacy policy: [deepgram.com/privacy](https://deepgram.com/privacy)

2. **Google Gemini (Prose Polish)**
   - Finished transcript text is sent over HTTPS directly from the Mac to `generativelanguage.googleapis.com` to clean grammar and punctuation.
   - Google privacy policy: [policies.google.com/privacy](https://policies.google.com/privacy)

---

### 3. macOS Keychain Storage
Personal API keys (Deepgram, Gemini) are stored solely in the local **macOS Keychain** (`kSecClassGenericPassword`) under `com.pibulus.talktype` and are transmitted only in the authentication header of the respective provider endpoint.

---

### 4. System Permissions
- **Microphone (`NSMicrophoneUsageDescription`)**: Captures voice audio exclusively while an active dictation take is running.
- **Speech Recognition (`NSSpeechRecognitionUsageDescription`)**: Required by macOS for Apple on-device speech recognition.
- **Accessibility (Direct Website DMG only)**: Used in the direct notarized DMG build for global modifier push-to-talk and synthetic `⌘V` paste into the active app. The Mac App Store build never links or requests Accessibility; it uses Carbon `⌃⌥ Space` and copies transcripts to the clipboard.

---

### 5. Contact & Canonical Pages
- **Mac App Store Privacy Page**: [mac.talktype.app/appstore-privacy](https://mac.talktype.app/appstore-privacy)
- **Direct Build Privacy Page**: [mac.talktype.app/privacy](https://mac.talktype.app/privacy)
- **Support Email**: [pibulus@gmail.com](mailto:pibulus@gmail.com)
