import EventKit
import Observation
import SwiftUI

/// A calendar appointment flattened into a value type so views never touch
/// EventKit objects directly.
struct DayEvent: Identifiable {
    let id: String
    /// The underlying EKEvent identifier, for editing and deleting.
    let eventIdentifier: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    var location: String? = nil
    var notes: String? = nil
    var calendarTitle: String? = nil
    var allowsEditing: Bool = false
}

/// A calendar event proposed by the parser, awaiting user confirmation.
/// Events are never auto-created — they always go through the summary sheet.
struct ParsedEvent {
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
}

/// One device calendar, for the Settings picker. The source (account) name
/// disambiguates same-named calendars that arrive via two routes.
struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let source: String
    let color: Color
}

/// Bridge to the device calendar via EventKit — reads events for the week
/// view and writes user-confirmed events. Google, iCloud and work calendars
/// all arrive through the same store once their accounts are on the phone —
/// no OAuth of our own.
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
                eventIdentifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                title: event.title ?? "Busy",
                start: startDate,
                end: endDate,
                isAllDay: event.isAllDay,
                color: color,
                location: event.location,
                notes: event.notes,
                calendarTitle: event.calendar?.title,
                allowsEditing: event.calendar?.allowsContentModifications ?? false
            )
        }
    }

    // MARK: - Writing

    /// The calendar new events go into: the one picked in Settings if it still
    /// exists and is writable, otherwise the system default.
    var targetCalendarForNewEvents: EKCalendar? {
        guard isConnected else { return nil }
        if let id = AppSettings.shared.defaultEventCalendarID,
           let calendar = store.calendar(withIdentifier: id),
           calendar.allowsContentModifications {
            return calendar
        }
        return store.defaultCalendarForNewEvents
    }

    /// Writable calendars only, for the "new events go to" picker in Settings.
    func writableCalendars() -> [CalendarInfo] {
        guard isConnected else { return [] }
        return store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
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

    @discardableResult
    func createEvent(_ parsed: ParsedEvent) -> Bool {
        guard isConnected, let calendar = targetCalendarForNewEvents else { return false }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = parsed.title
        event.startDate = parsed.start
        event.endDate = parsed.end
        event.isAllDay = parsed.isAllDay
        event.location = parsed.location
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            print("[CalendarService] Failed to create event: \(error)")
            return false
        }
    }

    @discardableResult
    func updateEvent(_ dayEvent: DayEvent, title: String, start: Date, end: Date, isAllDay: Bool, location: String?, notes: String?) -> Bool {
        guard let event = findEvent(for: dayEvent) else { return false }
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.location = (location?.isEmpty ?? true) ? nil : location
        event.notes = (notes?.isEmpty ?? true) ? nil : notes
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            print("[CalendarService] Failed to update event: \(error)")
            return false
        }
    }

    @discardableResult
    func deleteEvent(_ dayEvent: DayEvent) -> Bool {
        guard let event = findEvent(for: dayEvent) else { return false }
        do {
            try store.remove(event, span: .thisEvent)
            return true
        } catch {
            print("[CalendarService] Failed to delete event: \(error)")
            return false
        }
    }

    /// Finds the concrete EKEvent occurrence behind a DayEvent. A predicate
    /// lookup around the occurrence's own start date is needed because
    /// event(withIdentifier:) returns the first occurrence of a recurring
    /// series, not the tapped one.
    private func findEvent(for dayEvent: DayEvent) -> EKEvent? {
        guard isConnected else { return nil }
        let windowStart = dayEvent.start.addingTimeInterval(-1)
        let windowEnd = max(dayEvent.end, dayEvent.start.addingTimeInterval(1))
        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
        if let match = store.events(matching: predicate).first(where: {
            $0.eventIdentifier == dayEvent.eventIdentifier && $0.startDate == dayEvent.start
        }) {
            return match
        }
        return store.event(withIdentifier: dayEvent.eventIdentifier)
    }
}
