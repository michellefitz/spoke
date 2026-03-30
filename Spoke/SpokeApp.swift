import SwiftUI
import SwiftData

@main
struct SpokeApp: App {
    private let settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: SpokeTask.self)
                .fullScreenCover(isPresented: .constant(!settings.hasCompletedOnboarding)) {
                    OnboardingView()
                }
        }
    }
}
