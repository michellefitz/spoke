import Foundation

struct ParsedTask {
    let title: String
    let description: String?
    let deadline: Date?
    let tag: String?
    var deadlineIsWeek: Bool = false
}

enum ParsedAction {
    case create(ParsedTask)
    case edit(matchTitle: String, updates: ParsedTask)
    case createEvent(ParsedEvent)
    case editEvent(original: DayEvent, updates: ParsedEvent)

    /// True for anything that writes to the calendar — these always require
    /// user confirmation, never a silent apply.
    var isEvent: Bool {
        switch self {
        case .createEvent, .editEvent: return true
        case .create, .edit: return false
        }
    }
}

struct AssistantQuestion {
    let text: String
    let options: [String]
}

struct AssistantResponse {
    let actions: [ParsedAction]
    let remark: String?
    let question: AssistantQuestion?
    /// True when the model asked for changes that couldn't be carried out.
    /// Its remark will happily claim the change was made, so it must not be
    /// repeated back to the user.
    var droppedActions: Bool = false
}

enum RefineOutcome {
    case response(AssistantResponse)
    case approve
    case cancel
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
        let today = dateContext()
        let tagInstruction = tagPromptInstruction()
        let system = """
            \(today) You are a task parser. Given a voice transcript, extract one or more tasks. \
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
            - If the user mentions a specific day (e.g. "by next Wednesday", "on Tuesday", "before April 20", "this Friday"), resolve it relative to today and include it as "deadline" in YYYY-MM-DD format. If they say something is for "this week" or "next week" WITHOUT naming a day, use the literal string "this-week" or "next-week" as the deadline — do NOT invent a specific day. Omit "deadline" if no date is mentioned. A deadline applies only to the task it was mentioned with — do not copy it to other tasks. \
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

    static func parseEdit(transcript: String, currentTitle: String, currentDescription: String?, currentDeadline: Date? = nil, currentTag: String? = nil, currentDeadlineIsWeek: Bool = false) async -> ParsedTask {
        let start = Date()
        let desc = currentDescription ?? "none"
        let today = dateContext()
        let tagInstruction = tagPromptInstruction()
        let deadlineStr = currentDeadline.map { deadlineToken($0, isWeek: currentDeadlineIsWeek) } ?? "none"
        let tagStr = currentTag ?? "none"
        let system = """
            \(today) You are a task assistant that refines tasks from voice input. \
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
            - If the voice mentions a specific day, resolve it relative to today and include as "deadline" in YYYY-MM-DD format. If the voice says "this week" or "next week" without naming a day, use the literal string "this-week" or "next-week" — do NOT invent a specific day. Preserve the existing deadline if no new date is mentioned and existing deadline is not "none". Omit "deadline" if there is none. \
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

    /// Main assistant entry point: parses the transcript into actions plus an optional
    /// remark (something worth telling the user) and at most one clarifying question.
    static func parseAssistant(transcript: String, existingTasks: [(title: String, description: String?, deadline: Date?, tag: String?, deadlineIsWeek: Bool)], existingEvents: [DayEvent] = []) async -> AssistantResponse {
        let start = Date()
        let wordCount = transcript.split(separator: " ").count
        if wordCount <= 3 {
            let task = ParsedTask(title: sentenceCase(transcript), description: nil, deadline: nil, tag: nil)
            logEntry(mode: "assistant", transcript: transcript, system: "(short — skipped API)", user: transcript, response: nil, tasks: [task], error: nil, start: start)
            return AssistantResponse(actions: [.create(task)], remark: nil, question: nil)
        }
        let today = dateContext()
        let tagInstruction = tagPromptInstruction()
        let taskList = existingTaskListBlock(existingTasks)
        let eventList = eventListBlock(existingEvents)

        let system = """
            \(today) You are Spoke, a voice assistant for the user's to-do list. Given a voice transcript, decide what to change on the list and how to respond. \
            \(taskList) \
            \(eventList) \
            Return ONLY a valid JSON OBJECT with keys: "actions" (required array), "remark" (optional string), "question" (optional object). \
            \(actionRules(tagInstruction: tagInstruction)) \
            Remark rules: \
            - Include "remark" ONLY when you made a judgment worth reporting: created 2 or more tasks, set or inferred a deadline, merged into an existing task, or resolved something non-obvious. One sentence, max 140 characters, natural and direct. \
            - For a single obvious task with nothing decided, omit "remark". \
            Question rules: \
            - Ask AT MOST one question, as "question": {"text": "...", "options": ["...", "..."]}. \
            - Ask ONLY when the transcript closely duplicates an existing task (same intent) or an ambiguity genuinely changes what you would do. Otherwise never ask. \
            - "options" is exactly 2 short tappable answers, max 4 words each. \
            - When you include "question", return "actions": [] — final actions are decided after the user answers. \
            Return ONLY the JSON object, no markdown, no code fences, no commentary. \
            Examples: \
            Simple: {"actions": [{"action": "create", "title": "Call the dentist"}]} \
            Braindump: {"actions": [{"action": "create", "title": "Book car in for MOT", "deadline": "YYYY-MM-DD"}, {"action": "create", "title": "Sort out travel insurance", "deadline": "this-week"}, {"action": "create", "title": "Email landlord about boiler"}], "remark": "Got 3 tasks — set Friday on the MOT and put the insurance down for this week."} \
            Appointment: {"actions": [{"action": "event", "title": "Dentist appointment", "date": "YYYY-MM-DD", "start": "11:00"}], "remark": "Sounds like a calendar event — check it over before I add it."} \
            Reschedule: {"actions": [{"action": "edit-event", "match": "Hair appointment", "start": "14:00"}], "remark": "Moving your hair appointment to 2pm — confirm and I'll update the calendar."} \
            Duplicate: {"actions": [], "question": {"text": "You already have \\"Call the dentist\\" — same one, or a new appointment?", "options": ["Same one", "New task"]}}
            """
        let user = "Transcript: \"\(transcript)\""
        guard let text = await callClaudeRaw(system: system, user: user) else {
            lastRawResponse = nil
            let fb = fallback(transcript)
            logEntry(mode: "assistant", transcript: transcript, system: system, user: user, response: nil, tasks: [fb], error: "api_failed", start: start)
            return AssistantResponse(actions: [.create(fb)], remark: nil, question: nil)
        }
        lastRawResponse = text
        let json = extractJSON(from: text)
        if let response = parseAssistantResponse(json, existingTasks: existingTasks, existingEvents: existingEvents) {
            logEntry(mode: "assistant", transcript: transcript, system: system, user: user, response: text, tasks: response.actions.map(task(of:)), error: nil, start: start)
            return response
        }
        let fb = fallback(transcript)
        logEntry(mode: "assistant", transcript: transcript, system: system, user: user, response: text, tasks: [fb], error: "parse_failed", start: start)
        return AssistantResponse(actions: [.create(fb)], remark: nil, question: nil)
    }

    /// Second turn after a clarifying question: produce the final actions for the
    /// original transcript, honoring the user's answer. Returns nil on API/parse
    /// failure; an empty array is a deliberate "nothing to change".
    static func resolveClarification(transcript: String, question: String, answer: String, existingTasks: [(title: String, description: String?, deadline: Date?, tag: String?, deadlineIsWeek: Bool)], existingEvents: [DayEvent] = []) async -> [ParsedAction]? {
        let start = Date()
        let today = dateContext()
        let tagInstruction = tagPromptInstruction()
        let taskList = existingTaskListBlock(existingTasks)
        let eventList = eventListBlock(existingEvents)
        let system = """
            \(today) You are Spoke, a voice assistant for the user's to-do list. The user spoke a transcript, you asked a clarifying question, and the user has now answered. Produce the FINAL actions for the ENTIRE original transcript, honoring the user's answer. \
            \(taskList) \
            \(eventList) \
            \(actionRules(tagInstruction: tagInstruction)) \
            - If the user's answer means nothing should change (e.g. it was a duplicate of an existing task), return []. \
            Return ONLY a valid JSON ARRAY of action objects, no markdown, no code fences, no commentary.
            """
        let user = """
            Original transcript: "\(transcript)"
            Your question: "\(question)"
            User's answer: "\(answer)"
            """
        guard let text = await callClaudeRaw(system: system, user: user) else {
            lastRawResponse = nil
            logEntry(mode: "clarify", transcript: transcript, system: system, user: user, response: nil, tasks: [], error: "api_failed", start: start)
            return nil
        }
        lastRawResponse = text
        let json = extractJSON(from: text)
        // "[]" is valid here, so distinguish parse failure from a deliberate no-op
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            logEntry(mode: "clarify", transcript: transcript, system: system, user: user, response: text, tasks: [], error: "parse_failed", start: start)
            return nil
        }
        let actions = parseActions(from: array, existingTasks: existingTasks, existingEvents: existingEvents)
        logEntry(mode: "clarify", transcript: transcript, system: system, user: user, response: text, tasks: actions.map(task(of:)), error: nil, start: start)
        return actions
    }

    /// Follow-up turn on a pending summary: the user spoke again while reviewing the
    /// proposed tasks. The reply is an approval, a cancellation, or a replacement set.
    static func refineActions(transcript: String, pending: [ParsedAction], correction: String, existingTasks: [(title: String, description: String?, deadline: Date?, tag: String?, deadlineIsWeek: Bool)], existingEvents: [DayEvent] = []) async -> RefineOutcome {
        let start = Date()
        let today = dateContext()
        let tagInstruction = tagPromptInstruction()
        let taskList = existingTaskListBlock(existingTasks)
        let eventList = eventListBlock(existingEvents)
        let system = """
            \(today) You are Spoke, a voice assistant for the user's to-do list. The user spoke a transcript and you proposed tasks; the user is reviewing them and has spoken a follow-up. \
            \(taskList) \
            \(eventList) \
            Decide what the follow-up means: \
            - Pure approval ("yes", "yep", "looks good", "go ahead"): return {"approve": true}. \
            - Cancellation ("no", "cancel", "forget it", "discard that"): return {"cancel": true}. \
            - Otherwise return the full REPLACEMENT set as a JSON OBJECT: "actions" (the complete final set, incorporating the corrections AND the unchanged proposed tasks), optional "remark", optional "question" (same rules as before). \
            \(actionRules(tagInstruction: tagInstruction)) \
            Return ONLY valid JSON, no markdown, no code fences, no commentary.
            """
        let user = """
            Original transcript: "\(transcript)"
            Proposed tasks:
            \(serializeActions(pending))
            User's follow-up: "\(correction)"
            """
        guard let text = await callClaudeRaw(system: system, user: user) else {
            lastRawResponse = nil
            logEntry(mode: "refine", transcript: transcript, system: system, user: user, response: nil, tasks: pending.map(task(of:)), error: "api_failed", start: start)
            return .response(AssistantResponse(actions: pending, remark: nil, question: nil))
        }
        lastRawResponse = text
        let json = extractJSON(from: text)
        if let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if obj["approve"] as? Bool == true {
                logEntry(mode: "refine", transcript: transcript, system: system, user: user, response: text, tasks: pending.map(task(of:)), error: nil, start: start)
                return .approve
            }
            if obj["cancel"] as? Bool == true {
                logEntry(mode: "refine", transcript: transcript, system: system, user: user, response: text, tasks: [], error: nil, start: start)
                return .cancel
            }
        }
        if let response = parseAssistantResponse(json, existingTasks: existingTasks, existingEvents: existingEvents) {
            logEntry(mode: "refine", transcript: transcript, system: system, user: user, response: text, tasks: response.actions.map(task(of:)), error: nil, start: start)
            return .response(response)
        }
        logEntry(mode: "refine", transcript: transcript, system: system, user: user, response: text, tasks: pending.map(task(of:)), error: "parse_failed", start: start)
        return .response(AssistantResponse(actions: pending, remark: nil, question: nil))
    }

    // MARK: - Private

    private static var lastRawResponse: String?

    private static func actionRules(tagInstruction: String) -> String {
        """
        Action rules: \
        - Each action object has an "action" field: "create", "edit" or "event". \
        - For "create": include "title" (required), "description" (optional), "deadline" (optional), "tag" (optional). Action-oriented title, max 50 chars. Keep specific details — times, names, locations — in the title when they fit. \
        - Use "event" ONLY for appointment-like commitments at a specific clock time on a specific day: appointments, meetings, reservations, flights, classes, calls scheduled for a set time (e.g. "I have a dentist appointment next Tuesday at 11am"). For "event": include "title" (required, the appointment name, no leading verb like "Attend"), "date" (YYYY-MM-DD, required), "start" (HH:MM 24-hour, required), "end" (HH:MM, optional — omit unless the user gave one), "location" (optional). \
        - Something to get DONE is a task even when a time is mentioned as a deadline ("finish the report by 5pm", "call the plumber tomorrow morning") — use "create". Only a commitment to BE somewhere or attend something at a fixed time is an "event". When unsure, use "create". \
        - If the user mentions an appointment WITHOUT a specific clock time ("dentist sometime next week"), use "create" with a deadline, not "event". \
        - Use "edit-event" to change an EXISTING calendar event from the upcoming-events list ("move my hair appointment to 2pm", "push Friday's dentist back an hour"). Include "match" (the event's title from the list, exactly as shown) and only the fields that change: "title", "date", "start", "end", "location". When the user talks about moving or rescheduling something that appears in BOTH the task list and the upcoming-events list, they almost always mean the calendar event — prefer "edit-event". \
        - For "edit": include "match" (the title of the existing task to edit — must closely match one from the list above) and the updated fields: "title", "description", "deadline", "tag". Merge new information with what exists — don't drop existing content. \
        - Only use "edit" when the user clearly refers to an existing task by name or obvious reference (e.g. "add milk to the grocery list"). \
        - If the transcript contains multiple unrelated tasks, return multiple action objects. \
        - NEVER silently drop information. If a detail cannot fit the title, it must appear in the description. \
        - If a description needs 2 or more distinct items, use bullet format with a short intro sentence, each bullet on its OWN LINE: "Things to pick up:\\n• Milk\\n• Eggs" \
        - Dates: if the user names a specific day, resolve it relative to today as YYYY-MM-DD in "deadline". If they say something is for "this week" or "next week" WITHOUT naming a day (e.g. "sometime this week", "I need to get this done next week"), use the literal string "this-week" or "next-week" as the deadline — do NOT invent a specific day. A deadline applies only to the task it was mentioned with. \
        - \(tagInstruction)
        """
    }

    private static func existingTaskListBlock(_ existingTasks: [(title: String, description: String?, deadline: Date?, tag: String?, deadlineIsWeek: Bool)]) -> String {
        if existingTasks.isEmpty {
            return "There are no existing tasks."
        }
        let items = existingTasks.map { t in
            var parts = ["\"\(t.title)\""]
            if let desc = t.description, !desc.isEmpty {
                let preview = String(desc.prefix(80)).replacingOccurrences(of: "\n", with: " ")
                parts.append("desc: \(preview)")
            }
            return "- " + parts.joined(separator: " | ")
        }
        return "Existing tasks:\n" + items.joined(separator: "\n")
    }

    /// Upcoming calendar events, so "move my hair appointment to 2pm" edits
    /// the event instead of being mis-matched onto a similarly-named task.
    private static func eventListBlock(_ events: [DayEvent]) -> String {
        guard !events.isEmpty else { return "There are no upcoming calendar events." }
        let df = DateFormatter()
        df.dateFormat = "EEE yyyy-MM-dd"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let items = events.map { e in
            let when = e.isAllDay
                ? "\(df.string(from: e.start)) all day"
                : "\(df.string(from: e.start)) \(tf.string(from: e.start))–\(tf.string(from: e.end))"
            return "- \"\(e.title)\" \(when)"
        }
        return "Upcoming calendar events (read-only list — change them ONLY via \"edit-event\"):\n" + items.joined(separator: "\n")
    }

    private static func serializeActions(_ actions: [ParsedAction]) -> String {
        actions.map { action in
            switch action {
            case .create(let t):
                var line = "- CREATE \"\(t.title)\""
                if let d = t.deadline { line += " due \(deadlineToken(d, isWeek: t.deadlineIsWeek))" }
                if let tag = t.tag { line += " tag:\(tag)" }
                if let desc = t.description, !desc.isEmpty {
                    line += " — \(String(desc.prefix(80)).replacingOccurrences(of: "\n", with: " "))"
                }
                return line
            case .edit(let match, let u):
                var line = "- EDIT \"\(match)\" → \"\(u.title)\""
                if let d = u.deadline { line += " due \(deadlineToken(d, isWeek: u.deadlineIsWeek))" }
                if let tag = u.tag { line += " tag:\(tag)" }
                if let desc = u.description, !desc.isEmpty {
                    line += " — \(String(desc.prefix(80)).replacingOccurrences(of: "\n", with: " "))"
                }
                return line
            case .createEvent(let e):
                let df = DateFormatter()
                df.dateFormat = e.isAllDay ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
                var line = "- EVENT \"\(e.title)\" at \(df.string(from: e.start))"
                if let loc = e.location { line += " location:\(loc)" }
                return line
            case .editEvent(let original, let e):
                let df = DateFormatter()
                df.dateFormat = e.isAllDay ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
                return "- EDIT-EVENT \"\(original.title)\" → \"\(e.title)\" at \(df.string(from: e.start))"
            }
        }.joined(separator: "\n")
    }

    /// Serializes a deadline for prompt context, round-trippable with parseDictionary.
    private static func deadlineToken(_ date: Date, isWeek: Bool) -> String {
        guard isWeek else { return isoFormatter.string(from: date) }
        let cal = Calendar.current
        let week = cal.weekStart(for: date)
        if week == cal.weekStart(for: .now) { return "this-week" }
        if let next = cal.date(byAdding: .weekOfYear, value: 1, to: cal.weekStart(for: .now)), week == next { return "next-week" }
        return isoFormatter.string(from: date)
    }

    private static func task(of action: ParsedAction) -> ParsedTask {
        switch action {
        case .create(let t): return t
        case .edit(_, let t): return t
        case .createEvent(let e):
            // Flattened representation so the recording log can show events too
            return ParsedTask(title: "[Event] \(e.title)", description: e.location, deadline: e.start, tag: nil)
        case .editEvent(_, let e):
            return ParsedTask(title: "[Edit event] \(e.title)", description: e.location, deadline: e.start, tag: nil)
        }
    }

    /// Builds the full updated event for an "edit-event" action: the model
    /// sends only the fields that change, everything else carries over from
    /// the event being edited (including its duration when only the start moves).
    private static func mergedEventUpdate(_ dict: [String: Any], original: DayEvent) -> ParsedEvent? {
        let cal = Calendar.current
        let title = (dict["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? original.title
        let location = (dict["location"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? original.location

        let day: Date
        if let dateStr = dict["date"] as? String, let parsed = isoFormatter.date(from: dateStr) {
            day = parsed
        } else {
            day = original.start
        }

        func time(from string: Any?) -> (hour: Int, minute: Int)? {
            guard let string = string as? String else { return nil }
            let parts = string.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
            return (parts[0], parts[1])
        }

        let originalStartParts = cal.dateComponents([.hour, .minute], from: original.start)
        let startTime = time(from: dict["start"]) ?? (originalStartParts.hour ?? 9, originalStartParts.minute ?? 0)
        guard let start = cal.date(bySettingHour: startTime.hour, minute: startTime.minute, second: 0, of: day) else { return nil }

        if original.isAllDay && time(from: dict["start"]) == nil {
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return ParsedEvent(title: title, start: dayStart, end: dayEnd, isAllDay: true, location: location)
        }

        let end: Date
        if let endTime = time(from: dict["end"]),
           let explicitEnd = cal.date(bySettingHour: endTime.hour, minute: endTime.minute, second: 0, of: day),
           explicitEnd > start {
            end = explicitEnd
        } else {
            let duration = original.isAllDay ? 3600 : max(original.end.timeIntervalSince(original.start), 60)
            end = start.addingTimeInterval(duration)
        }
        return ParsedEvent(title: title, start: start, end: end, isAllDay: false, location: location)
    }

    /// Parses {"action": "event", "title": ..., "date": "YYYY-MM-DD", "start": "HH:MM", "end": "HH:MM", "location": ...}.
    /// Untimed events aren't produced by the prompt, but a missing start
    /// degrades to an all-day event rather than losing the appointment.
    private static func parseEventDictionary(_ dict: [String: Any]) -> ParsedEvent? {
        guard let title = dict["title"] as? String, !title.isEmpty,
              let dateStr = dict["date"] as? String,
              let day = isoFormatter.date(from: dateStr) else { return nil }
        let location = (dict["location"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let cal = Calendar.current

        func time(on day: Date, from string: String?) -> Date? {
            guard let string else { return nil }
            let parts = string.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
            return cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
        }

        guard let start = time(on: day, from: dict["start"] as? String) else {
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return ParsedEvent(title: title, start: dayStart, end: dayEnd, isAllDay: true, location: location)
        }
        let end = time(on: day, from: dict["end"] as? String).flatMap { $0 > start ? $0 : nil }
            ?? start.addingTimeInterval(3600)
        return ParsedEvent(title: title, start: start, end: end, isAllDay: false, location: location)
    }

    /// Parses the assistant object shape {"actions": [...], "remark": ..., "question": ...}.
    /// Tolerates a bare array (legacy shape) as actions-only.
    private static func parseAssistantResponse(_ text: String, existingTasks: [(title: String, description: String?, deadline: Date?, tag: String?, deadlineIsWeek: Bool)], existingEvents: [DayEvent] = []) -> AssistantResponse? {
        guard let data = text.data(using: .utf8) else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let actionDicts = obj["actions"] as? [[String: Any]] ?? []
            let actions = parseActions(from: actionDicts, existingTasks: existingTasks, existingEvents: existingEvents)
            let remark = (obj["remark"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            var question: AssistantQuestion? = nil
            if let q = obj["question"] as? [String: Any],
               let qText = q["text"] as? String, !qText.isEmpty {
                let opts = ((q["options"] as? [String]) ?? []).filter { !$0.isEmpty }
                question = AssistantQuestion(text: qText, options: opts.count >= 2 ? Array(opts.prefix(2)) : ["Yes", "No"])
            }
            if actions.isEmpty && question == nil && remark == nil {
                // Might be a single bare task object
                if let single = parseDictionary(obj) {
                    return AssistantResponse(actions: [.create(single)], remark: nil, question: nil)
                }
                return nil
            }
            return AssistantResponse(
                actions: actions,
                remark: remark,
                question: question,
                droppedActions: actions.count < actionDicts.count
            )
        }
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let actions = parseActions(from: array, existingTasks: existingTasks, existingEvents: existingEvents)
            return actions.isEmpty ? nil : AssistantResponse(actions: actions, remark: nil, question: nil)
        }
        return nil
    }

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
        let useProxy = !Config.proxyBaseURL.isEmpty
        let endpoint = useProxy
            ? Config.proxyBaseURL + "/v1/parse"
            : "https://api.anthropic.com/v1/messages"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any]
        if useProxy {
            // The worker pins model + max_tokens and returns the same
            // response shape the direct call does.
            request.setValue(Config.proxySecret, forHTTPHeaderField: "x-spoke-key")
            body = ["system": system, "user": user]
        } else {
            request.setValue(Config.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 800,
                "system": system,
                "messages": [["role": "user", "content": user]]
            ]
        }

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

    private static func parseActions(from array: [[String: Any]], existingTasks: [(title: String, description: String?, deadline: Date?, tag: String?, deadlineIsWeek: Bool)], existingEvents: [DayEvent] = []) -> [ParsedAction] {
        return array.compactMap { dict -> ParsedAction? in
            var dict = dict
            let action = dict["action"] as? String ?? "create"

            if action == "event" {
                if let event = parseEventDictionary(dict) { return .createEvent(event) }
                // Malformed event: salvage as a plain task rather than dropping it
                guard let parsed = parseDictionary(dict) else { return nil }
                return .create(parsed)
            }

            if action == "edit-event", let matchTitle = dict["match"] as? String {
                let lowered = matchTitle.lowercased()
                // Soonest upcoming occurrence wins when titles repeat (recurring events)
                let candidates = existingEvents.sorted { $0.start < $1.start }
                let original = candidates.first { $0.title.lowercased() == lowered }
                    ?? candidates.first { $0.title.lowercased().contains(lowered) }
                    ?? candidates.first { lowered.contains($0.title.lowercased()) }
                guard let original, let updates = mergedEventUpdate(dict, original: original) else {
                    // Unknown event — never invent a calendar write from a bad match
                    return nil
                }
                return .editEvent(original: original, updates: updates)
            }

            if action == "edit", let matchTitle = dict["match"] as? String {
                // Find best matching existing task (case-insensitive, prefix-tolerant)
                let match = existingTasks.first { $0.title.lowercased() == matchTitle.lowercased() }
                    ?? existingTasks.first { $0.title.lowercased().contains(matchTitle.lowercased()) }
                    ?? existingTasks.first { matchTitle.lowercased().contains($0.title.lowercased()) }

                if let match {
                    // An edit only carries the fields that change, so the title
                    // is routinely absent — "set that to today" needs no new
                    // title. parseDictionary requires one, so borrow the title
                    // of the task being edited. Without this the whole action
                    // was dropped and only the remark survived, so Spoke said
                    // it had made the change and then didn't.
                    if (dict["title"] as? String).map(\.isEmpty) ?? true {
                        dict["title"] = match.title
                    }
                    guard let parsed = parseDictionary(dict) else { return nil }
                    // Merge: keep existing values where the edit doesn't provide new ones
                    let mergedDesc = mergeDescription(existing: match.description, new: parsed.description)
                    let mergedDeadline = parsed.deadline ?? match.deadline
                    let mergedIsWeek = parsed.deadline != nil ? parsed.deadlineIsWeek : match.deadlineIsWeek
                    let mergedTag = parsed.tag ?? match.tag
                    let merged = ParsedTask(
                        title: parsed.title,
                        description: mergedDesc,
                        deadline: mergedDeadline,
                        tag: mergedTag,
                        deadlineIsWeek: mergedIsWeek
                    )
                    return .edit(matchTitle: match.title, updates: merged)
                } else {
                    // No match found — treat as create
                    guard let parsed = parseDictionary(dict) else { return nil }
                    return .create(parsed)
                }
            }
            guard let parsed = parseDictionary(dict) else { return nil }
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
        var deadlineIsWeek = false
        if let ds = json["deadline"] as? String, !ds.isEmpty {
            switch ds {
            case "this-week":
                deadline = Calendar.current.weekBucketDeadline(offsetWeeks: 0)
                deadlineIsWeek = true
            case "next-week":
                deadline = Calendar.current.weekBucketDeadline(offsetWeeks: 1)
                deadlineIsWeek = true
            default:
                deadline = isoFormatter.date(from: ds)
            }
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
        return ParsedTask(title: title, description: description?.isEmpty == true ? nil : description, deadline: deadline, tag: tag, deadlineIsWeek: deadlineIsWeek)
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

    /// Explicit weekday→date table for the prompt. Models are unreliable at
    /// deriving weekdays from a bare ISO date, which shifted every named day
    /// forward — so we spell out the next two weeks and forbid arithmetic.
    private static func dateContext() -> String {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        let cal = Calendar.current
        let entries = (0..<14).compactMap { offset -> String? in
            guard let date = cal.date(byAdding: .day, value: offset, to: .now) else { return nil }
            let label = offset == 0 ? " (today)" : (offset == 1 ? " (tomorrow)" : "")
            return "\(weekdayFormatter.string(from: date)) = \(isoFormatter.string(from: date))\(label)"
        }
        let todayName = weekdayFormatter.string(from: .now)
        return "Today is \(todayName), \(isoToday()). Resolve day names to dates using EXACTLY this table — a task due on a named day gets THAT day's date, never the day before or after: \(entries.joined(separator: "; "))."
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
