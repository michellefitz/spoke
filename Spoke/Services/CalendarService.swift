import EventKit
import Observation
import SwiftUI

/// A calendar appointment flattened into a value type so views never touch
/// EventKit objects directly.
struct DayEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

/// One device calendar, for the Settings picker. The source (account) name
/// disambiguates same-named calendars that arrive via two routes.
struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let source: String
    let color: Color
}

/// Read-only bridge to the device calendar via EventKit. Google, iCloud and
/// work calendars all arrive through the same store once their accounts are
/// on the phone — no OAuth of our own.
@Observable
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    private(set) var authorizationStatus: EKAuthorizationStatus

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var isConnected: Bool { authorizationStatus == .fullAccess }
    var canRequestAccess: Bool { authorizationStatus == .notDetermined }
    var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }

    @MainActor
    @discardableResult
    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        return granted
    }

    /// All event calendars on the device, sorted by account then name.
    func availableCalendars() -> [CalendarInfo] {
        guard isConnected else { return [] }
        return store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    source: calendar.source?.title ?? "Other",
                    color: calendar.cgColor.map { Color(cgColor: $0) } ?? Color(red: 1.0, green: 0.38, blue: 0.28)
                )
            }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// Events overlapping [start, end), with recurring events expanded to one
    /// entry per occurrence. Calendars hidden in Settings are excluded.
    func events(from start: Date, to end: Date) -> [DayEvent] {
        guard isConnected else { return [] }
        let hidden = AppSettings.shared.hiddenCalendarIDs
        let visibleCalendars = store.calendars(for: .event)
            .filter { !hidden.contains($0.calendarIdentifier) }
        guard !visibleCalendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visibleCalendars)
        return store.events(matching: predicate).compactMap { event in
            guard let startDate = event.startDate, let endDate = event.endDate else { return nil }
            let color: Color
            if let cgColor = event.calendar?.cgColor {
                color = Color(cgColor: cgColor)
            } else {
                color = Color(red: 1.0, green: 0.38, blue: 0.28)
            }
            return DayEvent(
                // Occurrences of a recurring event share an identifier, so key by date too.
                id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)-\(startDate.timeIntervalSinceReferenceDate)",
                title: event.title ?? "Busy",
                start: startDate,
                end: endDate,
                isAllDay: event.isAllDay,
                color: color
            )
        }
    }
}
