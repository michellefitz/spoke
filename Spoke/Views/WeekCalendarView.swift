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
    @State private var selectedEvent: DayEvent?
    @State private var timelineDay: TimelineDaySelection?
    @State private var undatedExpanded = false
    // Starts at the cap and shrinks once content is measured, so the pinned
    // header hugs its rows instead of claiming the whole allowance.
    @State private var pinnedContentHeight: CGFloat = .infinity
    @State private var weekEvents: [DayEvent] = []
    @AppStorage("calPinnedCollapsed") private var pinnedCollapsed = false

    private let undatedCap = 3
    private let settings = AppSettings.shared
    private let calendarService = CalendarService.shared

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let dateColumnWidth: CGFloat = 52
    /// Matches the compact date label (24pt badge + caption), so the label
    /// never makes a day's first row taller than the rest.
    private let scheduleRowMinHeight: CGFloat = 36
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

    /// The merged pinned pool: week-bucket tasks first (they're commitments
    /// for this week), then undated ones. One section — the no-date/any-day
    /// distinction matters to the parser, not to planning.
    private var pinnedTasks: [SpokeTask] {
        poolTasks + undatedTasks
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
        // Disconnecting in Settings should stop Spoke reading the calendar
        // at all, not just stop it drawing what it read.
        guard calendarService.isConnected, settings.showCalendarEvents else {
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

    /// A completed task belongs to the day it was DUE, not the day it was
    /// ticked off — catching up on yesterday's list shouldn't make today look
    /// productive. Tasks with no specific day fall back to when they were
    /// completed, the only date they have.
    private func completedAnchor(_ task: SpokeTask) -> Date? {
        if let deadline = task.deadline, !task.deadlineIsWeek { return deadline }
        return task.completedAt
    }

    /// Tasks belonging to this day that got done — shown after the active
    /// ones so the day reads as "still to do, then what got done".
    private func completedTasks(on day: Date) -> [SpokeTask] {
        guard settings.showCompletedInCalendar else { return [] }
        return allCompletedTasks.filter { task in
            guard let anchor = completedAnchor(task) else { return false }
            return cal.isDate(anchor, inSameDayAs: day)
        }
    }

    /// Unfiltered count, so a day where everything got done can say "All done"
    /// even when completed tasks are hidden from the calendar.
    private func completedCount(on day: Date) -> Int {
        allCompletedTasks.count { task in
            guard let anchor = completedAnchor(task) else { return false }
            return cal.isDate(anchor, inSameDayAs: day)
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
        GeometryReader { geo in
            VStack(spacing: 0) {
                if weekIsEmpty {
                    if showConnectCard {
                        connectCard
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }
                    emptyState
                } else {
                    // "Any day" and "no date" apply to the whole week, so they
                    // stay pinned while the days scroll underneath — capped so
                    // they never push the schedule below the fold.
                    if !pinnedTasks.isEmpty {
                        // A soft grey card marks the pool as week-wide holding
                        // space, distinct from the scheduled days — same
                        // rounded-block language as the calendar events.
                        // No gap below the card: the scroll veil starts right
                        // at its edge, so there's no white strip for content
                        // to hard-clip against.
                        pinnedHeader(maxHeight: geo.size.height * 0.45)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground).opacity(0.7))
                            )
                            .padding(.horizontal, 10)
                    }
                    ScrollViewReader { proxy in
                        dayList(proxy)
                    }
                }
            }
        }
        // Swipe left/right anywhere in the view to page between weeks. Only
        // clearly-horizontal drags count, so list scrolling stays untouched.
        .simultaneousGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5, abs(dx) > 50 else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        weekOffset += dx < 0 ? 1 : -1
                    }
                }
        )
        .task(id: weekOffset) { loadEvents() }
        .onChange(of: calendarService.isConnected) { loadEvents() }
        .onChange(of: settings.showCalendarEvents) { loadEvents() }
        .onChange(of: settings.hiddenCalendarIDs) { loadEvents() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in loadEvents() }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task, showCoachingToast: false)
                .presentationDetents([.fraction(0.7), .large])
                .presentationBackground(Color(.systemBackground))
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
                .presentationDetents([.fraction(0.7), .large])
                .presentationBackground(Color(.systemBackground))
        }
        .sheet(item: $timelineDay) { selection in
            DayTimelineView(day: selection.day)
                .presentationBackground(Color(.systemBackground))
        }
    }

    private func dayList(_ proxy: ScrollViewProxy) -> some View {
        List {
            if showConnectCard {
                connectCard
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(Array(days.enumerated()), id: \.element.timeIntervalSinceReferenceDate) { index, day in
                if index > 0 {
                    dayDivider.id(day)
                }
                // Past days keep their events (dimmed) so the week still reads
                // as a record; completed task rows fold into the "All done"
                // summary line, and only overdue tasks stay as rows.
                if isPast(day) {
                    scheduleRows(events: events(on: day), eventsDay: day, tasks: tasks(on: day), emptyText: "Nothing planned", doneCount: completedCount(on: day), dimmed: true) { dayLabel(day) }
                } else {
                    scheduleRows(events: events(on: day), eventsDay: day, tasks: tasks(on: day) + completedTasks(on: day), emptyText: "Nothing planned", emptyHighlighted: cal.isDateInToday(day), doneCount: completedCount(on: day)) { dayLabel(day) }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 10)
        // At rest the first day starts below the veil's strong zone, so only
        // scrolled-under content picks up the fade.
        .contentMargins(.top, pinnedTasks.isEmpty ? 0 : 12, for: .scrollContent)
        // Days dissolve under the pinned card instead of hard-clipping at
        // its edge — same veil the list view has under the tag pills.
        .overlay(alignment: .top) {
            if !pinnedTasks.isEmpty {
                topScrollFade
                    .frame(height: 26)
            }
        }
        .onAppear { scrollToToday(proxy) }
    }

    private var topScrollFade: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: Color(.systemBackground).opacity(0.85), location: 0.0),
                        .init(color: Color(.systemBackground).opacity(0.3), location: 0.55),
                        .init(color: Color(.systemBackground).opacity(0), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .mask(
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
            )
            .allowsHitTesting(false)
    }

    // MARK: - Pinned header

    /// The whole-week pool above the day schedule. Sized to content, capped at
    /// `maxHeight`, and scrollable within itself once it overflows the cap.
    private func pinnedHeader(maxHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if pinnedCollapsed {
                    collapsedSectionRow(count: pinnedTasks.count, label: { pinnedColumn }) {
                        withAnimation(.spokeTransition) { pinnedCollapsed = false }
                    }
                } else {
                    let visible = undatedExpanded ? pinnedTasks : Array(pinnedTasks.prefix(undatedCap))
                    let hiddenCount = pinnedTasks.count - visible.count
                    scheduleRows(tasks: visible, emptyText: nil, plain: true) {
                        Button {
                            withAnimation(.spokeTransition) { pinnedCollapsed = true }
                        } label: { pinnedColumn }
                            .buttonStyle(.plain)
                    }
                    if hiddenCount > 0 {
                        previewToggleRow("View \(hiddenCount) more") {
                            withAnimation(.spokeTransition) { undatedExpanded = true }
                        }
                    } else if undatedExpanded && pinnedTasks.count > undatedCap {
                        previewToggleRow("Show fewer") {
                            withAnimation(.spokeTransition) { undatedExpanded = false }
                        }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                pinnedContentHeight = $0
            }
        }
        .frame(height: min(pinnedContentHeight, maxHeight))
        // The height is state-driven, so the collapse needs its own animation
        // or the card snaps between sizes.
        .animation(.spokeTransition, value: pinnedContentHeight)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Opening the current week jumps straight to today, so a Sunday doesn't
    /// start with six faded days to scroll past.
    private func scrollToToday(_ proxy: ScrollViewProxy) {
        guard weekOffset == 0,
              let today = days.first(where: { cal.isDateInToday($0) }),
              today != days.first else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(today, anchor: .top)
        }
    }

    // MARK: - Schedule rows

    /// Renders one day (or the pool) as schedule rows: the label column is
    /// visible on the first row only, so tasks stack beside a single date.
    /// Calendar appointments render first, then tasks. `plain: true` renders
    /// with ordinary padding for use outside a List (the pinned header).
    @ViewBuilder
    private func scheduleRows<Label: View>(events: [DayEvent] = [], eventsDay: Date = .distantPast, tasks: [SpokeTask], emptyText: String?, emptyHighlighted: Bool = false, doneCount: Int = 0, dimmed: Bool = false, plain: Bool = false, @ViewBuilder label: @escaping () -> Label) -> some View {
        // Plain rows sit inside the pinned card, which is already inset 10pt
        // from the screen edge — 6pt here keeps their content on the same
        // 16pt grid as the day rows below.
        let sideInset: CGFloat = plain ? 6 : 16
        return buildScheduleRows(events: events, eventsDay: eventsDay, tasks: tasks, emptyText: emptyText, emptyHighlighted: emptyHighlighted, doneCount: doneCount, dimmed: dimmed, plain: plain, sideInset: sideInset, label: label)
    }

    @ViewBuilder
    private func buildScheduleRows<Label: View>(events: [DayEvent], eventsDay: Date, tasks: [SpokeTask], emptyText: String?, emptyHighlighted: Bool, doneCount: Int, dimmed: Bool, plain: Bool, sideInset: CGFloat, @ViewBuilder label: @escaping () -> Label) -> some View {
        if events.isEmpty && tasks.isEmpty {
            if doneCount > 0 {
                HStack(alignment: .center, spacing: 14) {
                    label()
                        .frame(width: dateColumnWidth)
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(coral.opacity(0.75))
                        Text("All done · \(doneCount) task\(doneCount == 1 ? "" : "s")")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    Spacer(minLength: 0)
                }
                .opacity(dimmed ? 0.45 : 1)
                .rowContainer(EdgeInsets(top: 3, leading: sideInset, bottom: 3, trailing: sideInset), plain: plain)
            } else if let emptyText {
                HStack(alignment: .center, spacing: 14) {
                    label()
                        .frame(width: dateColumnWidth)
                    Text(emptyText)
                        .font(.system(size: 13))
                        .italic()
                        // Coral only for today — a free day right now is worth
                        // noticing; on other days it read like a warning.
                        .foregroundStyle(emptyHighlighted ? coral.opacity(0.8) : Color(.quaternaryLabel))
                    Spacer(minLength: 0)
                }
                .opacity(dimmed ? 0.45 : 1)
                .rowContainer(EdgeInsets(top: 3, leading: sideInset, bottom: 3, trailing: sideInset), plain: plain)
            }
        } else {
            // Every row is at least date-label height, so the first row — which
            // carries the label inline — is no taller than its neighbours.
            // Anything less and the label opens a gap between a day's first
            // and second items. (An overlaid label doesn't work — List rows
            // clip overflow.) The floor also brings rows closer to a 44pt
            // touch target.
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .center, spacing: 14) {
                    if index == 0 {
                        label().frame(width: dateColumnWidth)
                    } else {
                        Color.clear.frame(width: dateColumnWidth, height: 1)
                    }
                    eventRow(event, on: eventsDay)
                }
                .frame(minHeight: scheduleRowMinHeight)
                .opacity(dimmed ? 0.45 : 1)
                // The event blocks' tinted background eats the visual gap, so
                // the last one gets extra room before the tasks start.
                .rowContainer(EdgeInsets(top: 1, leading: sideInset, bottom: index == events.count - 1 && !tasks.isEmpty ? 6 : 1, trailing: sideInset), plain: plain)
            }
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                let isFirstRow = events.isEmpty && index == 0
                HStack(alignment: .center, spacing: 14) {
                    if isFirstRow {
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
                .frame(minHeight: scheduleRowMinHeight)
                .opacity(dimmed ? 0.45 : 1)
                .rowContainer(EdgeInsets(top: 1, leading: sideInset, bottom: 1, trailing: sideInset), plain: plain)
            }
        }
    }

    /// A calendar appointment: tinted block with the calendar's colour as a
    /// spine, time underneath — deliberately un-task-like (no checkbox).
    /// Tapping opens the in-app event detail sheet.
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
            selectedEvent = event
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

    /// Collapsed section: the badge and the to-do count, tap to expand.
    /// Same row metrics as the expanded rows, so the badge doesn't shift
    /// when the section opens and closes.
    private func collapsedSectionRow<Label: View>(count: Int, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                label()
                    .frame(width: dateColumnWidth)
                Text("\(count) task\(count == 1 ? "" : "s") to do")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(.label).opacity(0.75))
                Spacer(minLength: 0)
            }
            .frame(minHeight: scheduleRowMinHeight)
        }
        .buttonStyle(.plain)
        .padding(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
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
        .padding(EdgeInsets(top: 2, leading: 6, bottom: 6, trailing: 6))
    }

    private var dayDivider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(height: 0.5)
            .listRowSeparator(.hidden)
            // Generous breathing room so each day reads as its own chunk,
            // while rows within a day stay tight.
            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
    }

    // MARK: - Date columns

    /// Date badge as a button: tapping opens the day-timeline prototype.
    private func dayLabel(_ day: Date) -> some View {
        Button {
            timelineDay = TimelineDaySelection(day: day)
        } label: {
            dateColumn(day)
        }
        .buttonStyle(.plain)
    }

    private func dateColumn(_ day: Date) -> some View {
        let isToday = cal.isDateInToday(day)
        let dayNumber = "\(cal.component(.day, from: day))"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"
        let weekday = weekdayFormatter.string(from: day).uppercased()

        // Compact on purpose: the label sits inline on a day's first row, so
        // every point of its height beyond a task row shows up as a gap
        // between the day's first and second items.
        return VStack(spacing: 1) {
            Text(dayNumber)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isToday ? .white : Color(.label))
                .frame(width: 24, height: 24)
                .background {
                    if isToday {
                        Circle().fill(coral)
                    }
                }
            Text(weekday)
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(isToday ? coral : Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
    }

    /// "THIS WEEK" on the current week; paging ahead relabels rather than
    /// pretending next week's pool is this week's.
    private var pinnedLabelText: String {
        switch weekOffset {
        case 0: return "THIS WEEK"
        case 1: return "NEXT WEEK"
        default: return "SOMETIME"
        }
    }

    private var pinnedColumn: some View {
        VStack(spacing: 1) {
            Image(systemName: "tray")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(coral)
                .frame(width: 24, height: 24)
                .background(Circle().fill(coral.opacity(0.12)))
            Text(pinnedLabelText)
                .font(.system(size: 8, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(coral)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

/// Date isn't Identifiable, so sheet(item:) needs this thin wrapper.
struct TimelineDaySelection: Identifiable {
    let id = UUID()
    let day: Date
}

private extension View {
    /// One row, two habitats: list insets inside the day List, ordinary
    /// padding inside the pinned header's ScrollView (where insets are inert).
    @ViewBuilder
    func rowContainer(_ insets: EdgeInsets, plain: Bool) -> some View {
        if plain {
            padding(insets)
        } else {
            listRowSeparator(.hidden)
                .listRowInsets(insets)
        }
    }
}

#Preview {
    WeekCalendarView(weekOffset: .constant(0))
        .modelContainer(for: SpokeTask.self, inMemory: true)
}
