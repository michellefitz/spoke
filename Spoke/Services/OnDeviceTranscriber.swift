import Foundation
@preconcurrency import AVFoundation
import Speech

/// Apple's on-device speech recognition, run alongside Deepgram so the two
/// can be compared on the same audio. Nothing here feeds the parser — the
/// result is recorded in the log for rating and nothing else.
///
/// Requires iOS 26's SpeechAnalyzer. On anything older this is inert and
/// `isSupported` is false, so the app still targets iOS 17.
@MainActor
final class OnDeviceTranscriber {

    /// Whether this device can run the comparison at all.
    static var isSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static let engineName = "Apple SpeechTranscriber"

    /// Held as Any so the surrounding class needs no availability annotation.
    private var engine: Any?
    private(set) var lastError: String?

    func start(locale: Locale = .current) {
        lastError = nil
        guard #available(iOS 26.0, *) else { return }
        let engine = Engine(locale: locale)
        self.engine = engine
        engine.start { [weak self] message in
            Task { @MainActor in self?.lastError = message }
        }
    }

    /// Called from the audio tap for every buffer, on the audio thread.
    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        guard #available(iOS 26.0, *) else { return }
        Task { @MainActor [weak self] in
            (self?.engine as? Engine)?.append(buffer)
        }
    }

    /// Stops the analyzer and returns whatever it heard.
    func finish() async -> String? {
        guard #available(iOS 26.0, *), let engine = engine as? Engine else { return nil }
        self.engine = nil
        return await engine.finish()
    }

    func cancel() {
        guard #available(iOS 26.0, *), let engine = engine as? Engine else { return }
        self.engine = nil
        engine.cancel()
    }
}

// MARK: - iOS 26 implementation

@available(iOS 26.0, *)
private final class Engine {
    private let locale: Locale
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collectTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var text = ""

    init(locale: Locale) {
        self.locale = locale
    }

    func start(onError: @escaping (String) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do {
                // Fall back to the closest supported locale rather than
                // failing outright on, say, en_IE.
                let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
                    ?? Locale(identifier: "en_US")
                NSLog("[OnDeviceTranscriber] locale %@ -> %@", locale.identifier, supported.identifier)

                let transcriber = SpeechTranscriber(
                    locale: supported,
                    transcriptionOptions: [],
                    reportingOptions: [],
                    attributeOptions: []
                )
                self.transcriber = transcriber

                // The language model is a download on first use, and the
                // locale must be reserved first or the install request is
                // rejected ("not subscribed to transcription.en").
                let installed = await SpeechTranscriber.installedLocales
                if !installed.contains(where: { $0.identifier(.bcp47) == supported.identifier(.bcp47) }) {
                    try await AssetInventory.reserve(locale: supported)
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                        NSLog("[OnDeviceTranscriber] downloading speech model")
                        try await request.downloadAndInstall()
                        NSLog("[OnDeviceTranscriber] model installed")
                    }
                }

                let analyzer = SpeechAnalyzer(modules: [transcriber])
                self.analyzer = analyzer
                self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
                NSLog("[OnDeviceTranscriber] analyzer format: %@", self.analyzerFormat?.description ?? "nil")

                let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                self.continuation = continuation
                try await analyzer.start(inputSequence: stream)
                NSLog("[OnDeviceTranscriber] analyzer running")

                self.collectTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        for try await result in transcriber.results where result.isFinal {
                            self.text += (self.text.isEmpty ? "" : " ")
                                + String(result.text.characters)
                        }
                    } catch {
                        onError(error.localizedDescription)
                    }
                }
            } catch {
                NSLog("[OnDeviceTranscriber] start failed: %@", String(describing: error))
                onError(error.localizedDescription)
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let continuation, let analyzerFormat else { return }
        guard let converted = convert(buffer, to: analyzerFormat) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async -> String? {
        continuation?.finish()
        continuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        _ = await collectTask?.result
        collectTask = nil
        analyzer = nil
        transcriber = nil
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog("[OnDeviceTranscriber] finish: %@", result.isEmpty ? "no transcript" : "\(result.count) chars")
        return result.isEmpty ? nil : result
    }

    func cancel() {
        continuation?.finish()
        continuation = nil
        collectTask?.cancel()
        collectTask = nil
        Task { [analyzer] in try? await analyzer?.cancelAndFinishNow() }
        analyzer = nil
        transcriber = nil
    }

    /// The tap hands us the microphone's native format; the analyzer wants
    /// its own. Converter is built once and reused.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, Double(buffer.frameLength) * ratio))
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var provided = false
        converter.convert(to: out, error: nil) { _, status in
            if provided { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData
            provided = true
            return buffer
        }
        return out.frameLength > 0 ? out : nil
    }
}
