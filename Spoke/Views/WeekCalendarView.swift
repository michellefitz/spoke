import SwiftUI
import SwiftData
import WidgetKit

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

    @State private var weekOffset = 0
    @State private var selectedTask: SpokeTask?

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

    private func tasks(on day: Date) -> [SpokeTask] {
        activeTasks.filter { task in
            guard let deadline = task.deadline, !task.deadlineIsWeek else { return false }
            return cal.isDate(deadline, inSameDayAs: day)
        }
    }

    private var weekTitle: String {
        switch weekOffset {
        case 0: return "This Week"
        case 1: return "Next Week"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            let end = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            return "\(formatter.string(from: weekStart)) – \(formatter.string(from: end))"
        }
    }

    private var weekIsEmpty: Bool {
        poolTasks.isEmpty && days.allSatisfy { tasks(on: $0).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if weekIsEmpty {
                emptyState
            } else {
                List {
                    if !poolTasks.isEmpty {
                        scheduleRows(tasks: poolTasks, emptyText: nil) { poolColumn }
                        dayDivider
                    }

                    ForEach(Array(days.enumerated()), id: \.element.timeIntervalSinceReferenceDate) { index, day in
                        scheduleRows(tasks: tasks(on: day), emptyText: "Nothing planned") { dateColumn(day) }
                        if index < days.count - 1 {
                            dayDivider
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 10)
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task, showCoachingToast: false)
                .presentationDetents([.fraction(0.7), .large])
                .presentationBackground(Color(.systemBackground))
        }
    }

    // MARK: - Schedule rows

    /// Renders one day (or the pool) as schedule rows: the label column is
    /// visible on the first row only, so tasks stack beside a single date.
    @ViewBuilder
    private func scheduleRows<Label: View>(tasks: [SpokeTask], emptyText: String?, @ViewBuilder label: @escaping () -> Label) -> some View {
        if tasks.isEmpty {
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
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
        } else {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                HStack(alignment: .top, spacing: 14) {
                    label()
                        .frame(width: dateColumnWidth)
                        .opacity(index == 0 ? 1 : 0)
                    TaskRowView(
                        task: task,
                        onToggleComplete: { toggleComplete(task) },
                        onDelete: { deleteTask(task) },
                        onTap: { selectedTask = task },
                        hideDeadlineChip: true
                    )
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
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

        return VStack(spacing: 3) {
            Text(dayNumber)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isToday ? .white : Color(.label))
                .frame(width: 34, height: 34)
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
        VStack(spacing: 3) {
            Image(systemName: "tray")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(coral)
                .frame(width: 34, height: 34)
                .background(Circle().fill(coral.opacity(0.12)))
            Text("ANY DAY")
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(coral)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                withAnimation(.spokeTransition) { weekOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(coral)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(weekTitle)
                    .font(.system(size: 17, weight: .semibold))
                // Always occupies its slot so the title doesn't jump when paging
                Button("Back to this week") {
                    withAnimation(.spokeTransition) { weekOffset = 0 }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(coral)
                .opacity(weekOffset == 0 ? 0 : 1)
                .disabled(weekOffset == 0)
            }

            Spacer()

            Button {
                withAnimation(.spokeTransition) { weekOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(coral)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
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
    WeekCalendarView()
        .modelContainer(for: SpokeTask.self, inMemory: true)
}
