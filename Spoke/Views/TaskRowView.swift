import SwiftUI

struct TaskRowView: View {
    let task: SpokeTask
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    @State private var strikeProgress: CGFloat = 0
    @State private var isAnimating = false
    @State private var pendingComplete = false

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    private var subtaskCounts: (done: Int, total: Int)? {
        guard let desc = task.taskDescription else { return nil }
        let lines = desc.components(separatedBy: "\n")
        let total = lines.filter { $0.hasPrefix("• ") || $0.hasPrefix("✓ ") }.count
        guard total > 0 else { return nil }
        let done = lines.filter { $0.hasPrefix("✓ ") }.count
        return (done, total)
    }

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Button(action: handleCompleteToggle) {
                let filled = task.isCompleted || pendingComplete
                Image(systemName: filled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(filled ? coral : Color(.tertiaryLabel))
                    .animation(.easeInOut(duration: 0.15), value: filled)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 16))
                .strikethrough(task.isCompleted)
                .opacity(task.isCompleted ? 0.45 : 1.0)
                .overlay {
                    // Animated strikethrough that draws left → right, following text lines
                    Text(task.title)
                        .font(.system(size: 16))
                        .foregroundStyle(.clear)
                        .strikethrough(true, color: Color.primary.opacity(0.45))
                        .mask(
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: geo.size.width * strikeProgress)
                            }
                        )
                }

            Spacer()

            HStack(spacing: 4) {
                if let tag = task.tag {
                    Text(tag.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(task.isCompleted ? Color(.secondaryLabel).opacity(0.4) : Color(.secondaryLabel))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.tertiarySystemFill).opacity(task.isCompleted ? 0.5 : 1.0))
                        )
                }

                if let deadline = task.deadline {
                    Text(Self.deadlineFormatter.string(from: deadline).uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(task.isCompleted ? coral.opacity(0.4) : coral)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(coral.opacity(task.isCompleted ? 0.06 : 0.12))
                        )
                }
            }

            let showChevron = !task.isCompleted && !(task.taskDescription ?? "").isEmpty
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
                .opacity(showChevron ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        // Swipe right → delete
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !task.isCompleted {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        // Swipe left → complete / uncomplete
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onToggleComplete) {
                if task.isCompleted {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                } else {
                    Label("Done", systemImage: "checkmark")
                }
            }
            .tint(task.isCompleted ? .orange : .green)
        }
    }

    // MARK: - Completion

    private func handleCompleteToggle() {
        if task.isCompleted {
            // Uncomplete → immediate, no animation needed
            onToggleComplete()
        } else {
            // Complete → show checkmark + draw strikethrough simultaneously,
            // then move the row to the completed section.
            guard !isAnimating else { return }
            isAnimating = true

            // 1. Checkmark fills in immediately; strikethrough draws left → right
            withAnimation(.easeInOut(duration: 0.15)) { pendingComplete = true }
            withAnimation(.linear(duration: 0.38)) { strikeProgress = 1.0 }

            // 2. After the line lands, trigger the section move
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pendingComplete = false  // task.isCompleted takes over from here
                onToggleComplete()
                // Reset in case the row isn't destroyed (e.g. uncomplete mid-flight)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    strikeProgress = 0
                    isAnimating = false
                }
            }
        }
    }
}

#Preview {
    List {
        TaskRowView(
            task: SpokeTask(title: "Book karate class for Alex", taskDescription: "• Find local dojos", deadline: Calendar.current.date(byAdding: .day, value: 7, to: .now), tag: "personal"),
            onToggleComplete: {},
            onDelete: {},
            onTap: {}
        )
        TaskRowView(
            task: SpokeTask(title: "Pick up groceries", tag: "errands"),
            onToggleComplete: {},
            onDelete: {},
            onTap: {}
        )
        TaskRowView(
            task: {
                let t = SpokeTask(title: "File taxes", tag: "finance")
                t.isCompleted = true
                t.completedAt = Date.now.addingTimeInterval(-3600)
                return t
            }(),
            onToggleComplete: {},
            onDelete: {},
            onTap: {}
        )
    }
    .modelContainer(for: SpokeTask.self, inMemory: true)
}
