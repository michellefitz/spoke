import Foundation

struct ParsedTask {
    let title: String
    let description: String?
}

enum TaskParser {
    static func parse(transcript: String) async -> ParsedTask {
        let wordCount = transcript.split(separator: " ").count
        if wordCount <= 5 {
            return ParsedTask(title: sentenceCase(transcript), description: nil)
        }
        return await callClaude(
            system: """
            You are a task parser. Given a voice transcript, extract a concise task title and an optional description. \
            Rules: \
            - Title must be short and action-oriented, max 6 words. \
            - Description captures supporting detail, context, or sub-tasks. \
            - When the description contains multiple items or sub-tasks, format each as a bullet using "• item" on its own line (e.g. "• Call venue\n• Confirm date\n• Send invites"). \
            - Use plain prose (no bullets) for a single sentence of context. \
            - Omit description entirely if there is nothing meaningful beyond the title. \
            Return ONLY valid JSON, no markdown, no code fences, no commentary: \
            {"title": "…"} or {"title": "…", "description": "…"}
            """,
            user: "Transcript: \"\(transcript)\""
        ) ?? fallback(transcript)
    }

    static func parseEdit(transcript: String, currentTitle: String, currentDescription: String?) async -> ParsedTask {
        let desc = currentDescription ?? "none"
        return await callClaude(
            system: """
            You are a task assistant that refines tasks from voice input. \
            You are given an existing task and new voice input spoken by the user. \
            The voice input may be additional context, new sub-tasks, a correction to something captured wrong, or a mix of all three. \
            Synthesize the existing task and the new voice into the best, most complete version of the task. \
            Rules: \
            - Preserve existing information that is still accurate; add new points; correct anything the voice contradicts. \
            - Title max 6 words, action-oriented. Update it only if the voice changes the core task. \
            - When description has multiple items or sub-tasks, format each as "• item" on its own line. \
            - Use plain prose (no bullets) for a single sentence of context. \
            - Omit description if nothing meaningful exists beyond the title. \
            Return ONLY valid JSON, no markdown, no code fences, no commentary: \
            {"title": "…"} or {"title": "…", "description": "…"}
            """,
            user: """
            Existing task:
            Title: "\(currentTitle)"
            Description: "\(desc)"

            New voice input: "\(transcript)"
            """
        ) ?? fallback(transcript)
    }

    // MARK: - Private

    private static func callClaude(system: String, user: String) async -> ParsedTask? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Config.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 400,
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
            return parseJSON(extractJSON(from: text))
        } catch {
            print("[TaskParser] Request failed: \(error)")
            return nil
        }
    }

    /// Strips markdown code fences (```json ... ``` or ``` ... ```) if present.
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Match ```json ... ``` or ``` ... ```
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let inner = lines.dropFirst().dropLast()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return inner.isEmpty ? trimmed : inner
        }
        return trimmed
    }

    private static func parseJSON(_ text: String) -> ParsedTask? {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let title = json["title"] as? String,
            !title.isEmpty
        else {
            print("[TaskParser] JSON parse failed for: \(text)")
            return nil
        }

        let description = json["description"] as? String
        return ParsedTask(title: title, description: description?.isEmpty == true ? nil : description)
    }

    private static func fallback(_ transcript: String) -> ParsedTask {
        ParsedTask(title: sentenceCase(transcript), description: nil)
    }

    private static func sentenceCase(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
