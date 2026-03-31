import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: SpokeTask
    var showCoachingToast: Bool = false

    @State private var recorder = VoiceRecorder()
    @State private var showPermissionAlert = false
    @State private var coachingToastVisible = false
    @State private var showDatePicker = false
    @State private var pickerDate: Date = .now

    // Local editing state — source of truth for the UI, synced to task.taskDescription
    @State private var editingNotes = ""
    @State private var editingBullets: [BulletDraft] = []
    @FocusState private var focusedField: FocusField?

    // Snapshot captured on appear — restored if the user taps X
    @State private var snapshotTitle = ""
    @State private var snapshotDescription: String? = nil
    @State private var snapshotDeadline: Date? = nil
    @State private var snapshotTag: String? = nil

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let settings = AppSettings.shared
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
            return "Completed \(shortRelativeDate(completedAt))"
        }
        let day = Calendar.current.component(.day, from: task.createdAt)
        let ordinal = Self.ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        let month = task.createdAt.formatted(.dateTime.month(.abbreviated))
        return "Added \(ordinal) \(month)"
    }

    private func shortRelativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        let elapsed = Date.now.timeIntervalSince(date)
        let minutes = Int(elapsed / 60)
        let hours = Int(elapsed / 3600)

        // Under 1 minute
        if minutes < 1 { return "just now" }
        // Under 1 hour: "12 min ago"
        if minutes < 60 { return "\(minutes) min ago" }
        // Under 6 hours and same day: "2 hr ago"
        if hours < 6 && cal.isDateInToday(date) {
            return "\(hours) hr ago"
        }
        // Otherwise show date: "30th Mar"
        let day = cal.component(.day, from: date)
        let ordinal = Self.ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        let month = date.formatted(.dateTime.month(.abbreviated))
        return "\(ordinal) \(month)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header buttons
            HStack {
                Button {
                    task.title = snapshotTitle
                    task.taskDescription = snapshotDescription
                    task.deadline = snapshotDeadline
                    task.tag = snapshotTag
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(.secondaryLabel))
                }

                Spacer()

                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(coral)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            // MARK: Title
            TextField("Task title", text: $task.title, axis: .vertical)
                .font(.title2)
                .fontWeight(.semibold)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .notes }
                .disabled(task.isCompleted)
                .padding(.top, 10)
                .padding(.horizontal, 24)

            // MARK: Pills row
            HStack(spacing: 6) {
                if settings.appMode == .organized {
                    if let deadline = task.deadline {
                        if task.isCompleted {
                            Text(deadlineLabel(for: deadline))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(coral)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(coral.opacity(0.12)))
                        } else {
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
                                Text(deadlineLabel(for: deadline))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(coral)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(coral.opacity(0.12)))
                            }
                            .animation(.easeInOut(duration: 0.2), value: deadline)
                        }
                    } else if !task.isCompleted {
                        Menu {
                            Button("Today")        { task.deadline = quickDate(daysAhead: 0) }
                            Button("Tomorrow")     { task.deadline = quickDate(daysAhead: 1) }
                            Button("This weekend") { task.deadline = thisWeekend }
                            Button("Next week")    { task.deadline = nextMonday }
                            Button("Custom…")      { pickerDate = .now; showDatePicker = true }
                        } label: {
                            Text("ADD DATE")
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
                        if task.isCompleted {
                            Text(tag.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(.secondaryLabel))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)))
                        } else {
                            Menu {
                                ForEach(TagStore.shared.tags, id: \.self) { option in
                                    Button(option.capitalized) {
                                        withAnimation(.easeInOut(duration: 0.2)) { task.tag = option }
                                    }
                                }
                                Divider()
                                Button("Remove tag", role: .destructive) {
                                    withAnimation(.easeInOut(duration: 0.2)) { task.tag = nil }
                                }
                            } label: {
                                Text(tag.uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(.secondaryLabel))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)))
                            }
                            .animation(.easeInOut(duration: 0.2), value: tag)
                        }
                    } else if !task.isCompleted {
                        Menu {
                            ForEach(TagStore.shared.tags, id: \.self) { tag in
                                Button(tag.capitalized) {
                                    withAnimation(.easeInOut(duration: 0.2)) { task.tag = tag }
                                }
                            }
                        } label: {
                            Text("ADD TAG")
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
                }

                Spacer()

                if settings.appMode == .organized {
                    Text(metadataDateString)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 24)

            // MARK: Scrollable description area
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Notes field — hidden for completed tasks with no description
                    if !task.isCompleted || !editingNotes.isEmpty {
                        TextField("Add a description…", text: $editingNotes, axis: .vertical)
                            .font(.body)
                            .foregroundStyle(.primary.opacity(0.75))
                            .focused($focusedField, equals: .notes)
                            .disabled(task.isCompleted)
                            .onChange(of: editingNotes) { _, _ in syncToModel() }
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                    }

                    // Subtask items
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($editingBullets) { $bullet in
                            HStack(alignment: .top, spacing: 10) {
                                Button {
                                    bullet.checked.toggle()
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    syncToModel()
                                } label: {
                                    Image(systemName: bullet.checked ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(bullet.checked ? coral : Color(.tertiaryLabel))
                                        .animation(.easeInOut(duration: 0.2), value: bullet.checked)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)

                                TextField("Item", text: $bullet.text, axis: .vertical)
                                    .font(.body)
                                    .strikethrough(bullet.checked)
                                    .foregroundStyle(.primary.opacity(bullet.checked ? 0.35 : 0.75))
                                    .focused($focusedField, equals: .bullet(bullet.id))
                                    .disabled(task.isCompleted)
                                    .submitLabel(.next)
                                    .onSubmit { addBulletAfter(bullet.id) }
                                    .onChange(of: bullet.text) { _, _ in syncToModel() }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if focusedField == .bullet(bullet.id) {
                                    Button { deleteBullet(bullet.id) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color(.quaternaryLabel))
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }
                        }

                        if !task.isCompleted {
                            Button { addBullet() } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Add item")
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(coral.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, editingBullets.isEmpty ? 8 : 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, editingNotes.isEmpty && editingBullets.isEmpty ? 4 : 20)

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // MARK: Voice button
            ZStack(alignment: .top) {
                VoiceButton(
                    state: voiceButtonState,
                    audioLevel: recorder.audioLevel,
                    onTap: handleTap
                )
                .frame(maxWidth: .infinity, minHeight: 96)

                // Coaching toast
                if coachingToastVisible {
                    Text("Tap the mic to add items, a description, or make changes.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color(.label).opacity(0.8)))
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .offset(y: -8)
                        .allowsHitTesting(false)
                }
            }
            .padding(.bottom, -4)
        }
        .onAppear { initEditingState() }
        .task {
            guard showCoachingToast else { return }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                coachingToastVisible = true
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selection: $pickerDate) { date in
                withAnimation(.easeInOut(duration: 0.2)) { task.deadline = date }
            } onClear: {
                withAnimation(.easeInOut(duration: 0.2)) { task.deadline = nil }
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

    // MARK: - Editing state

    private func initEditingState() {
        let (prose, bullets) = Self.decompose(task.taskDescription)
        editingNotes = prose
        editingBullets = bullets
        // Snapshot for discard
        snapshotTitle = task.title
        snapshotDescription = task.taskDescription
        snapshotDeadline = task.deadline
        snapshotTag = task.tag
    }

    /// Split a taskDescription string into prose notes and bullet items.
    private static func decompose(_ description: String?) -> (prose: String, bullets: [BulletDraft]) {
        guard let description, !description.isEmpty else { return ("", []) }
        var proseLines: [String] = []
        var bullets: [BulletDraft] = []
        for line in description.components(separatedBy: "\n") {
            if line.hasPrefix("✓ ") {
                bullets.append(BulletDraft(text: String(line.dropFirst(2)), checked: true))
            } else if line.hasPrefix("• ") {
                bullets.append(BulletDraft(text: String(line.dropFirst(2)), checked: false))
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                proseLines.append(line)
            }
        }
        return (proseLines.joined(separator: "\n"), bullets)
    }

    /// Reconstruct taskDescription from local editing state.
    private func compose() -> String? {
        var parts: [String] = []
        let prose = editingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prose.isEmpty { parts.append(prose) }
        for b in editingBullets {
            let text = b.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            parts.append((b.checked ? "✓ " : "• ") + text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func syncToModel() {
        task.taskDescription = compose()
    }

    private func addBullet() {
        let newBullet = BulletDraft(text: "", checked: false)
        editingBullets.append(newBullet)
        focusBullet(newBullet.id)
    }

    private func addBulletAfter(_ id: UUID) {
        let newBullet = BulletDraft(text: "", checked: false)
        if let index = editingBullets.firstIndex(where: { $0.id == id }) {
            editingBullets.insert(newBullet, at: index + 1)
        } else {
            editingBullets.append(newBullet)
        }
        focusBullet(newBullet.id)
    }

    private func focusBullet(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedField = .bullet(id)
        }
    }

    private func deleteBullet(_ id: UUID) {
        editingBullets.removeAll { $0.id == id }
        syncToModel()
    }

    // MARK: - Date display

    private func deadlineLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)    { return "TODAY" }
        if cal.isDateInTomorrow(date) { return "TOMORROW" }
        return Self.deadlineFormatter.string(from: date).uppercased()
    }

    // MARK: - Quick dates

    private func quickDate(daysAhead: Int) -> Date {
        let start = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .day, value: daysAhead, to: start) ?? start
    }

    private var thisWeekend: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today)
        let daysUntilSat = (7 - weekday + 7) % 7
        return cal.date(byAdding: .day, value: daysUntilSat == 0 ? 7 : daysUntilSat, to: today) ?? today
    }

    private var nextMonday: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today)
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

    private func handleTap() {
        switch recorder.recordingState {
        case .idle:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        case .recording:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            stopAndProcess()
        case .processing:
            break
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
            // Re-sync local editing state after voice update
            let (prose, bullets) = Self.decompose(parsed.description)
            editingNotes = prose
            editingBullets = bullets
            recorder.finishProcessing()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Supporting types

private struct BulletDraft: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var checked: Bool
}

private enum FocusField: Hashable {
    case title
    case notes
    case bullet(UUID)
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
    let task = SpokeTask(title: "Book karate class for Alex", taskDescription: "Find a studio nearby.\n• Call local dojos\n• Compare prices\n• Book trial class", deadline: Calendar.current.date(byAdding: .day, value: 7, to: .now), tag: "personal")
    TaskDetailView(task: task)
        .modelContainer(for: SpokeTask.self, inMemory: true)
}

#Preview("No description") {
    let task = SpokeTask(title: "Pick up groceries", tag: "errands")
    TaskDetailView(task: task)
        .modelContainer(for: SpokeTask.self, inMemory: true)
}
