import SwiftUI
import SwiftData
import WidgetKit

/// PROTOTYPE: a single-day timeline in the Google Calendar mould — tasks as
/// cards up top, then an hour-by-hour column where event blocks are sized by
/// duration, so a scattered day's busy/free shape is visible at a glance.
/// Opened by tapping a date badge in the week view.
struct DayTimelineView: View {
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<SpokeTask> { $0.isCompleted == false })
    private var activeTasks: [SpokeTask]

    @State private var events: [DayEvent] = []
    @State private var selectedEvent: DayEvent?
    @State private var selectedTask: SpokeTask?

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let hourHeight: CGFloat = 56
    private let timeGutter: CGFloat = 54
    private var cal: Calendar { Calendar.current }
    private var dayStart: Date { cal.startOfDay(for: day) }
    private var dayEnd: Date { cal.date(byAdding: .day, value: 1, to: dayStart) ?? day }

    private var dayTasks: [SpokeTask] {
        activeTasks.filter { task in
            guard let deadline = task.deadline, !task.deadlineIsWeek else { return false }
            return cal.isDate(deadline, inSameDayAs: day)
        }
    }

    private var timedEvents: [DayEvent] { events.filter { !$0.isAllDay } }
    private var allDayEvents: [DayEvent] { events.filter(\.isAllDay) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !dayTasks.isEmpty || !allDayEvents.isEmpty {
                VStack(spacing: 6) {
                    ForEach(allDayEvents) { event in
                        allDayChip(event)
                    }
                    ForEach(dayTasks) { task in
                        TaskRowView(
                            task: task,
                            onToggleComplete: { toggleComplete(task) },
                            onDelete: { deleteTask(task) },
                            onTap: { selectedTask = task },
                            calendarStyle: true
                        )
                    }
                }
                .padding(.horizontal, 10)
                // Roomier than the week-view card: this one has no title, so
                // the whitespace is what frames it.
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground).opacity(0.7)))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            timeline
        }
        .background(Color(.systemBackground))
        .task { loadEvents() }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
                .presentationDetents([.fraction(0.7), .large])
                .presentationBackground(Color(.systemBackground))
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task, showCoachingToast: false)
                .presentationDetents([.fraction(0.7), .large])
                .presentationBackground(Color(.systemBackground))
        }
    }

    private var header: some View {
        HStack {
            Text(dayTitle)
                .font(.system(size: 17, weight: .semibold))
            if cal.isDateInToday(day) {
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(coral))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: day)
    }

    // MARK: - Timeline

    private var timeline: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourGrid

                        ForEach(layoutItems(timedEvents), id: \.event.id) { item in
                            let lane = (geo.size.width - timeGutter - 12) / CGFloat(item.columns)
                            eventBlock(item.event)
                                .frame(width: lane - 3, height: blockHeight(item.event))
                                .offset(
                                    x: timeGutter + CGFloat(item.column) * lane,
                                    y: yOffset(clampedStart(item.event)) + 1
                                )
                        }

                        if cal.isDateInToday(day) {
                            nowLine
                                .offset(y: yOffset(.now))
                        }
                    }
                    .frame(height: hourHeight * 24)
                }
                .onAppear { scrollToMorning(proxy) }
            }
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(hourLabel(hour))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .frame(width: timeGutter - 10, alignment: .trailing)
                        .offset(y: -7)
                    Rectangle()
                        .fill(Color(.separator).opacity(0.35))
                        .frame(height: 0.5)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func eventBlock(_ event: DayEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
                .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(2)
                Text(blockTimeLabel(event))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .padding(.vertical, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(event.color.opacity(0.14)))
        .contentShape(Rectangle())
        .onTapGesture { selectedEvent = event }
    }

    private var nowLine: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(coral)
                .frame(width: 7, height: 7)
                .padding(.leading, timeGutter - 3)
            Rectangle()
                .fill(coral)
                .frame(height: 1.5)
        }
        .offset(y: -3.5)
        .allowsHitTesting(false)
    }

    private func allDayChip(_ event: DayEvent) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3, height: 16)
            Text(event.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("All day")
                .font(.system(size: 11))
                .foregroundStyle(Color(.secondaryLabel))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(event.color.opacity(0.1)))
        .contentShape(Rectangle())
        .onTapGesture { selectedEvent = event }
    }

    // MARK: - Geometry

    private func clampedStart(_ event: DayEvent) -> Date { max(event.start, dayStart) }

    private func yOffset(_ date: Date) -> CGFloat {
        let minutes = CGFloat(cal.dateComponents([.minute], from: dayStart, to: date).minute ?? 0)
        return minutes / 60 * hourHeight
    }

    private func blockHeight(_ event: DayEvent) -> CGFloat {
        let end = min(event.end, dayEnd)
        return max(30, yOffset(end) - yOffset(clampedStart(event)) - 2)
    }

    /// Overlapping events share the width: greedy column assignment within
    /// each overlap cluster, Google Calendar style.
    private struct TimelineItem { let event: DayEvent; let column: Int; let columns: Int }

    private func layoutItems(_ events: [DayEvent]) -> [TimelineItem] {
        let sorted = events.sorted { $0.start < $1.start }
        var clusters: [[DayEvent]] = []
        var clusterEnd = Date.distantPast
        for event in sorted {
            if clusters.isEmpty || clampedStart(event) >= clusterEnd {
                clusters.append([event])
            } else {
                clusters[clusters.count - 1].append(event)
            }
            clusterEnd = max(clusterEnd, min(event.end, dayEnd))
        }
        var items: [TimelineItem] = []
        for cluster in clusters {
            var columnEnds: [Date] = []
            var placed: [(DayEvent, Int)] = []
            for event in cluster {
                if let free = columnEnds.firstIndex(where: { $0 <= clampedStart(event) }) {
                    columnEnds[free] = event.end
                    placed.append((event, free))
                } else {
                    columnEnds.append(event.end)
                    placed.append((event, columnEnds.count - 1))
                }
            }
            items += placed.map { TimelineItem(event: $0.0, column: $0.1, columns: columnEnds.count) }
        }
        return items
    }

    private func hourLabel(_ hour: Int) -> String {
        guard let date = cal.date(byAdding: .hour, value: hour, to: dayStart) else { return "" }
        return Self.hourFormatter.string(from: date)
    }

    private func blockTimeLabel(_ event: DayEvent) -> String {
        "\(Self.hourFormatter.string(from: event.start)) – \(Self.hourFormatter.string(from: event.end))"
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func scrollToMorning(_ proxy: ScrollViewProxy) {
        let target: Int
        if cal.isDateInToday(day) {
            // One full hour of context above the now line — at 13:30 the view
            // opens with 12:00 anchored at the top, not the whole morning.
            target = max(0, cal.component(.hour, from: .now) - 1)
        } else {
            let firstEventHour = timedEvents.map { cal.component(.hour, from: clampedStart($0)) }.min()
            target = max(0, min(firstEventHour ?? 8, 8) - 1)
        }
        proxy.scrollTo(target, anchor: .top)
    }

    private func loadEvents() {
        guard CalendarService.shared.isConnected, AppSettings.shared.showCalendarEvents else {
            events = []
            return
        }
        events = CalendarService.shared.events(from: dayStart, to: dayEnd)
    }

    // MARK: - Task actions

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
    DayTimelineView(day: .now)
        .modelContainer(for: SpokeTask.self, inMemory: true)
}
