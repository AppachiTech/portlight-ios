import AVFoundation
import Observation
import Speech

/// Speech to text for the voice input controls, recognised on this phone
/// only: what's said may name servers or secrets, so audio never leaves
/// the device. Where on-device recognition isn't available it says so
/// rather than falling back to Apple's servers.
@MainActor
@Observable
final class SpeechDictation {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case failed(String)
    }

    private(set) var state: State = .idle
    /// What's been heard since the last start, revised as recognition firms up.
    private(set) var transcript = ""

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    /// Bumped on every start and cancel, so late results from an earlier
    /// recognition are ignored.
    @ObservationIgnored private var generation = 0

    var isListening: Bool { state == .starting || state == .listening }

    func start() {
        guard !isListening else { return }
        cancel()
        state = .starting
        let id = generation
        Task { await begin(id) }
    }

    /// Stops listening; the final words still arrive in `transcript`.
    func stop() {
        guard isListening else { return }
        request?.endAudio()
        stopAudio()
        state = .idle
    }

    /// Stops and forgets anything still on its way.
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        request = nil
        stopAudio()
        transcript = ""
        if isListening { state = .idle }
    }

    func dismissFailure() {
        if case .failed = state { state = .idle }
    }

    private func begin(_ id: Int) async {
        guard await Self.speechAuthorized() else {
            return fail(id, "Speech recognition is off for Portlight. Turn it on in Settings → Privacy & Security → Speech Recognition.")
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            return fail(id, "Microphone access is off for Portlight. Turn it on in Settings → Privacy & Security → Microphone.")
        }
        guard id == generation, state == .starting else { return }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            return fail(id, "Speech recognition isn't available right now.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            let language = Locale.current.localizedString(forIdentifier: recognizer.locale.identifier) ?? recognizer.locale.identifier
            return fail(id, "This iPhone can't recognise \(language) on the device, and Portlight doesn't send audio off it. The keyboard's dictation key still works.")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let engine = AVAudioEngine()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "Portlight", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone was found."])
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return fail(id, "Couldn't start the microphone: \(error.localizedDescription)")
        }

        self.engine = engine
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                if let text { self.transcript = text }
                if done { self.finished() }
            }
        }
        state = .listening
    }

    /// Recognition ended: after stop(), or on its own (silence, interruption).
    private func finished() {
        task = nil
        request = nil
        stopAudio()
        if isListening { state = .idle }
    }

    private func stopAudio() {
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ id: Int, _ message: String) {
        guard id == generation else { return }
        state = .failed(message)
    }

    private static func speechAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}
