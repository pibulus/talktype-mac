import Cocoa
import SwiftUI
import Speech
import AVFoundation
import ApplicationServices
import Security
import Carbon
import ServiceManagement

// MARK: - PTT Shortcut Trigger Options (Full Keyboard & Mobility Accessibility)
//
// Two families of trigger:
//   • Modifier-only keys (Right ⌥, Left ⌥, fn, Right ⌘) — watched through NSEvent global
//     monitors, which macOS only delivers once the app is trusted for Accessibility.
//   • Carbon hot key (⌃⌥ Space) — registered with RegisterEventHotKey. Works everywhere,
//     including the sandboxed App Store build, with zero permissions.
enum PTTTrigger: String, CaseIterable, Identifiable {
    case rightOption = "rightOption"
    case leftOption = "leftOption"
    case eitherOption = "eitherOption"
    case function = "function"
    case rightCommand = "rightCommand"
    case ctrlOptionSpace = "ctrlOptionSpace"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rightOption: return "Right ⌥ Option"
        case .leftOption: return "Left ⌥ Option"
        case .eitherOption: return "Either ⌥ Option"
        case .function: return "Globe / Function (fn) 🌐"
        case .rightCommand: return "Right ⌘ Command"
        case .ctrlOptionSpace: return "⌃⌥ Space (" + L10n.t("worksEverywhere") + ")"
        }
    }

    var shortTitle: String {
        switch self {
        case .rightOption: return "Right ⌥ Option"
        case .leftOption: return "Left ⌥ Option"
        case .eitherOption: return "Either ⌥ Option"
        case .function: return "Globe / fn 🌐"
        case .rightCommand: return "Right ⌘ Command"
        case .ctrlOptionSpace: return "⌃⌥ Space"
        }
    }

    /// The compact glyph used in the HUD hint and onboarding.
    var glyph: String {
        switch self {
        case .rightOption, .leftOption, .eitherOption: return "⌥"
        case .function: return "🌐"
        case .rightCommand: return "⌘"
        case .ctrlOptionSpace: return "⌃⌥␣"
        }
    }

    /// True for triggers driven by a Carbon hot key instead of modifier monitoring.
    var usesCarbonHotKey: Bool { self == .ctrlOptionSpace }

    /// True for triggers that need Accessibility trust before macOS delivers them globally.
    var needsAccessibility: Bool { !usesCarbonHotKey }

    /// The modifier flag this trigger is built from (nil for Carbon hot keys).
    var modifierFlag: NSEvent.ModifierFlags? {
        switch self {
        case .rightOption, .leftOption, .eitherOption: return .option
        case .function: return .function
        case .rightCommand: return .command
        case .ctrlOptionSpace: return nil
        }
    }

    /// Interprets a flagsChanged event.
    /// Returns nil when the event is not about this trigger's key, true on press, false on release.
    /// A press only counts when the trigger is the ONLY modifier held, so ⌥⌘I or ⌥e never
    /// start a recording by accident. Caps Lock state is ignored.
    func matches(event: NSEvent) -> Bool? {
        let keyCodes: Set<UInt16>
        switch self {
        case .rightOption: keyCodes = [61]
        case .leftOption: keyCodes = [58]
        case .eitherOption: keyCodes = [58, 61]
        case .function: keyCodes = [63]
        case .rightCommand: keyCodes = [54]
        case .ctrlOptionSpace: return nil
        }
        guard keyCodes.contains(event.keyCode), let flag = modifierFlag else { return nil }

        let held = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        if held.contains(flag) {
            // Press: must be exclusive (no other modifier riding along).
            return held == flag ? true : nil
        }
        return false
    }

    /// Reads the live hardware modifier state. Used to recover when a key-up event was
    /// swallowed by a modal dialog, a secure text field, or a Space switch.
    var isPhysicallyDown: Bool {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch self {
        case .ctrlOptionSpace: return flags.contains(.control) && flags.contains(.option)
        default:
            guard let flag = modifierFlag else { return false }
            return flags.contains(flag)
        }
    }
}
// MARK: - Transcription Language
enum TranscriptionLanguage: String, CaseIterable {
    case auto
    case en
    case es

    var title: String {
        switch self {
        case .auto: return L10n.t("auto")
        case .en: return L10n.t("english")
        case .es: return L10n.t("spanish")
        }
    }

    var appleLocale: Locale {
        switch self {
        case .auto:
            let isSpanish = Locale.current.identifier.starts(with: "es") || Locale.preferredLanguages.first?.starts(with: "es") == true
            if isSpanish {
                return Locale.current.identifier.starts(with: "es") ? Locale.current : Locale(identifier: "es-ES")
            }
            return Locale(identifier: "en-US")
        case .en: return Locale(identifier: "en-US")
        case .es:
            if Locale.current.identifier.starts(with: "es") {
                return Locale.current
            }
            return Locale(identifier: "es-ES")
        }
    }

    var deepgramLanguage: String {
        switch self {
        case .auto:
            let isSpanish = Locale.current.identifier.starts(with: "es") || Locale.preferredLanguages.first?.starts(with: "es") == true
            return isSpanish ? "es" : "en"
        case .en: return "en"
        case .es: return "es"
        }
    }
}

// MARK: - Localization
enum L10n {
    static func t(_ key: String) -> String {
        let isSpanish = TalkTypeConfig.language == .es || (TalkTypeConfig.language == .auto && (Locale.current.identifier.starts(with: "es") || Locale.preferredLanguages.first?.starts(with: "es") == true))
        let lang = isSpanish ? "es" : "en"
        return strings[key]?[lang] ?? strings[key]?["en"] ?? key
    }

    static let strings: [String: [String: String]] = [
        "auto": ["en": "Auto-detect", "es": "Detección automática"],
        "english": ["en": "English", "es": "Inglés"],
        "spanish": ["en": "Spanish", "es": "Español"],
        "language": ["en": "Language", "es": "Idioma"],
        "accessibilityDisabled": ["en": "⚠️ Accessibility Disabled (Click to Enable ⌘V)", "es": "⚠️ Accesibilidad desactivada (Clic para activar ⌘V)"],
        "copyLast": ["en": "Copy Last", "es": "Copiar último"],
        "noRecentTranscripts": ["en": "No Recent Transcripts", "es": "Sin transcripciones recientes"],
        "recentTranscripts": ["en": "Recent Transcripts", "es": "Transcripciones recientes"],
        "historyEmpty": ["en": "History empty", "es": "Historial vacío"],
        "pushToTalkKey": ["en": "Push to Talk Key", "es": "Tecla pulsar para hablar"],
        "transcriptionEngine": ["en": "Transcription Engine", "es": "Motor de transcripción"],
        "appleSpeech": ["en": "Apple Speech (On-Device, Offline)", "es": "Voz de Apple (en el dispositivo, sin conexión)"],
        "deepgramNova": ["en": "Deepgram Nova-3 (Live Streaming)", "es": "Deepgram Nova-3 (transmisión en vivo)"],
        "hudPosition": ["en": "HUD Position", "es": "Posición del HUD"],
        "bottomOfScreen": ["en": "Bottom of Screen", "es": "Parte inferior de la pantalla"],
        "topOfScreen": ["en": "Top of Screen", "es": "Parte superior de la pantalla"],
        "deepgramApiKey": ["en": "Deepgram API Key…", "es": "Clave de API de Deepgram…"],
        "quit": ["en": "Quit TalkType", "es": "Salir de TalkType"],
        "dgAlertTitle": ["en": "Deepgram API Key (Optional BYOK)", "es": "Clave de API de Deepgram (BYOK Opcional)"],
        "dgAlertInfo": ["en": "TalkType uses on-device Apple Speech by default (100% private, zero setup). Optionally add a Deepgram API key for cloud streaming Nova-3 transcription. Free tier available at console.deepgram.com.", "es": "TalkType usa la voz en el dispositivo de Apple por defecto (100% privada, sin configuración). Opcionalmente añade una clave de Deepgram para transcripción Nova-3 en la nube. Nivel gratuito en console.deepgram.com."],
        "save": ["en": "Save", "es": "Guardar"],
        "getKey": ["en": "Get a Deepgram Key…", "es": "Obtener clave de Deepgram…"],
        "cancel": ["en": "Cancel", "es": "Cancelar"],
        "pasteKey": ["en": "Paste Deepgram API key", "es": "Pegar clave de API de Deepgram"],
        "listeningSpeak": ["en": "Listening… speak freely", "es": "Escuchando… habla con libertad"],
        "listening": ["en": "Listening…", "es": "Escuchando…"],
        "live": ["en": "Live", "es": "En vivo"],
        "history": ["en": "History", "es": "Historial"],
        "holdGhost": ["en": "Hold the ghost to start talking…", "es": "Mantén el fantasma para empezar a hablar…"],
        "clickGhostHold": ["en": "Click ghost or hold ", "es": "Haz clic en el fantasma o mantén "],
        "noTranscriptsSaved": ["en": "No transcripts saved yet.", "es": "Aún no hay transcripciones guardadas."],
        "copy": ["en": "Copy", "es": "Copiar"],
        "copied": ["en": "Copied!", "es": "¡Copiado!"],
        "clearHistory": ["en": "Clear History", "es": "Borrar historial"],
        "copiedToClipboard": ["en": "Copied to clipboard — Press ⌘V to paste! 📋", "es": "Copiado al portapapeles — ¡Pulsa ⌘V para pegar! 📋"],
        "polishing": ["en": "Polishing…", "es": "Puliendo…"],
        "polishOutput": ["en": "Polish Output (Gemini)", "es": "Pulir texto (Gemini)"],
        "geminiApiKey": ["en": "Gemini API Key…", "es": "Clave de API de Gemini…"],
        "pasteGeminiKey": ["en": "Paste Gemini API key", "es": "Pegar clave de API de Gemini"],
        "geminiAlertTitle": ["en": "Gemini API Key (Optional BYOK)", "es": "Clave de API de Gemini (BYOK Opcional)"],
        "geminiAlertInfo": ["en": "TalkType operates completely standalone. Optionally add a Gemini API key to polish transcripts into clean prose. Free keys available at aistudio.google.com.", "es": "TalkType funciona de forma completamente independiente. Opcionalmente añade una clave de Gemini para pulir transcripciones. Claves gratuitas en aistudio.google.com."],
        "customKeywords": ["en": "Custom Vocabulary…", "es": "Vocabulario personalizado…"],
        "keywordsAlertTitle": ["en": "Custom Vocabulary & Keywords", "es": "Vocabulario y palabras clave"],
        "keywordsAlertInfo": ["en": "Add words or names speech recognition should prioritize (comma-separated, e.g. TalkType, pibulus, NoteBro). You can also use 'wrong -> right' rules (e.g. doctype -> TalkType).", "es": "Añade palabras que el reconocimiento de voz deba priorizar (separadas por comas, ej. TalkType, pibulus). También puedes usar reglas 'error -> corrección'."],
        "delete": ["en": "Delete", "es": "Eliminar"],
        "worksEverywhere": ["en": "works everywhere", "es": "funciona en todas partes"],
        "tapToLock": ["en": "Tap to Lock (hands-free)", "es": "Toque para fijar (manos libres)"],
        "launchAtLogin": ["en": "Launch at Login", "es": "Abrir al iniciar sesión"],
        "welcomeGuide": ["en": "Welcome Guide…", "es": "Guía de bienvenida…"],
        "lockedHint": ["en": "Hands-free — tap the key again to finish", "es": "Manos libres — toca la tecla otra vez para terminar"],
        "cancelled": ["en": "Cancelled", "es": "Cancelado"],
        "micDenied": ["en": "Microphone access is off — enable it in System Settings → Privacy & Security", "es": "El micrófono está desactivado — actívalo en Ajustes del Sistema → Privacidad y seguridad"],
        "speechDenied": ["en": "Speech Recognition is off — enable it in System Settings → Privacy & Security", "es": "El reconocimiento de voz está desactivado — actívalo en Ajustes del Sistema"],
        "speechUnavailable": ["en": "Speech recognition is unavailable for this language right now", "es": "El reconocimiento de voz no está disponible para este idioma ahora"],
        "audioFailed": ["en": "Couldn't open the microphone — is another app using it?", "es": "No se pudo abrir el micrófono — ¿lo está usando otra app?"],
        "accessibilityHint": ["en": "Grant Accessibility for the hotkey + auto-paste", "es": "Concede Accesibilidad para el atajo y pegado automático"],
        "onbWelcomeTitle": ["en": "Meet the ghost", "es": "Conoce al fantasma"],
        "onbWelcomeBody": ["en": "Hold a key, talk, let go. Your words land wherever your cursor is. No account, no cloud, nothing leaves your Mac.", "es": "Mantén una tecla, habla, suelta. Tus palabras aparecen donde esté tu cursor. Sin cuenta, sin nube, nada sale de tu Mac."],
        "onbPickKey": ["en": "Pick your push-to-talk key", "es": "Elige tu tecla de pulsar para hablar"],
        "onbFnTip": ["en": "Tip: set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.", "es": "Consejo: en Ajustes del Sistema → Teclado → “Al pulsar 🌐” elige No hacer nada."],
        "onbPermsTitleThree": ["en": "Three quick permissions", "es": "Tres permisos rápidos"],
        "onbPermsBody": ["en": "TalkType only listens while you hold the key. Everything is processed on your Mac.", "es": "TalkType solo escucha mientras mantienes la tecla. Todo se procesa en tu Mac."],
        "onbMic": ["en": "Microphone", "es": "Micrófono"],
        "onbMicWhy": ["en": "To hear you", "es": "Para escucharte"],
        "onbSpeech": ["en": "Speech Recognition", "es": "Reconocimiento de voz"],
        "onbSpeechWhy": ["en": "On-device transcription", "es": "Transcripción en el dispositivo"],
        "onbAX": ["en": "Accessibility", "es": "Accesibilidad"],
        "onbAXWhy": ["en": "Modifier hotkeys + pasting into apps", "es": "Atajos de modificador + pegar en apps"],
        "onbAXNote": ["en": "Skip it and TalkType still works: text goes to your clipboard, ⌘V to paste. ⌃⌥ Space needs no permission.", "es": "Si lo omites, TalkType igual funciona: el texto va al portapapeles, ⌘V para pegar. ⌃⌥ Espacio no necesita permiso."],
        "onbGranted": ["en": "Granted", "es": "Concedido"],
        "onbDenied": ["en": "Denied", "es": "Denegado"],
        "onbAllow": ["en": "Allow", "es": "Permitir"],
        "onbOpenSettings": ["en": "Open Settings", "es": "Abrir ajustes"],
        "onbTryTitle": ["en": "Say something", "es": "Di algo"],
        "onbTryBody": ["en": "Hold your key right now and talk. Let go when you're done.", "es": "Mantén tu tecla ahora y habla. Suelta cuando termines."],
        "onbTryEmpty": ["en": "Waiting for your voice…", "es": "Esperando tu voz…"],
        "onbNext": ["en": "Next", "es": "Siguiente"],
        "onbBack": ["en": "Back", "es": "Atrás"],
        "onbDone": ["en": "Let's go", "es": "¡Vamos!"],
        "onbSkip": ["en": "Skip", "es": "Omitir"],
        "onbMenubarHint": ["en": "TalkType lives in your menu bar. Right-click the ghost for settings.", "es": "TalkType vive en tu barra de menús. Clic derecho en el fantasma para ajustes."]
    ]
}

// MARK: - Constants & Config
enum TalkTypeConfig {
    // Legacy UserDefaults key (pre-Keychain). Kept only for one-time migration.
    static let deepgramKeyStorageKey = "deepgramApiKey"
    static let engineStorageKey = "talktypeEngine" // "apple" (default) or "deepgram"
    static let hudPositionStorageKey = "hudPosition" // "bottom" or "top"
    static let historyStorageKey = "talktypeHistory"
    static let pttTriggerStorageKey = "talktypePttTrigger"
    static let languageStorageKey = "talktypeLanguage"
    static let customKeywordsStorageKey = "talktypeCustomKeywords"
    static let tapToLockStorageKey = "talktypeTapToLock"
    static let onboardedStorageKey = "talktypeHasOnboarded"

    /// Longest a single dictation may run before TalkType finishes it on its own.
    static let maxRecordingSeconds: TimeInterval = 300
    /// A press-and-release shorter than this counts as a tap (hands-free lock) when enabled.
    static let tapLockWindow: TimeInterval = 0.35

    // Keychain location for the Deepgram API key.
    static let keychainService = "com.pibulus.talktype"
    static let keychainAccount = "deepgramApiKey"
    static let keychainAccountGemini = "geminiApiKey"
    static let polishStorageKey = "talktypePolish"
    static let geminiModel = "gemini-flash-latest"

    static var deepgramApiKey: String {
        if let key = KeychainHelper.read(service: keychainService, account: keychainAccount) {
            return key
        }
        // One-time migration from the old plaintext UserDefaults store.
        if let legacy = UserDefaults.standard.string(forKey: deepgramKeyStorageKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty {
            KeychainHelper.save(legacy, service: keychainService, account: keychainAccount)
            UserDefaults.standard.removeObject(forKey: deepgramKeyStorageKey)
            return legacy
        }
        return ""
    }
    
    static var isUsingDeepgram: Bool {
        let selected = UserDefaults.standard.string(forKey: engineStorageKey) ?? "apple"
        // Deepgram is only active if user selected it AND provided a valid key
        return selected == "deepgram" && !deepgramApiKey.isEmpty
    }

    static var geminiApiKey: String {
        return KeychainHelper.read(service: keychainService, account: keychainAccountGemini) ?? ""
    }

    static var isPolishing: Bool {
        get { return UserDefaults.standard.bool(forKey: polishStorageKey) }
        set { UserDefaults.standard.set(newValue, forKey: polishStorageKey) }
    }
    
    static var hudPosition: String {
        return UserDefaults.standard.string(forKey: hudPositionStorageKey) ?? "bottom"
    }
    
    /// Accessibility is optional everywhere. The store build defaults to the Carbon hot key
    /// because it works before any permission is granted; grant Accessibility and the
    /// modifier-only keys plus auto-paste light up there too.
    static var defaultTrigger: PTTTrigger {
        #if MAS_BUILD
        return .ctrlOptionSpace
        #else
        return .rightOption
        #endif
    }

    static var pttTrigger: PTTTrigger {
        get {
            let raw = UserDefaults.standard.string(forKey: pttTriggerStorageKey) ?? defaultTrigger.rawValue
            return PTTTrigger(rawValue: raw) ?? defaultTrigger
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: pttTriggerStorageKey)
            NotificationCenter.default.post(name: .talkTypeTriggerChanged, object: nil)
        }
    }

    /// Quick tap of the key locks recording on (hands-free); tap again to finish. Off by default.
    static var tapToLock: Bool {
        get { UserDefaults.standard.bool(forKey: tapToLockStorageKey) }
        set { UserDefaults.standard.set(newValue, forKey: tapToLockStorageKey) }
    }

    static var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: onboardedStorageKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardedStorageKey) }
    }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("⚠️ TalkType launch-at-login change failed: %@", error.localizedDescription)
            }
        }
    }

    static var language: TranscriptionLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: languageStorageKey) ?? TranscriptionLanguage.auto.rawValue
            return TranscriptionLanguage(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageStorageKey)
        }
    }
}

// MARK: - Vocabulary & Custom Keywords Normalizer
enum VocabularyManager {
    static var userKeywordsString: String {
        get { UserDefaults.standard.string(forKey: TalkTypeConfig.customKeywordsStorageKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: TalkTypeConfig.customKeywordsStorageKey) }
    }

    /// Contextual speech strings to hint recognition engines
    static var contextualHints: [String] {
        var hints = ["TalkType", "pibulus"]
        let userEntries = userKeywordsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for entry in userEntries {
            if entry.contains("->") {
                let parts = entry.components(separatedBy: "->")
                if parts.count == 2 {
                    let target = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !target.isEmpty && !hints.contains(target) {
                        hints.append(target)
                    }
                }
            } else if !hints.contains(entry) {
                hints.append(entry)
            }
        }
        return hints
    }

    /// Deepgram keyterm query parameter for Nova-3 (e.g. &keyterm=TalkType)
    static var deepgramKeywordsParam: String {
        let hints = contextualHints
        guard !hints.isEmpty else { return "" }
        let params = hints.compactMap { hint -> String? in
            guard let enc = hint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
            return "keyterm=\(enc)"
        }.joined(separator: "&")
        return params.isEmpty ? "" : "&" + params
    }

    /// Clean transcripts to fix common misrecognitions & apply user keyword rules
    static func clean(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var output = input

        // 1. Built-in TalkType phonetic fixes (word boundaries, case-insensitive)
        let builtInRules: [(pattern: String, replacement: String)] = [
            ("(?i)\\bdoc\\s*types?\\b", "TalkType"),
            ("(?i)\\bdoctype\\b", "TalkType"),
            ("(?i)\\bdock\\s*types?\\b", "TalkType"),
            ("(?i)\\btalk\\s*type\\b", "TalkType"),
            ("(?i)\\btalktype\\b", "TalkType"),
            ("(?i)\\btalk\\s*tight\\b", "TalkType")
        ]

        for rule in builtInRules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: rule.replacement)
            }
        }

        // 2. User-defined rules: "wrong -> right"
        let userEntries = userKeywordsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for entry in userEntries {
            if entry.contains("->") {
                let parts = entry.components(separatedBy: "->")
                if parts.count == 2 {
                    let wrong = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !wrong.isEmpty && !right.isEmpty {
                        let escaped = NSRegularExpression.escapedPattern(for: wrong)
                        if let regex = try? NSRegularExpression(pattern: "(?i)\\b\(escaped)\\b", options: []) {
                            let range = NSRange(output.startIndex..<output.endIndex, in: output)
                            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: right)
                        }
                    }
                }
            }
        }

        return output
    }
}

// MARK: - Gemini Polish
enum Polisher {
    static func polish(_ text: String, completion: @escaping (String) -> Void) {
        let key = TalkTypeConfig.geminiApiKey
        guard !key.isEmpty else { completion(text); return }
        let model = TalkTypeConfig.geminiModel
        let prompt = "Rewrite this dictation into clean, natural prose. Fix grammar, punctuation, and repeated words. Keep the meaning and voice exactly. Return only the rewritten text, no preamble or quotes:\n\n\(text)"
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            completion(text); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["thinkingConfig": ["thinkingBudget": 0]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            let polished: String? = {
                guard error == nil, let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let first = parts.first?["text"] as? String else { return nil }
                return first.trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            DispatchQueue.main.async {
                completion((polished?.isEmpty == false) ? polished! : text)
            }
        }.resume()
    }
}

// MARK: - Keychain Helper
enum KeychainHelper {
    @discardableResult
    static func save(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = base
            query[kSecValueData as String] = data
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

// MARK: - History Item
struct TranscriptRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    let engine: String
    
    init(text: String, engine: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.engine = engine
    }
}

// MARK: - History Store
class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published var records: [TranscriptRecord] = []
    
    init() {
        load()
    }
    
    func add(text: String, engine: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        DispatchQueue.main.async {
            // Deduplicate if identical to the most recent record
            if let last = self.records.first, last.text == trimmed {
                return
            }

            let record = TranscriptRecord(text: trimmed, engine: engine)
            self.records.insert(record, at: 0)
            if self.records.count > 50 {
                self.records = Array(self.records.prefix(50))
            }
            self.save()
        }
    }

    func delete(id: UUID) {
        DispatchQueue.main.async {
            self.records.removeAll { $0.id == id }
            self.save()
        }
    }
    
    func clear() {
        records.removeAll()
        save()
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: TalkTypeConfig.historyStorageKey)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: TalkTypeConfig.historyStorageKey),
           let loaded = try? JSONDecoder().decode([TranscriptRecord].self, from: data) {
            self.records = loaded
        }
    }
}


extension Notification.Name {
    static let talkTypeTriggerChanged = Notification.Name("talkTypeTriggerChanged")
}

// MARK: - App Delegate & Entry Point
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let engine = SpeechEngine()
    let history = HistoryStore.shared
    private var liveHUDController: LiveHUDWindowController?
    private var dictationTargetApp: NSRunningApplication?
    private var dictationStartedInOnboarding = false
    private var onboardingWindow: NSWindow?

    // Push-to-talk state machine
    private var pttMonitors: [Any] = []
    private var pttHeld = false            // the trigger key is physically held
    private var pttLocked = false          // hands-free: a quick tap locked the recording on
    private var pttPressedAt: Date?
    private var ignoreNextRelease = false  // the release belongs to a press we already consumed
    private var pendingPaste = false
    private var pasteWatchdogItem: DispatchWorkItem?
    private var maxDurationItem: DispatchWorkItem?
    private var modifierPollTimer: Timer?
    private var modifierMissCount = 0
    private var hotKeyRef: EventHotKeyRef?
    private static var hotKeyHandlerInstalled = false

    private var menubarBounceTimer: Timer?
    private var menubarActiveBlinkTimer: Timer?
    private var bouncePhase: Double = 0
    private var isRecordingBlink = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Setup Menu Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            resetMenuBarIcon()
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        statusItem.isVisible = true

        // Setup Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 330, height: 440)
        popover.behavior = .transient

        // Host the SwiftUI View
        let contentView = ContentView(speechEngine: engine, history: history, appDelegate: self)
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Live HUD controller
        liveHUDController = LiveHUDWindowController(speechEngine: engine)

        // The engine finalizes every session exactly once (final result, error, or timeout).
        engine.onFinal = { [weak self] rawText in
            self?.handleFinal(rawText)
        }

        engine.onStateChange = { [weak self] isRecording in
            guard let self = self else { return }
            if isRecording {
                self.startMenubarBounce()
                self.liveHUDController?.show()
                NSSound(named: "Tink")?.play()
            } else {
                self.stopMenubarBounce()
                NSSound(named: "Pop")?.play()
                // The HUD stays up until handleFinal / cancelDictation decides what to do with it.
            }
        }

        setupPushToTalk()
        NotificationCenter.default.addObserver(self, selector: #selector(triggerChanged), name: .talkTypeTriggerChanged, object: nil)

        if TalkTypeConfig.hasOnboarded {
            SFSpeechRecognizer.requestAuthorization { _ in }
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            checkAccessibilityPermissions()
        } else {
            // First run: the welcome guide walks through permissions one at a time
            // instead of three system dialogs stacking up on top of each other.
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if engine.isRecording {
            engine.cancelRecording()
        }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // MARK: - Menu Bar Icon (Serene When Idle, Living & Blinking While Dictating)
    func resetMenuBarIcon() {
        guard let button = statusItem.button else { return }
        if let originalGhost = NSImage(named: "ghost-menubar") {
            let icon = originalGhost.copy() as! NSImage
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            button.image = icon
        } else {
            button.title = "👻"
        }
    }

    func startMenubarBounce() {
        stopMenubarBounce()
        guard let normalGhost = NSImage(named: "ghost-menubar") else { return }
        let blinkGhost = NSImage(named: "ghost-menubar-squint") ?? (NSImage(named: "ghost-menubar-blink") ?? normalGhost)

        bouncePhase = 0
        isRecordingBlink = false

        // Silky 30fps harmonic floating sine wave
        menubarBounceTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem.button else { return }
            self.bouncePhase += 0.16
            let yOffset = sin(self.bouncePhase) * 1.8

            // Use squint/blink eyes during active blink; otherwise open eyes!
            let activeGhost = self.isRecordingBlink ? blinkGhost : normalGhost

            let size = NSSize(width: 18, height: 18)
            let bounced = NSImage(size: size)
            bounced.lockFocus()

            activeGhost.draw(in: NSRect(x: 0, y: yOffset, width: 18, height: 18),
                             from: .zero,
                             operation: .sourceOver,
                             fraction: 1.0)

            bounced.unlockFocus()
            bounced.isTemplate = true
            button.image = bounced
        }

        // Active blink while dictating: blinks every 1.6 - 2.4s while talking
        scheduleActiveBlink()
    }

    private func scheduleActiveBlink() {
        menubarActiveBlinkTimer?.invalidate()
        let interval = Double.random(in: 1.6...2.4)
        menubarActiveBlinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, self.engine.isRecording || self.pttHeld else { return }
            self.isRecordingBlink = true

            // Cute 130ms quick blink
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
                guard let self = self else { return }
                self.isRecordingBlink = false
                if self.engine.isRecording || self.pttHeld {
                    self.scheduleActiveBlink()
                }
            }
        }
    }

    func stopMenubarBounce() {
        menubarBounceTimer?.invalidate()
        menubarBounceTimer = nil
        menubarActiveBlinkTimer?.invalidate()
        menubarActiveBlinkTimer = nil
        isRecordingBlink = false
        resetMenuBarIcon()
    }

    // MARK: - Push to Talk (hold to dictate, release to paste)

    /// Modifier keys arrive as flagsChanged through NSEvent monitors (Accessibility required
    /// for the global one). The ⌃⌥ Space trigger is a Carbon hot key and needs nothing.
    /// A keyDown monitor handles Escape (cancel) and "the user was actually typing ⌥e".
    func setupPushToTalk() {
        let flagsHandler: (NSEvent) -> Void = { [weak self] event in self?.handleFlags(event) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler) {
            pttMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in
            flagsHandler(e); return e
        }) { pttMonitors.append(l) }

        if let g = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            _ = self?.handleKeyDown(event)
        }) { pttMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let consumed = self?.handleKeyDown(event) ?? false
            return consumed ? nil : event
        }) { pttMonitors.append(l) }

        refreshHotKey()
    }

    @objc private func triggerChanged() {
        if engine.isRecording || pttHeld || pttLocked {
            cancelDictation()
        }
        refreshHotKey()
    }

    private func handleFlags(_ event: NSEvent) {
        let trigger = TalkTypeConfig.pttTrigger
        guard !trigger.usesCarbonHotKey, let down = trigger.matches(event: event) else { return }
        if down {
            triggerPressed()
        } else {
            triggerReleased()
        }
    }

    /// Returns true when the event was consumed (only Escape while dictating).
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard engine.isRecording || pttHeld || pttLocked else { return false }

        if event.keyCode == 53 { // Escape: throw the take away, paste nothing
            cancelDictation()
            return true
        }

        // A real key while the modifier is physically held means the user is typing a
        // modifier combo (⌥e for é, fn+← …). That press was never meant for us.
        let trigger = TalkTypeConfig.pttTrigger
        if pttHeld, !pttLocked, let flag = trigger.modifierFlag, event.modifierFlags.contains(flag) {
            cancelDictation()
        }
        return false
    }

    func hotKeyChanged(isDown: Bool) {
        if isDown {
            triggerPressed()
        } else {
            triggerReleased()
        }
    }

    private func triggerPressed() {
        if pttLocked {
            // Second tap finishes a hands-free session; its release is not a new event.
            ignoreNextRelease = true
            finishDictation()
            return
        }
        guard !pttHeld else { return }
        // Any stale "ignore" from a lost release is irrelevant once a fresh press arrives.
        ignoreNextRelease = false
        // Fast re-press: flush a still-finalizing session so its text pastes first.
        engine.flushFinishingSession()
        pttHeld = true
        pttPressedAt = Date()
        beginDictation()
    }

    private func triggerReleased() {
        if ignoreNextRelease {
            ignoreNextRelease = false
            return
        }
        guard pttHeld else { return }
        pttHeld = false
        stopModifierPoll()

        if TalkTypeConfig.tapToLock,
           engine.isRecording,
           let pressed = pttPressedAt,
           Date().timeIntervalSince(pressed) < TalkTypeConfig.tapLockWindow {
            pttLocked = true
            engine.statusMessage = L10n.t("lockedHint")
            return
        }
        finishDictation()
    }

    private func beginDictation() {
        guard !engine.isRecording else { return }
        // Remember where the cursor was. When TalkType itself is frontmost (popover ghost
        // click), leave it nil: the popover closes and ⌘V lands in whatever comes back.
        let front = NSWorkspace.shared.frontmostApplication
        let selfPID = NSRunningApplication.current.processIdentifier
        dictationTargetApp = (front?.processIdentifier == selfPID) ? nil : front
        dictationStartedInOnboarding = (onboardingWindow?.isVisible == true) && NSApp.isActive
        engine.statusMessage = nil
        liveHUDController?.show()
        engine.startRecording()
        startModifierPoll()
        armMaxDuration()
    }

    /// Stop listening and paste whatever was said.
    private func finishDictation() {
        pttHeld = false
        pttLocked = false
        stopModifierPoll()
        maxDurationItem?.cancel()
        maxDurationItem = nil
        pendingPaste = true
        engine.stopRecording()
        armPasteWatchdog()
    }

    /// Stop listening and throw the take away (Escape, ⌥-combo typed, trigger changed).
    private func cancelDictation() {
        if pttHeld { ignoreNextRelease = true }
        pttHeld = false
        pttLocked = false
        pendingPaste = false
        stopModifierPoll()
        maxDurationItem?.cancel()
        maxDurationItem = nil
        pasteWatchdogItem?.cancel()
        pasteWatchdogItem = nil
        dictationTargetApp = nil
        engine.cancelRecording()
        engine.statusMessage = nil
        stopMenubarBounce()
        liveHUDController?.hide()
    }

    /// While the key is held, poll the real hardware modifier state. If macOS swallowed the
    /// key-up (modal dialog, secure input field, Space switch), this is what un-sticks us.
    private func startModifierPoll() {
        stopModifierPoll()
        modifierMissCount = 0
        modifierPollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.pttHeld else { self.stopModifierPoll(); return }
            if TalkTypeConfig.pttTrigger.isPhysicallyDown {
                self.modifierMissCount = 0
            } else {
                self.modifierMissCount += 1
                if self.modifierMissCount >= 2 {
                    NSLog("TalkType: key-up was never delivered; recovering from modifier state")
                    self.ignoreNextRelease = false
                    self.triggerReleased()
                }
            }
        }
    }

    private func stopModifierPoll() {
        modifierPollTimer?.invalidate()
        modifierPollTimer = nil
        modifierMissCount = 0
    }

    /// Nothing should record forever. After the cap, finish the take and paste it.
    private func armMaxDuration() {
        maxDurationItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.engine.isRecording else { return }
            if self.pttHeld { self.ignoreNextRelease = true }
            self.finishDictation()
        }
        maxDurationItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + TalkTypeConfig.maxRecordingSeconds, execute: item)
    }

    /// Outer safety net. The engine has its own finalize timeout; if it somehow never
    /// reports back, deliver what we have and reset so the next press works.
    private func armPasteWatchdog() {
        pasteWatchdogItem?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self = self, self.pendingPaste else { return }
            NSLog("⚠️ TalkType: engine never finalized; delivering buffered transcript")
            let buffered = self.engine.transcript
            self.engine.cancelRecording()
            self.handleFinal(buffered)
        }
        pasteWatchdogItem = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: watchdog)
    }

    /// Called once per session by the engine (or the watchdog) with the final transcript.
    private func handleFinal(_ rawText: String) {
        pasteWatchdogItem?.cancel()
        pasteWatchdogItem = nil
        maxDurationItem?.cancel()
        maxDurationItem = nil
        // If the engine ended on its own while the key is still down (mic unplugged, hard
        // error), the eventual key-up must not be read as the end of a different take.
        if pttHeld { ignoreNextRelease = true }
        pttHeld = false
        pttLocked = false
        stopModifierPoll()
        pendingPaste = false
        stopMenubarBounce()

        let text = VocabularyManager.clean(rawText.trimmingCharacters(in: .whitespacesAndNewlines))
        let engineName = engine.lastBackendName

        guard !text.isEmpty else {
            // Keep an error message readable for a moment; otherwise vanish instantly.
            liveHUDController?.hide(after: engine.statusMessage == nil ? 0 : 2.5)
            dictationTargetApp = nil
            return
        }

        history.add(text: text, engine: engineName)

        if TalkTypeConfig.isPolishing && !TalkTypeConfig.geminiApiKey.isEmpty {
            engine.transcript = L10n.t("polishing")
            Polisher.polish(text) { [weak self] polished in
                let cleanedPolished = VocabularyManager.clean(polished)
                self?.deliver(text: cleanedPolished)
            }
        } else {
            deliver(text: text)
        }
    }

    private func deliver(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // The welcome guide's "say something" step shows the take; it must not ⌘V into itself.
        let targetIsSelf = dictationStartedInOnboarding
        dictationStartedInOnboarding = false

        // Accessibility is optional in every build (sandbox included): granted → ⌘V into the
        // target app; not granted → clipboard with an explicit reminder in the HUD.
        if AXIsProcessTrusted() && !targetIsSelf {
            liveHUDController?.hide()
            pasteToActiveApp(text: text)
        } else {
            engine.transcript = L10n.t("copiedToClipboard")
            liveHUDController?.hide(after: 0.6)
            dictationTargetApp = nil
        }
    }

    /// Popover ghost button: start, or stop-and-paste.
    func requestPaste() {
        finishDictation()
    }

    func requestStart() {
        beginDictation()
    }

    // MARK: - Carbon hot key (⌃⌥ Space) — works without Accessibility, sandbox included

    private func refreshHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        let trigger = TalkTypeConfig.pttTrigger
        guard trigger.usesCarbonHotKey else { return }
        AppDelegate.installHotKeyHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x54545054), id: 1) // 'TTPT'
        let modifiers = UInt32(controlKey | optionKey)
        let status = RegisterEventHotKey(UInt32(kVK_Space), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("⚠️ TalkType: could not register ⌃⌥ Space hot key (status %d)", status)
        }
    }

    private static func installHotKeyHandlerIfNeeded() {
        guard !hotKeyHandlerInstalled else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let handler: EventHandlerUPP = { _, eventRef, _ in
            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
            let isDown = GetEventKind(eventRef) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.hotKeyChanged(isDown: isDown)
            }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), handler, ItemCount(specs.count), &specs, nil, nil)
        hotKeyHandlerInstalled = (status == noErr)
    }

    // MARK: - Permissions & Onboarding

    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc func showOnboarding() {
        if let existing = onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TalkType"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 1.0, green: 0.965, blue: 0.902, alpha: 1)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(speechEngine: engine, appDelegate: self))
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(onboardingClosed(_:)), name: NSWindow.willCloseNotification, object: window)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func onboardingClosed(_ note: Notification) {
        TalkTypeConfig.hasOnboarded = true
        if let window = onboardingWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        }
        onboardingWindow = nil
    }

    func finishOnboarding() {
        TalkTypeConfig.hasOnboarded = true
        onboardingWindow?.close()
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }
    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu(title: "TalkType")
        
        let titleItem = NSMenuItem(title: "TalkType", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "TalkType 👻",
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold)]
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // Accessibility nudge if not trusted (optional in every build)
        if !AXIsProcessTrusted() {
            let permItem = NSMenuItem(title: L10n.t("accessibilityDisabled"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        // Quick Recovery: Copy Last Transcript
        if let last = history.records.first {
            let snippet = last.text.count > 32 ? String(last.text.prefix(30)) + "…" : last.text
            let copyLast = NSMenuItem(title: "\(L10n.t("copyLast")): \"\(snippet)\"", action: #selector(copyLastTranscript), keyEquivalent: "c")
            copyLast.target = self
            menu.addItem(copyLast)
        } else {
            let copyLast = NSMenuItem(title: L10n.t("noRecentTranscripts"), action: nil, keyEquivalent: "")
            copyLast.isEnabled = false
            menu.addItem(copyLast)
        }
        
        // Recent History Submenu
        let historyMenu = NSMenu(title: "Recent")
        if history.records.isEmpty {
            let empty = NSMenuItem(title: L10n.t("historyEmpty"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
        } else {
            for record in history.records.prefix(8) {
                let preview = record.text.count > 40 ? String(record.text.prefix(38)) + "…" : record.text
                let item = NSMenuItem(title: preview, action: #selector(copySpecificRecord(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = record.text
                historyMenu.addItem(item)
            }
        }
        let historyParent = NSMenuItem(title: "\(L10n.t("recentTranscripts")) (\(history.records.count))", action: nil, keyEquivalent: "")
        historyParent.submenu = historyMenu
        menu.addItem(historyParent)
        
        menu.addItem(NSMenuItem.separator())
        
        // Push-to-Talk Shortcut Submenu (Accessibility)
        let shortcutMenu = NSMenu(title: "Shortcut")
        let activeTrigger = TalkTypeConfig.pttTrigger
        
        for trigger in PTTTrigger.allCases {
            let item = NSMenuItem(title: trigger.title, action: #selector(selectShortcutTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = trigger.rawValue
            item.state = (trigger == activeTrigger) ? .on : .off
            shortcutMenu.addItem(item)
        }
        
        shortcutMenu.addItem(NSMenuItem.separator())
        let lockItem = NSMenuItem(title: L10n.t("tapToLock"), action: #selector(toggleTapToLock), keyEquivalent: "")
        lockItem.target = self
        lockItem.state = TalkTypeConfig.tapToLock ? .on : .off
        shortcutMenu.addItem(lockItem)

        let shortcutParent = NSMenuItem(title: L10n.t("pushToTalkKey"), action: nil, keyEquivalent: "")
        shortcutParent.submenu = shortcutMenu
        menu.addItem(shortcutParent)
        
        // Model Selection Submenu
        let modelMenu = NSMenu(title: "Model")
        let isDeepgram = TalkTypeConfig.isUsingDeepgram
        
        let appleItem = NSMenuItem(title: L10n.t("appleSpeech"), action: #selector(selectAppleModel), keyEquivalent: "1")
        appleItem.target = self
        appleItem.state = !isDeepgram ? .on : .off
        modelMenu.addItem(appleItem)
        
        let dgItem = NSMenuItem(title: L10n.t("deepgramNova"), action: #selector(selectDeepgramModel), keyEquivalent: "2")
        dgItem.target = self
        dgItem.state = isDeepgram ? .on : .off
        modelMenu.addItem(dgItem)
        
        let modelParent = NSMenuItem(title: L10n.t("transcriptionEngine"), action: nil, keyEquivalent: "")
        modelParent.submenu = modelMenu
        menu.addItem(modelParent)

        // Language Submenu
        let langMenu = NSMenu(title: "Language")
        let activeLanguage = TalkTypeConfig.language
        for language in TranscriptionLanguage.allCases {
            let item = NSMenuItem(title: language.title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = (language == activeLanguage) ? .on : .off
            langMenu.addItem(item)
        }
        let langParent = NSMenuItem(title: L10n.t("language"), action: nil, keyEquivalent: "")
        langParent.submenu = langMenu
        menu.addItem(langParent)
        
        // HUD Position Submenu
        let posMenu = NSMenu(title: "HUD Position")
        let isTop = TalkTypeConfig.hudPosition == "top"
        
        let posBottom = NSMenuItem(title: L10n.t("bottomOfScreen"), action: #selector(setHudBottom), keyEquivalent: "")
        posBottom.target = self
        posBottom.state = !isTop ? .on : .off
        posMenu.addItem(posBottom)
        
        let posTop = NSMenuItem(title: L10n.t("topOfScreen"), action: #selector(setHudTop), keyEquivalent: "")
        posTop.target = self
        posTop.state = isTop ? .on : .off
        posMenu.addItem(posTop)
        
        let posParent = NSMenuItem(title: L10n.t("hudPosition"), action: nil, keyEquivalent: "")
        posParent.submenu = posMenu
        menu.addItem(posParent)
        
        menu.addItem(NSMenuItem.separator())
        
        // Deepgram Key Config
        let keyItem = NSMenuItem(title: L10n.t("deepgramApiKey"), action: #selector(promptDeepgramKey), keyEquivalent: "k")
        keyItem.target = self
        menu.addItem(keyItem)

        let geminiItem = NSMenuItem(title: L10n.t("geminiApiKey"), action: #selector(promptGeminiKey), keyEquivalent: "")
        geminiItem.target = self
        menu.addItem(geminiItem)

        let polishItem = NSMenuItem(title: L10n.t("polishOutput"), action: #selector(togglePolish), keyEquivalent: "")
        polishItem.target = self
        polishItem.state = TalkTypeConfig.isPolishing ? .on : .off
        menu.addItem(polishItem)
        
        let vocabItem = NSMenuItem(title: L10n.t("customKeywords"), action: #selector(promptCustomKeywords), keyEquivalent: "")
        vocabItem.target = self
        menu.addItem(vocabItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let loginItem = NSMenuItem(title: L10n.t("launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = TalkTypeConfig.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        let guideItem = NSMenuItem(title: L10n.t("welcomeGuide"), action: #selector(showOnboarding), keyEquivalent: "")
        guideItem.target = self
        menu.addItem(guideItem)

        let webItem = NSMenuItem(title: "TalkType on the Web…", action: #selector(openTalkTypeWeb), keyEquivalent: "")
        webItem.target = self
        menu.addItem(webItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: L10n.t("quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func selectShortcutTrigger(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let trigger = PTTTrigger(rawValue: raw) {
            TalkTypeConfig.pttTrigger = trigger
        }
    }

    @objc func toggleTapToLock() {
        TalkTypeConfig.tapToLock.toggle()
    }

    @objc func toggleLaunchAtLogin() {
        TalkTypeConfig.launchAtLogin.toggle()
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let language = TranscriptionLanguage(rawValue: raw) {
            TalkTypeConfig.language = language
        }
    }

    @objc func copyLastTranscript() {
        if let last = history.records.first {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(last.text, forType: .string)
        }
    }

    @objc func copySpecificRecord(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    @objc func setHudBottom() {
        UserDefaults.standard.set("bottom", forKey: TalkTypeConfig.hudPositionStorageKey)
        liveHUDController?.updatePosition()
    }

    @objc func setHudTop() {
        UserDefaults.standard.set("top", forKey: TalkTypeConfig.hudPositionStorageKey)
        liveHUDController?.updatePosition()
    }

    @objc func selectDeepgramModel() {
        if TalkTypeConfig.deepgramApiKey.isEmpty {
            promptDeepgramKey()
            if TalkTypeConfig.deepgramApiKey.isEmpty {
                UserDefaults.standard.set("apple", forKey: TalkTypeConfig.engineStorageKey)
                return
            }
        }
        UserDefaults.standard.set("deepgram", forKey: TalkTypeConfig.engineStorageKey)
    }

    @objc func selectAppleModel() {
        UserDefaults.standard.set("apple", forKey: TalkTypeConfig.engineStorageKey)
    }

    @objc func promptDeepgramKey() {
        let alert = NSAlert()
        alert.messageText = L10n.t("dgAlertTitle")
        alert.informativeText = L10n.t("dgAlertInfo")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t("save"))
        alert.addButton(withTitle: L10n.t("getKey"))
        alert.addButton(withTitle: L10n.t("cancel"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = TalkTypeConfig.deepgramApiKey
        input.placeholderString = L10n.t("pasteKey")
        alert.accessoryView = input

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                KeychainHelper.delete(service: TalkTypeConfig.keychainService, account: TalkTypeConfig.keychainAccount)
                UserDefaults.standard.removeObject(forKey: TalkTypeConfig.deepgramKeyStorageKey)
                UserDefaults.standard.set("apple", forKey: TalkTypeConfig.engineStorageKey)
            } else {
                KeychainHelper.save(key, service: TalkTypeConfig.keychainService, account: TalkTypeConfig.keychainAccount)
                UserDefaults.standard.removeObject(forKey: TalkTypeConfig.deepgramKeyStorageKey)
                UserDefaults.standard.set("deepgram", forKey: TalkTypeConfig.engineStorageKey)
            }
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://console.deepgram.com") {
                NSWorkspace.shared.open(url)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.promptDeepgramKey()
            }
        default:
            break
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func openTalkTypeWeb() {
        if let url = URL(string: "https://talktype.app") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func togglePolish() {
        TalkTypeConfig.isPolishing.toggle()
    }

    @objc func promptGeminiKey() {
        let alert = NSAlert()
        alert.messageText = L10n.t("geminiAlertTitle")
        alert.informativeText = L10n.t("geminiAlertInfo")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t("save"))
        alert.addButton(withTitle: L10n.t("getKey"))
        alert.addButton(withTitle: L10n.t("cancel"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = TalkTypeConfig.geminiApiKey
        input.placeholderString = L10n.t("pasteGeminiKey")
        alert.accessoryView = input

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                KeychainHelper.delete(service: TalkTypeConfig.keychainService, account: TalkTypeConfig.keychainAccountGemini)
                TalkTypeConfig.isPolishing = false
            } else {
                KeychainHelper.save(key, service: TalkTypeConfig.keychainService, account: TalkTypeConfig.keychainAccountGemini)
                TalkTypeConfig.isPolishing = true
            }
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                NSWorkspace.shared.open(url)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.promptGeminiKey()
            }
        default:
            break
        }
    }

    @objc func promptCustomKeywords() {
        let alert = NSAlert()
        alert.messageText = L10n.t("keywordsAlertTitle")
        alert.informativeText = L10n.t("keywordsAlertInfo")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t("save"))
        alert.addButton(withTitle: L10n.t("cancel"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 48))
        input.stringValue = VocabularyManager.userKeywordsString
        input.placeholderString = "TalkType, pibulus, doctype -> TalkType"
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let val = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            VocabularyManager.userKeywordsString = val
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if let button = statusItem.button {
                NSApp.activate(ignoringOtherApps: true)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    // Simulates Cmd+V to paste into the active app
    func pasteToActiveApp(text: String) {
        let targetApp = self.dictationTargetApp
        self.dictationTargetApp = nil

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        let wasPopoverShown = popover.isShown
        if wasPopoverShown {
            popover.performClose(nil)
        }
        
        // If an interfering window (e.g. expression script or system modal) stole focus,
        // reactivate the original target application before simulating Cmd+V.
        if let target = targetApp, target.processIdentifier != NSRunningApplication.current.processIdentifier {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        
        // Allow time for target app to gain focus and pasteboard propagation
        let delay: TimeInterval = (wasPopoverShown || targetApp != nil) ? 0.12 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let src = CGEventSource(stateID: .hidSystemState)
            let vKeyCode: CGKeyCode = 9 // 'v' key
            
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) else {
                return
            }
            
            // Strictly Command flag — completely strip any lingering Option/Alt modifier
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}


// MARK: - Live Transcript Floating HUD Window Controller
//
// A non-activating panel that joins every Space, rides above full-screen apps, and never
// takes focus. Visibility is driven directly (no NSAnimationContext on the window): a
// half-finished fade could previously leave the panel ordered-in at alpha 0, which reads
// as "the HUD didn't show up but the app still works". The fade-in lives in SwiftUI now.
final class LiveHUDWindowController: NSWindowController {
    let size = NSSize(width: 580, height: 76)
    private let speechEngine: SpeechEngine
    private var pendingHideItem: DispatchWorkItem?
    private var hostingView: NSHostingView<LiveTranscriptHUDView>?

    init(speechEngine: SpeechEngine) {
        self.speechEngine = speechEngine
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        LiveHUDWindowController.configure(panel)
        super.init(window: panel)
        window?.setFrame(NSRect(origin: LiveHUDWindowController.origin(for: size, on: LiveHUDWindowController.targetScreen()), size: size), display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func configure(_ panel: NSPanel) {
        // High overlay level: rides above full-screen apps, terminals and dialogs.
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
    }

    /// The screen the user is actually looking at: the one holding the focused window of the
    /// frontmost app (Accessibility, direct build only), else the one under the mouse.
    private static func targetScreen() -> NSScreen? {
        if let axScreen = focusedWindowScreen() {
            return axScreen
        }
        let mouseLoc = NSEvent.mouseLocation
        if let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
            return screenWithMouse
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private static func focusedWindowScreen() -> NSScreen? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowRef = windowValue else { return nil }
        let windowElement = windowRef as! AXUIElement
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posRef = posValue, let sizeRef = sizeValue else { return nil }
        var point = CGPoint.zero
        var windowSize = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &windowSize) else { return nil }
        // Accessibility coordinates have their origin at the top-left of the primary display;
        // AppKit's origin is bottom-left. Flip through the primary screen's height.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let center = NSPoint(x: point.x + windowSize.width / 2, y: primaryHeight - (point.y + windowSize.height / 2))
        return NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) })
    }

    private static func origin(for size: NSSize, on screen: NSScreen?) -> NSPoint {
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let isTop = TalkTypeConfig.hudPosition == "top"
        let y = isTop ? (screenFrame.maxY - size.height - 32) : (screenFrame.minY + 68)
        return NSPoint(x: screenFrame.midX - size.width / 2, y: y)
    }

    func updatePosition() {
        guard let window = self.window else { return }
        let origin = LiveHUDWindowController.origin(for: size, on: LiveHUDWindowController.targetScreen())
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func show() {
        guard let panel = self.window as? NSPanel else { return }
        pendingHideItem?.cancel()
        pendingHideItem = nil

        if hostingView == nil {
            let view = NSHostingView(rootView: LiveTranscriptHUDView(speechEngine: speechEngine))
            hostingView = view
            panel.contentView = view
        }
        // Re-assert everything that decides whether the panel is allowed on this Space.
        LiveHUDWindowController.configure(panel)
        updatePosition()
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
    }

    func hide(after delay: TimeInterval = 0) {
        pendingHideItem?.cancel()
        let hideBlock = DispatchWorkItem { [weak self] in
            guard let self = self, let panel = self.window else { return }
            panel.orderOut(nil)
            panel.contentView = NSView()
            self.hostingView = nil
        }
        pendingHideItem = hideBlock
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: hideBlock)
        } else if Thread.isMainThread {
            hideBlock.perform()
        } else {
            DispatchQueue.main.async(execute: hideBlock)
        }
    }
}

// MARK: - Live Transcript HUD View (Pure Crisp Rounded Capsule, 4.5px Chunky Neon Glow Border)
struct LiveTranscriptHUDView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @State private var wavePhase: Double = 0
    @State private var borderAngle: Double = 0
    @State private var ghostBounce: CGFloat = 1.0
    
    @State private var appeared = false

    private var isShowingStatus: Bool {
        speechEngine.transcript.isEmpty && speechEngine.statusMessage != nil
    }

    private var displayedText: String {
        if !speechEngine.transcript.isEmpty { return speechEngine.transcript }
        return speechEngine.statusMessage ?? L10n.t("listeningSpeak")
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Animated Peach Ghost Mark
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [TT.pink.opacity(0.35), TT.tangerine.opacity(0.12)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 26
                        )
                    )
                    .frame(width: 44, height: 44)
                
                GhostMark(isRecording: speechEngine.isRecording)
                    .frame(width: 32, height: 32)
                    .scaleEffect(ghostBounce)
            }
            .shadow(color: TT.pink.opacity(0.35), radius: 6, x: 0, y: 2)
            
            // Auto-scrolling Live Text Container (never cuts off)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Text(displayedText)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(
                                isShowingStatus
                                    ? Color(red: 0.72, green: 0.30, blue: 0.16)
                                    : (speechEngine.transcript.isEmpty
                                        ? Color(red: 0.35, green: 0.28, blue: 0.24).opacity(0.55)
                                        : Color(red: 0.12, green: 0.09, blue: 0.08))
                            )
                            .id("liveStreamText")
                        
                        // Trailing anchor for auto-scroll
                        Color.clear
                            .frame(width: 2, height: 2)
                            .id("trailingAnchor")
                    }
                    .padding(.vertical, 2)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: speechEngine.transcript.count > 25 ? 0.07 : 0),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .onChange(of: speechEngine.transcript) { _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("trailingAnchor", anchor: .trailing)
                    }
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        ghostBounce = 1.12
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            ghostBounce = 1.0
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Live pulsing soundwave radar dot
            ZStack {
                Circle()
                    .stroke(TT.pink.opacity(0.45), lineWidth: 1.5)
                    .scaleEffect(1.0 + CGFloat(sin(wavePhase)) * 0.45)
                    .opacity(0.85 - sin(wavePhase) * 0.35)
                    .frame(width: 24, height: 24)
                
                Circle()
                    .fill(TT.hot)
                    .frame(width: 11, height: 11)
                    .shadow(color: TT.pink.opacity(0.85), radius: 6)
            }
            .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Mild creamy translucent paper base (zero rectangular backdrop blur layer)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.992, green: 0.965, blue: 0.932).opacity(0.88))
                
                // Liquid flowing color border (chunkier 4.5px glowing neon stroke)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                TT.pink,
                                TT.tangerine,
                                Color(red: 1.0, green: 0.82, blue: 0.35),
                                TT.pink.opacity(0.9),
                                TT.tangerine,
                                TT.pink
                            ]),
                            center: .center,
                            startAngle: .degrees(borderAngle),
                            endAngle: .degrees(borderAngle + 360)
                        ),
                        lineWidth: 4.5
                    )
                
                // Inner hairline highlight
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    .padding(1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: TT.pink.opacity(0.35), radius: 16, x: 0, y: 6)
        .shadow(color: Color(red: 0.12, green: 0.09, blue: 0.08).opacity(0.12), radius: 8, x: 0, y: 3)
        .scaleEffect(appeared ? 1.0 : 0.94)
        .opacity(appeared ? 1.0 : 0.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TalkType live speech: \(displayedText)")
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                wavePhase = .pi * 2
            }
            withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                borderAngle = 360
            }
        }
        .onDisappear {
            // A repeatForever animation keeps driving frames until something
            // replaces it. Re-animating with duration 0 is what stops it.
            withAnimation(.linear(duration: 0)) {
                wavePhase = 0
                borderAngle = 0
            }
        }
    }
}


// MARK: - Speech Engine (Deepgram Nova-3 WebSocket + Apple On-Device)
//
// Every recording is a numbered session. Callbacks from the recognizer, the socket and the
// timers all carry the session number they belong to and are dropped when it is stale, so a
// late "final" from take #3 can never stop, hide or paste over take #4. Each session ends
// exactly once through finishSession (final result, error, or the finalize timeout).
class SpeechEngine: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    enum Backend {
        case apple
        case deepgram
    }

    private var recognizers: [String: SFSpeechRecognizer] = [:]
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var hasInstalledAudioTap = false

    // Deepgram WebSocket
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var confirmedTranscript = ""
    private var interimTranscript = ""

    // Session bookkeeping
    private var sessionID = 0
    private var activeBackend: Backend?
    private var isFinishing = false
    private var finalizeTimeoutItem: DispatchWorkItem?
    private let appleFinalizeTimeout: TimeInterval = 1.8
    private let deepgramFinalizeTimeout: TimeInterval = 1.2
    /// People let go of the key while the last syllable is still leaving their mouth.
    /// Keep the mic open this long after release before asking for the final.
    private let releaseTail: TimeInterval = 0.4
    private var releaseTailItem: DispatchWorkItem?

    @Published var transcript = ""
    @Published var isRecording = false
    /// Shown in the HUD when the transcript is empty: hands-free hint, permission errors…
    @Published var statusMessage: String?

    var onFinal: ((String) -> Void)?
    var onStateChange: ((Bool) -> Void)?

    /// Name of the backend that produced the most recent transcript, for history.
    private(set) var lastBackendName = "Apple"

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        urlSession?.invalidateAndCancel()
        safeRemoveTap()
    }

    // MARK: Recognizer cache
    // SFSpeechRecognizer must stay alive for as long as its task runs. Creating one per call
    // and letting it deallocate is a classic way to get a task that never reports a result.
    private func cachedRecognizer(for locale: Locale) -> SFSpeechRecognizer? {
        let key = locale.identifier
        if let cached = recognizers[key] {
            return cached
        }
        guard let created = SFSpeechRecognizer(locale: locale) else { return nil }
        recognizers[key] = created
        return created
    }

    @objc private func handleAudioEngineConfigChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // CoreAudio has already invalidated the tap on a hardware switch (AirPods
            // connecting, mic unplugged). Finish the take with whatever we have.
            self.hasInstalledAudioTap = false
            if self.isRecording {
                self.stopRecording()
            }
        }
    }

    private func safeRemoveTap() {
        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }
    }

    // MARK: Public controls

    func startRecording() {
        guard !isRecording else { return }
        if isFinishing {
            flushFinishingSession()
        }
        // A live take owns the mic; never toggle it off from a start request.
        if activeBackend != nil {
            return
        }
        // A stale engine (previous take failed mid-way) must be reset, not toggled.
        if audioEngine.isRunning {
            audioEngine.stop()
            safeRemoveTap()
        }

        sessionID += 1
        let session = sessionID
        transcript = ""
        confirmedTranscript = ""
        interimTranscript = ""
        isFinishing = false

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            fail(L10n.t("micDenied"))
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    // If the key was released while the prompt was up, this take is over.
                    guard let self = self, session == self.sessionID else { return }
                    if granted {
                        self.launch(session: session)
                    } else {
                        self.fail(L10n.t("micDenied"))
                    }
                }
            }
        default:
            launch(session: session)
        }
    }

    private func launch(session: Int) {
        guard session == sessionID, activeBackend == nil else { return }
        if TalkTypeConfig.isUsingDeepgram {
            activeBackend = .deepgram
            lastBackendName = "Nova-3"
            startDeepgramStreaming(session: session)
        } else {
            activeBackend = .apple
            lastBackendName = "Apple"
            startAppleSpeechRecognition(session: session)
        }
    }

    /// Stop capturing audio and let the backend deliver its final result.
    /// onFinal fires exactly once, no later than the finalize timeout.
    func stopRecording() {
        guard let backend = activeBackend else {
            // Nothing running, or still waiting on a permission prompt: end the take cleanly
            // and orphan the prompt callback so it can't start recording with nobody holding.
            sessionID += 1
            isFinishing = false
            onFinal?("")
            return
        }
        guard !isFinishing else { return }
        isFinishing = true
        let session = sessionID
        // Outer bound for the whole stop: tail + backend finalize.
        let finalizeSeconds = (backend == .apple ? appleFinalizeTimeout : deepgramFinalizeTimeout) + releaseTail
        armFinalizeTimeout(session: session, seconds: finalizeSeconds)

        releaseTailItem?.cancel()
        let tail = DispatchWorkItem { [weak self] in
            guard let self = self, session == self.sessionID else { return }
            switch backend {
            case .apple:
                self.stopAppleSpeechRecognition(session: session)
            case .deepgram:
                self.stopDeepgramStreaming(session: session)
            }
        }
        releaseTailItem = tail
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseTail, execute: tail)
    }

    /// Discard the take: no final result, no paste. Safe to call in any state.
    func cancelRecording() {
        let wasActive = isRecording || activeBackend != nil
        sessionID += 1 // orphan every in-flight callback
        finalizeTimeoutItem?.cancel()
        finalizeTimeoutItem = nil
        releaseTailItem?.cancel()
        releaseTailItem = nil
        teardownAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        activeBackend = nil
        isFinishing = false
        transcript = ""
        confirmedTranscript = ""
        interimTranscript = ""
        if wasActive {
            isRecording = false
            onStateChange?(false)
        }
    }

    /// If a previous take is still waiting for its final result, deliver it right now with
    /// whatever text it has so the next take can start on a clean engine.
    func flushFinishingSession() {
        guard isFinishing else { return }
        finishSession(sessionID, text: transcript)
    }

    // MARK: Session end

    private func fail(_ message: String) {
        statusMessage = message
        teardownAudio()
        activeBackend = nil
        isFinishing = false
        if isRecording {
            isRecording = false
            onStateChange?(false)
        }
        onFinal?("")
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        safeRemoveTap()
    }

    private func finishSession(_ session: Int, text: String) {
        guard session == sessionID, activeBackend != nil else { return }
        finalizeTimeoutItem?.cancel()
        finalizeTimeoutItem = nil
        releaseTailItem?.cancel()
        releaseTailItem = nil
        teardownAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if let socket = webSocketTask {
            socket.send(.string("{\"type\":\"CloseStream\"}")) { _ in }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                socket.cancel(with: .normalClosure, reason: nil)
            }
            webSocketTask = nil
        }
        activeBackend = nil
        isFinishing = false
        sessionID += 1 // anything still in flight for this take is now stale

        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = finalText
        if isRecording {
            isRecording = false
            onStateChange?(false)
        }
        onFinal?(finalText)
    }

    private func armFinalizeTimeout(session: Int, seconds: TimeInterval) {
        finalizeTimeoutItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, session == self.sessionID else { return }
            NSLog("TalkType: finalize timed out; delivering current transcript")
            self.finishSession(session, text: self.transcript)
        }
        finalizeTimeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func markRecording(session: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, session == self.sessionID, !self.isRecording else { return }
            self.isRecording = true
            self.onStateChange?(true)
        }
    }

    // MARK: - Deepgram WebSocket Streaming

    private func startDeepgramStreaming(session: Int) {
        let apiKey = TalkTypeConfig.deepgramApiKey
        let keywordsParam = VocabularyManager.deepgramKeywordsParam
        guard !apiKey.isEmpty,
              let url = URL(string: "wss://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&interim_results=true&encoding=linear16&sample_rate=16000&channels=1&language=\(TalkTypeConfig.language.deepgramLanguage)\(keywordsParam)") else {
            switchToApple(session: session)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let socket = urlSession?.webSocketTask(with: request)
        webSocketTask = socket
        socket?.resume()
        listenWebSocket(session: session)

        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            switchToApple(session: session)
            return
        }

        safeRemoveTap()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self, session == self.sessionID, let socket = self.webSocketTask else { return }

            let frameCount = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000.0 / nativeFormat.sampleRate) + 2)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            var allRead = false
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if allRead {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                allRead = true
                outStatus.pointee = .haveData
                return buffer
            }

            if let channelData = convertedBuffer.int16ChannelData {
                let data = Data(bytes: channelData.pointee, count: Int(convertedBuffer.frameLength) * 2)
                socket.send(.data(data)) { _ in }
            }
        }
        hasInstalledAudioTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
            markRecording(session: session)
        } catch {
            safeRemoveTap()
            fail(L10n.t("audioFailed"))
        }
    }

    private func listenWebSocket(session: Int) {
        guard let socket = webSocketTask else { return }
        socket.receive { [weak self] result in
            guard let self = self, session == self.sessionID else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.parseDeepgramJSON(text, session: session)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.parseDeepgramJSON(text, session: session)
                    }
                @unknown default:
                    break
                }
                self.listenWebSocket(session: session)

            case .failure(let error):
                NSLog("⚠️ TalkType Deepgram WebSocket error: %@", error.localizedDescription)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, session == self.sessionID else { return }
                    if self.isFinishing {
                        // The stream died while we waited for the last final: use what we have.
                        self.finishSession(session, text: self.transcript)
                    } else {
                        // Mid-take: fall over to on-device recognition without dropping the HUD.
                        self.switchToApple(session: session)
                    }
                }
            }
        }
    }

    /// Deepgram is unreachable: continue the same session on Apple's recognizer.
    private func switchToApple(session: Int) {
        guard session == sessionID else { return }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        teardownAudio()
        activeBackend = .apple
        lastBackendName = "Apple"
        startAppleSpeechRecognition(session: session)
    }

    private func parseDeepgramJSON(_ jsonString: String, session: Int) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let chunk = firstAlt["transcript"] as? String else { return }

        let isFinal = (json["is_final"] as? Bool) ?? false
        let fromFinalize = (json["from_finalize"] as? Bool) ?? false
        let trimmedChunk = VocabularyManager.clean(chunk.trimmingCharacters(in: .whitespacesAndNewlines))

        DispatchQueue.main.async {
            guard session == self.sessionID else { return }
            if isFinal {
                if !trimmedChunk.isEmpty {
                    self.confirmedTranscript = self.confirmedTranscript.isEmpty
                        ? trimmedChunk
                        : self.confirmedTranscript + " " + trimmedChunk
                }
                self.interimTranscript = ""
                self.transcript = self.confirmedTranscript
            } else if !trimmedChunk.isEmpty {
                self.interimTranscript = trimmedChunk
                self.transcript = self.confirmedTranscript.isEmpty
                    ? self.interimTranscript
                    : (self.confirmedTranscript + " " + self.interimTranscript)
            }
            // After Finalize, Deepgram flushes its buffer as one last is_final message.
            if self.isFinishing && (fromFinalize || isFinal) {
                self.finishSession(session, text: self.transcript)
            }
        }
    }

    private func stopDeepgramStreaming(session: Int) {
        teardownAudio()
        // Ask for the buffered audio to be transcribed now, then wait (briefly) for it.
        webSocketTask?.send(.string("{\"type\":\"Finalize\"}")) { _ in }
    }

    // MARK: - Apple Speech (on-device)

    private func startAppleSpeechRecognition(session: Int) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            fail(L10n.t("speechDenied"))
            return
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self = self, session == self.sessionID else { return }
                    if status == .authorized {
                        self.startAppleSpeechRecognition(session: session)
                    } else {
                        self.fail(L10n.t("speechDenied"))
                    }
                }
            }
            return
        default:
            break
        }

        guard let recognizer = cachedRecognizer(for: TalkTypeConfig.language.appleLocale), recognizer.isAvailable else {
            fail(L10n.t("speechUnavailable"))
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = VocabularyManager.contextualHints
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        safeRemoveTap()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, session == self.sessionID else { return }
            self.recognitionRequest?.append(buffer)
        }
        hasInstalledAudioTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            safeRemoveTap()
            fail(L10n.t("audioFailed"))
            return
        }
        markRecording(session: session)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, session == self.sessionID else { return }
                if let result = result {
                    self.transcript = VocabularyManager.clean(result.bestTranscription.formattedString)
                    if result.isFinal {
                        self.finishSession(session, text: self.transcript)
                        return
                    }
                }
                if let error = error {
                    // "No speech detected" and friends arrive here after endAudio(); any error
                    // during a live take also ends it with whatever text we already have.
                    NSLog("TalkType speech task ended: %@", error.localizedDescription)
                    self.finishSession(session, text: self.transcript)
                }
            }
        }
    }

    private func stopAppleSpeechRecognition(session: Int) {
        teardownAudio()
        recognitionRequest?.endAudio()
        // The recognizer normally answers within a few hundred ms; the outer finalize
        // timeout delivers the last partial if it doesn't.
    }
}

// MARK: - TalkType Palette
struct Palette {
    let ink: Color          // primary type
    let inkSoft: Color      // secondary type
    let paper: Color        // shell mid
    let paperLit: Color     // shell highlight
    let paperDim: Color     // shell edge
    let card: Color         // transcript surface
    let border: Color       // warm sepia rule
    let shadow: Color
    let ghostLift: Color
    let ghostLiftRadius: CGFloat
    let ghostLiftY: CGFloat

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }

    static let light = Palette(
        ink:      rgb(30, 23, 20),      // #1e1714
        inkSoft:  rgb(70, 63, 58),      // #463f3a
        paper:    rgb(255, 246, 230),   // #fff6e6
        paperLit: rgb(255, 248, 237),   // #fff8ed
        paperDim: rgb(255, 239, 218),   // #ffefda
        card:     rgb(253, 242, 224),   // deeper cream so the card reads as paper, not glare
        border:   rgb(30, 23, 20).opacity(0.22),
        shadow:   rgb(30, 23, 20).opacity(0.10),
        ghostLift: rgb(30, 23, 20).opacity(0.22),
        ghostLiftRadius: 8, ghostLiftY: 4)

    static let dark = Palette(
        ink:      rgb(255, 246, 230),   // cream type
        inkSoft:  rgb(203, 191, 174),
        paper:    rgb(30, 23, 20),      // #1e1714, never #000
        paperLit: rgb(40, 31, 27),
        paperDim: rgb(22, 17, 15),
        card:     rgb(43, 34, 29),
        border:   rgb(255, 246, 230).opacity(0.16),
        shadow:   rgb(12, 9, 8).opacity(0.55),
        ghostLift: rgb(255, 130, 202).opacity(0.28),
        ghostLiftRadius: 9, ghostLiftY: 1)

    var shell: RadialGradient {
        RadialGradient(
            stops: [.init(color: paperLit, location: 0.00),
                    .init(color: paper,    location: 0.52),
                    .init(color: paperDim, location: 1.00)],
            center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 340)
    }
}

enum TT {
    static let ghostInk  = Palette.rgb(30, 23, 20)     // #1e1714
    static let pink      = Palette.rgb(255, 130, 202)  // #ff82ca
    static let tangerine = Palette.rgb(255, 176,  96)  // #ffb060

    static let peachGhost = LinearGradient(
        stops: [.init(color: Palette.rgb(255,  96, 224), location: 0.00),
                .init(color: Palette.rgb(255, 130, 202), location: 0.35),
                .init(color: Palette.rgb(255, 154, 133), location: 0.65),
                .init(color: Palette.rgb(255, 176,  96), location: 0.85),
                .init(color: Palette.rgb(255, 207,  64), location: 1.00)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let hot = LinearGradient(colors: [pink, tangerine],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct GhostMark: View {
    var isRecording = false

    @State private var eyeScale: CGFloat = 1
    @State private var floatY: CGFloat = 0
    @State private var tilt: Double = 0
    @State private var blinkTimer: Timer?

    private let eyeAnchor = UnitPoint(x: 0.5, y: 464.0 / 1024.0)

    var body: some View {
        ZStack {
            layer("ghost-fill").foregroundStyle(TT.peachGhost)
            layer("ghost-line").foregroundStyle(TT.ghostInk)
            layer("ghost-eyes").foregroundStyle(TT.ghostInk)
                .scaleEffect(x: 1, y: eyeScale, anchor: eyeAnchor)
        }
        .offset(y: floatY)
        .rotationEffect(.degrees(tilt))
        .onAppear { startFloating(); scheduleBlink() }
        .onDisappear { stopFloating(); blinkTimer?.invalidate() }
        .onDisappear { blinkTimer?.invalidate(); blinkTimer = nil }
        .onChange(of: isRecording) { _ in startFloating() }
    }

    private func layer(_ name: String) -> some View {
        Group {
            if let img = NSImage(named: name) {
                Image(nsImage: img).resizable().renderingMode(.template).scaledToFit()
            } else {
                Color.clear
            }
        }
    }

    private func startFloating() {
        let duration = isRecording ? 3.4 : 5.8
        floatY = 0; tilt = 0
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            floatY = isRecording ? -4 : -3
            tilt   = isRecording ? 0.25 : 0.35
        }
    }

    private func stopFloating() {
        // Cancels the repeatForever above; without this the ghost keeps
        // animating inside a closed popover, which stays retained.
        withAnimation(.linear(duration: 0)) {
            floatY = 0
            tilt = 0
        }
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        let gap = Double.random(in: 4.0...9.0)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: gap, repeats: false) { _ in
            blink(double: Double.random(in: 0...1) < 0.25)
            scheduleBlink()
        }
    }

    private func blink(double: Bool) {
        shut()
        if double {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 + 0.08) { shut() }
        }
    }

    private func shut() {
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.075)) { eyeScale = 0.05 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.105) {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.075)) { eyeScale = 1 }
        }
    }
}

// MARK: - SwiftUI Popover UI (with History Tab & Quick Recovery)
struct ContentView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @ObservedObject var history: HistoryStore
    @Environment(\.colorScheme) private var scheme
    @State private var breathing = false
    @State private var selectedTab: Int = 0 // 0: Dictate, 1: History
    @State private var copiedId: UUID? = nil
    @State private var liveCopied: Bool = false
    var appDelegate: AppDelegate

    private var p: Palette { scheme == .dark ? .dark : .light }
    private var isRec: Bool { speechEngine.isRecording }
    private var pttKeyName: String { TalkTypeConfig.pttTrigger.shortTitle }

    var body: some View {
        VStack(spacing: 14) {
            // Header with Wordmark + Tab Picker (Rock-Solid Top Locked)
            HStack {
                HStack(spacing: 0) {
                    Text("Talk").foregroundStyle(p.ink)
                    Text("Type").foregroundStyle(TT.hot)
                }
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .kerning(-0.5)
                
                Spacer()
                
                // Mode Toggle
                HStack(spacing: 2) {
                    Button(action: { selectedTab = 0 }) {
                        Text(L10n.t("live"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selectedTab == 0 ? p.card : Color.clear)
                            .foregroundStyle(selectedTab == 0 ? p.ink : p.inkSoft.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { selectedTab = 1 }) {
                        HStack(spacing: 3) {
                            Text(L10n.t("history"))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            if !history.records.isEmpty {
                                Text("\(history.records.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(TT.pink.opacity(0.25))
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selectedTab == 1 ? p.card : Color.clear)
                        .foregroundStyle(selectedTab == 1 ? p.ink : p.inkSoft.opacity(0.6))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(p.border.opacity(0.12))
                .clipShape(Capsule())
            }
            
            if selectedTab == 0 {
                // Live View
                transcriptCard
                ghostButton
                statusLine
            } else {
                // History View (Never lose text again)
                historyCard
            }
        }
        .padding(18)
        .frame(width: 346, height: 440, alignment: .top)
        .background(p.shell)
    }

    private var transcriptCard: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                Text(speechEngine.transcript.isEmpty
                     ? L10n.t("holdGhost")
                     : speechEngine.transcript)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(speechEngine.transcript.isEmpty ? p.inkSoft.opacity(0.55) : p.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }

            if !speechEngine.transcript.isEmpty {
                HStack {
                    Text("\(speechEngine.transcript.split { $0.isWhitespace }.count) words")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(p.inkSoft.opacity(0.45))
                        .padding(.leading, 14)

                    Spacer()

                    Button(action: {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(speechEngine.transcript, forType: .string)
                        liveCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            liveCopied = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: liveCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9.5, weight: .bold))
                            Text(liveCopied ? L10n.t("copied") : L10n.t("copy"))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(liveCopied ? TT.pink.opacity(0.22) : p.border.opacity(0.12))
                        .foregroundStyle(liveCopied ? TT.pink : p.inkSoft)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(liveCopied ? TT.pink.opacity(0.5) : p.border.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        .frame(height: 142)
        .background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(p.border, lineWidth: 2)
        )
        .shadow(color: p.shadow, radius: 10, x: 0, y: 4)
    }

    private var ghostButton: some View {
        Button(action: toggle) {
            GhostMark(isRecording: isRec)
                .frame(width: 118, height: 118)
                .saturation(isRec ? 1.0 : 0.92)
                .scaleEffect(breathing && isRec ? 1.06 : 1.0)
                .shadow(color: isRec ? TT.pink.opacity(0.55) : p.ghostLift,
                        radius: isRec ? 15 : p.ghostLiftRadius,
                        x: 0, y: isRec ? 0 : p.ghostLiftY)
        }
        .buttonStyle(.plain)
        .onChange(of: isRec) { rec in
            withAnimation(rec ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                              : .easeOut(duration: 0.2)) {
                breathing = rec
            }
        }
    }

    private var needsAccessibilityNudge: Bool {
        !isRec && !AXIsProcessTrusted() && TalkTypeConfig.pttTrigger.needsAccessibility
    }

    private var statusLine: some View {
        Group {
            if needsAccessibilityNudge {
                Button(action: { appDelegate.openAccessibilitySettings() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(L10n.t("accessibilityHint"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(TT.tangerine)
                }
                .buttonStyle(.plain)
                .help(L10n.t("accessibilityDisabled"))
            } else {
                Text(isRec ? L10n.t("listening") : L10n.t("clickGhostHold") + pttKeyName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isRec ? AnyShapeStyle(TT.hot) : AnyShapeStyle(p.inkSoft.opacity(0.75)))
            }
        }
        .frame(height: 20)
    }

    private var historyCard: some View {
        VStack(spacing: 8) {
            if history.records.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(p.inkSoft.opacity(0.35))
                    Text(L10n.t("noTranscriptsSaved"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(p.inkSoft.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(history.records) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(record.timestamp, style: .time)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(p.inkSoft.opacity(0.55))
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 5) {
                                        Button(action: {
                                            let pb = NSPasteboard.general
                                            pb.clearContents()
                                            pb.setString(record.text, forType: .string)
                                            copiedId = record.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                                if copiedId == record.id { copiedId = nil }
                                            }
                                        }) {
                                            HStack(spacing: 3) {
                                                Image(systemName: copiedId == record.id ? "checkmark" : "doc.on.doc")
                                                Text(copiedId == record.id ? L10n.t("copied") : L10n.t("copy"))
                                            }
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(copiedId == record.id ? TT.pink.opacity(0.2) : p.border.opacity(0.12))
                                            .foregroundStyle(copiedId == record.id ? TT.pink : p.inkSoft)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                history.delete(id: record.id)
                                            }
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 9, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3.5)
                                                .background(p.border.opacity(0.10))
                                                .foregroundStyle(p.inkSoft.opacity(0.55))
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .help(L10n.t("delete"))
                                    }
                                }
                                
                                Text(record.text)
                                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                    .lineSpacing(2)
                                    .foregroundStyle(p.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(p.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(p.border.opacity(0.6), lineWidth: 1)
                            )
                        }
                    }
                    .padding(4)
                }
                .frame(height: 330)
                
                HStack {
                    Button(L10n.t("clearHistory")) {
                        history.clear()
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(p.inkSoft.opacity(0.5))
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func toggle() {
        if isRec {
            appDelegate.requestPaste()
        } else {
            appDelegate.requestStart()
        }
    }
}


// MARK: - Onboarding (first-launch welcome guide: key → permissions → say something)
struct OnboardingView: View {
    @ObservedObject var speechEngine: SpeechEngine
    var appDelegate: AppDelegate
    @Environment(\.colorScheme) private var scheme

    @State private var step = 0
    @State private var trigger: PTTTrigger = TalkTypeConfig.pttTrigger
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var speechStatus = SFSpeechRecognizer.authorizationStatus()
    @State private var axTrusted = false
    @State private var launchAtLogin = TalkTypeConfig.launchAtLogin
    @State private var lastTake = ""
    private let pollTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var p: Palette { scheme == .dark ? .dark : .light }
    private let cream = Palette.rgb(255, 246, 230)

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if step == 0 {
                    welcomeStep
                } else if step == 1 {
                    permissionsStep
                } else {
                    tryStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(.horizontal, 30)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(width: 480, height: 560)
        .background(p.shell.ignoresSafeArea())
        .onAppear { refreshPermissions() }
        .onReceive(pollTimer) { _ in refreshPermissions() }
        .onChange(of: speechEngine.isRecording) { recording in
            if !recording { lastTake = speechEngine.transcript }
        }
    }

    // MARK: Step 1 — meet the ghost, pick a key

    private var welcomeStep: some View {
        VStack(spacing: 14) {
            GhostMark(isRecording: false)
                .frame(width: 124, height: 124)
                .shadow(color: p.ghostLift, radius: p.ghostLiftRadius, x: 0, y: p.ghostLiftY)

            HStack(spacing: 0) {
                Text("Talk").foregroundStyle(p.ink)
                Text("Type").foregroundStyle(TT.hot)
            }
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .kerning(-0.6)

            Text(L10n.t("onbWelcomeTitle"))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(p.ink)

            Text(L10n.t("onbWelcomeBody"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(p.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel(L10n.t("onbPickKey"))
                keyPicker
                if trigger == .function {
                    Text(L10n.t("onbFnTip"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(p.inkSoft.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var keyPicker: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(PTTTrigger.allCases) { option in
                let selected = option == trigger
                Button(action: {
                    trigger = option
                    TalkTypeConfig.pttTrigger = option
                }) {
                    HStack(spacing: 6) {
                        Text(option.glyph)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                        Text(option.shortTitle)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(selected ? AnyShapeStyle(TT.hot) : AnyShapeStyle(p.card))
                    .foregroundStyle(selected ? cream : p.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? TT.ghostInk.opacity(0.85) : p.border, lineWidth: selected ? 2 : 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Step 2 — permissions, one at a time

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("onbPermsTitleThree"))
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(p.ink)

            Text(L10n.t("onbPermsBody"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(p.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                icon: "mic.fill",
                title: L10n.t("onbMic"),
                why: L10n.t("onbMicWhy"),
                granted: micStatus == .authorized,
                denied: micStatus == .denied || micStatus == .restricted,
                allow: { AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { refreshPermissions() } } },
                settings: { openPrivacyPane("Privacy_Microphone") }
            )

            permissionRow(
                icon: "waveform",
                title: L10n.t("onbSpeech"),
                why: L10n.t("onbSpeechWhy"),
                granted: speechStatus == .authorized,
                denied: speechStatus == .denied || speechStatus == .restricted,
                allow: { SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { refreshPermissions() } } },
                settings: { openPrivacyPane("Privacy_SpeechRecognition") }
            )

            permissionRow(
                icon: "hand.raised.fill",
                title: L10n.t("onbAX"),
                why: L10n.t("onbAXWhy"),
                granted: axTrusted,
                denied: false,
                allow: {
                    appDelegate.checkAccessibilityPermissions()
                    appDelegate.openAccessibilitySettings()
                },
                settings: { appDelegate.openAccessibilitySettings() }
            )
            Text(L10n.t("onbAXNote"))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(p.inkSoft.opacity(0.8))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func permissionRow(icon: String, title: String, why: String, granted: Bool, denied: Bool,
                               allow: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(granted ? AnyShapeStyle(TT.hot) : AnyShapeStyle(p.border.opacity(0.35)))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(granted ? cream : p.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(p.ink)
                Text(why)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(p.inkSoft.opacity(0.8))
            }
            Spacer()
            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(L10n.t("onbGranted"))
                }
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(TT.pink)
            } else if denied {
                Button(action: settings) {
                    Text(L10n.t("onbOpenSettings"))
                }
                .buttonStyle(ChunkyButtonStyle(filled: false))
            } else {
                Button(action: allow) {
                    Text(L10n.t("onbAllow"))
                }
                .buttonStyle(ChunkyButtonStyle(filled: true))
            }
        }
        .padding(12)
        .background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(p.border, lineWidth: 1.5)
        )
    }

    // MARK: Step 3 — say something

    private var tryStep: some View {
        VStack(spacing: 14) {
            Text(L10n.t("onbTryTitle"))
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(p.ink)

            Text(L10n.t("onbTryBody"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(p.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 8) {
                Text(trigger.glyph)
                Text(trigger.shortTitle)
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(p.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(p.card)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(TT.ghostInk.opacity(0.8), lineWidth: 2))
            .shadow(color: p.shadow, radius: 0, x: 3, y: 3)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(p.card)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(speechEngine.isRecording ? AnyShapeStyle(TT.hot) : AnyShapeStyle(p.border), lineWidth: 2)
                ScrollView(.vertical, showsIndicators: false) {
                    Text(tryText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .lineSpacing(3)
                        .foregroundStyle(tryTextIsPlaceholder ? p.inkSoft.opacity(0.55) : p.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            .frame(height: 150)
            .shadow(color: p.shadow, radius: 10, x: 0, y: 4)

            Toggle(isOn: $launchAtLogin) {
                Text(L10n.t("launchAtLogin"))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(p.ink)
            }
            .toggleStyle(.switch)
            .onChange(of: launchAtLogin) { value in
                TalkTypeConfig.launchAtLogin = value
            }

            Text(L10n.t("onbMenubarHint"))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(p.inkSoft.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    private var tryText: String {
        if speechEngine.isRecording {
            return speechEngine.transcript.isEmpty ? L10n.t("listening") : speechEngine.transcript
        }
        return lastTake.isEmpty ? L10n.t("onbTryEmpty") : lastTake
    }

    private var tryTextIsPlaceholder: Bool {
        speechEngine.isRecording ? speechEngine.transcript.isEmpty : lastTake.isEmpty
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? AnyShapeStyle(TT.hot) : AnyShapeStyle(p.border))
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
            }
            Spacer()
            if step > 0 {
                Button(action: { withAnimation(.easeOut(duration: 0.18)) { step -= 1 } }) {
                    Text(L10n.t("onbBack"))
                }
                .buttonStyle(ChunkyButtonStyle(filled: false))
            } else {
                Button(action: { appDelegate.finishOnboarding() }) {
                    Text(L10n.t("onbSkip"))
                }
                .buttonStyle(ChunkyButtonStyle(filled: false))
            }
            Button(action: {
                if step >= 2 {
                    appDelegate.finishOnboarding()
                } else {
                    withAnimation(.easeOut(duration: 0.18)) { step += 1 }
                }
            }) {
                Text(step >= 2 ? L10n.t("onbDone") : L10n.t("onbNext"))
            }
            .buttonStyle(ChunkyButtonStyle(filled: true))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 12)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .kerning(1)
            .foregroundStyle(p.inkSoft.opacity(0.7))
    }

    private func refreshPermissions() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        speechStatus = SFSpeechRecognizer.authorizationStatus()
        axTrusted = AXIsProcessTrusted()
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Chunky neo-brutalist pill: 2px ink border, hard offset shadow, peach fill when primary.
struct ChunkyButtonStyle: ButtonStyle {
    var filled: Bool
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let p: Palette = scheme == .dark ? .dark : .light
        return configuration.label
            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
            .foregroundStyle(filled ? Palette.rgb(255, 246, 230) : p.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(filled ? AnyShapeStyle(TT.hot) : AnyShapeStyle(p.card))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(TT.ghostInk.opacity(filled ? 0.9 : 0.6), lineWidth: 2))
            .shadow(color: TT.ghostInk.opacity(configuration.isPressed ? 0 : 0.35), radius: 0, x: 2.5, y: 2.5)
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}
