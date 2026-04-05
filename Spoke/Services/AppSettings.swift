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
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.autoDeleteCompleted   = defaults.object(forKey: "autoDeleteCompleted")   as? Bool ?? true
        self.hasSeenCoaching       = defaults.bool(forKey: "hasSeenCoaching")
        self.completedExpanded     = defaults.bool(forKey: "completedExpanded")
    }
}
