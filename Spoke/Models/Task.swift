import Foundation
import SwiftData

@Model
class SpokeTask {
    var id: UUID
    var title: String
    var taskDescription: String?
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date

    init(title: String, taskDescription: String? = nil) {
        self.id = UUID()
        self.title = title
        self.taskDescription = taskDescription
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = .now
    }
}
