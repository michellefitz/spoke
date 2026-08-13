import SwiftUI
import SwiftData
import Network
import WidgetKit
import EventKit

// MARK: - Network monitor

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}

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

// Users who had the removed "group by tag" mode stored fall back to the
// AppStorage default (date added) automatically.
private enum SortMode: String {
    case dateAdded  = "dateAdded"
    case dueDate    = "dueDate"
}

// MARK: - Assistant sheet state

private enum AssistantSheet {
    case summary(remark: String?, actions: [ParsedAction], transcript: String)
    case clarify(question: AssistantQuestion, transcript: String)
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
    if task.deadlineIsWeek {
        // Week-bucket task: compare weeks, never days
        let thisWeek = cal.weekStart(for: .now)
        let week = cal.weekStart(for: deadline)
        if week < thisWeek { return .overdue }
        if week == thisWeek { return .thisWeek }
        if let next = cal.date(byAdding: .weekOfYear, value: 1, to: thisWeek), week == next { return .nextWeek }
        return .later
    }
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
    private let network = NetworkMonitor.shared

    @State private var recorder = VoiceRecorder()
    @State private var selectedTask: SpokeTask?
    @State private var selectedEvent: DayEvent?
    @State private var listEvents: [DayEvent] = []
    @State private var showPermissionAlert = false
    @State private var selectedTag: String? = nil
    @State private var showSettings = false
    @AppStorage("calendarMode") private var calendarMode = false
    @State private var calendarWeekOffset = 0
    // completedExpanded is persisted via settings.completedExpanded
    @State private var toastMessage: String?
    @State private var coachingActive = false
    @State private var recordingTimer: Task<Void, Never>?
    @State private var assistantSheet: AssistantSheet? = nil
    @State private var undoableDiscard: AssistantSheet? = nil
    @State private var undoDiscardToken = UUID()
    private let tagStore = TagStore.shared

    private var hasTasks: Bool { !activeTasks.isEmpty || !completedTasks.isEmpty }
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let bottomBarHeight: CGFloat = 132

    private var availableTags: [String] {
        tagStore.tags
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

    // Group active tasks by deadline bucket, sorted by deadline within each
    // bucket. Calendar events slot into the same buckets ahead of the tasks —
    // matching the week view's events-first ordering — but only in the
    // unfiltered list, since events carry no tags.
    private var deadlineGroupedActiveTasks: [(DeadlineBucket, [DayEvent], [SpokeTask])] {
        let events = selectedTag == nil ? listEvents : []
        return DeadlineBucket.allCases.compactMap { b in
            let bucketEvents = events.filter { eventDeadlineBucket($0) == b }
            let tasks = filteredActiveTasks
                .filter { deadlineBucket(for: $0) == b }
                .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            return (bucketEvents.isEmpty && tasks.isEmpty) ? nil : (b, bucketEvents, tasks)
        }
    }

    /// The list only looks forward: events that already ended are dropped,
    /// everything else buckets by start day like a task's deadline.
    private func eventDeadlineBucket(_ event: DayEvent) -> DeadlineBucket? {
        guard event.end > .now else { return nil }
        let cal = Calendar.current
        let start = max(event.start, cal.startOfDay(for: .now))
        if cal.isDateInToday(start)    { return .today }
        if cal.isDateInTomorrow(start) { return .tomorrow }
        if cal.isDate(start, equalTo: .now, toGranularity: .weekOfYear) { return .thisWeek }
        if let nextWeek = cal.date(byAdding: .weekOfYear, value: 1, to: .now),
           cal.isDate(start, equalTo: nextWeek, toGranularity: .weekOfYear) {
            return .nextWeek
        }
        return .later
    }

    private func loadListEvents() {
        guard settings.showCalendarEvents, CalendarService.shared.isConnected else {
            listEvents = []
            return
        }
        let cal = Calendar.current
        let from = cal.startOfDay(for: .now)
        guard let to = cal.date(byAdding: .day, value: 60, to: from) else { return }
        listEvents = CalendarService.shared.events(from: from, to: to).sorted { $0.start < $1.start }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if calendarMode {
                    WeekCalendarView(weekOffset: $calendarWeekOffset)
                } else {
                    taskListView
                }
            }
                .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    // Wordmark + settings
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { calendarMode.toggle() }
                        } label: {
                            Image(systemName: calendarMode ? "list.bullet" : "calendar")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(coral)
                                .frame(width: 28, height: 28)
                                .background(Color(.tertiarySystemFill), in: Circle())
                        }
                        .frame(width: 44, height: 44)

                        Group {
                            if calendarMode {
                                // Week navigation takes the wordmark's slot
                                HStack(spacing: 2) {
                                    Button {
                                        withAnimation(.spokeTransition) { calendarWeekOffset -= 1 }
                                    } label: {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(coral)
                                            .frame(width: 32, height: 32)
                                    }

                                    Button {
                                        withAnimation(.spokeTransition) { calendarWeekOffset = 0 }
                                    } label: {
                                        Text(WeekCalendarView.title(forWeekOffset: calendarWeekOffset))
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        withAnimation(.spokeTransition) { calendarWeekOffset += 1 }
                                    } label: {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(coral)
                                            .frame(width: 32, height: 32)
                                    }
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Text("spoke")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Circle()
                                        .fill(coral)
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Menu {
                            // Sort options only apply to the list view
                            if !calendarMode {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { sortMode = .dateAdded }
                                } label: {
                                    Label("Sort by date added", systemImage: sortMode == .dateAdded ? "checkmark" : "")
                                }

                                if settings.showDueDates {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) { sortMode = .dueDate }
                                    } label: {
                                        Label("Sort by due date", systemImage: sortMode == .dueDate ? "checkmark" : "")
                                    }
                                }

                                Divider()
                            }

                            Button { showSettings = true } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(coral)
                                .frame(width: 28, height: 28)
                                .background(Color(.tertiarySystemFill), in: Circle())
                        }
                        .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    if hasTasks && settings.showTags && !calendarMode {
                        filterPillsView
                            .padding(.bottom, 0)
                    }
                }
                .background(.background)
            }
                .safeAreaPadding(.bottom, bottomBarHeight)

            if assistantSheet != nil {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { discardAssistantSheet() }
                    .transition(.opacity)
            }

            if let sheetMode = assistantSheetMode {
                AssistantSheetView(
                    mode: sheetMode,
                    bottomInset: bottomBarHeight,
                    onConfirm: confirmAssistant,
                    onAdjust: startRecordingFlow,
                    onOption: answerClarify,
                    onClose: discardAssistantSheet
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            bottomVoiceBar

            // Offline toast (persistent, near mic)
            if !network.isConnected {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12, weight: .semibold))
                        Text("No connection. Tasks can't be processed.")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(white: 0.15).opacity(0.9)))
                    .padding(.bottom, bottomBarHeight + 8)
                }
                .allowsHitTesting(false)
            }

            // Discard toast with undo — interactive, unlike the info toasts
            if undoableDiscard != nil {
                VStack {
                    Spacer()
                    Button(action: undoDiscard) {
                        HStack(spacing: 10) {
                            Text("Discarded")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                            Text("Undo")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.45))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color(white: 0.15).opacity(0.95)))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, bottomBarHeight + 8)
                }
            }

            // Toast for multi-task creation
            if let message = toastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color(white: 0.15).opacity(0.9)))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, bottomBarHeight + 8)
                }
                .allowsHitTesting(false)
            }
        }
        .sheet(item: $selectedTask, onDismiss: {
            if coachingActive {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    withAnimation(.spokeTransition) {
                        toastMessage = "You're all set ✓"
                    }
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation(.easeOut(duration: 0.18)) {
                        toastMessage = nil
                    }
                    coachingActive = false
                    settings.hasSeenCoaching = true
                }
            }
        }) { task in
            TaskDetailView(task: task, showCoachingToast: coachingActive)
                .presentationDetents([.fraction(0.7), .large])
                .presentationBackground(Color(.systemBackground))
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
                .presentationDetents([.fraction(0.7), .large])
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
        .task(id: sortMode) { loadListEvents() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in loadListEvents() }
        .onChange(of: settings.showCalendarEvents) { loadListEvents() }
        .onChange(of: settings.hiddenCalendarIDs) { loadListEvents() }
        .task {
            // Coaching: show first toast once after onboarding
            guard !settings.hasSeenCoaching && !activeTasks.isEmpty else { return }
            coachingActive = true
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.spokeTransition) {
                toastMessage = "Nice! Tap a task to see more."
            }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.18)) {
                if toastMessage == "Nice! Tap a task to see more." { toastMessage = nil }
            }
        }
        .onChange(of: selectedTask) { _, task in
            if task != nil && coachingActive {
                withAnimation(.easeOut(duration: 0.2)) { toastMessage = nil }
            }
        }
        .onChange(of: settings.showDueDates) { _, show in
            if !show && sortMode == .dueDate { sortMode = .dateAdded }
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
            if phase != .active, recorder.recordingState == .recording {
                // The audio background mode keeps the microphone live, so
                // glancing at another app mid-braindump no longer loses
                // what comes after it. Just note it for the log.
                recorder.noteBackgrounded()
            }
            if phase == .background {
                try? modelContext.save()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    // MARK: - Filter pills

    private var taskListView: some View {
        Group {
            if activeTasks.isEmpty && completedTasks.isEmpty {
                emptyStateView
            } else if selectedTag != nil && filteredActiveTasks.isEmpty && filteredCompletedTasks.isEmpty {
                filteredEmptyStateView
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
                    } else if sortMode == .dueDate {
                        ForEach(deadlineGroupedActiveTasks, id: \.0.rawValue) { (b, events, tasks) in
                            Section {
                                ForEach(events) { event in
                                    listEventRow(event)
                                }
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
                            if settings.completedExpanded {
                                ForEach(filteredCompletedTasks) { task in
                                    TaskRowView(
                                        task: task,
                                        onToggleComplete: { toggleComplete(task) },
                                        onDelete: { deleteTask(task) },
                                        onTap: { selectedTask = task }
                                    )
                                }
                            }
                        } header: {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    settings.completedExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Completed")
                                        .font(.caption)
                                        .foregroundStyle(Color(.label).opacity(0.6))
                                    Text("\(filteredCompletedTasks.count)")
                                        .font(.caption)
                                        .foregroundStyle(Color(.label).opacity(0.35))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color(.secondaryLabel))
                                        .rotationEffect(.degrees(settings.completedExpanded ? 90 : 0))
                                }
                            }
                            .buttonStyle(.plain)
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

            Text("Say something. We'll handle the rest.")
                .font(.subheadline)
                .foregroundStyle(Color(.systemGray2))
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    private var filteredEmptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray4).opacity(0.3))
                        .frame(width: 110, height: 8)
                }
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray4).opacity(0.3))
                        .frame(width: 80, height: 8)
                }
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray4).opacity(0.3))
                        .frame(width: 100, height: 8)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(.systemGray4).opacity(0.3), lineWidth: 1)
            )

            Text("Nothing here yet. Speak to add one.")
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
                        filterPill(label: "ALL", tag: nil)
                        ForEach(availableTags, id: \.self) { tag in
                            filterPill(label: tag.uppercased(), tag: tag)
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

        }
    }

    private func filterPill(label: String, tag: String?) -> some View {
        let isActive = selectedTag == tag
        return Button {
            withAnimation(.spokeFeedback) {
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

    // MARK: - List event row

    /// A calendar appointment in the day-sorted list, styled like the week
    /// view's blocks: colored spine, tinted background, no checkbox.
    private func listEventRow(_ event: DayEvent) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text(listEventTimeLabel(event))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 10).fill(event.color.opacity(0.09)))
        .contentShape(Rectangle())
        .onTapGesture { selectedEvent = event }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
    }

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func listEventTimeLabel(_ event: DayEvent) -> String {
        let cal = Calendar.current
        let dayPrefix: String
        if cal.isDateInToday(event.start) || cal.isDateInTomorrow(event.start) {
            dayPrefix = ""
        } else {
            let df = DateFormatter()
            df.dateFormat = "EEE d MMM"
            dayPrefix = df.string(from: event.start) + ", "
        }
        if event.isAllDay { return dayPrefix.isEmpty ? "All day" : dayPrefix + "all day" }
        let times = "\(Self.eventTimeFormatter.string(from: event.start)) – \(Self.eventTimeFormatter.string(from: event.end))"
        return dayPrefix + times
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

    // MARK: - Assistant sheet

    private var assistantSheetMode: AssistantSheetView.Mode? {
        switch assistantSheet {
        case .summary(let remark, let actions, _):
            return .summary(remark: remark, actions: actions)
        case .clarify(let question, _):
            return .clarify(text: question.text, options: question.options)
        case nil:
            return nil
        }
    }

    private func confirmAssistant() {
        guard case .summary(_, let actions, _) = assistantSheet else { return }
        // The mic may still be live (the orb stays on while the sheet is up);
        // tear the recording down properly or its tap outlives the sheet.
        recordingTimer?.cancel()
        recorder.cancelRecording()
        withAnimation(.spokeTransition) { assistantSheet = nil }
        Task { await applyActions(actions) }
    }

    private func answerClarify(_ answer: String) {
        guard case .clarify(let question, let transcript) = assistantSheet else { return }
        withAnimation(.spokeTransition) { assistantSheet = nil }
        recordingTimer?.cancel()
        recorder.cancelRecording()
        Task {
            let existingContext = activeTasks.map { t in
                (title: t.title, description: t.taskDescription, deadline: t.deadline, tag: t.tag, deadlineIsWeek: t.deadlineIsWeek)
            }
            guard let actions = await TaskParser.resolveClarification(
                transcript: transcript, question: question.text, answer: answer, existingTasks: existingContext
            ) else {
                recorder.finishProcessing()
                showToast("Something went wrong. Give it another go.")
                return
            }
            if actions.isEmpty {
                recorder.finishProcessing()
                showToast("Okay, left it as is")
            } else {
                await applyActions(actions)
            }
        }
    }

    /// Dismisses the assistant sheet without applying, keeping the pending
    /// response recoverable via the "Discarded — Undo" toast for a few seconds.
    private func discardAssistantSheet() {
        guard let sheet = assistantSheet else { return }
        recordingTimer?.cancel()
        recorder.cancelRecording()
        recorder.finishProcessing()
        let token = UUID()
        undoDiscardToken = token
        withAnimation(.spokeTransition) {
            assistantSheet = nil
            undoableDiscard = sheet
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard undoDiscardToken == token else { return }
            withAnimation(.easeOut(duration: 0.18)) { undoableDiscard = nil }
        }
    }

    private func undoDiscard() {
        guard let sheet = undoableDiscard else { return }
        undoDiscardToken = UUID()
        withAnimation(.spokeTransition) {
            undoableDiscard = nil
            assistantSheet = sheet
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
            startRecordingFlow()
        case .recording:
            recordingTimer?.cancel()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            stopAndProcess()
        case .processing:
            break
        }
    }

    private func startRecordingFlow() {
        guard recorder.recordingState == .idle else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            let granted = await recorder.requestPermissionsIfNeeded()
            guard granted else {
                showPermissionAlert = true
                return
            }
            do {
                try recorder.startRecording()
                startRecordingTimer()
            } catch {
                recorder.finishProcessing()
            }
        }
    }

    private func startRecordingTimer() {
        recordingTimer?.cancel()
        recordingTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            guard recorder.recordingState == .recording else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            stopAndProcess()
            withAnimation(.spokeTransition) {
                toastMessage = "Recording stopped — 1 minute max."
            }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.18)) {
                if toastMessage == "Recording stopped — 1 minute max." { toastMessage = nil }
            }
        }
    }

    private func stopAndProcess() {
        let transcript = recorder.stopRecording()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recorder.finishProcessing()
            return
        }
        Task {
            let existingContext = activeTasks.map { t in
                (title: t.title, description: t.taskDescription, deadline: t.deadline, tag: t.tag, deadlineIsWeek: t.deadlineIsWeek)
            }
            let eventContext = upcomingEventContext()
            switch assistantSheet {
            case .clarify(let question, let originalTranscript):
                // The speech is an answer to the open question
                withAnimation(.spokeTransition) { assistantSheet = nil }
                guard let actions = await TaskParser.resolveClarification(
                    transcript: originalTranscript, question: question.text, answer: transcript, existingTasks: existingContext, existingEvents: eventContext
                ) else {
                    recorder.finishProcessing()
                    showToast("Something went wrong. Give it another go.")
                    return
                }
                if actions.isEmpty {
                    recorder.finishProcessing()
                    showToast("Okay, left it as is")
                } else if actions.contains(where: \.isEvent) {
                    // Calendar events always get a confirmation pass
                    recorder.finishProcessing()
                    withAnimation(.spokeTransition) {
                        assistantSheet = .summary(remark: nil, actions: actions, transcript: originalTranscript)
                    }
                } else {
                    await applyActions(actions)
                }

            case .summary(_, let pending, let originalTranscript):
                // The speech is a follow-up on the proposed tasks
                let outcome = await TaskParser.refineActions(
                    transcript: originalTranscript, pending: pending, correction: transcript, existingTasks: existingContext, existingEvents: eventContext
                )
                switch outcome {
                case .approve:
                    withAnimation(.spokeTransition) { assistantSheet = nil }
                    await applyActions(pending)
                case .cancel:
                    withAnimation(.spokeTransition) { assistantSheet = nil }
                    recorder.finishProcessing()
                    showToast("Okay, discarded")
                case .response(let response):
                    await routeAssistantResponse(response, transcript: originalTranscript)
                }

            case nil:
                let response = await TaskParser.parseAssistant(transcript: transcript, existingTasks: existingContext, existingEvents: eventContext)
                await routeAssistantResponse(response, transcript: transcript)
            }
        }
    }

    /// The next few weeks of calendar events, so the parser can tell "move my
    /// hair appointment" refers to a calendar event rather than a task.
    private func upcomingEventContext() -> [DayEvent] {
        let service = CalendarService.shared
        guard service.isConnected else { return [] }
        let cal = Calendar.current
        let from = cal.startOfDay(for: .now)
        guard let to = cal.date(byAdding: .day, value: 60, to: from) else { return [] }
        return Array(service.events(from: from, to: to).sorted { $0.start < $1.start }.prefix(40))
    }

    /// Decides which tier a response lands in: clarify sheet, summary sheet,
    /// or silent apply with a toast.
    @MainActor
    private func routeAssistantResponse(_ response: AssistantResponse, transcript: String) async {
        if let question = response.question {
            recorder.finishProcessing()
            withAnimation(.spokeTransition) {
                assistantSheet = .clarify(question: question, transcript: transcript)
            }
            return
        }
        guard !response.actions.isEmpty else {
            recorder.finishProcessing()
            withAnimation(.spokeTransition) { assistantSheet = nil }
            // Never echo a remark describing a change that didn't happen.
            showToast(response.droppedActions
                      ? "Couldn't make that change. Give it another go."
                      : (response.remark ?? "Something went wrong. Give it another go."))
            return
        }
        if response.actions.count == 1 && !response.actions.contains(where: \.isEvent) {
            // Small change: just do it. The remark, if any, becomes the toast.
            // Calendar events never take this path — writing to the user's
            // calendar always needs explicit confirmation.
            withAnimation(.spokeTransition) { assistantSheet = nil }
            await applyActions(response.actions, remarkToast: response.remark)
        } else {
            recorder.finishProcessing()
            withAnimation(.spokeTransition) {
                assistantSheet = .summary(remark: response.remark, actions: response.actions, transcript: transcript)
            }
        }
    }

    @MainActor
    private func applyActions(_ actions: [ParsedAction], remarkToast: String? = nil) async {
        var createdCount = 0
        var editedTitles: [String] = []
        var eventCount = 0
        var eventEditCount = 0
        var eventEditsFailed = false
        var eventsFellBackToTasks = false

        // Events need calendar access, which may involve an async permission
        // prompt — sort that out before the synchronous animation block.
        let eventActions = actions.compactMap { action -> ParsedEvent? in
            if case .createEvent(let event) = action { return event }
            return nil
        }
        var failedEvents: [ParsedEvent] = []
        if !eventActions.isEmpty {
            let calendarService = CalendarService.shared
            if calendarService.canRequestAccess {
                await calendarService.requestAccess()
            }
            if calendarService.isConnected {
                for event in eventActions {
                    if calendarService.createEvent(event) {
                        eventCount += 1
                    } else {
                        failedEvents.append(event)
                    }
                }
            } else {
                failedEvents = eventActions
            }
            eventsFellBackToTasks = !failedEvents.isEmpty
        }
        for action in actions {
            if case .editEvent(let original, let updates) = action {
                let saved = CalendarService.shared.updateEvent(
                    original,
                    title: updates.title,
                    start: updates.start,
                    end: updates.end,
                    isAllDay: updates.isAllDay,
                    location: updates.location,
                    notes: original.notes
                )
                if saved { eventEditCount += 1 } else { eventEditsFailed = true }
            }
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            for action in actions {
                switch action {
                case .create(let parsed):
                    let task = SpokeTask(title: parsed.title, taskDescription: parsed.description, deadline: parsed.deadline, tag: parsed.tag, deadlineIsWeek: parsed.deadlineIsWeek)
                    modelContext.insert(task)
                    createdCount += 1

                case .edit(let matchTitle, let updates):
                    if let existing = activeTasks.first(where: { $0.title == matchTitle }) {
                        existing.title = updates.title
                        existing.taskDescription = updates.description
                        existing.deadline = updates.deadline
                        existing.deadlineIsWeek = updates.deadlineIsWeek
                        existing.tag = updates.tag
                        editedTitles.append(updates.title)
                    } else {
                        // Fallback: create if match not found
                        let task = SpokeTask(title: updates.title, taskDescription: updates.description, deadline: updates.deadline, tag: updates.tag, deadlineIsWeek: updates.deadlineIsWeek)
                        modelContext.insert(task)
                        createdCount += 1
                    }

                case .createEvent, .editEvent:
                    break // handled above
                }
            }
            // Anything that couldn't reach the calendar lands as a dated task
            // instead of vanishing.
            for event in failedEvents {
                let task = SpokeTask(title: event.title, taskDescription: event.location, deadline: event.start)
                modelContext.insert(task)
                createdCount += 1
            }
        }
        recorder.finishProcessing()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()

        guard !coachingActive else { return }
        let message: String?
        if eventsFellBackToTasks {
            message = "No calendar access — added as a task instead"
        } else if eventEditsFailed {
            message = "Couldn't update the calendar event. Give it another go."
        } else if eventEditCount > 0 && eventCount == 0 && createdCount == 0 && editedTitles.isEmpty {
            message = eventEditCount == 1 ? "Calendar event updated" : "\(eventEditCount) calendar events updated"
        } else if eventCount > 0 && createdCount == 0 && editedTitles.isEmpty && eventEditCount == 0 {
            message = eventCount == 1 ? "Added to your calendar" : "\(eventCount) events added to your calendar"
        } else if eventCount > 0 || eventEditCount > 0 {
            message = "Done — including \(eventCount + eventEditCount) calendar change\(eventCount + eventEditCount == 1 ? "" : "s")"
        } else if let remarkToast {
            message = remarkToast
        } else if !editedTitles.isEmpty && createdCount > 0 {
            message = "Updated \(editedTitles.count) task\(editedTitles.count == 1 ? "" : "s"), added \(createdCount)"
        } else if !editedTitles.isEmpty {
            if editedTitles.count == 1 {
                let short = String(editedTitles[0].prefix(30))
                message = "Updated \"\(short)\""
            } else {
                message = "Updated \(editedTitles.count) tasks"
            }
        } else if createdCount > 1 {
            message = "\(createdCount) tasks added"
        } else {
            message = nil
        }
        if let message { showToast(message) }
    }

    private func showToast(_ message: String, duration: Double = 2.5) {
        Task { @MainActor in
            withAnimation(.spokeTransition) { toastMessage = message }
            try? await Task.sleep(for: .seconds(duration))
            withAnimation(.easeOut(duration: 0.18)) {
                if toastMessage == message { toastMessage = nil }
            }
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
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func deleteTask(_ task: SpokeTask) {
        modelContext.delete(task)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Prune

    private func pruneCompletedTasks() {
        // Auto-complete sample task after 7 days
        let expiry = UserDefaults.standard.double(forKey: "sampleTaskExpiry")
        if expiry > 0 && Date.now.timeIntervalSince1970 > expiry {
            if let sample = activeTasks.first(where: { $0.title == "Welcome to Spoke" }) {
                sample.isCompleted = true
                sample.completedAt = .now
            }
            UserDefaults.standard.removeObject(forKey: "sampleTaskExpiry")
        }

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

