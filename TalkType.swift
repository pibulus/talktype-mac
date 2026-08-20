import Cocoa
import SwiftUI
import Speech
import AVFoundation
import ApplicationServices

// MARK: - App Delegate & Entry Point
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let engine = SpeechEngine()

    private var pttMonitors: [Any] = []
    private var pttHeld = false
    private var pendingPaste = false

    // Explicit entry point. The default @main for NSApplicationDelegate goes through
    // NSApplicationMain, which expects a nib to install the delegate -- we have no nib,
    // so applicationDidFinishLaunching never fired and the app sat there doing nothing.
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
            if let ghost = NSImage(named: "ghost-menubar") {
                ghost.isTemplate = true          // macOS tints it for light/dark menu bars
                ghost.size = NSSize(width: 18, height: 18)
                button.image = ghost
            } else {
                button.title = "👻"
            }
            button.action = #selector(togglePopover(_:))
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
        
        // Paste when the recogniser is actually done, not after a guessed delay.
        engine.onFinal = { [weak self] text in
            guard let self = self, self.pendingPaste else { return }
            self.pendingPaste = false
            guard !text.isEmpty else { return }
            self.pasteToActiveApp(text: text)
        }

        setupPushToTalk()

        // Check Accessibility Permissions early
        checkAccessibilityPermissions()
    }
    
    /// Hold Right Option anywhere to dictate; release to paste into whatever has focus.
    /// Global monitors and CGEvent posting both need Accessibility, so it is one permission.
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
        guard event.keyCode == 61 else { return }        // 61 = Right Option
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

    /// Stop-and-paste, shared by the ghost button and push-to-talk.
    func requestPaste() {
        pendingPaste = true
        engine.stopRecording()
    }

    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        print("Accessibility Trusted: \(isTrusted)")
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
        // First put text on clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Hide popover so focus returns to the active app
        popover.performClose(nil)
        
        // Give macOS a tiny fraction of a second to return focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Simulate Cmd+V using CGEvent
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

// MARK: - Speech Engine
class SpeechEngine: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var transcript = ""
    @Published var isRecording = false

    /// Fires once the recogniser has settled. Paste hangs off this, not off a guessed delay.
    var onFinal: ((String) -> Void)?
    
    func startRecording() {
        if audioEngine.isRunning {
            stopRecording()
            return
        }
        
        transcript = ""
        

        
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
                        self.onFinal?(self.transcript)
                    }
                }
            }
        } catch {
            print("Could not start audio engine: \(error)")
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
    }
}

// MARK: - TalkType Palette
// Tones lifted from talktype/src/app.css. Cream paper, warm near-black ink,
// the peach ghost gradient. No #fff, no #000 — light mode or dark.
struct Palette {
    let ink: Color          // primary type
    let inkSoft: Color      // secondary type
    let paper: Color        // shell mid
    let paperLit: Color     // shell highlight
    let paperDim: Color     // shell edge
    let card: Color         // transcript surface
    let border: Color       // warm sepia rule
    let shadow: Color
    /// What lifts the ghost off the page. On cream that is a shadow; on a dark
    /// ground a shadow is invisible, so it becomes a soft peach glow instead.
    let ghostLift: Color
    let ghostLiftRadius: CGFloat
    let ghostLiftY: CGFloat

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }

    /// Cream. The web app's page shell, unchanged.
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

    /// Night. Same warmth, inverted — the ink becomes the paper.
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
    /// The ghost's own ink. Fixed, never themed — see GhostMark.
    static let ghostInk  = Palette.rgb(30, 23, 20)     // #1e1714
    static let pink      = Palette.rgb(255, 130, 202)  // #ff82ca
    static let tangerine = Palette.rgb(255, 176,  96)  // #ffb060

    /// The peach ghost gradient, stop for stop, from ghost/gradients.js
    static let peachGhost = LinearGradient(
        stops: [.init(color: Palette.rgb(255,  96, 224), location: 0.00),  // #ff60e0
                .init(color: Palette.rgb(255, 130, 202), location: 0.35),  // #ff82ca
                .init(color: Palette.rgb(255, 154, 133), location: 0.65),  // #ff9a85
                .init(color: Palette.rgb(255, 176,  96), location: 0.85),  // #ffb060
                .init(color: Palette.rgb(255, 207,  64), location: 1.00)], // #ffcf40
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let hot = LinearGradient(colors: [pink, tangerine],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The ghost, alive. Three layers — gradient body, ink linework, ink eyes — so the
/// eyes can blink independently. Timings are lifted from the web app's
/// ghost/animationConfig.js and ghost-animations-optimized.css, not invented:
///   blink gap 4–9s · single blink 180ms · 25% chance of a double (80ms apart)
///   idle float 5.8s · recording float 3.4s · recording breathe 2.6s
struct GhostMark: View {
    var isRecording = false

    @State private var eyeScale: CGFloat = 1
    @State private var floatY: CGFloat = 0
    @State private var tilt: Double = 0
    @State private var blinkTimer: Timer?

    // Eyes sit at y=464 of the 1024 canvas; blink squashes about their own centre,
    // not the canvas centre, or they slide down the face.
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
        let gap = Double.random(in: 4.0...9.0)          // BLINK_CONFIG MIN_GAP / MAX_GAP
        blinkTimer = Timer.scheduledTimer(withTimeInterval: gap, repeats: false) { _ in
            blink(double: Double.random(in: 0...1) < 0.25)   // DOUBLE_CHANCE
            scheduleBlink()
        }
    }

    private func blink(double: Bool) {
        shut()
        if double {
            // 180ms blink, 80ms pause, then the second one.
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

// MARK: - SwiftUI UI
struct ContentView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @Environment(\.colorScheme) private var scheme
    @State private var breathing = false
    var appDelegate: AppDelegate

    private var p: Palette { scheme == .dark ? .dark : .light }
    private var isRec: Bool { speechEngine.isRecording }

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

    // "Talk" in ink, "Type" in the brand gradient — same split as the web app.
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
        VStack(spacing: 3) {
            Text(isRec ? "Listening…" : "Click the ghost, we do the most.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isRec ? AnyShapeStyle(TT.hot) : AnyShapeStyle(p.inkSoft.opacity(0.8)))
            Text("or hold ⌥ right option, anywhere")
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
