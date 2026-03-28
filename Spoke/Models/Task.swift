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
    var deadline: Date?
    var tag: String?

    init(title: String, taskDescription: String? = nil, deadline: Date? = nil, tag: String? = nil) {
        self.id = UUID()
        self.title = title
        self.taskDescription = taskDescription
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = .now
        self.deadline = deadline
        self.tag = tag
    }
}
