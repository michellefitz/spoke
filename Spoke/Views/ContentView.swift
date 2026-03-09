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
        sort: [SortDescriptor(\SpokeTask.createdAt, order: .reverse)]
    )
    private var completedTasks: [SpokeTask]

    @State private var recorder = VoiceRecorder()
    @State private var selectedTask: SpokeTask?
    @State private var showPermissionAlert = false
    @State private var tapModeActive = false

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    // Group active tasks by time bucket, dropping empty buckets
    private var groupedActiveTasks: [(TaskBucket, [SpokeTask])] {
        TaskBucket.allCases.compactMap { b in
            let tasks = activeTasks.filter { bucket(for: $0) == b }
            return tasks.isEmpty ? nil : (b, tasks)
        }
    }

    var body: some View {
        ZStack {
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

                if !completedTasks.isEmpty {
                    Section {
                        ForEach(completedTasks) { task in
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
            .safeAreaInset(edge: .top) {
                // Wordmark
                HStack(spacing: 4) {
                    Text("spoke")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Circle()
                        .fill(coral)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .safeAreaInset(edge: .bottom) {
                VoiceButton(
                    state: voiceButtonState,
                    onStart: handleStart,
                    onRelease: handleRelease
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
                .background(.clear)
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
                .presentationDetents([.medium, .large])
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pruneCompletedTasks() }
        }
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
            let task = SpokeTask(title: parsed.title, taskDescription: parsed.description)
            modelContext.insert(task)
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
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let predicate = #Predicate<SpokeTask> {
            $0.isCompleted == true
            && $0.completedAt != nil
            && $0.completedAt! < cutoff
        }
        try? modelContext.delete(model: SpokeTask.self, where: predicate)
    }
}
