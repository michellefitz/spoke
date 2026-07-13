import SwiftUI
import SwiftData
import WidgetKit

/// Weekly planning view: a pool of week-bucket tasks ("this week, any day")
/// followed by the seven days with their day-specific tasks.
struct WeekCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<SpokeTask> { $0.isCompleted == false },
        sort: [SortDescriptor(\SpokeTask.deadline)]
    )
    private var activeTasks: [SpokeTask]

    @State private var weekOffset = 0
    @State private var selectedTask: SpokeTask?

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
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
                        Section {
                            ForEach(poolTasks) { task in
                                row(task)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(weekOffset == 1 ? "Next week — any day" : "Any day")
                                    .font(.caption)
                                    .foregroundStyle(Color(.label).opacity(0.6))
                                Text("\(poolTasks.count)")
                                    .font(.caption)
                                    .foregroundStyle(Color(.label).opacity(0.35))
                            }
                        }
                    }

                    ForEach(days, id: \.timeIntervalSinceReferenceDate) { day in
                        let dayTasks = tasks(on: day)
                        if !dayTasks.isEmpty {
                            Section {
                                ForEach(dayTasks) { task in
                                    row(task)
                                }
                            } header: {
                                dayHeader(day)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .listSectionSpacing(0)
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task, showCoachingToast: false)
                .presentationDetents([.fraction(0.7), .large])
                .presentationBackground(Color(.systemBackground))
        }
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
                if weekOffset != 0 {
                    Button("Back to this week") {
                        withAnimation(.spokeTransition) { weekOffset = 0 }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(coral)
                }
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
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func dayHeader(_ day: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        let isToday = cal.isDateInToday(day)
        return HStack(spacing: 6) {
            Text(formatter.string(from: day))
                .font(.caption)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? coral : Color(.label).opacity(0.6))
            if isToday {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(coral.opacity(0.7))
            }
        }
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

    // MARK: - Rows & actions

    private func row(_ task: SpokeTask) -> some View {
        TaskRowView(
            task: task,
            onToggleComplete: { toggleComplete(task) },
            onDelete: { deleteTask(task) },
            onTap: { selectedTask = task }
        )
    }

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
