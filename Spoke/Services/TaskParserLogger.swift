import Foundation
import Observation

/// What happened during the recording itself, as opposed to the parse.
/// This is what answers "did it actually hear me?" — without it a short
/// transcript is indistinguishable from a dropped connection.
struct RecordingDiagnostics: Codable, Equatable {
    var durationMs: Int = 0
    var finalSegments: Int = 0      // completed phrases Deepgram sent back
    var interrupted: Bool = false   // call, Siri, alarm took the microphone
    var backgrounded: Bool = false  // app left the foreground mid-recording
    var connectionError: String?    // websocket or token failure

    /// Backgrounding isn't a fault — Spoke keeps recording through it — so
    /// it doesn't count here.
    var endedEarly: Bool {
        interrupted || connectionError != nil
    }

    /// Plain-language explanation for the log UI, or nil if all was well.
    var explanation: String? {
        if let connectionError {
            return "The connection to the transcription service dropped, so anything said after that wasn't heard. (\(connectionError))"
        }
        if interrupted {
            return "Something else took over the microphone — a call, Siri or an alarm — so anything said after that wasn't heard."
        }
        return nil
    }
}

struct ParserLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let mode: String          // "create", "edit", or "recording" (nothing heard)
    let transcript: String    // raw speech-to-text
    let systemPrompt: String  // the prompt sent to Claude
    let userMessage: String   // the user message sent
    let claudeResponse: String? // raw JSON response
    let parsedTasks: [ParsedTaskLog] // what we extracted
    let error: String?        // any error
    let durationMs: Int       // how long the API call took
    // Optional so entries written before this existed still decode.
    var recording: RecordingDiagnostics?

    // A/B comparison. `transcript` above is the one the app actually used
    // (Deepgram); this is the same audio heard by the on-device engine,
    // recorded for rating and nothing else.
    var altTranscript: String?
    var altEngine: String?
    /// "cloud", "device" or "tie" — set by tapping in the recording log.
    var transcriptRating: String?

    struct ParsedTaskLog: Codable {
        let title: String
        let description: String?
        let deadline: String?
        let tag: String?
    }
}

@Observable
final class TaskParserLogger {
    static let shared = TaskParserLogger()

    private(set) var entries: [ParserLogEntry] = []
    private let fileURL: URL

    /// Set by VoiceRecorder when a recording stops; stamped onto the next
    /// entry logged, which is the parse of that recording.
    var pendingDiagnostics: RecordingDiagnostics?
    /// Likewise for the on-device transcript of the same audio.
    var pendingAltTranscript: String?

    /// The on-device transcript finishes a beat after the recording stops,
    /// which is usually before the parse has come back — hence the pending
    /// slot. If the parse got there first, patch the entry it just wrote.
    func attachAltTranscript(_ text: String) {
        if let newest = entries.first,
           newest.altTranscript == nil,
           Date().timeIntervalSince(newest.timestamp) < 60 {
            entries[0].altTranscript = text
            entries[0].altEngine = OnDeviceTranscriber.engineName
            saveToDisk()
        } else {
            pendingAltTranscript = text
        }
    }

    /// Records which transcript was better. Ratings live with the entry so
    /// they survive a restart and come out in the CSV.
    func rate(_ entryID: UUID, as rating: String?) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].transcriptRating = rating
        saveToDisk()
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("spoke_parser_log.json")
        loadFromDisk()
    }

    /// A recording that produced no transcript never reaches the parser, so
    /// it would otherwise leave no trace at all — which is precisely the
    /// case worth seeing.
    func logSilentRecording(_ diagnostics: RecordingDiagnostics) {
        log(ParserLogEntry(
            id: UUID(),
            timestamp: Date(),
            mode: "recording",
            transcript: "",
            systemPrompt: "",
            userMessage: "",
            claudeResponse: nil,
            parsedTasks: [],
            error: diagnostics.connectionError,
            durationMs: 0,
            recording: diagnostics,
            altTranscript: pendingAltTranscript,
            altEngine: pendingAltTranscript == nil ? nil : OnDeviceTranscriber.engineName
        ))
    }

    func log(_ entry: ParserLogEntry) {
        var entry = entry
        if entry.recording == nil, let pending = pendingDiagnostics {
            entry.recording = pending
        }
        if entry.altTranscript == nil, let alt = pendingAltTranscript {
            entry.altTranscript = alt
            entry.altEngine = OnDeviceTranscriber.engineName
        }
        pendingDiagnostics = nil
        pendingAltTranscript = nil
        entries.insert(entry, at: 0) // newest first
        // Keep last 100 entries
        if entries.count > 100 { entries = Array(entries.prefix(100)) }
        saveToDisk()
        // Also print summary to console
        print("[ParserLog] \(entry.mode) | transcript: \"\(entry.transcript.prefix(60))\" | tasks: \(entry.parsedTasks.count) | \(entry.durationMs)ms\(entry.error.map { " | ERROR: \($0)" } ?? "")")
    }

    func clearAll() {
        entries.removeAll()
        saveToDisk()
    }

    func exportCSV() -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let csvURL = docs.appendingPathComponent("spoke_parser_log.csv")

        var csv = "Timestamp,Mode,Transcript (cloud),Transcript (on-device),Engine,Rating,Tasks Created,Titles,Tags,Deadlines,Duration (ms),Error,Recording (s),Segments,Ended Early,Reason\n"
        for entry in entries {
            let titles = entry.parsedTasks.map { $0.title }.joined(separator: " | ")
            let tags = entry.parsedTasks.compactMap { $0.tag }.joined(separator: " | ")
            let deadlines = entry.parsedTasks.compactMap { $0.deadline }.joined(separator: " | ")
            let transcript = entry.transcript.replacingOccurrences(of: "\"", with: "\"\"")
            let error = (entry.error ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let rec = entry.recording
            let seconds = rec.map { String(format: "%.1f", Double($0.durationMs) / 1000) } ?? ""
            let segments = rec.map { String($0.finalSegments) } ?? ""
            let endedEarly = rec.map { $0.endedEarly ? "yes" : "no" } ?? ""
            let reason = (rec?.explanation ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let alt = (entry.altTranscript ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(entry.timestamp)\",\"\(entry.mode)\",\"\(transcript)\",\"\(alt)\",\"\(entry.altEngine ?? "")\",\"\(entry.transcriptRating ?? "")\",\(entry.parsedTasks.count),\"\(titles)\",\"\(tags)\",\"\(deadlines)\",\(entry.durationMs),\"\(error)\",\(seconds),\(segments),\(endedEarly),\"\(reason)\"\n"
        }

        do {
            try csv.write(to: csvURL, atomically: true, encoding: .utf8)
            return csvURL
        } catch {
            print("[ParserLog] CSV export failed: \(error)")
            return nil
        }
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL)
        } catch {
            print("[ParserLog] Save failed: \(error)")
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ParserLogEntry].self, from: data)
        else { return }
        entries = decoded
    }
}
