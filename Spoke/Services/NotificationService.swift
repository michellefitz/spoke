import Foundation
import UserNotifications

/// Local notifications only: per-task voice reminders ("remind me at 6") and
/// the morning digest. Everything is recomputed from current state when the
/// app leaves the foreground — every task edit happens in-app, so the state
/// at backgrounding is always the truth and no incremental bookkeeping is
/// needed.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let settings = AppSettings.shared
    private let delegate = ForegroundBannerDelegate()
    /// Days of digests scheduled ahead; past that the next app open reschedules.
    private let digestHorizon = 7

    private init() {
        center.delegate = delegate
    }

    /// True if notifications are usable (asks the user on first call).
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    var isAuthorized: Bool {
        get async {
            let status = await center.notificationSettings().authorizationStatus
            return status == .authorized || status == .provisional
        }
    }

    /// Wipes and reschedules everything pending from the given active tasks.
    func refresh(tasks: [SpokeTask]) async {
        guard await isAuthorized else { return }
        center.removeAllPendingNotificationRequests()
        scheduleTaskReminders(tasks)
        scheduleDigests(tasks)
    }

    // MARK: - Per-task reminders

    private func scheduleTaskReminders(_ tasks: [SpokeTask]) {
        for task in tasks {
            guard !task.isCompleted, let remindAt = task.remindAt, remindAt > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.title
            if let description = task.taskDescription, !description.isEmpty {
                content.body = description.components(separatedBy: "\n").first ?? ""
            }
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: remindAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: "remind-\(task.id.uuidString)", content: content, trigger: trigger))
        }
    }

    // MARK: - Morning digest

    private func scheduleDigests(_ tasks: [SpokeTask]) {
        guard settings.morningDigestEnabled else { return }
        let cal = Calendar.current
        for offset in 0..<digestHorizon {
            guard let day = cal.date(byAdding: .day, value: offset, to: .now) else { continue }
            let dayStart = cal.startOfDay(for: day)
            guard let fireDate = cal.date(byAdding: .minute, value: settings.digestMinutes, to: dayStart),
                  fireDate > .now else { continue }

            let dueTasks = tasks.filter { task in
                guard !task.isCompleted, let deadline = task.deadline, !task.deadlineIsWeek else { return false }
                return cal.isDate(deadline, inSameDayAs: day)
            }
            let events = digestEvents(on: day)
            guard !dueTasks.isEmpty || !events.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = digestTitle(taskCount: dueTasks.count, eventCount: events.count)
            content.body = digestBody(tasks: dueTasks, events: events)
            content.sound = .default
            let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let dayID = ISO8601DateFormatter.string(from: dayStart, timeZone: .current, formatOptions: [.withFullDate])
            center.add(UNNotificationRequest(identifier: "digest-\(dayID)", content: content, trigger: trigger))
        }
    }

    private func digestEvents(on day: Date) -> [DayEvent] {
        guard settings.showCalendarEvents, CalendarService.shared.isConnected else { return [] }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return CalendarService.shared.events(from: dayStart, to: dayEnd)
    }

    private func digestTitle(taskCount: Int, eventCount: Int) -> String {
        let tasks = taskCount == 1 ? "1 task" : "\(taskCount) tasks"
        let events = eventCount == 1 ? "1 appointment" : "\(eventCount) appointments"
        switch (taskCount > 0, eventCount > 0) {
        case (true, true):   return "Today: \(tasks), \(events)"
        case (true, false):  return "Today: \(tasks)"
        case (false, true):  return "Today: \(events)"
        case (false, false): return "Today"
        }
    }

    private func digestBody(tasks: [SpokeTask], events: [DayEvent]) -> String {
        var parts = tasks.prefix(3).map(\.title)
        if tasks.count > 3 { parts.append("+\(tasks.count - 3) more") }
        if parts.isEmpty, let first = events.first {
            parts.append(first.title)
            if events.count > 1 { parts.append("+\(events.count - 1) more") }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Dev

    /// Fires today's digest a moment from now so its content and delivery can
    /// be checked without waiting for morning. Temporary testing aid.
    func sendTestDigest(tasks: [SpokeTask]) async {
        guard await requestAuthorizationIfNeeded() else { return }
        let cal = Calendar.current
        let dueTasks = tasks.filter { task in
            guard !task.isCompleted, let deadline = task.deadline, !task.deadlineIsWeek else { return false }
            return cal.isDateInToday(deadline)
        }
        let events = digestEvents(on: .now)
        let content = UNMutableNotificationContent()
        content.title = digestTitle(taskCount: dueTasks.count, eventCount: events.count)
        content.body = dueTasks.isEmpty && events.isEmpty ? "Nothing planned today." : digestBody(tasks: dueTasks, events: events)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "digest-test", content: content, trigger: trigger))
    }
}

/// Shows notifications as banners even while Spoke is foregrounded — needed
/// for the test digest, and harmless for real reminders.
private final class ForegroundBannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
