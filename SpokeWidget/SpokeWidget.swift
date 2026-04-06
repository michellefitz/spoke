import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline entry

struct TaskEntry: TimelineEntry {
    let date: Date
    let dueTodayTasks: [TaskSnapshot]
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
                TaskSnapshot(title: "Pick up dry cleaning", isCompleted: true, tag: nil)
            ],
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
            return TaskEntry(date: .now, dueTodayTasks: [], totalActiveCount: 0)
        }

        let container: ModelContainer
        do {
            container = try ModelContainer(for: SpokeTask.self, configurations: ModelConfiguration(
                url: storeURL
            ))
        } catch {
            return TaskEntry(date: .now, dueTodayTasks: [], totalActiveCount: 0)
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

        let dueTodayTasks: [TaskSnapshot] = allTasks
            .filter { !$0.isCompleted && $0.deadline != nil && $0.deadline! >= today && $0.deadline! < tomorrow }
            .map { TaskSnapshot(title: $0.title, isCompleted: $0.isCompleted, tag: $0.tag) }

        let totalActive = allTasks.filter { !$0.isCompleted }.count

        return TaskEntry(date: .now, dueTodayTasks: dueTodayTasks, totalActiveCount: totalActive)
    }
}

// MARK: - Small widget view

struct SpokeWidgetSmallView: View {
    let entry: TaskEntry

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

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

            if entry.dueTodayTasks.isEmpty {
                Text("Nothing due today")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(entry.dueTodayTasks.count)")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(coral)
                Text("due today")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if entry.totalActiveCount > 0 {
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

                if !entry.dueTodayTasks.isEmpty {
                    Text("Due Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(coral)
                }
            }

            Spacer(minLength: 8)

            if entry.dueTodayTasks.isEmpty {
                Spacer()
                Text("Nothing due today ✓")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                let visible = Array(entry.dueTodayTasks.prefix(maxItems))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, task in
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(.tertiaryLabel))
                            Text(task.title)
                                .font(.system(size: 14))
                                .lineLimit(1)
                            Spacer()
                            if let tag = task.tag {
                                Text(tag.uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(.tertiarySystemFill))
                                    )
                            }
                        }
                    }
                }

                let overflow = entry.dueTodayTasks.count - maxItems
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock screen widget (accessory circular)

struct SpokeWidgetLockScreenView: View {
    let entry: TaskEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text("\(entry.dueTodayTasks.count)")
                    .font(.system(size: 22, weight: .semibold))
                Text("today")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Lock screen widget (accessory inline)

struct SpokeWidgetInlineView: View {
    let entry: TaskEntry

    var body: some View {
        let count = entry.dueTodayTasks.count
        if count == 0 {
            Text("Nothing due today")
        } else {
            Text("\(count) task\(count == 1 ? "" : "s") due today")
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
        .configurationDisplayName("Due Today")
        .description("See what's due today at a glance.")
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

#Preview("Small", as: .systemSmall) {
    SpokeWidget()
} timeline: {
    TaskEntry(
        date: .now,
        dueTodayTasks: [
            TaskSnapshot(title: "Call the dentist", isCompleted: false, tag: "personal"),
            TaskSnapshot(title: "Review Q2 budget", isCompleted: false, tag: "work"),
            TaskSnapshot(title: "Pick up dry cleaning", isCompleted: false, tag: nil)
        ],
        totalActiveCount: 7
    )
}

#Preview("Medium", as: .systemMedium) {
    SpokeWidget()
} timeline: {
    TaskEntry(
        date: .now,
        dueTodayTasks: [
            TaskSnapshot(title: "Call the dentist", isCompleted: false, tag: "personal"),
            TaskSnapshot(title: "Review Q2 budget", isCompleted: false, tag: "work"),
            TaskSnapshot(title: "Pick up dry cleaning", isCompleted: false, tag: nil),
            TaskSnapshot(title: "Grocery shopping", isCompleted: false, tag: "shopping"),
            TaskSnapshot(title: "Book flights", isCompleted: false, tag: "personal")
        ],
        totalActiveCount: 12
    )
}

#Preview("Empty", as: .systemSmall) {
    SpokeWidget()
} timeline: {
    TaskEntry(date: .now, dueTodayTasks: [], totalActiveCount: 3)
}
