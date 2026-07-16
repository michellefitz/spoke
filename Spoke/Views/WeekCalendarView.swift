import SwiftUI
import SwiftData
import WidgetKit
import EventKit

/// Weekly planning view styled like a calendar schedule: a prominent date
/// column on the left, tasks indented to the right, a hairline between days,
/// and today badged with a filled circle. The week-bucket pool ("any day")
/// sits pinned above the days.
struct WeekCalendarView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<SpokeTask> { $0.isCompleted == false },
        sort: [SortDescriptor(\SpokeTask.deadline)]
    )
    private var activeTasks: [SpokeTask]

    @Query(
        filter: #Predicate<SpokeTask> { $0.isCompleted == true },
        sort: [SortDescriptor(\SpokeTask.completedAt, order: .reverse)]
    )
    private var allCompletedTasks: [SpokeTask]

    /// Owned by ContentView so the app header can drive week paging.
    @Binding var weekOffset: Int
    @Environment(\.openURL) private var openURL
    @State private var selectedTask: SpokeTask?
    @State private var undatedExpanded = false
    @State private var weekEvents: [DayEvent] = []
    @AppStorage("calUndatedCollapsed") private var undatedCollapsed = false
    @AppStorage("calPoolCollapsed") private var poolCollapsed = false

    private let undatedCap = 3
    private let settings = AppSettings.shared
    private let calendarService = CalendarService.shared

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let dateColumnWidth: CGFloat = 52
    private var cal: Calendar { Calendar.current }

    private var weekStart: Date {
        let base = cal.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
        return cal.weekStart(for: base)
    }

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var poolTasks: [SpokeTask] {
        activeTasks.filter { task in
            guard let deadline = task.deadline, task.deadlineIsWeek else { return false }
            return cal.weekStart(for: deadline) == weekStart
        }
    }

    /// Undated tasks are timeless, so they surface at the top of every week.
    private var undatedTasks: [SpokeTask] {
        guard settings.showUndatedInCalendar else { return [] }
        return activeTasks
            .filter { $0.deadline == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func tasks(on day: Date) -> [SpokeTask] {
        activeTasks.filter { task in
            guard let deadline = task.deadline, !task.deadlineIsWeek else { return false }
            return cal.isDate(deadline, inSameDayAs: day)
        }
    }

    /// Calendar appointments overlapping this day: all-day first, then by
    /// start time. Multi-day events appear on every day they touch.
    private func events(on day: Date) -> [DayEvent] {
        guard settings.showCalendarEvents else { return [] }
        let dayStart = cal.startOfDay(for: day)
        return weekEvents
            .filter { $0.start >= dayStart ? cal.isDate($0.start, inSameDayAs: day) : $0.end > dayStart }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                if a.start != b.start { return a.start < b.start }
                return a.title < b.title
            }
    }

    private func loadEvents() {
        guard calendarService.isConnected else {
            weekEvents = []
            return
        }
        let end = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        weekEvents = calendarService.events(from: weekStart, to: end)
    }

    private var showConnectCard: Bool {
        calendarService.canRequestAccess && !settings.calendarPromptDismissed
    }

    private func isPast(_ day: Date) -> Bool {
        day < cal.startOfDay(for: .now) && !cal.isDateInToday(day)
    }

    /// In the current week, land with today at the top — past days stay one
    /// scroll up, faded. Other weeks (and Mondays) open from the top.
    private func scrollToToday(_ proxy: ScrollViewProxy) {
        guard weekOffset == 0,
              let index = days.firstIndex(where: { cal.isDateInToday($0) }),
              index > 0 else { return }
        proxy.scrollTo("day-\(index)", anchor: .top)
    }

    /// Tasks completed on this day — shown after the active ones so the day
    /// reads as "still to do, then what got done".
    private func completedTasks(on day: Date) -> [SpokeTask] {
        guard settings.showCompletedInCalendar else { return [] }
        return allCompletedTasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return cal.isDate(completedAt, inSameDayAs: day)
        }
    }

    /// Title for a week offset — used by ContentView's header in calendar mode.
    static func title(forWeekOffset offset: Int) -> String {
        switch offset {
        case 0: return "This Week"
        case 1: return "Next Week"
        default:
            let cal = Calendar.current
            let base = cal.date(byAdding: .weekOfYear, value: offset, to: .now) ?? .now
            let start = cal.weekStart(for: base)
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
    }

    private var weekIsEmpty: Bool {
        undatedTasks.isEmpty && poolTasks.isEmpty
            && days.allSatisfy { tasks(on: $0).isEmpty && completedTasks(on: $0).isEmpty && events(on: $0).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            if weekIsEmpty {
                if showConnectCard {
                    connectCard
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }
                emptyState
            } else {
                ScrollViewReader { proxy in
                List {
                    if showConnectCard {
                        connectCard
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
                    }

                    if !undatedTasks.isEmpty {
                        if undatedCollapsed {
                            collapsedSectionRow(count: undatedTasks.count, label: { undatedColumn }) {
                                withAnimation(.spokeTransition) { undatedCollapsed = false }
                            }
                        } else {
                            let visible = undatedExpanded ? undatedTasks : Array(undatedTasks.prefix(undatedCap))
                            let hiddenCount = undatedTasks.count - visible.count
                            scheduleRows(tasks: visible, emptyText: nil) {
                                Button {
                                    withAnimation(.spokeTransition) { undatedCollapsed = true }
                                } label: { undatedColumn }
                                    .buttonStyle(.plain)
                            }
                            if hiddenCount > 0 {
                                previewToggleRow("View \(hiddenCount) more") {
                                    withAnimation(.spokeTransition) { undatedExpanded = true }
                                }
                            } else if undatedExpanded && undatedTasks.count > undatedCap {
                                previewToggleRow("Show fewer") {
                                    withAnimation(.spokeTransition) { undatedExpanded = false }
                                }
                            }
                        }
                        dayDivider
                    }

                    if !poolTasks.isEmpty {
                        if poolCollapsed {
                            collapsedSectionRow(count: poolTasks.count, label: { poolColumn }) {
                                withAnimation(.spokeTransition) { poolCollapsed = false }
                            }
                        } else {
                            scheduleRows(tasks: poolTasks, emptyText: nil) {
                                Button {
                                    withAnimation(.spokeTransition) { poolCollapsed = true }
                                } label: { poolColumn }
                                    .buttonStyle(.plain)
                            }
                        }
                        dayDivider
                    }

                    // Divider above each day (not after) so it can carry the
                    // day's scroll anchor for the open-at-today jump.
                    ForEach(Array(days.enumerated()), id: \.element.timeIntervalSinceReferenceDate) { index, day in
                        if index > 0 {
                            dayDivider.id("day-\(index)")
                        }
                        scheduleRows(events: events(on: day), eventsDay: day, tasks: tasks(on: day) + completedTasks(on: day), emptyText: "Nothing planned", dimmed: isPast(day)) { dateColumn(day) }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 10)
                .task(id: weekOffset) {
                    // Let the rows lay out before jumping.
                    try? await Task.sleep(for: .milliseconds(80))
                    scrollToToday(proxy)
                }
                }
            }
        }
        .task(id: weekOffset) { loadEvents() }
        .onChange(of: calendarService.isConnected) { loadEvents() }
        .onChange(of: settings.hiddenCalendarIDs) { loadEvents() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in loadEvents() }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task, showCoachingToast: false)
                .presentationDetents([.fraction(0.7), .large])
                .presentationBackground(Color(.systemBackground))
        }
    }

    // MARK: - Schedule rows

    /// Renders one day (or the pool) as schedule rows: the label column is
    /// visible on the first row only, so tasks stack beside a single date.
    /// Calendar appointments render first, then tasks.
    @ViewBuilder
    private func scheduleRows<Label: View>(events: [DayEvent] = [], eventsDay: Date = .distantPast, tasks: [SpokeTask], emptyText: String?, dimmed: Bool = false, @ViewBuilder label: @escaping () -> Label) -> some View {
        if events.isEmpty && tasks.isEmpty {
            if let emptyText {
                HStack(alignment: .center, spacing: 14) {
                    label()
                        .frame(width: dateColumnWidth)
                    Text(emptyText)
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(Color(.quaternaryLabel))
                    Spacer(minLength: 0)
                }
                .opacity(dimmed ? 0.45 : 1)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
            }
        } else {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 14) {
                    // The invisible label must not reserve its height on
                    // later rows, or every row inflates to date-column size.
                    if index == 0 {
                        label().frame(width: dateColumnWidth)
                    } else {
                        Color.clear.frame(width: dateColumnWidth, height: 1)
                    }
                    eventRow(event, on: eventsDay)
                }
                .opacity(dimmed ? 0.45 : 1)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                HStack(alignment: .top, spacing: 14) {
                    if events.isEmpty && index == 0 {
                        label().frame(width: dateColumnWidth)
                    } else {
                        Color.clear.frame(width: dateColumnWidth, height: 1)
                    }
                    TaskRowView(
                        task: task,
                        onToggleComplete: { toggleComplete(task) },
                        onDelete: { deleteTask(task) },
                        onTap: { selectedTask = task },
                        calendarStyle: true
                    )
                }
                .opacity(dimmed ? 0.45 : 1)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
        }
    }

    /// A calendar appointment: tinted block with the calendar's colour as a
    /// spine, time underneath — deliberately un-task-like (no checkbox).
    /// Tapping opens the Calendar app at the event's time.
    private func eventRow(_ event: DayEvent, on day: Date) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text(timeLabel(for: event, on: day))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(event.color.opacity(0.09)))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: "calshow:\(Int(event.start.timeIntervalSinceReferenceDate))") {
                openURL(url)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func timeLabel(for event: DayEvent, on day: Date) -> String {
        if event.isAllDay { return "All day" }
        let end = Self.timeFormatter.string(from: event.end)
        guard cal.isDate(event.start, inSameDayAs: day) else { return "Until \(end)" }
        return "\(Self.timeFormatter.string(from: event.start)) – \(end)"
    }

    /// One-time prompt to link the device calendar, shown until connected or
    /// dismissed.
    private var connectCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 22))
                .foregroundStyle(coral)
            VStack(alignment: .leading, spacing: 2) {
                Text("See your appointments here")
                    .font(.system(size: 14, weight: .semibold))
                Text("Connect your calendar and the week shows what's booked next to what needs doing.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    withAnimation(.spokeTransition) { settings.calendarPromptDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
                Button {
                    Task {
                        if await calendarService.requestAccess() { loadEvents() }
                    }
                } label: {
                    Text("Connect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(coral))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    /// Collapsed section: just the badge and a light count, tap to expand.
    private func collapsedSectionRow<Label: View>(count: Int, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                label()
                    .frame(width: dateColumnWidth)
                Text("\(count) task\(count == 1 ? "" : "s") hidden")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.tertiaryLabel))
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
    }

    private func previewToggleRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Color.clear.frame(width: dateColumnWidth, height: 1)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(coral)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16))
    }

    private var dayDivider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(height: 0.5)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
    }

    // MARK: - Date columns

    private func dateColumn(_ day: Date) -> some View {
        let isToday = cal.isDateInToday(day)
        let dayNumber = "\(cal.component(.day, from: day))"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"
        let weekday = weekdayFormatter.string(from: day).uppercased()

        return VStack(spacing: 2) {
            Text(dayNumber)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isToday ? .white : Color(.label))
                .frame(width: 30, height: 30)
                .background {
                    if isToday {
                        Circle().fill(coral)
                    }
                }
            Text(weekday)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(isToday ? coral : Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
    }

    private var poolColumn: some View {
        VStack(spacing: 2) {
            Image(systemName: "tray")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(coral)
                .frame(width: 30, height: 30)
                .background(Circle().fill(coral.opacity(0.12)))
            Text("ANY DAY")
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(coral)
        }
        .frame(maxWidth: .infinity)
    }

    private var undatedColumn: some View {
        VStack(spacing: 2) {
            Image(systemName: "infinity")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(.secondaryLabel))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(.tertiarySystemFill)))
            Text("NO DATE")
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 28))
                .foregroundStyle(Color(.systemGray3))
            Text(weekOffset == 0 ? "Nothing scheduled this week." : "Nothing scheduled.")
                .font(.subheadline)
                .foregroundStyle(Color(.systemGray2))
            Text("Say \u{201C}I need to sort the boiler this week\u{201D} and it'll land here.")
                .font(.footnote)
                .foregroundStyle(Color(.systemGray3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func toggleComplete(_ task: SpokeTask) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            if task.isCompleted {
                task.isCompleted = false
                task.completedAt = nil
            } else {
                task.isCompleted = true
                task.completedAt = .now
            }
        }
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func deleteTask(_ task: SpokeTask) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            modelContext.delete(task)
        }
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    WeekCalendarView(weekOffset: .constant(0))
        .modelContainer(for: SpokeTask.self, inMemory: true)
}
