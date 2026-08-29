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
    static let hudPositionStorageKey = "hudPosition" // "bottom" or "top"
    static let historyStorageKey = "talktypeHistory"
    
    static var deepgramApiKey: String {
        let custom = UserDefaults.standard.string(forKey: deepgramKeyStorageKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? defaultDeepgramKey : custom
    }
    
    static var isUsingDeepgram: Bool {
        return (UserDefaults.standard.string(forKey: engineStorageKey) ?? "deepgram") == "deepgram"
    }
    
    static var hudPosition: String {
        return UserDefaults.standard.string(forKey: hudPositionStorageKey) ?? "bottom"
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

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
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
    
    // Generates sleek native vector icons: open eyes when idle, smiling listening slits (^ ^) when recording
    func updateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size)
        icon.lockFocus()
        
        // Base ghost silhouette
        let path = NSBezierPath()
        // Head curve
        path.move(to: NSPoint(x: 9, y: 16))
        path.curve(to: NSPoint(x: 16, y: 9.5), controlPoint1: NSPoint(x: 14.5, y: 16), controlPoint2: NSPoint(x: 16, y: 13.5))
        // Right side
        path.line(to: NSPoint(x: 16, y: 4))
        // Bottom ruffles / skirt
        path.curve(to: NSPoint(x: 12.5, y: 5), controlPoint1: NSPoint(x: 15, y: 4.5), controlPoint2: NSPoint(x: 14, y: 5.5))
        path.curve(to: NSPoint(x: 9, y: 3.5), controlPoint1: NSPoint(x: 11, y: 4.5), controlPoint2: NSPoint(x: 10, y: 3.5))
        path.curve(to: NSPoint(x: 5.5, y: 5), controlPoint1: NSPoint(x: 8, y: 3.5), controlPoint2: NSPoint(x: 7, y: 4.5))
        path.curve(to: NSPoint(x: 2, y: 4), controlPoint1: NSPoint(x: 4, y: 5.5), controlPoint2: NSPoint(x: 3, y: 4.5))
        // Left side
        path.line(to: NSPoint(x: 2, y: 9.5))
        path.curve(to: NSPoint(x: 9, y: 16), controlPoint1: NSPoint(x: 2, y: 13.5), controlPoint2: NSPoint(x: 3.5, y: 16))
        path.close()
        
        NSColor.black.setFill()
        path.fill()
        
        // Eyes (cut out from the silhouette)
        
        if isRecording {
            // Cute listening slits / smiling squint (^ ^)
            let leftEye = NSBezierPath()
            leftEye.move(to: NSPoint(x: 5.0, y: 10.0))
            leftEye.line(to: NSPoint(x: 6.5, y: 11.5))
            leftEye.line(to: NSPoint(x: 8.0, y: 10.0))
            leftEye.lineWidth = 1.3
            leftEye.lineCapStyle = .round
            
            let rightEye = NSBezierPath()
            rightEye.move(to: NSPoint(x: 10.0, y: 10.0))
            rightEye.line(to: NSPoint(x: 11.5, y: 11.5))
            rightEye.line(to: NSPoint(x: 13.0, y: 10.0))
            rightEye.lineWidth = 1.3
            rightEye.lineCapStyle = .round
            
            NSGraphicsContext.current?.compositingOperation = .clear
            leftEye.stroke()
            rightEye.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        } else {
            // Open dot eyes
            let leftEye = NSRect(x: 5.5, y: 9.5, width: 2.2, height: 2.5)
            let rightEye = NSRect(x: 10.3, y: 9.5, width: 2.2, height: 2.5)
            
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: leftEye).fill()
            NSBezierPath(ovalIn: rightEye).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }
        
        icon.unlockFocus()
        icon.isTemplate = true
        button.image = icon
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
        
        // Quick Recovery: Copy Last Transcript
        if let last = history.records.first {
            let snippet = last.text.count > 32 ? String(last.text.prefix(30)) + "…" : last.text
            let copyLast = NSMenuItem(title: "Copy Last: \"\(snippet)\"", action: #selector(copyLastTranscript), keyEquivalent: "c")
            copyLast.target = self
            menu.addItem(copyLast)
        } else {
            let copyLast = NSMenuItem(title: "No Recent Transcripts", action: nil, keyEquivalent: "")
            copyLast.isEnabled = false
            menu.addItem(copyLast)
        }
        
        // Recent History Submenu
        let historyMenu = NSMenu(title: "Recent")
        if history.records.isEmpty {
            let empty = NSMenuItem(title: "History empty", action: nil, keyEquivalent: "")
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
        let historyParent = NSMenuItem(title: "Recent Transcripts (\(history.records.count))", action: nil, keyEquivalent: "")
        historyParent.submenu = historyMenu
        menu.addItem(historyParent)
        
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
        
        // HUD Position Submenu
        let posMenu = NSMenu(title: "HUD Position")
        let isTop = TalkTypeConfig.hudPosition == "top"
        
        let posBottom = NSMenuItem(title: "Bottom of Screen", action: #selector(setHudBottom), keyEquivalent: "")
        posBottom.target = self
        posBottom.state = !isTop ? .on : .off
        posMenu.addItem(posBottom)
        
        let posTop = NSMenuItem(title: "Top of Screen", action: #selector(setHudTop), keyEquivalent: "")
        posTop.target = self
        posTop.state = isTop ? .on : .off
        posMenu.addItem(posTop)
        
        let posParent = NSMenuItem(title: "HUD Position", action: nil, keyEquivalent: "")
        posParent.submenu = posMenu
        menu.addItem(posParent)
        
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

    @objc func copyLastTranscript() {
        if let last = history.records.first {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(last.text, forType: .string)
            print("Copied last transcript to clipboard: \(last.text)")
        }
    }

    @objc func copySpecificRecord(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("Copied transcript to clipboard: \(text)")
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

// MARK: - Live Transcript Floating HUD Window Controller
final class LiveHUDWindowController: NSWindowController {
    let size = NSSize(width: 640, height: 110)
    
    init(speechEngine: SpeechEngine) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let isTop = TalkTypeConfig.hudPosition == "top"
        let y = isTop ? (screenFrame.maxY - size.height - 32) : (screenFrame.minY + 68)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: y)
        
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
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LiveTranscriptHUDView(speechEngine: speechEngine))
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updatePosition() {
        guard let window = self.window else { return }
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let isTop = TalkTypeConfig.hudPosition == "top"
        let y = isTop ? (screenFrame.maxY - size.height - 32) : (screenFrame.minY + 68)
        window.setFrameOrigin(NSPoint(x: screenFrame.midX - size.width / 2, y: y))
    }
    
    func show() {
        guard let window = self.window else { return }
        updatePosition()
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1.0
        }
    }
    
    func hide() {
        guard let window = self.window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}

// MARK: - Live Transcript HUD View (Lush, Floating, Liquid Color Flow)
struct LiveTranscriptHUDView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @State private var wavePhase: Double = 0
    @State private var borderAngle: Double = 0
    @State private var ghostBounce: CGFloat = 1.0
    
    private var displayedText: String {
        speechEngine.transcript.isEmpty ? "Listening… speak freely" : speechEngine.transcript
    }
    
    var body: some View {
        // Container with generous internal padding so soft shadows and glowing corners never clip
        ZStack {
            HStack(spacing: 16) {
                // Animated Peach Ghost with bouncy reaction
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [TT.pink.opacity(0.32), TT.tangerine.opacity(0.12)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 28
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    GhostMark(isRecording: speechEngine.isRecording)
                        .frame(width: 36, height: 36)
                        .scaleEffect(ghostBounce)
                }
                .shadow(color: TT.pink.opacity(0.35), radius: 8, x: 0, y: 2)
                
                // Auto-scrolling Live Text Container (never cuts off)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            Text(displayedText)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
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
                        .padding(.vertical, 4)
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
                        // Cute subtle bounce when words stream in
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
                    // Expanding outer aura ring
                    Circle()
                        .stroke(TT.pink.opacity(0.45), lineWidth: 1.5)
                        .scaleEffect(1.0 + CGFloat(sin(wavePhase)) * 0.45)
                        .opacity(0.85 - sin(wavePhase) * 0.35)
                        .frame(width: 26, height: 26)
                    
                    // Soft glow halo
                    Circle()
                        .fill(TT.hot)
                        .frame(width: 12, height: 12)
                        .shadow(color: TT.pink.opacity(0.85), radius: 8)
                }
                .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // Warm creamy paper grounding
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color(red: 0.992, green: 0.965, blue: 0.932).opacity(0.95))
                    
                    // Liquid gradient color flow on outline
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
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
                            lineWidth: 2.5
                        )
                    
                    // Inner hairline highlight
                    RoundedRectangle(cornerRadius: 31, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                        .padding(1)
                }
            )
            // Multi-stage drop shadows
            .shadow(color: TT.pink.opacity(0.32), radius: 22, x: 0, y: 8)
            .shadow(color: Color(red: 0.12, green: 0.09, blue: 0.08).opacity(0.12), radius: 10, x: 0, y: 3)
        }
        .padding(8) // Prevents window boundary clip
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                wavePhase = .pi * 2
            }
            withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                borderAngle = 360
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
    private var isDeepgram: Bool { TalkTypeConfig.isUsingDeepgram }

    var body: some View {
        VStack(spacing: 12) {
            // Header with Wordmark + Tab Picker
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
                        Text("Live")
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
                            Text("History")
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
        .frame(width: 330, height: 440)
        .background(p.shell)
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

    private var historyCard: some View {
        VStack(spacing: 8) {
            if history.records.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(p.inkSoft.opacity(0.35))
                    Text("No transcripts saved yet.")
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
                                            Text(copiedId == record.id ? "Copied!" : "Copy")
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
                .frame(maxHeight: 330)
                
                HStack {
                    Button("Clear History") {
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
