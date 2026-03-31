import Foundation
import Observation

@Observable
final class TagStore {
    static let shared = TagStore()

    private let key = "spoke_allowed_tags"
    private let defaults = UserDefaults.standard

    private static let defaultTags = ["personal", "work", "shopping", "health", "finance"]

    var tags: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(tags) {
                defaults.set(data, forKey: key)
            }
        }
    }

    init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.tags = decoded
        } else {
            self.tags = Self.defaultTags
            if let data = try? JSONEncoder().encode(Self.defaultTags) {
                defaults.set(data, forKey: key)
            }
        }
    }

    func addTag(_ name: String) {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !tags.contains(normalized) else { return }
        tags.append(normalized)
    }

    func removeTag(_ name: String) {
        tags.removeAll { $0 == name }
    }

    func moveTag(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
    }
}
