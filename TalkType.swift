import Cocoa
import SwiftUI
import Speech
import AVFoundation
import ApplicationServices

// MARK: - Constants & Config
enum TalkTypeConfig {
    static let defaultDeepgramKey = "REDACTED_ROTATE_ME"
    static let deepgramKeyStorageKey = "deepgramApiKey"
    static let engineStorageKey = "talktypeEngine" // "deepgram" or "apple"
    
    static var deepgramApiKey: String {
        let custom = UserDefaults.standard.string(forKey: deepgramKeyStorageKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? defaultDeepgramKey : custom
    }
    
    static var isUsingDeepgram: Bool {
        return (UserDefaults.standard.string(forKey: engineStorageKey) ?? "deepgram") == "deepgram"
    }
}

// MARK: - App Delegate & Entry Point
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let engine = SpeechEngine()
    private var liveHUDController: LiveHUDWindowController?

    private var pttMonitors: [Any] = []
    private var pttHeld = false
    private var pendingPaste = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Request Permissions
        SFSpeechRecognizer.requestAuthorization { authStatus in
            print("Speech auth status: \(authStatus.rawValue)")
        }
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("Mic access granted: \(granted)")
        }

        // Setup Menu Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            updateMenuBarIcon(isRecording: false)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        statusItem.isVisible = true

        // Setup Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 418)
        popover.behavior = .transient
        
        // Host the SwiftUI View
        let contentView = ContentView(speechEngine: engine, appDelegate: self)
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Live HUD controller
        liveHUDController = LiveHUDWindowController(speechEngine: engine)

        // Setup paste hook
        engine.onFinal = { [weak self] text in
            guard let self = self, self.pendingPaste else { return }
            self.pendingPaste = false
            self.liveHUDController?.hide()
            self.updateMenuBarIcon(isRecording: false)
            guard !text.isEmpty else { return }
            self.pasteToActiveApp(text: text)
        }
        
        engine.onStateChange = { [weak self] isRecording in
            DispatchQueue.main.async {
                self?.updateMenuBarIcon(isRecording: isRecording)
                if isRecording {
                    self?.liveHUDController?.show()
                } else if !(self?.pendingPaste ?? false) {
                    self?.liveHUDController?.hide()
                }
            }
        }

        setupPushToTalk()
        checkAccessibilityPermissions()
    }
    
    func updateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        if let ghost = NSImage(named: "ghost-menubar") {
            let size = NSSize(width: 18, height: 18)
            ghost.size = size
            if isRecording {
                // Warm glowing blush tint when recording
                ghost.isTemplate = false
                button.image = tintedGhost(image: ghost, color: NSColor(red: 1.0, green: 0.51, blue: 0.79, alpha: 1.0))
            } else {
                ghost.isTemplate = true
                button.image = ghost
            }
        } else {
            button.title = isRecording ? "🎙️" : "👻"
        }
    }
    
    private func tintedGhost(image: NSImage, color: NSColor) -> NSImage {
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill()
        image.draw(in: imageRect, from: .zero, operation: .destinationIn, fraction: 1.0)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    /// Hold Right Option anywhere to dictate; release to paste into whatever has focus.
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
        guard event.keyCode == 61 else { return } // 61 = Right Option
        let down = event.modifierFlags.contains(.option)
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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        print("Accessibility Trusted: \(isTrusted)")
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
        
        // Model Selection Submenu
        let modelMenu = NSMenu(title: "Model")
        let isDeepgram = TalkTypeConfig.isUsingDeepgram
        
        let dgItem = NSMenuItem(title: "Deepgram Nova-3 (Live Streaming)", action: #selector(selectDeepgramModel), keyEquivalent: "1")
        dgItem.target = self
        dgItem.state = isDeepgram ? .on : .off
        modelMenu.addItem(dgItem)
        
        let appleItem = NSMenuItem(title: "Apple Speech (Offline)", action: #selector(selectAppleModel), keyEquivalent: "2")
        appleItem.target = self
        appleItem.state = !isDeepgram ? .on : .off
        modelMenu.addItem(appleItem)
        
        let modelParent = NSMenuItem(title: "Transcription Engine", action: nil, keyEquivalent: "")
        modelParent.submenu = modelMenu
        menu.addItem(modelParent)
        
        menu.addItem(NSMenuItem.separator())
        
        // Deepgram Key Config
        let keyItem = NSMenuItem(title: "Custom Deepgram Key…", action: #selector(promptDeepgramKey), keyEquivalent: "k")
        keyItem.target = self
        menu.addItem(keyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let pttInfo = NSMenuItem(title: "Shortcut: Hold Right ⌥ Option", action: nil, keyEquivalent: "")
        pttInfo.isEnabled = false
        menu.addItem(pttInfo)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit TalkType", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func selectDeepgramModel() {
        UserDefaults.standard.set("deepgram", forKey: TalkTypeConfig.engineStorageKey)
    }

    @objc func selectAppleModel() {
        UserDefaults.standard.set("apple", forKey: TalkTypeConfig.engineStorageKey)
    }

    @objc func promptDeepgramKey() {
        let alert = NSAlert()
        alert.messageText = "Deepgram API Key"
        alert.informativeText = "Enter your own Deepgram API Key (or leave blank to use the built-in fleet key):"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Use Built-in Key")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = UserDefaults.standard.string(forKey: TalkTypeConfig.deepgramKeyStorageKey) ?? ""
        input.placeholderString = "Paste API key here"
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(key, forKey: TalkTypeConfig.deepgramKeyStorageKey)
        } else if response == .alertThirdButtonReturn {
            UserDefaults.standard.removeObject(forKey: TalkTypeConfig.deepgramKeyStorageKey)
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
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
            print("Pasted: \(text)")
        }
    }
}

// MARK: - Live Transcript Floating HUD
final class LiveHUDWindowController: NSWindowController {
    init(speechEngine: SpeechEngine) {
        let size = NSSize(width: 520, height: 96)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.minY + 64
        )
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LiveTranscriptHUDView(speechEngine: speechEngine))
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        guard let window = self.window else { return }
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1.0
        }
    }
    
    func hide() {
        guard let window = self.window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}

// MARK: - Live Transcript HUD View (Blush, Warm & Delicious)
struct LiveTranscriptHUDView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @State private var wavePhase: Double = 0
    
    private var displayedText: String {
        speechEngine.transcript.isEmpty ? "Listening…" : speechEngine.transcript
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Little breathing ghost mark
            ZStack {
                Circle()
                    .fill(TT.hot.opacity(0.18))
                    .frame(width: 44, height: 44)
                
                GhostMark(isRecording: speechEngine.isRecording)
                    .frame(width: 32, height: 32)
            }
            
            // Live typing text
            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayedText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(speechEngine.transcript.isEmpty ? Color.black.opacity(0.4) : Color(red: 0.12, green: 0.09, blue: 0.08))
                    .lineLimit(2)
                    .frame(minHeight: 40, alignment: .leading)
                    .animation(.easeOut(duration: 0.15), value: displayedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Waveform recording pulse dot
            Circle()
                .fill(TT.pink)
                .frame(width: 10, height: 10)
                .shadow(color: TT.pink.opacity(0.8), radius: 6)
                .scaleEffect(1.0 + sin(wavePhase) * 0.25)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // Creamy paper surface with blush glass blur
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.99, green: 0.96, blue: 0.92).opacity(0.94))
                
                // Warm blush peach edge
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [TT.pink.opacity(0.7), TT.tangerine.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: TT.pink.opacity(0.25), radius: 18, y: 6)
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                wavePhase = .pi * 2
            }
        }
    }
}

// MARK: - Speech Engine (Deepgram Nova-3 WebSocket + Apple Fallback)
class SpeechEngine: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
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
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
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
        guard let url = URL(string: "wss://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&interim_results=true&encoding=linear16&sample_rate=16000&channels=1") else {
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
            print("Could not create audio converter")
            startAppleSpeechRecognition()
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }
            
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / nativeFormat.sampleRate)
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
                self.webSocketTask?.send(.data(data)) { sendError in
                    if let sendError = sendError {
                        print("WebSocket send error: \(sendError)")
                    }
                }
            }
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
                self.onStateChange?(true)
            }
        } catch {
            print("Audio engine start failed: \(error)")
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
                
            case .failure(let error):
                print("WebSocket receive error: \(error)")
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
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Send close frame
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
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            onStateChange?(true)
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
                var isFinal = false
                if let result = result {
                    DispatchQueue.main.async {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    isFinal = result.isFinal
                }
                
                if error != nil || isFinal {
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    DispatchQueue.main.async {
                        self.isRecording = false
                        self.onStateChange?(false)
                        self.onFinal?(self.transcript)
                    }
                }
            }
        } catch {
            print("Could not start audio engine: \(error)")
        }
    }
    
    private func stopAppleSpeechRecognition() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        onStateChange?(false)
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

// MARK: - SwiftUI Popover UI
struct ContentView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @Environment(\.colorScheme) private var scheme
    @State private var breathing = false
    var appDelegate: AppDelegate

    private var p: Palette { scheme == .dark ? .dark : .light }
    private var isRec: Bool { speechEngine.isRecording }
    private var isDeepgram: Bool { TalkTypeConfig.isUsingDeepgram }

    var body: some View {
        VStack(spacing: 14) {
            wordmark
            transcriptCard
            ghostButton
            statusLine
        }
        .padding(22)
        .frame(width: 320, height: 418)
        .background(p.shell)
    }

    private var wordmark: some View {
        HStack(spacing: 0) {
            Text("Talk").foregroundStyle(p.ink)
            Text("Type").foregroundStyle(TT.hot)
        }
        .font(.system(size: 30, weight: .heavy, design: .rounded))
        .kerning(-0.5)
    }

    private var transcriptCard: some View {
        ScrollView {
            Text(speechEngine.transcript.isEmpty
                 ? "Hold the ghost to start talking…"
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
        VStack(spacing: 4) {
            Text(isRec ? "Listening (\(isDeepgram ? "Deepgram Nova-3" : "Apple Speech"))…" : "Click ghost or hold ⌥ Right Option")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isRec ? AnyShapeStyle(TT.hot) : AnyShapeStyle(p.inkSoft.opacity(0.8)))
            
            Text(isDeepgram ? "⚡ Live streaming with Nova-3" : "🔒 Offline Apple Speech")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(p.inkSoft.opacity(0.5))
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
