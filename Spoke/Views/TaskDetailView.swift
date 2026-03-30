import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let task: SpokeTask

    @State private var recorder = VoiceRecorder()
    @State private var showPermissionAlert = false
    @State private var tapModeActive = false
    @State private var showDatePicker = false
    @State private var pickerDate: Date = .now

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let ordinalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f
    }()

    private var metadataDateString: String {
        if task.isCompleted, let completedAt = task.completedAt {
            return "Completed \(relativeFormatter.localizedString(for: completedAt, relativeTo: .now))"
        }
        let day = Calendar.current.component(.day, from: task.createdAt)
        let ordinal = Self.ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        let month = task.createdAt.formatted(.dateTime.month(.abbreviated))
        return "Added \(ordinal) \(month)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(task.title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 28)
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.3), value: task.title)

            HStack(spacing: 6) {
                if let deadline = task.deadline {
                    Menu {
                        Button("Today")        { task.deadline = quickDate(daysAhead: 0) }
                        Button("Tomorrow")     { task.deadline = quickDate(daysAhead: 1) }
                        Button("This weekend") { task.deadline = thisWeekend }
                        Button("Next week")    { task.deadline = nextMonday }
                        Button("Custom…")      { pickerDate = deadline; showDatePicker = true }
                        Divider()
                        Button("Remove date", role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.2)) { task.deadline = nil }
                        }
                    } label: {
                        Text(Self.deadlineFormatter.string(from: deadline).uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(coral)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(coral.opacity(0.12))
                            )
                    }
                    .animation(.easeInOut(duration: 0.2), value: deadline)
                } else if !task.isCompleted {
                    Menu {
                        Button("Today")        { task.deadline = quickDate(daysAhead: 0) }
                        Button("Tomorrow")     { task.deadline = quickDate(daysAhead: 1) }
                        Button("This weekend") { task.deadline = thisWeekend }
                        Button("Next week")    { task.deadline = nextMonday }
                        Button("Custom…")      { pickerDate = .now; showDatePicker = true }
                    } label: {
                        Text("Add date")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(.tertiaryLabel).opacity(0.5),
                                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            )
                    }
                }

                if let tag = task.tag, !tag.isEmpty {
                    Text(tag.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.tertiarySystemFill))
                        )
                        .animation(.easeInOut(duration: 0.2), value: tag)
                } else if !task.isCompleted {
                    Menu {
                        ForEach(TagStore.shared.tags, id: \.self) { tag in
                            Button(tag.capitalized) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    task.tag = tag
                                }
                            }
                        }
                    } label: {
                        Text("Add tag")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(.tertiaryLabel).opacity(0.5),
                                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            )
                    }
                }

                Spacer()

                Text(metadataDateString)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .padding(.top, 10)
            .padding(.horizontal, 24)

            if let desc = task.taskDescription, !desc.isEmpty {
                DescriptionItemsView(description: desc) { updated in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        task.taskDescription = updated
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .padding(.top, 20)
                .padding(.horizontal, 24)
                .transition(.opacity)
            } else {
                Text("No description. Tap the microphone to add more details or subtasks.")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(Color(.systemGray3))
                    .padding(.top, 20)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 4) {
                VoiceButton(
                    state: voiceButtonState,
                    audioLevel: recorder.audioLevel,
                    onStart: handleStart,
                    onRelease: handleRelease
                )
                .frame(maxWidth: .infinity, minHeight: 96)
            }
            .padding(.bottom, -4)
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selection: $pickerDate) { date in
                withAnimation(.easeInOut(duration: 0.2)) {
                    task.deadline = date
                }
            } onClear: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    task.deadline = nil
                }
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
        .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Spoke needs microphone and speech recognition access. Please enable them in Settings.")
        }
    }

    // MARK: - Quick dates

    private func quickDate(daysAhead: Int) -> Date {
        let start = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .day, value: daysAhead, to: start) ?? start
    }

    private var thisWeekend: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today) // 1=Sun, 7=Sat
        let daysUntilSat = (7 - weekday + 7) % 7
        return cal.date(byAdding: .day, value: daysUntilSat == 0 ? 7 : daysUntilSat, to: today) ?? today
    }

    private var nextMonday: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today) // 1=Sun, 2=Mon
        let daysUntilMon = (2 - weekday + 7) % 7
        return cal.date(byAdding: .day, value: daysUntilMon == 0 ? 7 : daysUntilMon, to: today) ?? today
    }

    // MARK: - Voice

    private var voiceButtonState: VoiceButtonState {
        switch recorder.recordingState {
        case .idle:       .idle
        case .recording:  .recording
        case .processing: .processing
        }
    }

    private func handleStart() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard recorder.recordingState == .idle else { return }
        Task {
            let granted = await recorder.requestPermissionsIfNeeded()
            guard granted else {
                showPermissionAlert = true
                return
            }
            do {
                try recorder.startRecording()
            } catch {
                recorder.finishProcessing()
            }
        }
    }

    private func handleRelease(elapsed: TimeInterval) {
        switch recorder.recordingState {
        case .recording:
            if tapModeActive {
                tapModeActive = false
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                stopAndProcess()
            } else if elapsed < 0.3 {
                tapModeActive = true
            } else {
                tapModeActive = false
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                stopAndProcess()
            }
        default:
            tapModeActive = false
        }
    }

    private func stopAndProcess() {
        let transcript = recorder.stopRecording()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recorder.finishProcessing()
            return
        }
        Task {
            let parsed = await TaskParser.parseEdit(
                transcript: transcript,
                currentTitle: task.title,
                currentDescription: task.taskDescription,
                currentDeadline: task.deadline,
                currentTag: task.tag
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                task.title = parsed.title
                task.taskDescription = parsed.description
                task.deadline = parsed.deadline
                task.tag = parsed.tag
            }
            recorder.finishProcessing()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Description items

/// Renders a description string as interactive checkmark rows.
/// Bullet lines start with "• " (unchecked) or "✓ " (checked).
/// Plain-prose lines are shown as non-interactive text.
private struct DescriptionItemsView: View {
    let description: String
    let onToggle: (String) -> Void

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    private struct Item {
        let lineIndex: Int   // index in original \n-split array
        let text: String
        let checked: Bool
        let isBullet: Bool
    }

    private var items: [Item] {
        description
            .components(separatedBy: "\n")
            .enumerated()
            .compactMap { i, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return nil }
                if line.hasPrefix("✓ ") {
                    return Item(lineIndex: i, text: String(line.dropFirst(2)), checked: true,  isBullet: true)
                } else if line.hasPrefix("• ") {
                    return Item(lineIndex: i, text: String(line.dropFirst(2)), checked: false, isBullet: true)
                } else {
                    return Item(lineIndex: i, text: line, checked: false, isBullet: false)
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.lineIndex) { item in
                if item.isBullet {
                    Button {
                        onToggle(toggled(at: item.lineIndex))
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(item.checked ? coral : Color(.tertiaryLabel))
                                .animation(.easeInOut(duration: 0.2), value: item.checked)

                            Text(item.text)
                                .font(.body)
                                .foregroundStyle(.primary.opacity(0.75))
                                .strikethrough(item.checked, color: .secondary)
                                .opacity(item.checked ? 0.4 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: item.checked)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(item.text)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.75))
                }
            }
        }
    }

    /// Returns a new description string with the item at `lineIndex` toggled.
    private func toggled(at lineIndex: Int) -> String {
        var lines = description.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return description }
        let line = lines[lineIndex]
        if line.hasPrefix("✓ ") {
            lines[lineIndex] = "• " + line.dropFirst(2)
        } else if line.hasPrefix("• ") {
            lines[lineIndex] = "✓ " + line.dropFirst(2)
        }
        return lines.joined(separator: "\n")
    }
}


// MARK: - Date picker sheet

private struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Date
    let onConfirm: (Date) -> Void
    let onClear: () -> Void

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Clear") {
                    onClear()
                    dismiss()
                }
                .foregroundStyle(Color(.secondaryLabel))

                Spacer()

                Button("Done") {
                    onConfirm(selection)
                    dismiss()
                }
                .fontWeight(.semibold)
                .foregroundStyle(coral)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            DatePicker("", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(coral)
                .padding(.horizontal, 12)
        }
    }
}

#Preview("With description") {
    let task = SpokeTask(title: "Book karate class for Alex", taskDescription: "• Find local dojos\n• Compare prices\n• Book trial class", deadline: Calendar.current.date(byAdding: .day, value: 7, to: .now), tag: "personal")
    TaskDetailView(task: task)
        .modelContainer(for: SpokeTask.self, inMemory: true)
}

#Preview("No description") {
    let task = SpokeTask(title: "Pick up groceries", tag: "errands")
    TaskDetailView(task: task)
        .modelContainer(for: SpokeTask.self, inMemory: true)
}
