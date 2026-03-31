import Foundation
import Observation

enum AppMode: String {
    case simple
    case organized
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var appMode: AppMode {
        didSet { defaults.set(appMode.rawValue, forKey: "appMode") }
    }

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

    init() {
        if let raw = defaults.string(forKey: "appMode"),
           let mode = AppMode(rawValue: raw) {
            self.appMode = mode
        } else {
            self.appMode = .simple
        }
        self.showTags              = defaults.object(forKey: "showTags")              as? Bool ?? true
        self.showDueDates          = defaults.object(forKey: "showDueDates")          as? Bool ?? true
        self.expandSubtasks        = defaults.object(forKey: "expandSubtasks")        as? Bool ?? false
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.autoDeleteCompleted   = defaults.object(forKey: "autoDeleteCompleted")   as? Bool ?? true
        self.hasSeenCoaching       = defaults.bool(forKey: "hasSeenCoaching")
    }
}
