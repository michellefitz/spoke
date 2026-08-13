import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var showTags: Bool {
        didSet { defaults.set(showTags, forKey: "showTags") }
    }

    var showDueDates: Bool {
        didSet { defaults.set(showDueDates, forKey: "showDueDates") }
    }

    var expandSubtasks: Bool {
        didSet { defaults.set(expandSubtasks, forKey: "expandSubtasks") }
    }

    var showUndatedInCalendar: Bool {
        didSet { defaults.set(showUndatedInCalendar, forKey: "showUndatedInCalendar") }
    }

    var showCompletedInCalendar: Bool {
        didSet { defaults.set(showCompletedInCalendar, forKey: "showCompletedInCalendar") }
    }

    /// Runs Apple's on-device engine alongside Deepgram so the two
    /// transcripts can be compared in the recording log. Costs a little
    /// battery and changes nothing about what the app does with your words.
    var compareTranscription: Bool {
        didSet { defaults.set(compareTranscription, forKey: "compareTranscription") }
    }

    var showCalendarEvents: Bool {
        didSet { defaults.set(showCalendarEvents, forKey: "showCalendarEvents") }
    }

    var calendarPromptDismissed: Bool {
        didSet { defaults.set(calendarPromptDismissed, forKey: "calendarPromptDismissed") }
    }

    /// Calendars unticked in Settings; everything else stays visible so new
    /// calendars show up by default.
    var hiddenCalendarIDs: Set<String> {
        didSet { defaults.set(Array(hiddenCalendarIDs), forKey: "hiddenCalendarIDs") }
    }

    /// Where new events created from Spoke go. Nil means the system default.
    var defaultEventCalendarID: String? {
        didSet { defaults.set(defaultEventCalendarID, forKey: "defaultEventCalendarID") }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var autoDeleteCompleted: Bool {
        didSet { defaults.set(autoDeleteCompleted, forKey: "autoDeleteCompleted") }
    }

    var hasSeenCoaching: Bool {
        didSet { defaults.set(hasSeenCoaching, forKey: "hasSeenCoaching") }
    }

    var completedExpanded: Bool {
        didSet { defaults.set(completedExpanded, forKey: "completedExpanded") }
    }

    init() {
        self.showTags              = defaults.object(forKey: "showTags")              as? Bool ?? true
        self.showDueDates          = defaults.object(forKey: "showDueDates")          as? Bool ?? true
        self.expandSubtasks        = defaults.object(forKey: "expandSubtasks")        as? Bool ?? false
        self.showUndatedInCalendar = defaults.object(forKey: "showUndatedInCalendar") as? Bool ?? true
        self.showCompletedInCalendar = defaults.object(forKey: "showCompletedInCalendar") as? Bool ?? false
        self.showCalendarEvents    = defaults.object(forKey: "showCalendarEvents")    as? Bool ?? true
        self.compareTranscription  = defaults.object(forKey: "compareTranscription")  as? Bool ?? true
        self.calendarPromptDismissed = defaults.bool(forKey: "calendarPromptDismissed")
        self.hiddenCalendarIDs     = Set(defaults.stringArray(forKey: "hiddenCalendarIDs") ?? [])
        self.defaultEventCalendarID = defaults.string(forKey: "defaultEventCalendarID")
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.autoDeleteCompleted   = defaults.object(forKey: "autoDeleteCompleted")   as? Bool ?? true
        self.hasSeenCoaching       = defaults.bool(forKey: "hasSeenCoaching")
        self.completedExpanded     = defaults.bool(forKey: "completedExpanded")
    }
}
