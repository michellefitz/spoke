import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline entry

struct TaskEntry: TimelineEntry {
    let date: Date
    let dueTodayTasks: [TaskSnapshot]
    let overdueTasks: [TaskSnapshot]
    let recentTasks: [TaskSnapshot]
    let totalActiveCount: Int
}

struct TaskSnapshot {
    let title: String
    let isCompleted: Bool
    let tag: String?
}

// MARK: - Timeline provider

struct SpokeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(
            date: .now,
            dueTodayTasks: [
                TaskSnapshot(title: "Call the dentist", isCompleted: false, tag: "personal"),
                TaskSnapshot(title: "Review Q2 budget", isCompleted: false, tag: "work"),
                TaskSnapshot(title: "Pick up dry cleaning", isCompleted: false, tag: nil)
            ],
            overdueTasks: [],
            recentTasks: [],
            totalActiveCount: 5
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = fetchEntry()
        // Refresh at the start of the next hour, or midnight for the new day
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func fetchEntry() -> TaskEntry {
        let storeURL = SharedContainer.url.appendingPathComponent("Spoke.sqlite")
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return TaskEntry(date: .now, dueTodayTasks: [], overdueTasks: [], recentTasks: [], totalActiveCount: 0)
        }

        let container: ModelContainer
        do {
            container = try ModelContainer(for: SpokeTask.self, configurations: ModelConfiguration(
                url: storeURL
            ))
        } catch {
            return TaskEntry(date: .now, dueTodayTasks: [], overdueTasks: [], recentTasks: [], totalActiveCount: 0)
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false

        let allTasks: [SpokeTask]
        do {
            allTasks = try context.fetch(FetchDescriptor<SpokeTask>())
        } catch {
            allTasks = []
        }

        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let activeTasks = allTasks.filter { !$0.isCompleted }

        let dueTodayTasks: [TaskSnapshot] = activeTasks
            .filter { $0.deadline != nil && $0.deadline! >= today && $0.deadline! < tomorrow }
            .map { TaskSnapshot(title: $0.title, isCompleted: false, tag: $0.tag) }

        let overdueTasks: [TaskSnapshot] = activeTasks
            .filter { $0.deadline != nil && $0.deadline! < today }
            .sorted { $0.deadline! > $1.deadline! }
            .map { TaskSnapshot(title: $0.title, isCompleted: false, tag: $0.tag) }

        // Recent tasks (no deadline or future deadline) — fallback when nothing due today
        let recentTasks: [TaskSnapshot] = activeTasks
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(6)
            .map { TaskSnapshot(title: $0.title, isCompleted: false, tag: $0.tag) }

        return TaskEntry(
            date: .now,
            dueTodayTasks: dueTodayTasks,
            overdueTasks: overdueTasks,
            recentTasks: recentTasks,
            totalActiveCount: activeTasks.count
        )
    }
}

// MARK: - Small widget view

struct SpokeWidgetSmallView: View {
    let entry: TaskEntry

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    private var urgentCount: Int { entry.overdueTasks.count + entry.dueTodayTasks.count }
    private var hasUrgent: Bool { urgentCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("spoke")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Circle()
                    .fill(coral)
                    .frame(width: 4, height: 4)
            }

            Spacer()

            if hasUrgent {
                Text("\(urgentCount)")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(coral)
                if entry.overdueTasks.isEmpty {
                    Text("due today")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else if entry.dueTodayTasks.isEmpty {
                    Text("overdue")
                        .font(.system(size: 13))
                        .foregroundStyle(coral.opacity(0.7))
                } else {
                    Text("\(entry.overdueTasks.count) overdue, \(entry.dueTodayTasks.count) today")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if entry.totalActiveCount > 0 {
                Text("\(entry.totalActiveCount)")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.6))
                Text("active task\(entry.totalActiveCount == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Text("All clear")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if hasUrgent && entry.totalActiveCount > urgentCount {
                Text("\(entry.totalActiveCount) total")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Medium widget view

struct SpokeWidgetMediumView: View {
    let entry: TaskEntry

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let maxItems = 4

    /// Combined list: overdue first, then due today
    private var urgentTasks: [WidgetTaskItem] {
        let overdue = entry.overdueTasks.map { WidgetTaskItem(title: $0.title, isOverdue: true) }
        let today = entry.dueTodayTasks.map { WidgetTaskItem(title: $0.title, isOverdue: false) }
        return overdue + today
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Text("spoke")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Circle()
                        .fill(coral)
                        .frame(width: 4, height: 4)
                }

                Spacer()

                if !urgentTasks.isEmpty {
                    let label = entry.overdueTasks.isEmpty ? "Due Today" : "Needs Attention"
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(coral)
                } else if entry.totalActiveCount > 0 {
                    Text("Recent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if !urgentTasks.isEmpty {
                taskList(urgentTasks, total: urgentTasks.count)
            } else if !entry.recentTasks.isEmpty {
                taskList(entry.recentTasks.map { WidgetTaskItem(title: $0.title, isOverdue: false) }, total: entry.totalActiveCount)
            } else {
                Spacer()
                Text("All clear")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func taskList(_ items: [WidgetTaskItem], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let visible = Array(items.prefix(maxItems))
            ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(item.isOverdue ? coral.opacity(0.6) : Color(.tertiaryLabel), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    Text(item.title)
                        .font(.system(size: 14))
                        .foregroundStyle(item.isOverdue ? .primary : .primary)
                        .lineLimit(1)
                    Spacer()
                    if item.isOverdue {
                        Text("OVERDUE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(coral.opacity(0.8))
                    }
                }
            }

            let overflow = total - maxItems
            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }
}

private struct WidgetTaskItem {
    let title: String
    let isOverdue: Bool
}

// MARK: - Lock screen widget (accessory circular)

struct SpokeWidgetLockScreenView: View {
    let entry: TaskEntry

    private var urgentCount: Int { entry.overdueTasks.count + entry.dueTodayTasks.count }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if urgentCount > 0 {
                Text("\(urgentCount)")
                    .font(.system(size: 24, weight: .semibold))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Lock screen widget (accessory inline)

struct SpokeWidgetInlineView: View {
    let entry: TaskEntry

    private var urgentCount: Int { entry.overdueTasks.count + entry.dueTodayTasks.count }

    var body: some View {
        if urgentCount == 0 {
            Text("Spoke — all clear")
        } else if entry.overdueTasks.isEmpty {
            Text("\(urgentCount) due today")
        } else {
            Text("\(urgentCount) need attention")
        }
    }
}

// MARK: - Widget definition

struct SpokeWidget: Widget {
    let kind = "SpokeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpokeTimelineProvider()) { entry in
            SpokeWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Spoke Tasks")
        .description("See what needs attention at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}

struct SpokeWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TaskEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SpokeWidgetSmallView(entry: entry)
        case .systemMedium:
            SpokeWidgetMediumView(entry: entry)
        case .accessoryCircular:
            SpokeWidgetLockScreenView(entry: entry)
        case .accessoryInline:
            SpokeWidgetInlineView(entry: entry)
        default:
            SpokeWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget bundle (entry point)

@main
struct SpokeWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpokeWidget()
    }
}

// MARK: - Previews

#Preview("Small — Due Today", as: .systemSmall) {
    SpokeWidget()
} timeline: {
    TaskEntry(
        date: .now,
        dueTodayTasks: [
            TaskSnapshot(title: "Call the dentist", isCompleted: false, tag: "personal"),
            TaskSnapshot(title: "Review Q2 budget", isCompleted: false, tag: "work"),
            TaskSnapshot(title: "Pick up dry cleaning", isCompleted: false, tag: nil)
        ],
        overdueTasks: [],
        recentTasks: [],
        totalActiveCount: 7
    )
}

#Preview("Medium — Mixed", as: .systemMedium) {
    SpokeWidget()
} timeline: {
    TaskEntry(
        date: .now,
        dueTodayTasks: [
            TaskSnapshot(title: "Review Q2 budget", isCompleted: false, tag: "work"),
            TaskSnapshot(title: "Pick up dry cleaning", isCompleted: false, tag: nil)
        ],
        overdueTasks: [
            TaskSnapshot(title: "File tax return", isCompleted: false, tag: "finance"),
            TaskSnapshot(title: "Renew car insurance", isCompleted: false, tag: nil)
        ],
        recentTasks: [],
        totalActiveCount: 12
    )
}

#Preview("Small — No Deadlines", as: .systemSmall) {
    SpokeWidget()
} timeline: {
    TaskEntry(
        date: .now,
        dueTodayTasks: [],
        overdueTasks: [],
        recentTasks: [
            TaskSnapshot(title: "Buy birthday present", isCompleted: false, tag: "personal"),
            TaskSnapshot(title: "Clean garage", isCompleted: false, tag: nil)
        ],
        totalActiveCount: 5
    )
}

#Preview("Medium — Recent Fallback", as: .systemMedium) {
    SpokeWidget()
} timeline: {
    TaskEntry(
        date: .now,
        dueTodayTasks: [],
        overdueTasks: [],
        recentTasks: [
            TaskSnapshot(title: "Buy birthday present", isCompleted: false, tag: "personal"),
            TaskSnapshot(title: "Clean garage", isCompleted: false, tag: nil),
            TaskSnapshot(title: "Call electrician", isCompleted: false, tag: nil)
        ],
        totalActiveCount: 3
    )
}

#Preview("Small — All Clear", as: .systemSmall) {
    SpokeWidget()
} timeline: {
    TaskEntry(date: .now, dueTodayTasks: [], overdueTasks: [], recentTasks: [], totalActiveCount: 0)
}
