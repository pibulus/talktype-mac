import Cocoa
import SwiftUI
import Speech
import AVFoundation
import ApplicationServices
import Security

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
        case .rightOption: return "Right ⌥ Option (Default)"
        case .leftOption: return "Left ⌥ Option"
        case .eitherOption: return "Either ⌥ Option"
        case .function: return "Globe / Function (fn) 🌐"
        case .rightCommand: return "Right ⌘ Command"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .rightOption: return "Right ⌥ Option"
        case .leftOption: return "Left ⌥ Option"
        case .eitherOption: return "Either ⌥ Option"
        case .function: return "Globe / fn 🌐"
        case .rightCommand: return "Right ⌘ Command"
        }
    }
    
    func matches(event: NSEvent) -> Bool? {
        switch self {
        case .rightOption:
            guard event.keyCode == 61 else { return nil }
            return event.modifierFlags.contains(.option)
        case .leftOption:
            guard event.keyCode == 58 else { return nil }
            return event.modifierFlags.contains(.option)
        case .eitherOption:
            guard event.keyCode == 61 || event.keyCode == 58 else { return nil }
            return event.modifierFlags.contains(.option)
        case .function:
            guard event.keyCode == 63 else { return nil }
            return event.modifierFlags.contains(.function)
        case .rightCommand:
            guard event.keyCode == 54 else { return nil }
            return event.modifierFlags.contains(.command)
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
        case .auto: return Locale.current
        case .en: return Locale(identifier: "en-US")
        case .es: return Locale(identifier: "es-ES")
        }
    }

    var deepgramLanguage: String {
        switch self {
        case .auto: return "multi"
        case .en: return "en"
        case .es: return "es"
        }
    }
}

// MARK: - Localization
enum L10n {
    static func t(_ key: String) -> String {
        let lang = TalkTypeConfig.language == .es ? "es" : "en"
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
        "dgAlertTitle": ["en": "Deepgram API Key", "es": "Clave de API de Deepgram"],
        "dgAlertInfo": ["en": "Enter your Deepgram API Key for live streaming transcription (leave empty to use Apple on-device speech). No key? Get one free at console.deepgram.com.", "es": "Introduce tu clave de API de Deepgram para la transcripción en vivo (déjala vacía para usar la voz en el dispositivo de Apple). ¿Sin clave? Consíguela gratis en console.deepgram.com."],
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
        "geminiAlertTitle": ["en": "Gemini API Key", "es": "Clave de API de Gemini"],
        "geminiAlertInfo": ["en": "Optional. Paste a Gemini API key to polish transcripts into clean prose (leave empty to keep raw text). No key? Get one free at aistudio.google.com.", "es": "Opcional. Pega una clave de API de Gemini para pulir las transcripciones (déjala vacía para conservar el texto original). ¿Sin clave? Consíguela gratis en aistudio.google.com."]
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
        let raw = UserDefaults.standard.string(forKey: pttTriggerStorageKey) ?? PTTTrigger.rightOption.rawValue
        return PTTTrigger(rawValue: raw) ?? .rightOption
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
        
        let record = TranscriptRecord(text: trimmed, engine: engine)
        DispatchQueue.main.async {
            self.records.insert(record, at: 0)
            if self.records.count > 50 {
                self.records = Array(self.records.prefix(50))
            }
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

    private var pttMonitors: [Any] = []
    private var pttHeld = false
    private var pendingPaste = false
    
    private var menubarBounceTimer: Timer?
    private var bouncePhase: Double = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

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
        engine.onFinal = { [weak self] text in
            guard let self = self else { return }
            let engineName = TalkTypeConfig.isUsingDeepgram ? "Nova-3" : "Apple"
            if !text.isEmpty {
                self.history.add(text: text, engine: engineName)
            }
            
            guard self.pendingPaste else { return }
            self.pendingPaste = false
            self.stopMenubarBounce()
            guard !text.isEmpty else {
                self.liveHUDController?.hide()
                return
            }
            
            let deliver = { (finalText: String) in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(finalText, forType: .string)
                
                #if MAS_BUILD
                // Sandboxed App Store build: no Accessibility/auto-paste. Clipboard only.
                self.engine.transcript = L10n.t("copiedToClipboard")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.liveHUDController?.hide()
                }
                #else
                if AXIsProcessTrusted() {
                    self.liveHUDController?.hide()
                    self.pasteToActiveApp(text: finalText)
                } else {
                    // Clipboard fallback with explicit visual feedback
                    self.engine.transcript = L10n.t("copiedToClipboard")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        self?.liveHUDController?.hide()
                    }
                }
                #endif
            }
            
            if TalkTypeConfig.isPolishing && !TalkTypeConfig.geminiApiKey.isEmpty {
                self.engine.transcript = L10n.t("polishing")
                Polisher.polish(text) { polished in
                    deliver(polished)
                }
            } else {
                deliver(text)
            }
        }
        
        engine.onStateChange = { [weak self] isRecording in
            DispatchQueue.main.async {
                if isRecording {
                    self?.startMenubarBounce()
                    self?.liveHUDController?.show()
                } else {
                    self?.stopMenubarBounce()
                    if !(self?.pendingPaste ?? false) {
                        self?.liveHUDController?.hide()
                    }
                }
            }
        }

        setupPushToTalk()
        checkAccessibilityPermissions()
    }
    
    // MARK: - Menu Bar Icon (Original TalkType Ghost with Smooth Floating Animation)
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
        guard let originalGhost = NSImage(named: "ghost-menubar") else { return }
        bouncePhase = 0
        
        // Silky 30fps harmonic floating sine wave
        menubarBounceTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem.button else { return }
            self.bouncePhase += 0.16
            let yOffset = sin(self.bouncePhase) * 1.8
            
            let size = NSSize(width: 18, height: 18)
            let bounced = NSImage(size: size)
            bounced.lockFocus()
            
            originalGhost.draw(in: NSRect(x: 0, y: yOffset, width: 18, height: 18),
                               from: .zero,
                               operation: .sourceOver,
                               fraction: 1.0)
            
            bounced.unlockFocus()
            bounced.isTemplate = true
            button.image = bounced
        }
    }
    
    func stopMenubarBounce() {
        menubarBounceTimer?.invalidate()
        menubarBounceTimer = nil
        resetMenuBarIcon()
    }

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
        let trigger = TalkTypeConfig.pttTrigger
        guard let down = trigger.matches(event: event) else { return }
        
        if down, !pttHeld {
            pttHeld = true
            engine.startRecording()
        } else if !down, pttHeld {
            pttHeld = false
            pendingPaste = true
            engine.stopRecording()
        }
    }

    func requestPaste() {
        pendingPaste = true
        engine.stopRecording()
    }

    func checkAccessibilityPermissions() {
        #if !MAS_BUILD
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
        #endif
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
        
        // Accessibility Status Alert if not trusted (direct distribution only)
        #if !MAS_BUILD
        if !AXIsProcessTrusted() {
            let permItem = NSMenuItem(title: L10n.t("accessibilityDisabled"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
            menu.addItem(NSMenuItem.separator())
        }
        #endif
        
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
        
        menu.addItem(NSMenuItem.separator())
        
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
            if let url = URL(string: "https://aistudio.google.com") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        popover.performClose(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let vKeyCode: CGKeyCode = 9 // 'v' key
            let cmdFlag = CGEventFlags.maskCommand
            
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
                return
            }
            
            keyDown.flags = cmdFlag
            keyUp.flags = cmdFlag
            
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Live Transcript Floating HUD Window Controller
final class LiveHUDWindowController: NSWindowController {
    let size = NSSize(width: 580, height: 76)
    private var isVisibleTarget = false
    private let speechEngine: SpeechEngine

    init(speechEngine: SpeechEngine) {
        self.speechEngine = speechEngine
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        // Content is built in show() and torn down in hide(). The HUD's
        // .repeatForever animations keep CoreAnimation committing frames for
        // as long as the view exists — orderOut() does not stop them — so a
        // view built here would spin ~50% of a core from launch, forever.

        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updatePosition() {
        guard let window = self.window else { return }
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let isTop = TalkTypeConfig.hudPosition == "top"
        let y = isTop ? (screenFrame.maxY - size.height - 32) : (screenFrame.minY + 68)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: y)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
    
    func show() {
        guard let window = self.window else { return }
        isVisibleTarget = true
        if !(window.contentView is NSHostingView<LiveTranscriptHUDView>) {
            window.contentView = NSHostingView(
                rootView: LiveTranscriptHUDView(speechEngine: speechEngine))
        }
        updatePosition()
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            window.animator().alphaValue = 1.0
        }
    }
    
    func hide() {
        guard let window = self.window else { return }
        isVisibleTarget = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            if !self.isVisibleTarget {
                window.orderOut(nil)
                // Release the SwiftUI view; that is what actually stops the
                // repeating animations and drops CPU back to idle.
                window.contentView = NSView()
            }
        })
    }
}

// MARK: - Live Transcript HUD View (Pure Crisp Rounded Capsule, 4.5px Chunky Neon Glow Border)
struct LiveTranscriptHUDView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @State private var wavePhase: Double = 0
    @State private var borderAngle: Double = 0
    @State private var ghostBounce: CGFloat = 1.0
    
    private var displayedText: String {
        speechEngine.transcript.isEmpty ? L10n.t("listeningSpeak") : speechEngine.transcript
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TalkType live speech: \(displayedText)")
        .onAppear {
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

// MARK: - Speech Engine (Deepgram Nova-3 WebSocket + Apple Fallback)
class SpeechEngine: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    private var speechRecognizer: SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: TalkTypeConfig.language.appleLocale)
    }
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var hasInstalledAudioTap = false
    
    // Deepgram WebSocket
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var confirmedTranscript = ""
    private var interimTranscript = ""
    
    @Published var transcript = ""
    @Published var isRecording = false

    var onFinal: ((String) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    
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
    
    @objc private func handleAudioEngineConfigChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // CoreAudio has already invalidated the tap on hardware switch
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
    
    func startRecording() {
        if audioEngine.isRunning {
            stopRecording()
            return
        }
        
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
        if TalkTypeConfig.isUsingDeepgram {
            stopDeepgramStreaming()
        } else {
            stopAppleSpeechRecognition()
        }
    }
    
    // MARK: - Deepgram WebSocket Streaming
    private func startDeepgramStreaming() {
        let apiKey = TalkTypeConfig.deepgramApiKey
        guard !apiKey.isEmpty,
              let url = URL(string: "wss://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&interim_results=true&encoding=linear16&sample_rate=16000&channels=1&language=\(TalkTypeConfig.language.deepgramLanguage)") else {
            startAppleSpeechRecognition()
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        listenWebSocket()
        
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else {
            startAppleSpeechRecognition()
            return
        }
        
        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            startAppleSpeechRecognition()
            return
        }
        
        safeRemoveTap()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }
            
            let frameCount = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000.0 / nativeFormat.sampleRate) + 2)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
            
            var error: NSError?
            var allRead = false
            converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                if allRead {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                allRead = true
                outStatus.pointee = .haveData
                return buffer
            }
            
            if let channelData = convertedBuffer.int16ChannelData {
                let channelDataPointer = channelData.pointee
                let data = Data(bytes: channelDataPointer, count: Int(convertedBuffer.frameLength) * 2)
                self.webSocketTask?.send(.data(data)) { _ in }
            }
        }
        hasInstalledAudioTap = true
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
                self.onStateChange?(true)
            }
        } catch {
            safeRemoveTap()
            stopRecording()
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
                
            case .failure:
                // If Deepgram WebSocket fails mid-recording, seamlessly fallback
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.isRecording else { return }
                    self.safeRemoveTap()
                    self.audioEngine.stop()
                    self.startAppleSpeechRecognition()
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
        let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        
        DispatchQueue.main.async {
            if isFinal && !trimmedChunk.isEmpty {
                if self.confirmedTranscript.isEmpty {
                    self.confirmedTranscript = trimmedChunk
                } else {
                    self.confirmedTranscript += " " + trimmedChunk
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
        audioEngine.stop()
        safeRemoveTap()
        
        let closeData = Data()
        webSocketTask?.send(.data(closeData)) { _ in }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            self.isRecording = false
            self.onStateChange?(false)
            
            let finalOutput = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            self.onFinal?(finalOutput)
        }
    }
    
    // MARK: - Apple Speech Fallback
    private func startAppleSpeechRecognition() {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        safeRemoveTap()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        hasInstalledAudioTap = true
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
                self.onStateChange?(true)
            }
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                var isFinal = false
                if let result = result {
                    DispatchQueue.main.async {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    isFinal = result.isFinal
                }
                
                if error != nil || isFinal {
                    DispatchQueue.main.async {
                        self.audioEngine.stop()
                        self.safeRemoveTap()
                        self.recognitionRequest = nil
                        self.recognitionTask = nil
                        self.isRecording = false
                        self.onStateChange?(false)
                        self.onFinal?(self.transcript)
                    }
                }
            }
        } catch {
            safeRemoveTap()
            print("Could not start audio engine: \(error)")
        }
    }
    
    private func stopAppleSpeechRecognition() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.audioEngine.stop()
            self.recognitionRequest?.endAudio()
            self.safeRemoveTap()
            self.isRecording = false
            self.onStateChange?(false)
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
        .frame(width: 330, height: 440, alignment: .top)
        .background(p.shell)
    }

    private var transcriptCard: some View {
        ScrollView {
            Text(speechEngine.transcript.isEmpty
                 ? L10n.t("holdGhost")
                 : speechEngine.transcript)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .lineSpacing(3)
                .foregroundStyle(speechEngine.transcript.isEmpty ? p.inkSoft.opacity(0.55) : p.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
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

    private var statusLine: some View {
        Text(isRec ? L10n.t("listening") : L10n.t("clickGhostHold") + pttKeyName)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isRec ? AnyShapeStyle(TT.hot) : AnyShapeStyle(p.inkSoft.opacity(0.75)))
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
            speechEngine.startRecording()
        }
    }
}
