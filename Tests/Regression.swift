// Concatenated with TalkType.swift by run-regressions.sh. No mic or network is used.
import Foundation

private enum AuditKeychain {
    static var readStatus: OSStatus = errSecItemNotFound
    static var updateStatus: OSStatus = errSecItemNotFound
    static var addStatus: OSStatus = errSecInteractionNotAllowed
    static var stored: Data?
    static var writes = 0
    static var reads = 0
    static func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
        writes += 1
        return updateStatus
    }
    static func add(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        writes += 1
        if addStatus == errSecSuccess {
            stored = (query as NSDictionary)[kSecValueData] as? Data
            readStatus = errSecSuccess
        }
        return addStatus
    }
    static func read(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        reads += 1
        if readStatus == errSecSuccess { result?.pointee = stored as CFTypeRef? }
        return readStatus
    }
    static func delete(_ query: CFDictionary) -> OSStatus { errSecItemNotFound }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
private func pump(_ seconds: Double = 0.03) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

extension KeychainHelper {
    static func regressionChecks() {
        let legacy = TalkTypeConfig.deepgramKeyStorageKey
        UserDefaults.standard.set("fixture-key", forKey: legacy)
        expect(TalkTypeConfig.deepgramApiKey.isEmpty, "Failed migration must not activate cloud")
        expect(UserDefaults.standard.string(forKey: legacy) == "fixture-key", "Failed migration lost its source")
        AuditKeychain.addStatus = errSecSuccess
        expect(TalkTypeConfig.deepgramApiKey == "fixture-key", "Successful migration lost value")
        expect(UserDefaults.standard.object(forKey: legacy) == nil, "Successful migration left plaintext")
        AuditKeychain.readStatus = errSecInteractionNotAllowed
        AuditKeychain.writes = 0
        UserDefaults.standard.set("outdated-key", forKey: legacy)
        expect(TalkTypeConfig.deepgramApiKey.isEmpty, "Denied read returned a credential")
        expect(AuditKeychain.writes == 0, "Denied read caused an existing credential to be overwritten")
        expect(UserDefaults.standard.string(forKey: legacy) == "outdated-key", "Denied read erased migration source")
        pump() // Settle previous error notifications before checking repeated reads.
        reportedReadFailures.removeAll()
        var reports = 0
        onFailure = { _ in reports += 1 }
        for _ in 0..<20 { _ = lookup(service: "fixture", account: "fixture") }
        pump()
        expect(reports == 1, "Configuration reads create a HUD feedback loop")
        _ = save("new-key", service: "fixture", account: "fixture")
        // updateStatus is missing and add succeeds here: no error.
        expect(delete(service: "fixture", account: "fixture"), "Deleting an absent key should succeed")
        onFailure = nil
        UserDefaults.standard.removeObject(forKey: legacy)
        print("PASS Keychain migration success/failure, denied-read preservation, repeated error suppression")
    }
}

extension SpeechEngine {
    private static func fixture(_ text: String, final: Bool, start: Double = 0) -> String {
        let body: [String: Any] = ["type":"Results", "start":start, "duration":1.0,
                                  "is_final":final, "speech_final":final,
                                  "channel":["alternatives":[["transcript":text]]]]
        return String(data: try! JSONSerialization.data(withJSONObject: body), encoding: .utf8)!
    }
    static func regressionChecks() {
        let engine = SpeechEngine()
        var delivered: [String] = []
        engine.onFinal = { text in delivered.append(text); engine.phase = .ready }
        let socket = URLSession.shared.webSocketTask(with: URL(string: "wss://example.invalid")!)
        // Intentionally never resumed. Captured audio and credentials cannot leave this test.
        engine.webSocketTask = socket
        engine.activeBackend = .deepgram
        engine.isRecording = true
        engine.phase = .listening
        let oldSession = engine.currentSessionId
        engine.parseDeepgramJSON(fixture("hello world", final: false))
        engine.stopRecording()
        engine.stopRecording()
        pump(0.5) // A legitimate final can arrive after the old 350ms cutoff.
        expect(delivered.isEmpty, "Stop published before final processing completed")
        engine.parseDeepgramJSON(fixture("Hello world.", final: true))
        engine.parseDeepgramJSON(fixture("Hello world.", final: true))
        engine.parseDeepgramJSON("{\"type\":\"Metadata\"}")
        expect(delivered == ["Hello world."], "Interim/final or repeated stop duplicated delivery")
        engine.currentSessionId = UUID()
        engine.isRecording = true
        engine.transcript = "new take"
        engine.finishDeepgram(sessionID: oldSession, socket: socket)
        expect(engine.isRecording && engine.transcript == "new take", "Old completion stopped a new take")
        engine.isRecording = false
        engine.phase = .processing
        let blockedSession = engine.currentSessionId
        engine.startRecording()
        expect(engine.currentSessionId == blockedSession && engine.phase == .processing, "Restart discarded a pending take")
        print("PASS late Deepgram final, duplicate final, double stop, stale completion, processing guard")

        // The deadline must exist even if conversion has not drained.
        let blocked = DispatchSemaphore(value: 0)
        engine.audioProcessingQueue.async { blocked.wait() }
        let stalled = URLSession.shared.webSocketTask(with: URL(string: "wss://example.invalid")!)
        engine.webSocketTask = stalled
        engine.isRecording = true
        engine.phase = .listening
        engine.transcript = "retained partial"
        engine.interimTranscript = ""
        engine.stopRecording()
        expect(engine.deepgramStopDeadline != nil, "Deadline was deferred behind audio conversion")
        engine.deepgramStopDeadline?.perform()
        expect(delivered.last == "retained partial" && !engine.isStopping, "Deadline did not recover a blocked drain")
        blocked.signal()
        engine.audioProcessingQueue.sync {}
        print("PASS stop deadline remains independent of the audio queue")

        // Drive the actual Apple result reducer without invoking SFSpeechRecognizer.
        engine.currentSessionId = UUID()
        engine.appleTaskID = UUID()
        let sessionID = engine.currentSessionId
        let taskID = engine.appleTaskID
        engine.confirmedTranscript = "Earlier sentence."
        engine.appleSegmentText = ""
        engine.isStopping = true
        engine.receiveAppleResult(text: "Trailing words.", isFinal: false, error: nil, sessionID: sessionID, taskID: taskID)
        engine.receiveAppleResult(text: "", isFinal: true, error: nil, sessionID: sessionID, taskID: taskID)
        let count = delivered.count
        expect(delivered.last == "Earlier sentence. Trailing words.", "Empty Apple final erased words")
        engine.receiveAppleResult(text: "duplicate", isFinal: true, error: nil, sessionID: sessionID, taskID: taskID)
        expect(delivered.count == count, "Finished Apple task delivered twice")
        engine.currentSessionId = UUID()
        engine.appleTaskID = UUID()
        engine.confirmedTranscript = ""
        engine.appleSegmentText = "Kept before error."
        engine.isRecording = true
        var failures = 0
        engine.onFailure = { _ in failures += 1 }
        engine.receiveAppleResult(text: nil, isFinal: false, error: NSError(domain: "Fixture", code: 1),
                                  sessionID: engine.currentSessionId, taskID: engine.appleTaskID)
        expect(!engine.isRecording && failures == 1 && delivered.last == "Kept before error.", "Speech error lost text or retried")
        print("PASS empty Apple final, stale Apple task, fatal service error retention")

        engine.activeBackend = .apple
        engine.isRecording = true
        engine.phase = .listening
        UserDefaults.standard.set("deepgram", forKey: TalkTypeConfig.engineStorageKey)
        let reads = AuditKeychain.reads
        let stoppingSession = engine.currentSessionId
        engine.stopRecording()
        expect(engine.isStopping && !engine.isRecording, "Fallback did not stop Apple capture")
        expect(AuditKeychain.reads == reads, "Stop routed via a fresh Keychain/config read")
        engine.finishApple(sessionID: stoppingSession)
        print("PASS stop uses active backend after fallback")

        for format in [AVAudioCommonFormat.pcmFormatFloat32, .pcmFormatInt16] {
            for interleaved in [false, true] {
                let audioFormat = AVAudioFormat(commonFormat: format, sampleRate: 48000, channels: 2, interleaved: interleaved)!
                let input = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 16)!
                input.frameLength = 4
                let buffers = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
                for buffer in buffers { memset(buffer.mData!, 1, Int(buffer.mDataByteSize)) }
                let copied = copyAudio(input)!
                let copies = UnsafeMutableAudioBufferListPointer(copied.mutableAudioBufferList)
                for index in buffers.indices {
                    expect(memcmp(buffers[index].mData!, copies[index].mData!, Int(copies[index].mDataByteSize)) == 0,
                           "Buffer copy lost planar/interleaved samples")
                }
                engine.audioProcessingQueue.sync {
                    engine.lastMeterPublishTime = 0
                    engine.publishInputLevel(from: copied, sessionID: engine.currentSessionId)
                }
            }
        }
        pump()
        print("PASS float/int16 stereo buffer ownership and interleaved metering")
        engine.onFinal = nil // Release the test callback's strong capture.
    }
}

#if !MAS_BUILD
extension AppDelegate {
    static func regressionChecks() {
        let app = AppDelegate()
        UserDefaults.standard.set(PTTTrigger.eitherOption.rawValue, forKey: TalkTypeConfig.pttTriggerStorageKey)
        app.pttHeld = true
        app.pttPressTime = Date()
        app.engine.isRecording = true
        app.engine.phase = .listening
        let release = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                       isARepeat: false, keyCode: 61)!
        app.handleFlags(release)
        expect(!app.pttHeld && app.isHandsFreeMode, "Rapid release was swallowed instead of applying tap semantics")
        app.engine.isRecording = false
        print("PASS rapid modifier release")
    }
}
#endif

@main struct AuditRegression {
    static func main() {
        defer {
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        }
        KeychainHelper.regressionChecks()
        SpeechEngine.regressionChecks()
        let setting = TalkTypeConfig.customKeywordsStorageKey
        UserDefaults.standard.set("R&D&language=fr", forKey: setting)
        let url = URL(string: "https://example.invalid/?language=en" + VocabularyManager.deepgramKeywordsParam)!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        expect(items.filter { $0.name == "language" }.map { $0.value! } == ["en"], "Vocabulary injected a parameter")
        expect(items.last?.value == "R&D&language=fr", "Vocabulary value did not round trip")
        print("PASS vocabulary query escaping")
        #if !MAS_BUILD
        AppDelegate.regressionChecks()
        #endif
    }
}
