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

    @AppStorage("hasUsedVoice") private var hasUsedVoice = false

    @State private var recorder = VoiceRecorder()
    @State private var selectedTask: SpokeTask?
    @State private var showPermissionAlert = false
    @State private var tapModeActive = false
    @State private var selectedTag: String? = nil
    @State private var showSettings = false
    private let tagStore = TagStore.shared

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
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Circle()
                                .fill(coral)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)

                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(coral)
                        }
                        .frame(width: 44)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
                    .padding(.bottom, availableTags.isEmpty ? 4 : 8)

                    if !availableTags.isEmpty {
                        filterPillsView
                            .padding(.bottom, 6)
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
        List {
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
                    sectionHeader(b.rawValue)
                }
            }

            if !filteredCompletedTasks.isEmpty {
                Section {
                    ForEach(filteredCompletedTasks) { task in
                        TaskRowView(
                            task: task,
                            onToggleComplete: { toggleComplete(task) },
                            onDelete: {},
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

    private var bottomVoiceBar: some View {
        VStack(spacing: 4) {
            VoiceButton(
                state: voiceButtonState,
                audioLevel: recorder.audioLevel,
                onStart: handleStart,
                onRelease: handleRelease
            )
            .frame(maxWidth: .infinity, minHeight: 96)

            if recorder.recordingState == .idle && !hasUsedVoice {
                Text("Tap or hold to speak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(label: "All", tag: nil)
                ForEach(availableTags, id: \.self) { tag in
                    filterPill(label: tag.capitalized, tag: tag)
                }
            }
            .padding(.horizontal, 16)
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
            .foregroundStyle(.secondary)
    }

    // MARK: - Voice button state

    private var voiceButtonState: VoiceButtonState {
        switch recorder.recordingState {
        case .idle:       .idle
        case .recording:  .recording
        case .processing: .processing
        }
    }

    // MARK: - Voice gesture handlers

    /// Called on every press-down. Starts recording only if currently idle.
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

    /// Called on every release. Elapsed < 0.3 s = tap; ≥ 0.3 s = hold release.
    private func handleRelease(elapsed: TimeInterval) {
        switch recorder.recordingState {
        case .recording:
            if tapModeActive {
                // Second tap → stop
                tapModeActive = false
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                stopAndProcess()
            } else if elapsed < 0.3 {
                // Quick tap started recording → stay recording, wait for second tap
                tapModeActive = true
            } else {
                // Hold release → stop immediately
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
            let parsed = await TaskParser.parse(transcript: transcript)
            let task = SpokeTask(title: parsed.title, taskDescription: parsed.description, deadline: parsed.deadline, tag: parsed.tag)
            modelContext.insert(task)
            recorder.finishProcessing()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            hasUsedVoice = true
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
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
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
