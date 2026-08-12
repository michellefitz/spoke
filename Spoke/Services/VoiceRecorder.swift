import Foundation
@preconcurrency import AVFoundation
import Accelerate

enum RecordingState: Equatable {
    case idle
    case recording
    case processing
}

@Observable
@MainActor
final class VoiceRecorder {
    var recordingState: RecordingState = .idle
    var liveTranscript: String = ""
    var audioLevel: Float = 0.0

    private var audioEngine = AVAudioEngine()
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var connectTask: Task<Void, Never>?

    // Frames captured before the websocket is up (proxy-token fetch takes a
    // few hundred ms) are buffered and flushed on connect.
    private var pendingFrames: [Data] = []
    private static let maxPendingFrames = 400

    // Diagnostics for the recording log.
    private var startedAt: Date?
    private var diagnostics = RecordingDiagnostics()
    private var interruptionObserver: NSObjectProtocol?

    /// Diagnostics for the most recent recording — nil until one finishes.
    private(set) var lastDiagnostics: RecordingDiagnostics?

    // Transcript accumulation
    private var finalSegments: [String] = []
    private var currentInterim: String = ""

    // MARK: - Permissions

    func requestPermissionsIfNeeded() async -> Bool {
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Recording

    func startRecording() throws {
        guard recordingState == .idle else { return }

        finalSegments = []
        currentInterim = ""
        liveTranscript = ""
        recordingState = .recording
        startedAt = Date()
        diagnostics = RecordingDiagnostics()
        observeInterruptions()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        connectTask = Task { await self.connectWebSocket() }
        try startAudioCapture()
        startPingTask()
    }

    func stopRecording() -> String {
        guard recordingState == .recording else { return "" }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        disconnectWebSocket()
        stopObservingInterruptions()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        recordingState = .processing
        audioLevel = 0.0

        // Return accumulated finals + any trailing interim
        var parts = finalSegments
        if !currentInterim.isEmpty { parts.append(currentInterim) }
        let transcript = parts.joined(separator: " ")

        diagnostics.durationMs = Int((Date().timeIntervalSince(startedAt ?? Date())) * 1000)
        diagnostics.finalSegments = finalSegments.count
        lastDiagnostics = diagnostics
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Nothing to parse, so nothing would otherwise be logged — but a
            // recording that heard nothing is exactly what's worth seeing.
            TaskParserLogger.shared.logSilentRecording(diagnostics)
        } else {
            TaskParserLogger.shared.pendingDiagnostics = diagnostics
        }
        startedAt = nil

        return transcript
    }

    /// Called when the app leaves the foreground while recording. iOS stops
    /// delivering microphone audio, so the recording is over whether we like
    /// it or not — mark it so the log can explain the short transcript.
    func noteBackgrounded() {
        guard recordingState == .recording else { return }
        diagnostics.backgrounded = true
    }

    func finishProcessing() {
        recordingState = .idle
        liveTranscript = ""
        audioLevel = 0.0
        finalSegments = []
        currentInterim = ""
    }

    // MARK: - Audio capture

    private func startAudioCapture() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Deepgram expects: 16 kHz, mono, signed 16-bit PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else { return }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            // Calculate output frame count for the sample-rate ratio
            let ratio = 16_000.0 / inputFormat.sampleRate
            let outFrames = AVAudioFrameCount(max(1, Double(buffer.frameLength) * ratio))
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return }

            nonisolated(unsafe) var provided = false
            converter.convert(to: outBuffer, error: nil) { _, status in
                if provided { status.pointee = .noDataNow; return nil }
                status.pointee = .haveData
                provided = true
                return buffer
            }

            guard let pcm = outBuffer.int16ChannelData else { return }
            let byteCount = Int(outBuffer.frameLength) * 2
            let audioData = Data(bytes: pcm[0], count: byteCount)

            // Calculate RMS audio level from the original float buffer
            var rms: Float = 0.0
            if let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                vDSP_measqv(channelData, 1, &rms, vDSP_Length(buffer.frameLength))
                rms = sqrtf(rms)
            }
            // Power curve: sensitive at low levels, soft ceiling at loud levels
            let normalizedLevel = min(1.0 - exp(-rms * 20.0), 1.0)

            Task { @MainActor [weak self] in
                self?.audioLevel = normalizedLevel
                self?.sendFrame(audioData)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - WebSocket

    private func connectWebSocket() async {
        var comps = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        comps.queryItems = [
            URLQueryItem(name: "model",           value: "nova-3"),
            URLQueryItem(name: "language",        value: "en"),
            URLQueryItem(name: "smart_format",    value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "utterance_end_ms",value: "1000"),
            URLQueryItem(name: "vad_events",      value: "true"),
            URLQueryItem(name: "encoding",        value: "linear16"),
            URLQueryItem(name: "sample_rate",     value: "16000"),
            URLQueryItem(name: "channels",        value: "1"),
        ]
        guard let url = comps.url else { return }

        var request = URLRequest(url: url)
        if Config.proxyBaseURL.isEmpty {
            // Dev fallback: direct key on the device.
            request.setValue("Token \(Config.deepgramAPIKey)", forHTTPHeaderField: "Authorization")
        } else {
            guard let token = await fetchDeepgramToken() else {
                print("[VoiceRecorder] Could not mint Deepgram token")
                diagnostics.connectionError = "Couldn't reach the transcription service."
                return
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // The user may have stopped recording while the token was minting.
        guard recordingState == .recording else { return }

        let session = URLSession(configuration: .default)
        urlSession = session
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessages()
        flushPendingFrames()
    }

    private func fetchDeepgramToken() async -> String? {
        guard let url = URL(string: Config.proxyBaseURL + "/v1/deepgram-token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Config.proxySecret, forHTTPHeaderField: "x-spoke-key")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["access_token"] as? String
        else { return nil }
        return token
    }

    private func sendFrame(_ data: Data) {
        if let ws = webSocketTask {
            ws.send(.data(data)) { _ in }
        } else if pendingFrames.count < Self.maxPendingFrames {
            pendingFrames.append(data)
        }
    }

    private func flushPendingFrames() {
        for frame in pendingFrames {
            webSocketTask?.send(.data(frame)) { _ in }
        }
        pendingFrames.removeAll()
    }

    private func disconnectWebSocket() {
        connectTask?.cancel()
        connectTask = nil
        pendingFrames.removeAll()
        if let data = #"{"type":"CloseStream"}"#.data(using: .utf8) {
            webSocketTask?.send(.data(data)) { _ in }
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    self.handleMessage(msg)
                    if self.recordingState == .recording {
                        self.receiveMessages()
                    }
                case .failure(let error):
                    // Previously this branch did nothing: the receive loop
                    // simply stopped, audio kept streaming into a dead
                    // socket, and every word after the drop was lost with
                    // no sign anything had gone wrong.
                    guard self.recordingState == .recording else { return }
                    self.diagnostics.connectionError = error.localizedDescription
                    print("[VoiceRecorder] Transcription socket failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Interruptions

    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                AVAudioSession.InterruptionType(rawValue: raw) == .began
            else { return }
            Task { @MainActor [weak self] in
                guard let self, self.recordingState == .recording else { return }
                self.diagnostics.interrupted = true
            }
        }
    }

    private func stopObservingInterruptions() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d):   text = String(data: d, encoding: .utf8) ?? ""
        @unknown default:    return
        }

        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["type"] as? String == "Results",
            let channel = json["channel"] as? [String: Any],
            let alternatives = channel["alternatives"] as? [[String: Any]],
            let transcript = alternatives.first?["transcript"] as? String,
            !transcript.isEmpty
        else { return }

        let isFinal = json["is_final"] as? Bool ?? false

        if isFinal {
            finalSegments.append(transcript)
            currentInterim = ""
        } else {
            currentInterim = transcript
        }

        var parts = finalSegments
        if !currentInterim.isEmpty { parts.append(currentInterim) }
        liveTranscript = parts.joined(separator: " ")
    }

    // MARK: - Keep-alive

    private func startPingTask() {
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.recordingState == .recording else { break }
                self.webSocketTask?.sendPing { _ in }
            }
        }
    }
}
