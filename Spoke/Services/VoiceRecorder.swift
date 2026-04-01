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

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        connectWebSocket()
        try startAudioCapture()
        startPingTask()
    }

    func stopRecording() -> String {
        guard recordingState == .recording else { return "" }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        disconnectWebSocket()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        recordingState = .processing
        audioLevel = 0.0

        // Return accumulated finals + any trailing interim
        var parts = finalSegments
        if !currentInterim.isEmpty { parts.append(currentInterim) }
        return parts.joined(separator: " ")
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
                self?.webSocketTask?.send(.data(audioData)) { _ in }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - WebSocket

    private func connectWebSocket() {
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
        request.setValue("Token \(Config.deepgramAPIKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        urlSession = session
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessages()
    }

    private func disconnectWebSocket() {
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
                if case .success(let msg) = result {
                    self.handleMessage(msg)
                    if self.recordingState == .recording {
                        self.receiveMessages()
                    }
                }
            }
        }
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
