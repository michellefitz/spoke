import Foundation
import SwiftData

@Model
class SpokeTask {
    var id: UUID
    var title: String
    var taskDescription: String?
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var deadline: Date?
    var tag: String?
    /// When true, `deadline` means "sometime that week" rather than a specific day.
    /// The stored date is the last day of the week, so "due by end of week" ordering
    /// and overdue checks work without special-casing.
    var deadlineIsWeek: Bool = false

    init(title: String, taskDescription: String? = nil, deadline: Date? = nil, tag: String? = nil, deadlineIsWeek: Bool = false) {
        self.id = UUID()
        self.title = title
        self.taskDescription = taskDescription
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = .now
        self.deadline = deadline
        self.tag = tag
        self.deadlineIsWeek = deadlineIsWeek
    }
}

extension Calendar {
    /// First instant of the week containing `date`.
    func weekStart(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    /// Start-of-day of the LAST day of the week `offsetWeeks` from now.
    /// Week-bucket deadlines are stored as this date.
    func weekBucketDeadline(offsetWeeks: Int) -> Date {
        let base = date(byAdding: .weekOfYear, value: offsetWeeks, to: .now) ?? .now
        guard let interval = dateInterval(of: .weekOfYear, for: base),
              let lastDay = date(byAdding: .day, value: -1, to: interval.end) else {
            return startOfDay(for: base)
        }
        return startOfDay(for: lastDay)
    }
}
