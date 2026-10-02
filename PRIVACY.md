# Privacy Policy for TalkType

*Last updated: October 2, 2026*

TalkType is built with a simple, unwavering philosophy: **software should serve humans, not harvest them.**

We do not track you, we do not profile you, we do not run analytics, and we do not store or sell your data. TalkType is designed to run locally on your Mac, respecting your privacy and security at every layer.

---

### 1. Zero Data Collection by Default
- **Local by Default**: TalkType uses Apple's native on-device speech recognition framework (`SFSpeechRecognizer`). Your voice audio is processed locally on your Mac and never leaves your machine.
- **No Analytics / Telemetry**: TalkType contains zero tracking SDKs, telemetry beacons, crash reporters, or advertising networks.
- **Local History**: Your transcription history is stored solely on your device in your local macOS application container (`UserDefaults`). It is never synced to any remote server by TalkType. You can clear this history at any time with a single click.

---

### 2. Optional Third-Party Services (Bring Your Own Key - BYOK)
TalkType allows you to optionally enhance your experience with cloud providers. These services are strictly **opt-in** and require you to provide your own API keys:

1. **Deepgram (Nova-3 Speech Streaming)**
   - If you choose to configure a Deepgram API key, audio is streamed directly and securely via HTTPS/WSS to Deepgram's API (`api.deepgram.com`) for real-time transcription.
   - **Zero Model Training**: TalkType explicitly sends `mip_opt_out=true` with every WebSocket session, ensuring Deepgram does not use your audio or transcripts for model training or data logging.
   - For Deepgram's privacy terms, visit [deepgram.com/privacy](https://deepgram.com/privacy).

2. **Google Gemini (AI Text Polishing)**
   - If you choose to configure a Google Gemini API key to polish transcripts into formatted prose, the raw transcribed text is sent securely to Google's Generative AI API.
   - For Google's AI privacy practices, visit [policies.google.com/privacy](https://policies.google.com/privacy).

---

### 3. Secure Key Storage (macOS Keychain)
All user-provided API keys (Deepgram, Gemini) are stored strictly inside your private **macOS Keychain** (`kSecClassGenericPassword`), protected by your system password and hardware encryption. TalkType never transmits your credentials anywhere other than the respective official API endpoints.

---

### 4. System Permissions
TalkType requests the minimum necessary permissions to function:
- **Microphone (`NSMicrophoneUsageDescription`)**: Required exclusively to capture your voice during active dictation. Audio is only accessed while recording is initiated by you.
- **Speech Recognition (`NSSpeechRecognitionUsageDescription`)**: Required for Apple Speech on-device transcription.
- **Accessibility (Direct Distribution Build only)**: Optional in the direct distribution build solely to insert text via simulated keystroke (`⌘V`) into your frontmost application upon release. The Mac App Store build does not use Accessibility and copies directly to your clipboard.

---

### 5. Open Contact
TalkType is created by Pablo Alvarado. If you have questions about privacy, security, or the codebase, contact:
- **GitHub**: [github.com/pibulus/talktype-mac](https://github.com/pibulus/talktype-mac)
- **Web**: [quickcat.club](https://quickcat.club)
