import SwiftUI
import SwiftData

// MARK: - Time bucket

private enum TaskBucket: String, CaseIterable {
    case today     = "Today"
    case yesterday = "Yesterday"
    case thisWeek  = "This Week"
    case earlier   = "Earlier"
}

private func bucket(for task: SpokeTask) -> TaskBucket {
    let cal = Calendar.current
    if cal.isDateInToday(task.createdAt)     { return .today }
    if cal.isDateInYesterday(task.createdAt) { return .yesterday }
    if cal.isDate(task.createdAt, equalTo: .now, toGranularity: .weekOfYear) { return .thisWeek }
    return .earlier
}

// MARK: - Sort mode

private enum SortMode: String {
    case dateAdded = "dateAdded"
    case dueDate   = "dueDate"
}

private enum DeadlineBucket: String, CaseIterable {
    case overdue    = "Overdue"
    case today      = "Today"
    case tomorrow   = "Tomorrow"
    case thisWeek   = "This Week"
    case nextWeek   = "Next Week"
    case later      = "Later"
    case noDueDate  = "No Due Date"
}

private func deadlineBucket(for task: SpokeTask) -> DeadlineBucket {
    guard let deadline = task.deadline else { return .noDueDate }
    let cal = Calendar.current
    if cal.isDateInToday(deadline)    { return .today }
    if cal.isDateInTomorrow(deadline) { return .tomorrow }
    if deadline < .now                { return .overdue }
    if cal.isDate(deadline, equalTo: .now, toGranularity: .weekOfYear) { return .thisWeek }
    if let nextWeek = cal.date(byAdding: .weekOfYear, value: 1, to: .now),
       cal.isDate(deadline, equalTo: nextWeek, toGranularity: .weekOfYear) {
        return .nextWeek
    }
    return .later
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(
        filter: #Predicate<SpokeTask> { $0.isCompleted == false },
        sort: [SortDescriptor(\SpokeTask.createdAt, order: .reverse)]
    )
    private var activeTasks: [SpokeTask]

    @Query(
        filter: #Predicate<SpokeTask> { $0.isCompleted == true },
        sort: [SortDescriptor(\SpokeTask.completedAt, order: .reverse)]
    )
    private var completedTasks: [SpokeTask]

    @AppStorage("sortMode") private var sortMode: SortMode = .dateAdded
    private let settings = AppSettings.shared

    @State private var recorder = VoiceRecorder()
    @State private var selectedTask: SpokeTask?
    @State private var showPermissionAlert = false
    @State private var selectedTag: String? = nil
    @State private var showSettings = false
    private let tagStore = TagStore.shared

    private var hasTasks: Bool { !activeTasks.isEmpty || !completedTasks.isEmpty }
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let bottomBarHeight: CGFloat = 132

    private var availableTags: [String] {
        let allowed = Set(tagStore.tags)
        let allTasks = activeTasks + completedTasks
        return Array(Set(allTasks.compactMap { $0.tag }).intersection(allowed)).sorted()
    }

    private var filteredActiveTasks: [SpokeTask] {
        guard let tag = selectedTag else { return activeTasks }
        return activeTasks.filter { $0.tag == tag }
    }

    private var filteredCompletedTasks: [SpokeTask] {
        guard let tag = selectedTag else { return completedTasks }
        return completedTasks.filter { $0.tag == tag }
    }

    // Group active tasks by time bucket, dropping empty buckets
    private var groupedActiveTasks: [(TaskBucket, [SpokeTask])] {
        TaskBucket.allCases.compactMap { b in
            let tasks = filteredActiveTasks.filter { bucket(for: $0) == b }
            return tasks.isEmpty ? nil : (b, tasks)
        }
    }

    // Group active tasks by deadline bucket, sorted by deadline within each bucket
    private var deadlineGroupedActiveTasks: [(DeadlineBucket, [SpokeTask])] {
        DeadlineBucket.allCases.compactMap { b in
            let tasks = filteredActiveTasks
                .filter { deadlineBucket(for: $0) == b }
                .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            return tasks.isEmpty ? nil : (b, tasks)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            taskListView
                .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    // Wordmark + settings
                    HStack {
                        Spacer()
                            .frame(width: 44)

                        HStack(spacing: 4) {
                            Text("spoke")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                            Circle()
                                .fill(coral)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)

                        Button { showSettings = true } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(coral)
                        }
                        .frame(width: 44)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    if hasTasks && settings.appMode == .organized && settings.showTags {
                        filterPillsView
                            .padding(.bottom, 0)
                    }
                }
                .background(.background)
            }
                .safeAreaPadding(.bottom, bottomBarHeight)

            bottomVoiceBar
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color(.systemBackground))
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(tagStore: tagStore)
                .presentationDetents([.large])
                .presentationBackground(.background.opacity(0.92))
        }
        .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Spoke needs microphone and speech recognition access to create voice tasks. Please enable them in Settings.")
        }
        .task { pruneCompletedTasks() }
        .onChange(of: settings.appMode) { _, mode in
            if mode == .simple { sortMode = .dateAdded }
        }
        .onChange(of: settings.showDueDates) { _, show in
            if !show { sortMode = .dateAdded }
        }
        .onChange(of: availableTags) { _, tags in
            if let selected = selectedTag, !tags.contains(selected) {
                selectedTag = nil
            }
        }
        .onChange(of: tagStore.tags) { _, allowed in
            let allowedSet = Set(allowed)
            for task in activeTasks + completedTasks {
                if let tag = task.tag, !allowedSet.contains(tag) {
                    task.tag = nil
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pruneCompletedTasks() }
        }
    }

    // MARK: - Filter pills

    private var taskListView: some View {
        Group {
            if activeTasks.isEmpty && completedTasks.isEmpty {
                emptyStateView
            } else {
                List {
                    if sortMode == .dateAdded {
                        ForEach(groupedActiveTasks, id: \.0.rawValue) { (b, tasks) in
                            Section {
                                ForEach(tasks) { task in
                                    TaskRowView(
                                        task: task,
                                        onToggleComplete: { toggleComplete(task) },
                                        onDelete: { deleteTask(task) },
                                        onTap: { selectedTask = task }
                                    )
                                }
                            } header: {
                                sectionHeader(sectionLabel(b))
                            }
                        }
                    } else {
                        ForEach(deadlineGroupedActiveTasks, id: \.0.rawValue) { (b, tasks) in
                            Section {
                                ForEach(Array(tasks.enumerated()), id: \.element.id) { _, task in
                                    TaskRowView(
                                        task: task,
                                        onToggleComplete: { toggleComplete(task) },
                                        onDelete: { deleteTask(task) },
                                        onTap: { selectedTask = task }
                                    )
                                }
                            } header: {
                                sectionHeader(sectionLabel(b))
                            }
                        }
                    }

                    if !filteredCompletedTasks.isEmpty {
                        Section {
                            ForEach(filteredCompletedTasks) { task in
                                TaskRowView(
                                    task: task,
                                    onToggleComplete: { toggleComplete(task) },
                                    onDelete: { deleteTask(task) },
                                    onTap: { selectedTask = task }
                                )
                            }
                        } header: {
                            sectionHeader("Completed")
                        }
                    }
                }
                .listStyle(.plain)
                .listSectionSpacing(0)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Task list illustration
            VStack(alignment: .leading, spacing: 10) {
                // Checked task row
                HStack(spacing: 10) {
                    Circle()
                        .fill(coral.opacity(0.2))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(coral.opacity(0.5))
                        )
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray4).opacity(0.5))
                        .frame(width: 110, height: 8)
                }

                // Unchecked task row
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray4).opacity(0.5))
                        .frame(width: 140, height: 8)
                }

                // Checked task row
                HStack(spacing: 10) {
                    Circle()
                        .fill(coral.opacity(0.2))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(coral.opacity(0.5))
                        )
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray4).opacity(0.5))
                        .frame(width: 90, height: 8)
                }

                // Unchecked task row
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray4).opacity(0.5))
                        .frame(width: 120, height: 8)
                }

                // Unchecked task row
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray4).opacity(0.5))
                        .frame(width: 100, height: 8)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(.systemGray4).opacity(0.4), lineWidth: 1)
            )

            Text("Tap or hold the mic to add your first task.")
                .font(.subheadline)
                .foregroundStyle(Color(.systemGray2))
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    private var bottomVoiceBar: some View {
        VStack(spacing: 4) {
            VoiceButton(
                state: voiceButtonState,
                audioLevel: recorder.audioLevel,
                onTap: handleTap
            )
            .frame(maxWidth: .infinity, minHeight: 96)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            BottomVoiceFade()
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var filterPillsView: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !availableTags.isEmpty {
                        filterPill(label: "All", tag: nil)
                        ForEach(availableTags, id: \.self) { tag in
                            filterPill(label: tag.capitalized, tag: tag)
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
            }
            .mask(
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 24)
                }
            )

            sortToggleButton
                .padding(.trailing, 16)
        }
    }

    private var sortToggleButton: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { sortMode = .dateAdded }
            } label: {
                Label("Sort by date added", systemImage: sortMode == .dateAdded ? "checkmark" : "")
            }

            if settings.appMode == .organized && settings.showDueDates {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { sortMode = .dueDate }
                } label: {
                    Label("Sort by due date", systemImage: sortMode == .dueDate ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(sortMode == .dueDate ? coral : Color(.secondaryLabel))
                .frame(width: 32, height: 32)
        }
    }

    private func filterPill(label: String, tag: String?) -> some View {
        let isActive = selectedTag == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTag = isActive ? nil : tag
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? .white : Color(.secondaryLabel))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isActive ? coral : Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color(.label).opacity(0.6))
    }

    private func sectionLabel(_ bucket: TaskBucket) -> String {
        switch bucket {
        case .today:     return "Added today"
        case .yesterday: return "Added yesterday"
        case .thisWeek:  return "This week"
        case .earlier:   return "Earlier"
        }
    }

    private func sectionLabel(_ bucket: DeadlineBucket) -> String {
        switch bucket {
        case .overdue:   return "Overdue"
        case .today:     return "Due today"
        case .tomorrow:  return "Due tomorrow"
        case .thisWeek:  return "Due this week"
        case .nextWeek:  return "Due next week"
        case .later:     return "Later"
        case .noDueDate: return "No due date"
        }
    }

    // MARK: - Voice button state

    private var voiceButtonState: VoiceButtonState {
        switch recorder.recordingState {
        case .idle:       .idle
        case .recording:  .recording
        case .processing: .processing
        }
    }

    // MARK: - Voice tap handler

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
            let parsed = await TaskParser.parse(transcript: transcript)
            let task = SpokeTask(title: parsed.title, taskDescription: parsed.description, deadline: parsed.deadline, tag: parsed.tag)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                modelContext.insert(task)
            }
            recorder.finishProcessing()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Task actions

    private func toggleComplete(_ task: SpokeTask) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            if task.isCompleted {
                task.isCompleted = false
                task.completedAt = nil
                // createdAt is intentionally untouched — task returns to its original time bucket
            } else {
                task.isCompleted = true
                task.completedAt = .now
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func deleteTask(_ task: SpokeTask) {
        modelContext.delete(task)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    // MARK: - Prune

    private func pruneCompletedTasks() {
        guard settings.autoDeleteCompleted else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now)!
        let predicate = #Predicate<SpokeTask> {
            $0.isCompleted == true
            && $0.completedAt != nil
            && $0.completedAt! < cutoff
        }
        try? modelContext.delete(model: SpokeTask.self, where: predicate)
    }
}

// MARK: - Bottom bar background

private struct BottomVoiceFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(.systemBackground).opacity(0), location: 0.0),
                .init(color: Color(.systemBackground).opacity(0.45), location: 0.34),
                .init(color: Color(.systemBackground).opacity(0.82), location: 0.7),
                .init(color: Color(.systemBackground), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}
#Preview {
    ContentView()
        .modelContainer(for: SpokeTask.self, inMemory: true)
}

