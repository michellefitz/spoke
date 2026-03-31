import Foundation

struct ParsedTask {
    let title: String
    let description: String?
    let deadline: Date?
    let tag: String?
}

enum TaskParser {
    private static let logger = TaskParserLogger.shared

    static func parse(transcript: String) async -> [ParsedTask] {
        let start = Date()
        let wordCount = transcript.split(separator: " ").count
        if wordCount <= 3 {
            let result = [ParsedTask(title: sentenceCase(transcript), description: nil, deadline: nil, tag: nil)]
            logEntry(mode: "create", transcript: transcript, system: "(short — skipped API)", user: transcript, response: nil, tasks: result, error: nil, start: start)
            return result
        }
        let today = isoToday()
        let tagInstruction = tagPromptInstruction()
        let system = """
            Today's date is \(today). You are a task parser. Given a voice transcript, extract one or more tasks. \
            Rules: \
            - If the transcript contains MULTIPLE UNRELATED tasks (e.g. "call the dentist, do grocery shopping, and pick up Alex"), return a JSON ARRAY of task objects. \
            - If the transcript describes a SINGLE task with details or sub-items (e.g. "do the grocery shopping — milk, eggs, and broccoli"), return a JSON ARRAY with ONE object, using bullets in the description for the sub-items. \
            - Each task object has: "title" (required), "description" (optional), "deadline" (optional), "tag" (optional). \
            - Title must be action-oriented and at most 50 characters. Keep specific details — times, names, locations — in the title when they fit. "Pick up Alex at 3 PM" is a better title than "Pick up Alex" with "3 PM" in the description. \
            - Description is for sub-tasks, multi-step context, or detail that genuinely would not fit a 50-character title. Do NOT move times or locations to the description just to shorten the title — only do so if the title truly exceeds 50 characters with them included. \
            - NEVER silently drop information. If a detail cannot fit the title, it must appear in the description. \
            - If the description contains 2 or more distinct actions, topics, or steps, you MUST use bullet format — never write multiple ideas as prose sentences. \
            - When using bullets, always write a short intro sentence first (e.g. "Things to pick up:"), then each bullet on its OWN LINE using \\n as the separator. Each bullet MUST start at the beginning of its line as "• item" — never inline. JSON example: "description": "Things to pick up:\\n• Milk\\n• Eggs\\n• Broccoli" \
            - Use plain prose only (no bullets) when there is a single sentence of overflow detail. \
            - Omit description entirely when the title captures everything. \
            - If the user mentions a date or deadline (e.g. "by next Wednesday", "on Tuesday", "before April 20", "this Friday"), resolve it relative to today and include it as "deadline" in YYYY-MM-DD format. Omit "deadline" if no date is mentioned. A deadline applies only to the task it was mentioned with — do not copy it to other tasks. \
            - \(tagInstruction) \
            Return ONLY a valid JSON ARRAY, no markdown, no code fences, no commentary. \
            Examples: \
            Single task: [{"title": "Call the dentist"}] \
            Single task with details: [{"title": "Do grocery shopping", "description": "Things to pick up:\\n• Milk\\n• Eggs\\n• Broccoli"}] \
            Multiple tasks: [{"title": "Call the dentist"}, {"title": "Do grocery shopping", "description": "Things to pick up:\\n• Milk\\n• Eggs"}, {"title": "Pick up Alex at 5 PM tomorrow", "deadline": "YYYY-MM-DD"}]
            """
        let user = "Transcript: \"\(transcript)\""
        let result = await callClaudeMulti(system: system, user: user) ?? [fallback(transcript)]
        logEntry(mode: "create", transcript: transcript, system: system, user: user, response: nil, tasks: result, error: result.isEmpty ? "empty" : nil, start: start)
        return result
    }

    static func parseEdit(transcript: String, currentTitle: String, currentDescription: String?, currentDeadline: Date? = nil, currentTag: String? = nil) async -> ParsedTask {
        let start = Date()
        let desc = currentDescription ?? "none"
        let today = isoToday()
        let tagInstruction = tagPromptInstruction()
        let deadlineStr = currentDeadline.map { isoFormatter.string(from: $0) } ?? "none"
        let tagStr = currentTag ?? "none"
        let system = """
            Today's date is \(today). You are a task assistant that refines tasks from voice input. \
            You are given an existing task and new voice input spoken by the user. \
            Synthesize the existing task and the new voice into the best, most complete version of the task. \
            Rules: \
            - CRITICAL: The voice input is a natural-language COMMAND to update the task — interpret the user's intent, do NOT copy their words verbatim into content. \
              Examples: "add a subtask for the venue" → add "• Venue" as a bullet. "create subtask items for X, Y, and Z" → add "• X\\n• Y\\n• Z" as bullets. "set the deadline to Friday" → update the deadline field. \
            - Preserve existing information that is still accurate; add new points; correct anything the voice contradicts. \
            - Title at most 50 characters, action-oriented. Keep times, names, and locations in the title when they fit — do not move them to the description just to shorten it. \
            - NEVER drop information — if a detail doesn't fit the title, it must appear in the description. \
            - If the description contains 2 or more distinct actions, topics, or steps, you MUST use bullet format — never write multiple ideas as prose sentences. \
            - When using bullets, always write a short intro sentence first (e.g. "Things to cover:"), then each bullet on its OWN LINE using \\n as the separator. Each bullet MUST start at the beginning of its line as "• item" — never inline. JSON example: "description": "Things to cover:\\n• Strategy doc\\n• New targets". If the existing description already has a prose intro, preserve or refine it. \
            - Use plain prose only (no bullets) when there is a single sentence of overflow detail. \
            - Omit description only when the title captures everything. \
            - If the voice mentions a date or deadline, resolve it relative to today and include as "deadline" in YYYY-MM-DD format. Preserve the existing deadline if no new date is mentioned and existing deadline is not "none". Omit "deadline" if there is none. \
            - Preserve the existing tag if it still fits. \(tagInstruction) \
            Return ONLY valid JSON, no markdown, no code fences, no commentary. \
            Example: {"title": "…", "description": "…", "deadline": "YYYY-MM-DD", "tag": "work"}
            """
        let user = """
            Existing task:
            Title: "\(currentTitle)"
            Description: "\(desc)"
            Deadline: "\(deadlineStr)"
            Tag: "\(tagStr)"

            New voice input: "\(transcript)"
            """
        let result = await callClaude(system: system, user: user) ?? fallback(transcript)
        logEntry(mode: "edit", transcript: transcript, system: system, user: user, response: nil, tasks: [result], error: nil, start: start)
        return result
    }

    // MARK: - Private

    private static func callClaude(system: String, user: String) async -> ParsedTask? {
        guard let text = await callClaudeRaw(system: system, user: user) else { return nil }
        let json = extractJSON(from: text)
        // Handle both single object and array (take first element)
        if let tasks = parseJSONArray(json), let first = tasks.first {
            return first
        }
        return parseJSONObject(json)
    }

    private static func callClaudeMulti(system: String, user: String) async -> [ParsedTask]? {
        guard let text = await callClaudeRaw(system: system, user: user) else { return nil }
        let json = extractJSON(from: text)
        // Handle both array and single object
        if let tasks = parseJSONArray(json), !tasks.isEmpty {
            return tasks
        }
        if let single = parseJSONObject(json) {
            return [single]
        }
        return nil
    }

    private static func callClaudeRaw(system: String, user: String) async -> String? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Config.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 800,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let raw = String(data: data, encoding: .utf8) ?? "(unreadable)"
                print("[TaskParser] API error \(http.statusCode): \(raw)")
                return nil
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let content = (json["content"] as? [[String: Any]])?.first,
                let text = content["text"] as? String
            else {
                let raw = String(data: data, encoding: .utf8) ?? "(unreadable)"
                print("[TaskParser] Unexpected response shape: \(raw)")
                return nil
            }

            print("[TaskParser] Raw Claude response: \(text)")
            return text
        } catch {
            print("[TaskParser] Request failed: \(error)")
            return nil
        }
    }

    /// Strips markdown code fences (```json ... ``` or ``` ... ```) if present.
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let inner = lines.dropFirst().dropLast()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return inner.isEmpty ? trimmed : inner
        }
        return trimmed
    }

    private static func parseJSONArray(_ text: String) -> [ParsedTask]? {
        guard
            let data = text.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }
        let tasks = array.compactMap { parseDictionary($0) }
        return tasks.isEmpty ? nil : tasks
    }

    private static func parseJSONObject(_ text: String) -> ParsedTask? {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[TaskParser] JSON parse failed for: \(text)")
            return nil
        }
        return parseDictionary(json)
    }

    private static func parseDictionary(_ json: [String: Any]) -> ParsedTask? {
        guard let title = json["title"] as? String, !title.isEmpty else { return nil }

        let description = json["description"] as? String
        let deadline: Date?
        if let ds = json["deadline"] as? String, !ds.isEmpty {
            deadline = isoFormatter.date(from: ds)
        } else {
            deadline = nil
        }
        let tag: String?
        if let t = json["tag"] as? String, !t.isEmpty {
            let allowed = TagStore.shared.tags
            tag = allowed.contains(t.lowercased()) ? t.lowercased() : nil
        } else {
            tag = nil
        }
        return ParsedTask(title: title, description: description?.isEmpty == true ? nil : description, deadline: deadline, tag: tag)
    }

    private static func tagPromptInstruction() -> String {
        let tags = TagStore.shared.tags
        if tags.isEmpty {
            return "Do not include a \"tag\" field."
        }
        return "If the task clearly belongs to one of these categories, include it as \"tag\": \(tags.joined(separator: ", ")). Omit \"tag\" if unsure."
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func isoToday() -> String {
        isoFormatter.string(from: Date())
    }

    private static func fallback(_ transcript: String) -> ParsedTask {
        let words = transcript.split(separator: " ")
        if words.count <= 6 {
            return ParsedTask(title: sentenceCase(transcript), description: nil, deadline: nil, tag: nil)
        }
        let title = words.prefix(6).joined(separator: " ")
        let description = words.dropFirst(6).joined(separator: " ")
        return ParsedTask(
            title: sentenceCase(title),
            description: description.isEmpty ? nil : sentenceCase(description),
            deadline: nil,
            tag: nil
        )
    }

    private static func sentenceCase(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func logEntry(mode: String, transcript: String, system: String, user: String, response: String?, tasks: [ParsedTask], error: String?, start: Date) {
        let entry = ParserLogEntry(
            id: UUID(),
            timestamp: Date(),
            mode: mode,
            transcript: transcript,
            systemPrompt: system,
            userMessage: user,
            claudeResponse: response,
            parsedTasks: tasks.map {
                .init(title: $0.title, description: $0.description, deadline: $0.deadline.map { isoFormatter.string(from: $0) }, tag: $0.tag)
            },
            error: error,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
        logger.log(entry)
    }
}
