import Foundation
import Observation

struct ParserLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let mode: String          // "create" or "edit"
    let transcript: String    // raw speech-to-text
    let systemPrompt: String  // the prompt sent to Claude
    let userMessage: String   // the user message sent
    let claudeResponse: String? // raw JSON response
    let parsedTasks: [ParsedTaskLog] // what we extracted
    let error: String?        // any error
    let durationMs: Int       // how long the API call took

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

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("spoke_parser_log.json")
        loadFromDisk()
    }

    func log(_ entry: ParserLogEntry) {
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

        var csv = "Timestamp,Mode,Transcript,Tasks Created,Titles,Tags,Deadlines,Duration (ms),Error\n"
        for entry in entries {
            let titles = entry.parsedTasks.map { $0.title }.joined(separator: " | ")
            let tags = entry.parsedTasks.compactMap { $0.tag }.joined(separator: " | ")
            let deadlines = entry.parsedTasks.compactMap { $0.deadline }.joined(separator: " | ")
            let transcript = entry.transcript.replacingOccurrences(of: "\"", with: "\"\"")
            let error = (entry.error ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(entry.timestamp)\",\"\(entry.mode)\",\"\(transcript)\",\(entry.parsedTasks.count),\"\(titles)\",\"\(tags)\",\"\(deadlines)\",\(entry.durationMs),\"\(error)\"\n"
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
