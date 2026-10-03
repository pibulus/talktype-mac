import Cocoa
import SwiftUI
import Combine
import Speech
import AVFoundation
import ApplicationServices
import Security
import Carbon

/// Short-lived state for the dictation loop; processing blocks a second take
/// until the current transcript has been delivered.
enum SpeechPhase: Equatable {
    case idle
    case listening
    case processing
    case ready
}

final class AudioLevelMeter: ObservableObject {
    @Published var level: Double = 0
}

enum PermissionHelpIssue: Equatable {
    case microphone
    case speechRecognition
    case accessibility

    var titleKey: String {
        switch self {
        case .microphone: return "permissionMicTitle"
        case .speechRecognition: return "permissionSpeechTitle"
        case .accessibility: return "permissionPasteTitle"
        }
    }

    var detailKey: String {
        switch self {
        case .microphone: return "permissionMicDetail"
        case .speechRecognition: return "permissionSpeechDetail"
        case .accessibility: return "permissionPasteDetail"
        }
    }

    var symbol: String {
        switch self {
        case .microphone: return "mic.slash.fill"
        case .speechRecognition: return "waveform"
        case .accessibility: return "keyboard"
        }
    }
}

// MARK: - PTT Shortcut Trigger Options (Full Keyboard & Mobility Accessibility)
enum PTTTrigger: String, CaseIterable, Identifiable {
    case rightOption = "rightOption"
    case leftOption = "leftOption"
    case eitherOption = "eitherOption"
    case function = "function"
    case rightCommand = "rightCommand"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .eitherOption: return "Either ⌥ Option (Default)"
        case .rightOption: return "Right ⌥ Option"
        case .leftOption: return "Left ⌥ Option"
        case .function: return "Globe / Function (fn)"
        case .rightCommand: return "Right ⌘ Command"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .eitherOption: return "⌥ Option"
        case .rightOption: return "Right ⌥ Option"
        case .leftOption: return "Left ⌥ Option"
        case .function: return "Globe / fn"
        case .rightCommand: return "Right ⌘ Command"
        }
    }
    
    func matches(event: NSEvent) -> Bool? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowed: NSEvent.ModifierFlags = [.control, .shift]
        switch self {
        case .rightOption:
            guard event.keyCode == 61 else { return nil }
            guard flags.intersection(disallowed).isEmpty, !flags.contains(.command) else { return false }
            return flags.contains(.option)
        case .leftOption:
            guard event.keyCode == 58 else { return nil }
            guard flags.intersection(disallowed).isEmpty, !flags.contains(.command) else { return false }
            return flags.contains(.option)
        case .eitherOption:
            guard event.keyCode == 61 || event.keyCode == 58 else { return nil }
            guard flags.intersection(disallowed).isEmpty, !flags.contains(.command) else { return false }
            return flags.contains(.option)
        case .function:
            guard event.keyCode == 63 else { return nil }
            return flags.contains(.function)
        case .rightCommand:
            guard event.keyCode == 54 else { return nil }
            guard flags.intersection(disallowed).isEmpty, !flags.contains(.option) else { return false }
            return flags.contains(.command)
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
        "accessibilityDisabled": ["en": "Accessibility Disabled (Click to Enable ⌘V)", "es": "Accesibilidad desactivada (Clic para activar ⌘V)"],
        "copyLast": ["en": "Copy Last Take", "es": "Copiar última toma"],
        "changePass": ["en": "Change Pass…", "es": "Cambiar pase…"],
        "polishTranscripts": ["en": "Polish Transcripts", "es": "Pulir transcripciones"],
        "noRecentTranscripts": ["en": "No Recent Transcripts", "es": "Sin transcripciones recientes"],
        "recentTranscripts": ["en": "Recent Transcripts", "es": "Transcripciones recientes"],
        "historyEmpty": ["en": "History empty", "es": "Historial vacío"],
        "pushToTalkKey": ["en": "Push to Talk Key", "es": "Tecla pulsar para hablar"],
        "transcriptionEngine": ["en": "Voice Mode", "es": "Modo de voz"],
        "appleSpeech": ["en": "Mac Built-in (Offline · Private)", "es": "Integrado en Mac (sin conexión · privado)"],
        "deepgramNova": ["en": "Supercharged (Nova-3 · Real-Time)", "es": "Sobrealimentado (Nova-3 · en vivo)"],
        "hudPosition": ["en": "HUD Position", "es": "Posición del HUD"],
        "bottomOfScreen": ["en": "Bottom of Screen", "es": "Parte inferior de la pantalla"],
        "topOfScreen": ["en": "Top of Screen", "es": "Parte superior de la pantalla"],
        "deepgramApiKey": ["en": "Unlock Supercharged Voice (Free $200 Pass)…", "es": "Desbloquear voz sobrealimentada (Pase de $200 gratis)…"],
        "unlockSupercharged": ["en": "Supercharged (Free $200 Pass)…", "es": "Voz sobrealimentada (Pase de $200 gratis)…"],
        "superchargedConnected": ["en": "Supercharged Connected (Change Code…)", "es": "Voz sobrealimentada conectada (cambiar código…)"],
        "trySuperchargedBadge": ["en": "Try Supercharged Voice (Free)", "es": "Probar voz sobrealimentada (Gratis)"],
        "superchargedActiveBadge": ["en": "Supercharged Voice Active", "es": "Voz sobrealimentada activa"],
        "trySuperchargedHelp": ["en": "Get $200 free credit (~45,000 mins) for ultra-accurate streaming transcription", "es": "Consigue $200 de crédito gratis (~45.000 mins) para transcripción ultraprecisa"],
        "superchargedHelp": ["en": "Supercharged voice active (Deepgram Nova-3). Click to manage pass.", "es": "Voz sobrealimentada activa (Deepgram Nova-3). Clic para gestionar pase."],
        "quit": ["en": "Quit TalkType", "es": "Salir de TalkType"],
        "dgAlertTitle": ["en": "Unlock Supercharged Voice (100% Free)", "es": "Desbloquear voz sobrealimentada (100% gratis)"],
        "dgAlertInfo": ["en": "TalkType uses your Mac's built-in voice by default (works offline, completely private).\n\nWant mind-blowing accuracy and instant real-time streaming? Deepgram gives everyone a free $200 pass (~45,000 minutes of speech, no credit card required).\n\n1. Click 'Get Free Pass' to grab your code on their site.\n2. Paste it below to activate.", "es": "TalkType usa la voz integrada de tu Mac por defecto (funciona sin conexión y es 100% privada).\n\n¿Quieres una precisión asombrosa y transcripción en tiempo real? Deepgram regala un pase de $200 a todo el mundo (~45.000 minutos de voz, sin tarjeta de crédito).\n\n1. Haz clic en 'Obtener pase gratis' para conseguir tu código.\n2. Pégalo a continuación para activarlo."],
        "save": ["en": "Activate Pass", "es": "Activar pase"],
        "updatePass": ["en": "Update Pass", "es": "Actualizar pase"],
        "getKey": ["en": "Get Free Pass ↗", "es": "Obtener pase gratis ↗"],
        "cancel": ["en": "Cancel", "es": "Cancelar"],
        "pasteKey": ["en": "Paste your code here", "es": "Pega tu código aquí"],
        "pasteKeyOrClear": ["en": "Paste new code, or leave blank to remove", "es": "Pega un código nuevo, o déjalo vacío para eliminarlo"],
        "listeningSpeak": ["en": "Listening… speak freely", "es": "Escuchando… habla con libertad"],
        "listening": ["en": "Listening…", "es": "Escuchando…"],
        "live": ["en": "Live", "es": "En vivo"],
        "history": ["en": "History", "es": "Historial"],
        "holdGhost": ["en": "Click the ghost to start talking…", "es": "Haz clic en el fantasma para empezar a hablar…"],
        "clickGhostHold": ["en": "Click ghost or hold ", "es": "Haz clic en el fantasma o mantén "],
        "clickAgainToFinish": ["en": "Click again to finish", "es": "Haz clic otra vez para terminar"],
        "noTranscriptsSaved": ["en": "No transcripts saved yet.", "es": "Aún no hay transcripciones guardadas."],
        "copy": ["en": "Copy", "es": "Copiar"],
        "copied": ["en": "Copied!", "es": "¡Copiado!"],
        "clearHistory": ["en": "Clear History", "es": "Borrar historial"],
        "copiedToClipboard": ["en": "Copied to clipboard — Press ⌘V to paste!", "es": "Copiado al portapapeles — ¡Pulsa ⌘V para pegar!"],
        "polishing": ["en": "Polishing…", "es": "Puliendo…"],
        "autoPolish": ["en": "Auto-Polish", "es": "Pulido automático"],
        "autoPolishTranscripts": ["en": "Auto-Polish Transcripts", "es": "Pulir transcripciones automáticamente"],
        "geminiPass": ["en": "Free Polish Pass…", "es": "Pase de pulido gratis…"],
        "pasteGeminiKey": ["en": "Paste your pass code here", "es": "Pega tu código de pase aquí"],
        "geminiAlertTitle": ["en": "Auto-Polish Transcripts (Free Pass)", "es": "Pulido automático (Pase gratis)"],
        "geminiAlertInfo": ["en": "TalkType operates completely standalone. Optionally add a free pass from Google AI Studio (no credit card required) to automatically format and polish your transcripts into clean prose.", "es": "TalkType funciona de forma completamente independiente. Opcionalmente añade un pase gratuito de Google AI Studio (sin tarjeta de crédito) para dar formato y pulir tus transcripciones."],
        "talkTypeWeb": ["en": "TalkType on the Web…", "es": "TalkType en la Web…"],
        "customKeywords": ["en": "Custom Vocabulary…", "es": "Vocabulario personalizado…"],
        "keywordsAlertTitle": ["en": "Custom Vocabulary & Keywords", "es": "Vocabulario y palabras clave"],
        "keywordsAlertInfo": ["en": "Add words or names speech recognition should prioritize (comma-separated, e.g. TalkType, pibulus, NoteBro). You can also use 'wrong -> right' rules (e.g. doctype -> TalkType).", "es": "Añade palabras que el reconocimiento de voz deba priorizar (separadas por comas, ej. TalkType, pibulus). También puedes usar reglas 'error -> corrección'."],
        "privacyPolicy": ["en": "Privacy Policy…", "es": "Política de privacidad…"],
        "micDisabled": ["en": "Microphone Denied (Click to Fix)", "es": "Micrófono denegado (Clic para activar)"],
        "speechDisabled": ["en": "Speech Recognition Denied (Click to Fix)", "es": "Reconocimiento de voz denegado (Clic para activar)"],
        "thinking": ["en": "Finishing…", "es": "Terminando…"],
        "ready": ["en": "Done", "es": "Listo"],
        "permissionMicTitle": ["en": "Microphone access is off", "es": "El acceso al micrófono está desactivado"],
        "permissionMicDetail": ["en": "Allow TalkType in System Settings to dictate.", "es": "Permite TalkType en Ajustes del Sistema para dictar."],
        "permissionSpeechTitle": ["en": "Speech Recognition is off", "es": "El reconocimiento de voz está desactivado"],
        "permissionSpeechDetail": ["en": "Turn it on to use Apple Speech.", "es": "Actívalo para usar Voz de Apple."],
        "permissionsReadyShortcut": ["en": "All set. Press your shortcut again to talk.", "es": "Todo listo. Pulsa el atajo otra vez para hablar."],
        "permissionPasteTitle": ["en": "Automatic paste is off", "es": "El pegado automático está desactivado"],
        "permissionPasteDetail": ["en": "Text still copies. Allow access to paste it for you.", "es": "El texto se copia. Permite el acceso para pegarlo automáticamente."],
        "fixPermission": ["en": "Fix", "es": "Ajustes"],
        "delete": ["en": "Delete", "es": "Eliminar"],
        "paste": ["en": "Paste", "es": "Pegar"],
        "menuBarClick": ["en": "Left / Right Click", "es": "Clic izquierdo / derecho"],
        "clickDefault": ["en": "Left: Card · Right: Menu", "es": "Izquierdo: Tarjeta · Derecho: Menú"],
        "clickSwapped": ["en": "Left: Menu · Right: Card", "es": "Izquierdo: Menú · Derecho: Tarjeta"]
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
    static let swapClicksStorageKey = "talktypeSwapClicks"

    static var isClicksSwapped: Bool {
        get { UserDefaults.standard.bool(forKey: swapClicksStorageKey) }
        set { UserDefaults.standard.set(newValue, forKey: swapClicksStorageKey) }
    }

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
    
    static var pttTrigger: PTTTrigger {
        let raw = UserDefaults.standard.string(forKey: pttTriggerStorageKey) ?? PTTTrigger.eitherOption.rawValue
        return PTTTrigger(rawValue: raw) ?? .eitherOption
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
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            completion(text); return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
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

// MARK: - App Delegate & Entry Point
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let engine = SpeechEngine()
    let history = HistoryStore.shared
    private var liveHUDController: LiveHUDWindowController?
    private var dictationTargetApp: NSRunningApplication?
    private var lastExternalApp: NSRunningApplication?

    private var pttMonitors: [Any] = []
    private var pttHeld = false
    private var pttPressTime: Date?
    private var isHandsFreeMode = false
    private var lastFlagsEventTime: TimeInterval = 0
    private var pendingPaste = false
    private var pasteWatchdogItem: DispatchWorkItem?
    private var deliverySessionId = UUID()
    
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
        // Track the active user application so menu take pasting hits the right window
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.lastExternalApp = app
            }
        }

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

        // Setup paste & history hook
        engine.onFinal = { [weak self] rawText in
            guard let self = self else { return }
            let text = VocabularyManager.clean(rawText.trimmingCharacters(in: .whitespacesAndNewlines))
            let engineName = TalkTypeConfig.isUsingDeepgram ? "Nova-3" : "Local"
            
            self.pasteWatchdogItem?.cancel()
            self.pasteWatchdogItem = nil
            self.stopMenubarBounce()
            self.isHandsFreeMode = false
            
            guard !text.isEmpty else {
                self.pendingPaste = false
                self.engine.phase = .idle
                self.liveHUDController?.hide()
                return
            }
            
            // 1. ALWAYS persist take into history
            self.history.add(text: text, engine: engineName)
            
            // 2. Deliver to clipboard & paste to active app
            if TalkTypeConfig.isPolishing && !TalkTypeConfig.geminiApiKey.isEmpty {
                self.engine.transcript = L10n.t("polishing")
                let activeSession = UUID()
                self.deliverySessionId = activeSession
                Polisher.polish(text) { [weak self] polished in
                    guard let self = self, self.deliverySessionId == activeSession else { return }
                    let cleanedPolished = VocabularyManager.clean(polished)
                    self.deliver(text: cleanedPolished)
                }
            } else {
                self.deliver(text: text)
            }
        }
        
        engine.onStateChange = { [weak self] isRecording in
            DispatchQueue.main.async {
                if isRecording {
                    self?.startMenubarBounce()
                    self?.liveHUDController?.show()
                    NSSound(named: "Tink")?.play()
                } else {
                    self?.stopMenubarBounce()
                    NSSound(named: "Pop")?.play()
                    if !(self?.pendingPaste ?? false), self?.engine.phase != .ready {
                        self?.engine.phase = .idle
                        self?.liveHUDController?.hide()
                    }
                }
            }
        }

        #if !MAS_BUILD
        setupPushToTalk()
        #endif
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

    #if !MAS_BUILD
    /// Hold designated shortcut anywhere to dictate; release to paste into whatever has focus.
    func setupPushToTalk() {
        let handler: (NSEvent) -> Void = { [weak self] event in self?.handleFlags(event) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
            pttMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in
            handler(e); return e
        }) { pttMonitors.append(l) }
    }

    private func handleFlags(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFlagsEventTime > 0.04 else { return } // Debounce 40ms contact chatter
        lastFlagsEventTime = now
        let trigger = TalkTypeConfig.pttTrigger
        guard let down = trigger.matches(event: event) else { return }
        
        if down {
            // If already recording in hands-free mode, or user taps shortcut while engine is running:
            // Stop recording and paste immediately!
            if isHandsFreeMode || (engine.isRecording && !pttHeld) {
                isHandsFreeMode = false
                pttHeld = false
                pendingPaste = true
                engine.stopRecording()
                return
            }
            
            if !pttHeld {
                pttHeld = true
                deliverySessionId = UUID()
                pttPressTime = Date()
                pendingPaste = true
                dictationTargetApp = NSWorkspace.shared.frontmostApplication
                lastExternalApp = dictationTargetApp
                liveHUDController?.show()
                engine.startRecording(resumeAfterPermission: false)
            }
        } else if pttHeld {
            pttHeld = false
            let pressDuration = Date().timeIntervalSince(pttPressTime ?? Date())
            
            if pressDuration < 0.28 {
                // Short tap (< 0.28s): Enter hands-free mode! Keeps recording until tapped again
                isHandsFreeMode = true
            } else {
                // Hold and release: Push-to-Talk finish & paste!
                isHandsFreeMode = false
                pendingPaste = true
                engine.stopRecording()
                
                pasteWatchdogItem?.cancel()
                let watchdog = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.stopMenubarBounce()
                    let fallbackText = VocabularyManager.clean(self.engine.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
                    if !fallbackText.isEmpty {
                        self.history.add(text: fallbackText, engine: TalkTypeConfig.isUsingDeepgram ? "Nova-3" : "Local")
                        self.deliver(text: fallbackText)
                    } else {
                        self.engine.phase = .idle
                        self.liveHUDController?.hide()
                    }
                }
                self.pasteWatchdogItem = watchdog
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: watchdog)
            }
        }
    }
    #endif

    private func deliver(text: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.deliver(text: text) }
            return
        }

        // 1. ALWAYS copy to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        engine.phase = .ready

#if MAS_BUILD
        // The sandboxed App Store build stays click-to-dictate and clipboard-only.
        engine.transcript = L10n.t("copiedToClipboard")
        self.liveHUDController?.hide(after: 1.5)
#else
        let targetApp = self.dictationTargetApp ?? self.lastExternalApp
        let shouldAutoPaste = self.pendingPaste || (targetApp != nil && targetApp?.bundleIdentifier != Bundle.main.bundleIdentifier)
        self.pendingPaste = false

        if AXIsProcessTrusted() && shouldAutoPaste {
            engine.transcript = text
            self.pasteToActiveApp(text: text)
            self.liveHUDController?.hide(after: 0.9)
        } else {
            // Clipboard fallback with explicit visual feedback
            self.engine.transcript = L10n.t("copiedToClipboard")
            self.liveHUDController?.hide(after: 1.5)
        }
#endif

        let resetReadyState = DispatchWorkItem { [weak self] in
            guard let self = self, self.engine.phase == .ready else { return }
            self.engine.phase = .idle
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: resetReadyState)
    }

    func requestPaste() {
        pendingPaste = true
        isHandsFreeMode = false
        engine.stopRecording()
        
        pasteWatchdogItem?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.stopMenubarBounce()
            let fallbackText = VocabularyManager.clean(self.engine.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
            if !fallbackText.isEmpty {
                self.history.add(text: fallbackText, engine: TalkTypeConfig.isUsingDeepgram ? "Nova-3" : "Local")
                self.deliver(text: fallbackText)
            } else {
                self.engine.phase = .idle
                self.liveHUDController?.hide()
            }
        }
        self.pasteWatchdogItem = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: watchdog)
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            dictationTargetApp = front
            lastExternalApp = front
        }
        guard let event = NSApp.currentEvent else { return }
        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        let shouldShowMenu = TalkTypeConfig.isClicksSwapped ? !isRightClick : isRightClick

        if shouldShowMenu {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            dictationTargetApp = front
            lastExternalApp = front
        }

        let menu = NSMenu(title: "TalkType")
        menu.autoenablesItems = false

        // ══════════════════════════════════════════════════════════
        // 1. RECENT TAKES (CLICK TO PASTE)
        // ══════════════════════════════════════════════════════════
        if history.records.isEmpty {
            let emptyItem = NSMenuItem(title: L10n.t("noRecentTranscripts"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            // Top 5 takes directly in root menu with ⌘1..⌘5 shortcuts (pure snippet text, no numbers/quotes)
            for (idx, record) in history.records.prefix(5).enumerated() {
                let clean = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = clean.count > 46 ? String(clean.prefix(44)) + "…" : clean
                let keyEq = "\(idx + 1)"

                let item = NSMenuItem(
                    title: preview,
                    action: #selector(pasteSpecificRecord(_:)),
                    keyEquivalent: keyEq
                )
                item.target = self
                item.representedObject = clean
                item.toolTip = "Paste into active app: \"\(clean)\""
                menu.addItem(item)

                // Alternate: Hold Option to copy without pasting
                let altItem = NSMenuItem(
                    title: "Copy: \(preview)",
                    action: #selector(copySpecificRecord(_:)),
                    keyEquivalent: keyEq
                )
                altItem.isAlternate = true
                altItem.keyEquivalentModifierMask = [.option]
                altItem.target = self
                altItem.representedObject = clean
                menu.addItem(altItem)
            }

            // Older takes submenu if > 5
            if history.records.count > 5 {
                let olderMenu = NSMenu(title: "Older Takes")
                for record in history.records.dropFirst(5).prefix(20) {
                    let clean = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let preview = clean.count > 46 ? String(clean.prefix(44)) + "…" : clean
                    let item = NSMenuItem(
                        title: preview,
                        action: #selector(pasteSpecificRecord(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = clean
                    item.toolTip = "Paste into active app: \"\(clean)\""
                    olderMenu.addItem(item)
                }
                let olderParent = NSMenuItem(title: "More Takes (\(history.records.count - 5))…", action: nil, keyEquivalent: "")
                olderParent.submenu = olderMenu
                menu.addItem(olderParent)
            }

            if history.records.first != nil {
                let copyLast = NSMenuItem(title: L10n.t("copyLast"), action: #selector(copyLastTranscript), keyEquivalent: "c")
                copyLast.target = self
                menu.addItem(copyLast)
            }

            let clearItem = NSMenuItem(title: L10n.t("clearHistory"), action: #selector(clearHistoryMenuAction), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        menu.addItem(NSMenuItem.separator())

        // ══════════════════════════════════════════════════════════
        // 2. SETTINGS & PREFERENCES (Consolidated & Tightly Grouped)
        // ══════════════════════════════════════════════════════════
        // Voice Mode (Zero duplicate labels)
        let modelMenu = NSMenu(title: "Voice Mode")
        let isDeepgram = TalkTypeConfig.isUsingDeepgram
        let hasDeepgramKey = !TalkTypeConfig.deepgramApiKey.isEmpty

        let appleItem = NSMenuItem(title: L10n.t("appleSpeech"), action: #selector(selectAppleModel), keyEquivalent: "")
        appleItem.target = self
        appleItem.state = !isDeepgram ? .on : .off
        modelMenu.addItem(appleItem)

        if hasDeepgramKey {
            let dgItem = NSMenuItem(title: L10n.t("deepgramNova"), action: #selector(selectDeepgramModel), keyEquivalent: "")
            dgItem.target = self
            dgItem.state = isDeepgram ? .on : .off
            modelMenu.addItem(dgItem)

            modelMenu.addItem(NSMenuItem.separator())
            let changeKeyItem = NSMenuItem(title: L10n.t("changePass"), action: #selector(promptDeepgramKey), keyEquivalent: "")
            changeKeyItem.target = self
            modelMenu.addItem(changeKeyItem)
        } else {
            let dgItem = NSMenuItem(title: L10n.t("unlockSupercharged"), action: #selector(selectDeepgramModel), keyEquivalent: "")
            dgItem.target = self
            modelMenu.addItem(dgItem)
        }

        let modelParent = NSMenuItem(title: L10n.t("transcriptionEngine"), action: nil, keyEquivalent: "")
        modelParent.submenu = modelMenu
        menu.addItem(modelParent)

        #if !MAS_BUILD
        let shortcutMenu = NSMenu(title: "Shortcut")
        let activeTrigger = TalkTypeConfig.pttTrigger
        for trigger in PTTTrigger.allCases {
            let item = NSMenuItem(title: trigger.title, action: #selector(selectShortcutTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = trigger.rawValue
            item.state = (trigger == activeTrigger) ? .on : .off
            shortcutMenu.addItem(item)
        }
        let shortcutParent = NSMenuItem(title: L10n.t("pushToTalkKey"), action: nil, keyEquivalent: "")
        shortcutParent.submenu = shortcutMenu
        menu.addItem(shortcutParent)
        #endif

        // Left / Right Click Action
        let clickMenu = NSMenu(title: L10n.t("menuBarClick"))
        let isSwapped = TalkTypeConfig.isClicksSwapped

        let defaultClickItem = NSMenuItem(
            title: L10n.t("clickDefault"),
            action: #selector(setClickActionDefault),
            keyEquivalent: ""
        )
        defaultClickItem.target = self
        defaultClickItem.state = !isSwapped ? .on : .off
        clickMenu.addItem(defaultClickItem)

        let swappedClickItem = NSMenuItem(
            title: L10n.t("clickSwapped"),
            action: #selector(setClickActionSwapped),
            keyEquivalent: ""
        )
        swappedClickItem.target = self
        swappedClickItem.state = isSwapped ? .on : .off
        clickMenu.addItem(swappedClickItem)

        let clickParent = NSMenuItem(title: L10n.t("menuBarClick"), action: nil, keyEquivalent: "")
        clickParent.submenu = clickMenu
        menu.addItem(clickParent)

        // Auto-Polish (Self-contained submenu: toggle + pass configuration)
        let polishMenu = NSMenu(title: "Auto-Polish")
        let polishToggle = NSMenuItem(
            title: L10n.t("autoPolishTranscripts"),
            action: #selector(togglePolish),
            keyEquivalent: ""
        )
        polishToggle.target = self
        polishToggle.state = TalkTypeConfig.isPolishing ? .on : .off
        polishMenu.addItem(polishToggle)

        polishMenu.addItem(NSMenuItem.separator())
        let geminiKeyItem = NSMenuItem(
            title: TalkTypeConfig.geminiApiKey.isEmpty ? L10n.t("geminiPass") : L10n.t("changePass"),
            action: #selector(promptGeminiKey),
            keyEquivalent: ""
        )
        geminiKeyItem.target = self
        polishMenu.addItem(geminiKeyItem)

        let polishParent = NSMenuItem(title: L10n.t("autoPolish"), action: nil, keyEquivalent: "")
        polishParent.submenu = polishMenu
        menu.addItem(polishParent)

        // Custom Vocabulary
        let vocabItem = NSMenuItem(title: L10n.t("customKeywords"), action: #selector(promptCustomKeywords), keyEquivalent: "")
        vocabItem.target = self
        menu.addItem(vocabItem)

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

        // ══════════════════════════════════════════════════════════
        // 3. PERMISSIONS / SYSTEM ALERTS (Only if needed)
        // ══════════════════════════════════════════════════════════
        var hasAlert = false
        #if !MAS_BUILD
        if !AXIsProcessTrusted() {
            if !hasAlert { menu.addItem(NSMenuItem.separator()); hasAlert = true }
            let permItem = NSMenuItem(title: L10n.t("accessibilityDisabled"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }
        #endif

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            if !hasAlert { menu.addItem(NSMenuItem.separator()); hasAlert = true }
            let micItem = NSMenuItem(title: L10n.t("micDisabled"), action: #selector(openMicrophoneSettings), keyEquivalent: "")
            micItem.target = self
            menu.addItem(micItem)
        }

        if !TalkTypeConfig.isUsingDeepgram {
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            if speechStatus == .denied || speechStatus == .restricted {
                if !hasAlert { menu.addItem(NSMenuItem.separator()); hasAlert = true }
                let speechItem = NSMenuItem(title: L10n.t("speechDisabled"), action: #selector(openSpeechRecognitionSettings), keyEquivalent: "")
                speechItem.target = self
                menu.addItem(speechItem)
            }
        }

        // ══════════════════════════════════════════════════════════
        // 4. FOOTER
        // ══════════════════════════════════════════════════════════
        menu.addItem(NSMenuItem.separator())

        let webItem = NSMenuItem(title: L10n.t("talkTypeWeb"), action: #selector(openTalkTypeWeb), keyEquivalent: "")
        webItem.target = self
        menu.addItem(webItem)

        let quitItem = NSMenuItem(title: L10n.t("quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    #if !MAS_BUILD
    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif

    @objc func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openSpeechRecognitionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openPrivacyPolicy() {
        if let url = URL(string: "https://talktype.app/privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func selectShortcutTrigger(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String {
            UserDefaults.standard.set(raw, forKey: TalkTypeConfig.pttTriggerStorageKey)
        }
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
            NSSound(named: "Pop")?.play()
        }
    }

    @objc func pasteSpecificRecord(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        #if !MAS_BUILD
        if AXIsProcessTrusted() {
            pasteToActiveApp(text: text)
            return
        }
        #endif
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NSSound(named: "Pop")?.play()
    }

    @objc func copySpecificRecord(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NSSound(named: "Pop")?.play()
    }

    @objc func openVisualPopover() {
        if let button = statusItem.button {
            togglePopover(button)
        }
    }

    @objc func clearHistoryMenuAction() {
        history.clear()
        NSSound(named: "Pop")?.play()
    }

    @objc func setHudBottom() {
        UserDefaults.standard.set("bottom", forKey: TalkTypeConfig.hudPositionStorageKey)
        liveHUDController?.updatePosition()
    }

    @objc func setHudTop() {
        UserDefaults.standard.set("top", forKey: TalkTypeConfig.hudPositionStorageKey)
        liveHUDController?.updatePosition()
    }

    @objc func setClickActionDefault() {
        TalkTypeConfig.isClicksSwapped = false
    }

    @objc func setClickActionSwapped() {
        TalkTypeConfig.isClicksSwapped = true
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
        let hasKey = !TalkTypeConfig.deepgramApiKey.isEmpty
        alert.addButton(withTitle: hasKey ? L10n.t("updatePass") : L10n.t("save"))
        alert.addButton(withTitle: L10n.t("getKey"))
        alert.addButton(withTitle: L10n.t("cancel"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = TalkTypeConfig.deepgramApiKey
        input.placeholderString = hasKey ? L10n.t("pasteKeyOrClear") : L10n.t("pasteKey")
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
            if let url = URL(string: "https://console.deepgram.com/signup") {
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
        if !TalkTypeConfig.isPolishing && TalkTypeConfig.geminiApiKey.isEmpty {
            promptGeminiKey()
            return
        }
        TalkTypeConfig.isPolishing.toggle()
    }

    @objc func promptGeminiKey() {
        let alert = NSAlert()
        alert.messageText = L10n.t("geminiAlertTitle")
        alert.informativeText = L10n.t("geminiAlertInfo")
        alert.alertStyle = .informational
        let hasKey = !TalkTypeConfig.geminiApiKey.isEmpty
        alert.addButton(withTitle: hasKey ? L10n.t("updatePass") : L10n.t("save"))
        alert.addButton(withTitle: L10n.t("getKey"))
        alert.addButton(withTitle: L10n.t("cancel"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = TalkTypeConfig.geminiApiKey
        input.placeholderString = hasKey ? L10n.t("pasteKeyOrClear") : L10n.t("pasteGeminiKey")
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
    
    #if !MAS_BUILD
    private func resolvePasteKeyCode() -> CGKeyCode {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return 9 // ANSI 'v' fallback
        }
        let header = unsafeBitCast(layoutData, to: CFData.self)
        guard let uchrHeader = CFDataGetBytePtr(header) else { return 9 }
        let keyboardType = UInt32(LMGetKbdType())
        for code in 0..<128 {
            var deadKeyState: UInt32 = 0
            var actualStringLength: Int = 0
            var unicodeString = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                uchrHeader.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 },
                UInt16(code),
                UInt16(kUCKeyActionDown),
                0,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                unicodeString.count,
                &actualStringLength,
                &unicodeString
            )
            if status == noErr && actualStringLength > 0 && unicodeString[0] == 0x76 /* 'v' */ {
                return CGKeyCode(code)
            }
        }
        return 9
    }

    // Simulates Cmd+V to paste into the active app
    func pasteToActiveApp(text: String) {
        let targetApp = self.dictationTargetApp ?? self.lastExternalApp
        self.dictationTargetApp = nil
        
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
        let delay: TimeInterval = (wasPopoverShown || targetApp != nil) ? 0.18 : 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            let src = CGEventSource(stateID: .combinedSessionState)
            let vKeyCode: CGKeyCode = self.resolvePasteKeyCode()
            
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) else {
                return
            }
            
            // Explicitly clear all hardware modifiers and strictly assign Command
            keyDown.flags = []
            keyDown.flags = .maskCommand
            keyUp.flags = []
            keyUp.flags = .maskCommand
            
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
    #endif
}

// MARK: - Live Transcript Floating HUD Window Controller
final class LiveHUDWindowController: NSWindowController {
    let size = NSSize(width: 580, height: 76)
    private var isVisibleTarget = false
    private let speechEngine: SpeechEngine
    private var pendingHideItem: DispatchWorkItem?

    init(speechEngine: SpeechEngine) {
        self.speechEngine = speechEngine
        let mouseLoc = NSEvent.mouseLocation
        let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
        let screen = screenWithMouse ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let isTop = TalkTypeConfig.hudPosition == "top"
        let y = isTop ? (screenFrame.maxY - size.height - 32) : (screenFrame.minY + 68)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: y)
        
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // High overlay level: sits strictly above all full-screen apps, terminal windows, and dialogues
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        window.contentView = NSHostingView(
            rootView: LiveTranscriptHUDView(
                speechEngine: speechEngine,
                audioMeter: speechEngine.audioMeter
            ))

        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updatePosition() {
        guard let window = self.window else { return }
        let mouseLoc = NSEvent.mouseLocation
        let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
        let screen = screenWithMouse ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let isTop = TalkTypeConfig.hudPosition == "top"
        let y = isTop ? (screenFrame.maxY - size.height - 32) : (screenFrame.minY + 68)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: y)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
    
    func show() {
        guard let window = self.window else { return }
        // 1. Cancel any pending delayed hide from a prior recording session
        pendingHideItem?.cancel()
        pendingHideItem = nil

        isVisibleTarget = true
        updatePosition()
        window.orderFrontRegardless()
        
        // 2. Immediately ensure full opacity without getting stuck at alpha 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1.0
        }
    }
    
    func hide(after delay: TimeInterval = 0) {
        guard let window = self.window else { return }
        pendingHideItem?.cancel()
        
        let hideBlock = DispatchWorkItem { [weak self, weak window] in
            guard let self = self, let window = window else { return }
            self.isVisibleTarget = false
            if delay == 0 {
                // Instant zero-lag dismissal
                window.alphaValue = 0
                window.orderOut(nil)
            } else {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.08
                    window.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    guard let self = self else { return }
                    if !self.isVisibleTarget {
                        window.orderOut(nil)
                    }
                })
            }
        }
        
        self.pendingHideItem = hideBlock
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: hideBlock)
        } else {
            if Thread.isMainThread {
                hideBlock.perform()
            } else {
                DispatchQueue.main.async(execute: hideBlock)
            }
        }
    }
}

// MARK: - Live Transcript HUD View (Pure Crisp Rounded Capsule, 4.5px Chunky Neon Glow Border)
struct LiveTranscriptHUDView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @ObservedObject var audioMeter: AudioLevelMeter
    @State private var wavePhase: Double = 0
    @State private var borderAngle: Double = 0
    @State private var ghostBounce: CGFloat = 1.0
    
    private var displayedText: String {
        if !speechEngine.transcript.isEmpty { return speechEngine.transcript }
        switch speechEngine.phase {
        case .idle: return L10n.t("holdGhost")
        case .listening: return L10n.t("listeningSpeak")
        case .processing: return L10n.t("thinking")
        case .ready: return L10n.t("ready")
        }
    }

    private var phaseLabel: String {
        switch speechEngine.phase {
        case .idle: return L10n.t("holdGhost")
        case .listening: return L10n.t("listening")
        case .processing: return L10n.t("thinking")
        case .ready: return L10n.t("ready")
        }
    }

    @ViewBuilder
    private var activityIndicator: some View {
        switch speechEngine.phase {
        case .idle:
            Circle()
                .fill(TT.tangerine.opacity(0.7))
                .frame(width: 10, height: 10)
                .frame(width: 42, height: 34)
        case .listening:
            ZStack {
                Circle()
                    .stroke(TT.pink.opacity(0.45), lineWidth: 1.5)
                    .scaleEffect(1.0 + CGFloat(sin(wavePhase)) * 0.25 + CGFloat(audioMeter.level) * 0.4)
                    .opacity(0.72 + CGFloat(audioMeter.level) * 0.22)
                    .frame(width: 24, height: 24)

                Circle()
                    .fill(TT.hot)
                    .frame(width: 11, height: 11)
                    .shadow(color: TT.pink.opacity(0.85), radius: 6)
            }
            .frame(width: 42, height: 34)
            .accessibilityLabel(L10n.t("listening"))
        case .processing:
            VStack(spacing: 3) {
                ProcessingWaveform()
                    .frame(height: 20)
                Text(L10n.t("thinking"))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(TT.tangerine)
            }
            .frame(width: 54, height: 34)
        case .ready:
            VStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(L10n.t("ready"))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(TT.hot)
            .frame(width: 46, height: 34)
            .accessibilityLabel(L10n.t("ready"))
        }
    }

    private func updateMotion(for phase: SpeechPhase) {
        if phase == .listening {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                wavePhase = .pi * 2
            }
            withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                borderAngle = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                wavePhase = 0
                borderAngle = 0
            }
        }
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
                    .scaleEffect(ghostBounce * (1.0 + CGFloat(audioMeter.level) * 0.07))
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
                                speechEngine.transcript.isEmpty
                                    ? Color(red: 0.35, green: 0.28, blue: 0.24).opacity(0.55)
                                    : Color(red: 0.12, green: 0.09, blue: 0.08)
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
            
            activityIndicator
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            speechEngine.transcript.isEmpty
                ? "TalkType \(phaseLabel)"
                : "TalkType \(phaseLabel): \(displayedText)"
        )
        .onAppear {
            updateMotion(for: speechEngine.phase)
        }
        .onChange(of: speechEngine.phase) { phase in
            updateMotion(for: phase)
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

private struct ProcessingWaveform: View {
    @State private var isAnimating = false
    private let heights: [CGFloat] = [10, 17, 13, 19, 12]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? TT.pink : TT.tangerine)
                    .frame(width: 3, height: isAnimating ? heights[index] : 6)
                    .animation(
                        .easeInOut(duration: 0.34)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.06),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
        .accessibilityHidden(true)
    }
}

// MARK: - Speech Engine (Deepgram Nova-3 WebSocket + Apple Fallback)
class SpeechEngine: NSObject, ObservableObject {
    private var cachedSpeechRecognizer: SFSpeechRecognizer?
    private var cachedSpeechRecognizerLocale: Locale?
    private var speechRecognizer: SFSpeechRecognizer? {
        let currentLocale = TalkTypeConfig.language.appleLocale
        if let cached = cachedSpeechRecognizer, cachedSpeechRecognizerLocale == currentLocale {
            return cached
        }
        let recognizer = SFSpeechRecognizer(locale: currentLocale)
        cachedSpeechRecognizer = recognizer
        cachedSpeechRecognizerLocale = currentLocale
        return recognizer
    }
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var hasInstalledAudioTap = false
    private var lastMeterPublishTime: TimeInterval = 0
    let audioMeter = AudioLevelMeter()
    
    // CoreAudio real-time processing queue & Session tracking
    private let audioProcessingQueue = DispatchQueue(label: "com.talktype.audioProcessing", qos: .userInitiated)
    private var currentSessionId = UUID()
    private var audioConverter: AVAudioConverter?
    private var targetAudioFormat: AVAudioFormat?

    // Deepgram WebSocket
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var confirmedTranscript = ""
    private var interimTranscript = ""
    private var isStopping = false
    private var permissionRequestInProgress = false
    
    private func commitInterim() {
        guard !interimTranscript.isEmpty else { return }
        if confirmedTranscript.isEmpty {
            confirmedTranscript = interimTranscript
        } else {
            confirmedTranscript += " " + interimTranscript
        }
        interimTranscript = ""
        transcript = confirmedTranscript
    }
    
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var phase: SpeechPhase = .idle

    var hasActiveCapture: Bool {
        isRecording || audioEngine.isRunning
    }

    var onFinal: ((String) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        urlSession?.invalidateAndCancel()
        safeRemoveTap()
    }
    
    @objc private func handleAudioEngineConfigChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NSLog("🔄 TalkType: Audio engine route changed (e.g. AirPods connected/disconnected)")
            self.hasInstalledAudioTap = false // Route change destroys taps internally
            if self.isRecording {
                self.stopRecording()
            }
            self.audioEngine.stop()
            self.audioEngine.reset()
            self.phase = .idle
        }
    }

    @objc private func handleSystemSleep(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NSLog("💤 TalkType: System going to sleep, resetting audio engine")
            if self.isRecording {
                self.stopRecording()
            }
            self.safeRemoveTap()
            self.audioEngine.stop()
            self.audioEngine.reset()
            self.phase = .idle
        }
    }

    @objc private func handleSystemWake(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NSLog("☀️ TalkType: System woke up, resetting engine state to idle")
            self.audioEngine.reset()
            self.phase = .idle
        }
    }
    
    private func safeRemoveTap() {
        guard hasInstalledAudioTap else { return }
        hasInstalledAudioTap = false
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func resolveInputFormat() -> AVAudioFormat? {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            NSLog("⚠️ TalkType: No hardware audio input device found")
            return nil
        }
        let inputNode = audioEngine.inputNode
        var format = inputNode.outputFormat(forBus: 0)
        if format.sampleRate <= 0 || format.channelCount == 0 {
            audioEngine.reset()
            hasInstalledAudioTap = false
            format = inputNode.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("⚠️ TalkType: Audio input format unavailable (sampleRate: %f, channels: %d)", format.sampleRate, format.channelCount)
            return nil
        }
        return format
    }

    private func publishInputLevel(from buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMeterPublishTime >= 0.04 else { return }
        lastMeterPublishTime = now

        var sumOfSquares = 0.0
        var totalSamples = 0
        let step = max(1, frameCount / 64)
        if let channels = buffer.floatChannelData {
            for channel in 0..<channelCount {
                let samples = channels[channel]
                var frame = 0
                while frame < frameCount {
                    let sample = Double(samples[frame])
                    sumOfSquares += sample * sample
                    totalSamples += 1
                    frame += step
                }
            }
        } else if let channels = buffer.int16ChannelData {
            for channel in 0..<channelCount {
                let samples = channels[channel]
                var frame = 0
                while frame < frameCount {
                    let sample = Double(samples[frame]) / 32768.0
                    sumOfSquares += sample * sample
                    totalSamples += 1
                    frame += step
                }
            }
        } else {
            return
        }

        guard totalSamples > 0 else { return }
        let level = min(1.0, max(0.0, sqrt(sumOfSquares / Double(totalSamples)) * 5.0))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.audioMeter.level = self.isRecording ? level : 0
        }
    }
    
    func startRecording(resumeAfterPermission: Bool = true) {
        if phase == .processing || isStopping {
            // User re-triggered dictation while flushing prior take: force-finalize immediately
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            isStopping = false
        }

        isStopping = false
        if audioEngine.isRunning {
            safeRemoveTap()
            audioEngine.stop()
            audioEngine.reset()
        }
        guard !permissionRequestInProgress else { return }

        phase = .idle

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            continueAfterMicrophonePermission(resumeAfterPermission: resumeAfterPermission, requestedPermission: false)
        case .notDetermined:
            permissionRequestInProgress = true
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.permissionRequestInProgress = false
                    guard granted else {
                        self.transcript = L10n.t("permissionMicTitle")
                        return
                    }
                    self.continueAfterMicrophonePermission(resumeAfterPermission: resumeAfterPermission, requestedPermission: true)
                }
            }
        default:
            transcript = L10n.t("permissionMicTitle")
        }
    }

    private func continueAfterMicrophonePermission(resumeAfterPermission: Bool, requestedPermission: Bool) {
        if !TalkTypeConfig.isUsingDeepgram {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                beginAuthorizedRecording(resumeAfterPermission: resumeAfterPermission, requestedPermission: requestedPermission)
            case .notDetermined:
                permissionRequestInProgress = true
                SFSpeechRecognizer.requestAuthorization { [weak self] status in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.permissionRequestInProgress = false
                        guard status == .authorized else {
                            self.transcript = L10n.t("permissionSpeechTitle")
                            return
                        }
                        self.beginAuthorizedRecording(resumeAfterPermission: resumeAfterPermission, requestedPermission: true)
                    }
                }
            default:
                transcript = L10n.t("permissionSpeechTitle")
            }
        } else {
            beginAuthorizedRecording(resumeAfterPermission: resumeAfterPermission, requestedPermission: requestedPermission)
        }
    }

    private func beginAuthorizedRecording(resumeAfterPermission: Bool, requestedPermission: Bool) {
        if requestedPermission && !resumeAfterPermission {
            transcript = L10n.t("permissionsReadyShortcut")
            return
        }

        isStopping = false
        currentSessionId = UUID()
        transcript = ""
        confirmedTranscript = ""
        interimTranscript = ""
        
        if TalkTypeConfig.isUsingDeepgram {
            startDeepgramStreaming()
        } else {
            startAppleSpeechRecognition()
        }
    }
    
    func stopRecording() {
        guard isRecording || audioEngine.isRunning || webSocketTask != nil else { return }

        if TalkTypeConfig.isUsingDeepgram {
            stopDeepgramStreaming()
        } else {
            stopAppleSpeechRecognition()
        }
    }
    
    // MARK: - Deepgram WebSocket Streaming
    private func startDeepgramStreaming() {
        isStopping = false
        let apiKey = TalkTypeConfig.deepgramApiKey
        let keywordsParam = VocabularyManager.deepgramKeywordsParam
        guard !apiKey.isEmpty,
              let url = URL(string: "wss://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&interim_results=true&encoding=linear16&sample_rate=16000&channels=1&mip_opt_out=true&language=\(TalkTypeConfig.language.deepgramLanguage)\(keywordsParam)") else {
            startAppleSpeechRecognition()
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        listenWebSocket()
        
        guard let nativeFormat = resolveInputFormat() else {
            startAppleSpeechRecognition()
            return
        }
        
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else {
            startAppleSpeechRecognition()
            return
        }
        
        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            startAppleSpeechRecognition()
            return
        }
        
        self.audioConverter = converter
        self.targetAudioFormat = targetFormat
        
        safeRemoveTap()
        let sampleRate = nativeFormat.sampleRate
        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }
            self.publishInputLevel(from: buffer)
            
            // Deep-copy audio frame data before CoreAudio driver recycles the underlying buffer
            guard let bufferCopy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else { return }
            bufferCopy.frameLength = buffer.frameLength
            let channelCount = Int(buffer.format.channelCount)
            if let srcChannels = buffer.floatChannelData, let dstChannels = bufferCopy.floatChannelData {
                for channel in 0..<channelCount {
                    dstChannels[channel].update(from: srcChannels[channel], count: Int(buffer.frameLength))
                }
            } else if let srcChannels = buffer.int16ChannelData, let dstChannels = bufferCopy.int16ChannelData {
                for channel in 0..<channelCount {
                    dstChannels[channel].update(from: srcChannels[channel], count: Int(buffer.frameLength))
                }
            }
            
            // Offload buffer allocation, conversion, and websocket send from real-time CoreAudio thread
            self.audioProcessingQueue.async { [weak self, bufferCopy] in
                guard let self = self, self.isRecording else { return }
                let frameCount = AVAudioFrameCount(ceil(Double(bufferCopy.frameLength) * 16000.0 / sampleRate) + 2)
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
                    return bufferCopy
                }
                
                if let channelData = convertedBuffer.int16ChannelData {
                    let data = Data(bytes: channelData.pointee, count: Int(convertedBuffer.frameLength) * 2)
                    self.webSocketTask?.send(.data(data)) { _ in }
                }
            }
        }
        hasInstalledAudioTap = true
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            self.isRecording = true
            self.phase = .listening
            self.onStateChange?(true)
        } catch {
            NSLog("⚠️ TalkType: Failed to start audioEngine: %@", error.localizedDescription)
            safeRemoveTap()
            audioEngine.reset()
            self.isRecording = false
            self.phase = .idle
            self.onStateChange?(false)
        }
    }
    
    private func listenWebSocket() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.isRecording || self.webSocketTask != nil else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.parseDeepgramJSON(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.parseDeepgramJSON(text)
                    }
                @unknown default:
                    break
                }
                self.listenWebSocket()
                
            case .failure(let error):
                // If stream was intentionally stopped, this closure error is expected
                if self.isStopping {
                    return
                }
                guard self.isRecording else { return }
                
                NSLog("⚠️ TalkType Deepgram WebSocket error during recording: %@", error.localizedDescription)
                // If Deepgram WebSocket fails mid-recording, seamlessly fallback without losing prior words
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.isRecording, !self.isStopping else { return }
                    self.commitInterim()
                    self.safeRemoveTap()
                    self.audioEngine.stop()
                    self.startAppleSpeechRecognition(appendingToExisting: true)
                }
            }
        }
    }
    
    private func parseDeepgramJSON(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let chunk = firstAlt["transcript"] as? String else { return }
        
        let isFinal = (json["is_final"] as? Bool) ?? false
        let speechFinal = (json["speech_final"] as? Bool) ?? false
        let trimmedChunk = VocabularyManager.clean(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
        
        DispatchQueue.main.async {
            guard self.isRecording || self.isStopping else { return }
            
            if isFinal || speechFinal {
                let toCommit = !trimmedChunk.isEmpty ? trimmedChunk : self.interimTranscript
                if !toCommit.isEmpty {
                    if self.confirmedTranscript.isEmpty {
                        self.confirmedTranscript = toCommit
                    } else {
                        self.confirmedTranscript += " " + toCommit
                    }
                }
                self.interimTranscript = ""
                self.transcript = self.confirmedTranscript
            } else if !trimmedChunk.isEmpty {
                self.interimTranscript = trimmedChunk
                self.transcript = self.confirmedTranscript.isEmpty ? self.interimTranscript : (self.confirmedTranscript + " " + self.interimTranscript)
            }
        }
    }
    
    private func stopDeepgramStreaming() {
        isStopping = true
        audioEngine.stop()
        safeRemoveTap()
        DispatchQueue.main.async { [weak self] in
            self?.audioMeter.level = 0
            self?.phase = .processing
            self?.commitInterim()
        }
        
        // Drain any unread tail frames in converter on the processing queue before sending close frame
        audioProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            if let converter = self.audioConverter, let targetFormat = self.targetAudioFormat {
                if let flushBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1024) {
                    var error: NSError?
                    converter.convert(to: flushBuffer, error: &error) { _, outStatus in
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    if flushBuffer.frameLength > 0, let channelData = flushBuffer.int16ChannelData {
                        let data = Data(bytes: channelData.pointee, count: Int(flushBuffer.frameLength) * 2)
                        self.webSocketTask?.send(.data(data)) { _ in }
                    }
                }
                converter.reset()
            }
            self.audioConverter = nil
            self.targetAudioFormat = nil
            
            let closeData = Data()
            self.webSocketTask?.send(.data(closeData)) { _ in }
        }
        
        // Give Deepgram time to return final flushed transcription segment before disconnecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }
            self.commitInterim()
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            self.isRecording = false
            self.isStopping = false
            self.audioMeter.level = 0
            self.phase = .processing
            self.onStateChange?(false)
            
            let finalOutput = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            self.onFinal?(finalOutput)
        }
    }
    
    // MARK: - Apple Speech Fallback
    private func startAppleSpeechRecognition(appendingToExisting: Bool = false) {
        isStopping = false
        if !appendingToExisting {
            currentSessionId = UUID()
            confirmedTranscript = ""
            interimTranscript = ""
            transcript = ""
        }
        let baseText = confirmedTranscript
        let sessionId = self.currentSessionId
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = VocabularyManager.contextualHints
        
        if #available(macOS 13.0, *) {
            recognitionRequest.addsPunctuation = true
        }
        // Strictly require on-device recognition: zero audio leaves this Mac
        recognitionRequest.requiresOnDeviceRecognition = true
        
        guard let recordingFormat = resolveInputFormat() else {
            DispatchQueue.main.async { [weak self] in
                self?.isRecording = false
                self?.isStopping = false
                self?.phase = .idle
                self?.onStateChange?(false)
            }
            return
        }
        
        safeRemoveTap()
        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording, self.currentSessionId == sessionId else { return }
            self.publishInputLevel(from: buffer)
            self.recognitionRequest?.append(buffer)
        }
        hasInstalledAudioTap = true
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            self.isRecording = true
            self.phase = .listening
            self.onStateChange?(true)
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self, self.currentSessionId == sessionId else { return }
                var isFinal = false
                if let result = result {
                    let cleaned = VocabularyManager.clean(result.bestTranscription.formattedString)
                    DispatchQueue.main.async {
                        guard self.currentSessionId == sessionId else { return }
                        if baseText.isEmpty {
                            self.transcript = cleaned
                        } else if cleaned.isEmpty {
                            self.transcript = baseText
                        } else {
                            self.transcript = baseText + " " + cleaned
                        }
                    }
                    isFinal = result.isFinal
                }
                
                if error != nil || isFinal {
                    DispatchQueue.main.async {
                        guard self.currentSessionId == sessionId else { return }
                        self.currentSessionId = UUID()
                        self.audioEngine.stop()
                        self.safeRemoveTap()
                        self.recognitionRequest = nil
                        self.recognitionTask = nil
                        self.isRecording = false
                        self.isStopping = false
                        self.phase = .processing
                        self.onStateChange?(false)
                        self.onFinal?(self.transcript)
                    }
                }
            }
        } catch {
            NSLog("⚠️ TalkType: Failed to start Apple Speech audio engine: %@", error.localizedDescription)
            safeRemoveTap()
            audioEngine.reset()
            self.isRecording = false
            self.isStopping = false
            self.phase = .idle
            self.onStateChange?(false)
        }
    }
    
    private func stopAppleSpeechRecognition() {
        isStopping = true
        let sessionId = self.currentSessionId
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.currentSessionId == sessionId else { return }
            self.audioEngine.stop()
            self.recognitionRequest?.endAudio()
            self.safeRemoveTap()
            self.isRecording = false
            self.audioMeter.level = 0
            self.phase = .processing
            self.onStateChange?(false)
            
            // Safety timeout: if Apple Speech hangs on silence, finalize with current buffer
            let current = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self, self.currentSessionId == sessionId, self.recognitionTask != nil else { return }
                self.currentSessionId = UUID() // Invalidate session to drop subsequent cancel callbacks
                self.recognitionTask?.cancel()
                self.recognitionTask = nil
                self.recognitionRequest = nil
                self.isStopping = false
                let finalOut = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                self.onFinal?(finalOut.isEmpty ? current : finalOut)
            }
        }
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

    static let cyberGhost = LinearGradient(
        stops: [.init(color: Palette.rgb(175, 82, 222), location: 0.00),
                .init(color: Palette.rgb(120, 110, 255), location: 0.50),
                .init(color: Palette.rgb(60, 220, 240), location: 1.00)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let matchaGhost = LinearGradient(
        stops: [.init(color: Palette.rgb(70, 210, 120), location: 0.00),
                .init(color: Palette.rgb(140, 230, 90), location: 0.50),
                .init(color: Palette.rgb(255, 220, 80), location: 1.00)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let amigaGhost = LinearGradient(
        stops: [.init(color: Palette.rgb(255, 60, 110), location: 0.00),
                .init(color: Palette.rgb(255, 150, 40), location: 0.50),
                .init(color: Palette.rgb(90, 200, 255), location: 1.00)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let hot = LinearGradient(colors: [pink, tangerine],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct GhostMark: View {
    var isRecording = false
    @AppStorage("talktypeGhostMood") private var ghostMood: Int = 0

    @State private var eyeScale: CGFloat = 1
    @State private var floatY: CGFloat = 0
    @State private var tilt: Double = 0
    @State private var blinkTimer: Timer?

    private let eyeAnchor = UnitPoint(x: 0.5, y: 464.0 / 1024.0)

    private var ghostGradient: LinearGradient {
        switch ghostMood % 4 {
        case 1: return TT.cyberGhost
        case 2: return TT.matchaGhost
        case 3: return TT.amigaGhost
        default: return TT.peachGhost
        }
    }

    var body: some View {
        ZStack {
            layer("ghost-fill").foregroundStyle(ghostGradient)
            layer("ghost-line").foregroundStyle(TT.ghostInk)
            layer("ghost-eyes").foregroundStyle(TT.ghostInk)
                .scaleEffect(x: 1, y: eyeScale, anchor: eyeAnchor)
        }
        .offset(y: floatY)
        .rotationEffect(.degrees(tilt))
        .onAppear { startFloating(); scheduleBlink() }
        .onDisappear { stopFloating(); blinkTimer?.invalidate(); blinkTimer = nil }
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

struct CopyPillButton: View {
    let isCopied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5, weight: .bold))
                Text(isCopied ? L10n.t("copied") : L10n.t("copy"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isCopied ? AnyShapeStyle(TT.pink.opacity(0.28)) : AnyShapeStyle(TT.hot.opacity(0.18)))
            .foregroundStyle(isCopied ? AnyShapeStyle(TT.pink) : AnyShapeStyle(TT.hot))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct HistoryRecordCard: View {
    let record: TranscriptRecord
    let isCopied: Bool
    let p: Palette
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(record.timestamp, style: .time)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(p.inkSoft.opacity(0.55))

                Spacer()

                HStack(spacing: 5) {
                    CopyPillButton(isCopied: isCopied, action: onCopy)

                    Button(action: onDelete) {
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

// MARK: - SwiftUI Popover UI (with History Tab & Quick Recovery)
struct ContentView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @ObservedObject var history: HistoryStore
    @Environment(\.colorScheme) private var scheme
    @State private var breathing = false
    @State private var selectedTab: Int = 0 // 0: Dictate, 1: History
    @State private var copiedId: UUID? = nil
    @State private var liveCopied: Bool = false
    @State private var permissionRefreshVersion = 0
    @AppStorage(TalkTypeConfig.engineStorageKey) private var storedEngine: String = "apple"
    @AppStorage("talktypeGhostMood") private var ghostMood: Int = 0
    @State private var hasDeepgramKey: Bool = !TalkTypeConfig.deepgramApiKey.isEmpty
    @State private var wordmarkScale: CGFloat = 1.0
    var appDelegate: AppDelegate

    private var isSupercharged: Bool {
        storedEngine == "deepgram" && hasDeepgramKey
    }

    private var currentMoodGradient: LinearGradient {
        switch ghostMood % 4 {
        case 1: return TT.cyberGhost
        case 2: return TT.matchaGhost
        case 3: return TT.amigaGhost
        default: return TT.hot
        }
    }

    private var p: Palette { scheme == .dark ? .dark : .light }
    private var isRec: Bool { speechEngine.isRecording }
    private var pttKeyName: String { TalkTypeConfig.pttTrigger.shortTitle }

    private var permissionHelpIssue: PermissionHelpIssue? {
        _ = permissionRefreshVersion
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if microphoneStatus == .denied || microphoneStatus == .restricted {
            return .microphone
        }

        if !TalkTypeConfig.isUsingDeepgram {
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            if speechStatus == .denied || speechStatus == .restricted {
                return .speechRecognition
            }
        }

#if MAS_BUILD
        return nil
#else
        return AXIsProcessTrusted() ? nil : .accessibility
#endif
    }

    var body: some View {
        VStack(spacing: permissionHelpIssue == nil ? 14 : 9) {
            // Header with Wordmark + Tab Picker (Rock-Solid Top Locked)
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
                        ghostMood = (ghostMood + 1) % 4
                        wordmarkScale = 1.08
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                            wordmarkScale = 1.0
                        }
                    }
                    NSSound(named: "Pop")?.play()
                }) {
                    HStack(spacing: 0) {
                        Text("Talk").foregroundStyle(p.ink)
                        Text("Type").foregroundStyle(currentMoodGradient)
                    }
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .kerning(-0.5)
                    .scaleEffect(wordmarkScale)
                }
                .buttonStyle(.plain)
                
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
                        Text(L10n.t("history"))
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
                if permissionHelpIssue != nil {
                    permissionHelper
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ghostButton
                statusLine

                voiceModeBadge
                    .padding(.top, 2)
                
                Spacer(minLength: 0)

                HStack {
                    Button(L10n.t("privacyPolicy")) {
                        appDelegate.openPrivacyPolicy()
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(p.inkSoft.opacity(0.5))
                    .buttonStyle(.plain)

                    Spacer()

                    Button(L10n.t("quit")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(p.inkSoft.opacity(0.5))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            } else {
                // History View (Never lose text again)
                historyCard
            }
        }
        .padding(18)
        .frame(width: 346, height: 440, alignment: .top)
        .background(p.shell)
        .animation(.easeOut(duration: 0.18), value: permissionHelpIssue)
        .onAppear {
            refreshPermissionStatus()
            hasDeepgramKey = !TalkTypeConfig.deepgramApiKey.isEmpty
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatus()
            hasDeepgramKey = !TalkTypeConfig.deepgramApiKey.isEmpty
        }
    }

    @ViewBuilder
    private var permissionHelper: some View {
        if let issue = permissionHelpIssue {
            HStack(spacing: 9) {
                Image(systemName: issue.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TT.hot)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(issue.titleKey))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(p.ink)
                    Text(L10n.t(issue.detailKey))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(p.inkSoft.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 2)

                Button(L10n.t("fixPermission")) {
                    openSystemSettings(for: issue)
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(p.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(TT.pink.opacity(0.22))
                .clipShape(Capsule())
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(p.card.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(p.border.opacity(0.7), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        }
    }

    private func openSystemSettings(for issue: PermissionHelpIssue) {
        switch issue {
        case .microphone:
            appDelegate.openMicrophoneSettings()
        case .speechRecognition:
            appDelegate.openSpeechRecognitionSettings()
        case .accessibility:
#if !MAS_BUILD
            appDelegate.openAccessibilitySettings()
#else
            break
#endif
        }
    }

    private func refreshPermissionStatus() {
        permissionRefreshVersion &+= 1
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

                    CopyPillButton(isCopied: liveCopied) {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(speechEngine.transcript, forType: .string)
                        liveCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            liveCopied = false
                        }
                    }
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
        .disabled(speechEngine.phase == .processing)
        .onChange(of: isRec) { rec in
            withAnimation(rec ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                              : .easeOut(duration: 0.2)) {
                breathing = rec
            }
        }
    }

    private var statusLine: some View {
        let label: String
        let style: AnyShapeStyle
        switch speechEngine.phase {
        case .idle:
#if MAS_BUILD
            label = L10n.t("holdGhost")
#else
            label = L10n.t("clickGhostHold") + pttKeyName
#endif
            style = AnyShapeStyle(p.inkSoft.opacity(0.75))
        case .listening:
#if MAS_BUILD
            label = L10n.t("clickAgainToFinish")
#else
            label = L10n.t("listening")
#endif
            style = AnyShapeStyle(TT.hot)
        case .processing:
            label = L10n.t("thinking")
            style = AnyShapeStyle(TT.tangerine)
        case .ready:
            label = L10n.t("ready")
            style = AnyShapeStyle(TT.hot)
        }

        return Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(style)
            .frame(height: 20)
    }

    private var voiceModeBadge: some View {
        Button(action: {
            appDelegate.promptDeepgramKey()
            hasDeepgramKey = !TalkTypeConfig.deepgramApiKey.isEmpty
        }) {
            HStack(spacing: 5) {
                if isSupercharged {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(L10n.t("superchargedActiveBadge"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(L10n.t("trySuperchargedBadge"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 4.5)
            .background(isSupercharged ? Color.mint.opacity(0.18) : TT.pink.opacity(0.12))
            .foregroundStyle(isSupercharged ? Color.mint : TT.pink)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSupercharged ? Color.mint.opacity(0.35) : TT.pink.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(isSupercharged ? L10n.t("superchargedHelp") : L10n.t("trySuperchargedHelp"))
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
                            HistoryRecordCard(
                                record: record,
                                isCopied: copiedId == record.id,
                                p: p,
                                onCopy: {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(record.text, forType: .string)
                                    copiedId = record.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        if copiedId == record.id { copiedId = nil }
                                    }
                                },
                                onDelete: {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        history.delete(id: record.id)
                                    }
                                }
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

                    Button(L10n.t("privacyPolicy")) {
                        appDelegate.openPrivacyPolicy()
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(p.inkSoft.opacity(0.5))
                    .buttonStyle(.plain)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(p.inkSoft.opacity(0.3))

                    Button(L10n.t("quit")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(p.inkSoft.opacity(0.5))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func toggle() {
        if isRec {
            appDelegate.requestPaste()
        } else {
            speechEngine.startRecording()
        }
    }
}
