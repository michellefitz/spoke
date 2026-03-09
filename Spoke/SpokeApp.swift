import SwiftUI
import SwiftData

@main
struct SpokeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: SpokeTask.self)
        }
    }
}
