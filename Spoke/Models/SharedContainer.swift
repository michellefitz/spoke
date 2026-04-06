import Foundation
import SwiftData

enum SharedContainer {
    static let appGroupID = "group.com.michellefitzpatrick.Spoke"

    static var url: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return groupURL
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static var modelContainer: ModelContainer {
        let config = ModelConfiguration(url: url.appendingPathComponent("Spoke.sqlite"))
        return try! ModelContainer(for: SpokeTask.self, configurations: config)
    }
}
