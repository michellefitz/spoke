import SwiftUI
import SwiftData

// Very dark grey for dark mode instead of pure black
private let darkBackground = Color(red: 0.07, green: 0.07, blue: 0.07)

@main
struct SpokeApp: App {
    @Environment(\.colorScheme) private var colorScheme
    private let settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if settings.hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .background(colorScheme == .dark ? darkBackground : Color(.systemBackground))
            .preferredColorScheme(nil) // respect system setting
        }
        .modelContainer(for: SpokeTask.self)
    }
}
