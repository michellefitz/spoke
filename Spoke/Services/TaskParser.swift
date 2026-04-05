import Foundation

struct ParsedTask {
    let title: String
    let description: String?
    let deadline: Date?
    let tag: String?
}

enum ParsedAction {
    case create(ParsedTask)
    case edit(matchTitle: String, updates: ParsedTask)
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
        logEntry(mode: "create", transcript: transcript, system: system, user: user, response: lastRawResponse, tasks: result, error: result.isEmpty ? "empty" : nil, start: start)
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
        logEntry(mode: "edit", transcript: transcript, system: system, user: user, response: lastRawResponse, tasks: [result], error: nil, start: start)
        return result
    }

    static func parseUnified(transcript: String, existingTasks: [(title: String, description: String?, deadline: Date?, tag: String?)]) async -> [ParsedAction] {
        let start = Date()
        let wordCount = transcript.split(separator: " ").count
        if wordCount <= 3 {
            let task = ParsedTask(title: sentenceCase(transcript), description: nil, deadline: nil, tag: nil)
            logEntry(mode: "unified", transcript: transcript, system: "(short — skipped API)", user: transcript, response: nil, tasks: [task], error: nil, start: start)
            return [.create(task)]
        }
        let today = isoToday()
        let tagInstruction = tagPromptInstruction()

        // Build existing task list for context
        let taskList: String
        if existingTasks.isEmpty {
            taskList = "There are no existing tasks."
        } else {
            let items = existingTasks.map { t in
                var parts = ["\"\(t.title)\""]
                if let desc = t.description, !desc.isEmpty {
                    let preview = String(desc.prefix(80)).replacingOccurrences(of: "\n", with: " ")
                    parts.append("desc: \(preview)")
                }
                return "- " + parts.joined(separator: " | ")
            }
            taskList = "Existing tasks:\n" + items.joined(separator: "\n")
        }

        let system = """
            Today's date is \(today). You are a voice task assistant. Given a voice transcript, determine whether the user wants to CREATE new tasks, EDIT existing tasks, or both. \
            \(taskList) \
            Rules: \
            - Return a JSON ARRAY of action objects. Each object MUST have an "action" field: either "create" or "edit". \
            - For "create" actions: include "title" (required), "description" (optional), "deadline" (optional), "tag" (optional). Same rules as a task parser — action-oriented title, max 50 chars, bullets for multi-item descriptions. \
            - For "edit" actions: include "match" (the title of the existing task to edit — must closely match one from the list above) and the updated fields: "title", "description", "deadline", "tag". Merge new information with what exists — don't drop existing content. \
            - CRITICAL: Only use "edit" when the user clearly refers to an existing task by name or obvious reference (e.g. "add milk to the grocery list", "change the dentist appointment to Thursday"). If in doubt, create a new task. \
            - If the transcript contains multiple unrelated tasks, return multiple action objects. \
            - If the transcript is about adding detail to an existing task (e.g. "add eggs and bread to the grocery shopping"), return one "edit" action. \
            - Title must be action-oriented, max 50 chars. Keep specific details (times, names, locations) in the title when they fit. \
            - NEVER silently drop information. \
            - If a description needs 2+ items, use bullet format: "intro:\\n• Item1\\n• Item2" \
            - Dates: resolve relative to today as YYYY-MM-DD. A deadline applies only to the task it was mentioned with. \
            - \(tagInstruction) \
            Return ONLY a valid JSON ARRAY, no markdown, no code fences, no commentary. \
            Examples: \
            New task: [{"action": "create", "title": "Call the dentist"}] \
            Edit existing: [{"action": "edit", "match": "Do grocery shopping", "title": "Do grocery shopping", "description": "Things to pick up:\\n• Milk\\n• Eggs\\n• Bread"}] \
            Mixed: [{"action": "create", "title": "Book hotel for trip"}, {"action": "edit", "match": "Pack for vacation", "description": "Don't forget:\\n• Sunscreen\\n• Charger"}]
            """
        let user = "Transcript: \"\(transcript)\""
        guard let text = await callClaudeRaw(system: system, user: user) else {
            lastRawResponse = nil
            let fb = fallback(transcript)
            logEntry(mode: "unified", transcript: transcript, system: system, user: user, response: nil, tasks: [fb], error: "api_failed", start: start)
            return [.create(fb)]
        }
        lastRawResponse = text
        let json = extractJSON(from: text)
        let actions = parseActionArray(json, existingTasks: existingTasks)
        let allTasks = actions.map { action -> ParsedTask in
            switch action {
            case .create(let t): return t
            case .edit(_, let t): return t
            }
        }
        logEntry(mode: "unified", transcript: transcript, system: system, user: user, response: text, tasks: allTasks, error: actions.isEmpty ? "empty" : nil, start: start)
        return actions.isEmpty ? [.create(fallback(transcript))] : actions
    }

    // MARK: - Private

    private static var lastRawResponse: String?

    private static func callClaude(system: String, user: String) async -> ParsedTask? {
        guard let text = await callClaudeRaw(system: system, user: user) else { lastRawResponse = nil; return nil }
        lastRawResponse = text
        let json = extractJSON(from: text)
        if let tasks = parseJSONArray(json), let first = tasks.first {
            return first
        }
        return parseJSONObject(json)
    }

    private static func callClaudeMulti(system: String, user: String) async -> [ParsedTask]? {
        guard let text = await callClaudeRaw(system: system, user: user) else { lastRawResponse = nil; return nil }
        lastRawResponse = text
        let json = extractJSON(from: text)
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

    private static func parseActionArray(_ text: String, existingTasks: [(title: String, description: String?, deadline: Date?, tag: String?)]) -> [ParsedAction] {
        guard
            let data = text.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            // Try single object
            if let single = parseJSONObject(text) {
                return [.create(single)]
            }
            return []
        }
        return array.compactMap { dict -> ParsedAction? in
            let action = dict["action"] as? String ?? "create"
            guard let parsed = parseDictionary(dict) else { return nil }

            if action == "edit", let matchTitle = dict["match"] as? String {
                // Find best matching existing task (case-insensitive, prefix-tolerant)
                let match = existingTasks.first { $0.title.lowercased() == matchTitle.lowercased() }
                    ?? existingTasks.first { $0.title.lowercased().contains(matchTitle.lowercased()) }
                    ?? existingTasks.first { matchTitle.lowercased().contains($0.title.lowercased()) }

                if let match {
                    // Merge: keep existing values where the edit doesn't provide new ones
                    let mergedDesc = mergeDescription(existing: match.description, new: parsed.description)
                    let mergedDeadline = parsed.deadline ?? match.deadline
                    let mergedTag = parsed.tag ?? match.tag
                    let merged = ParsedTask(
                        title: parsed.title,
                        description: mergedDesc,
                        deadline: mergedDeadline,
                        tag: mergedTag
                    )
                    return .edit(matchTitle: match.title, updates: merged)
                } else {
                    // No match found — treat as create
                    return .create(parsed)
                }
            }
            return .create(parsed)
        }
    }

    /// Merge existing and new descriptions, preserving existing bullets and adding new ones.
    private static func mergeDescription(existing: String?, new: String?) -> String? {
        guard let new, !new.isEmpty else { return existing }
        guard let existing, !existing.isEmpty else { return new }
        // If the new description already contains the existing content, use it as-is
        if new.contains(existing) { return new }
        // If both have bullets, combine them
        let existingLines = existing.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        let existingBullets = Set(existingLines.filter { $0.hasPrefix("• ") || $0.hasPrefix("✓ ") })
        let newBullets = newLines.filter { $0.hasPrefix("• ") || $0.hasPrefix("✓ ") }
        let newProse = newLines.filter { !$0.hasPrefix("• ") && !$0.hasPrefix("✓ ") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // If Claude already merged properly, just use the new description
        if !newBullets.isEmpty && newBullets.allSatisfy({ existingBullets.contains($0) || !existingBullets.isEmpty }) {
            return new
        }
        return new
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
