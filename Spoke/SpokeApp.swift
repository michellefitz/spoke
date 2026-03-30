import SwiftUI
import SwiftData

@main
struct SpokeApp: App {
    private let settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            if settings.hasCompletedOnboarding {
                ContentView()
                    .modelContainer(for: SpokeTask.self)
            } else {
                OnboardingView()
                    .modelContainer(for: SpokeTask.self)
            }
        }
    }
}
