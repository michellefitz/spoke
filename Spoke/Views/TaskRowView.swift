import SwiftUI

struct TaskRowView: View {
    let task: SpokeTask
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    @State private var strikeProgress: CGFloat = 0
    @State private var isAnimating = false

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Button(action: handleCompleteToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(task.isCompleted ? coral : Color(.tertiaryLabel))
                    .animation(.easeInOut(duration: 0.15), value: task.isCompleted)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.body)
                .strikethrough(task.isCompleted)
                .opacity(task.isCompleted ? 0.45 : 1.0)
                .overlay {
                    // Animated strikethrough that draws left → right, following text lines
                    Text(task.title)
                        .font(.body)
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

            if !task.isCompleted,
               let desc = task.taskDescription, !desc.isEmpty {
                Image(systemName: "note.text")
                    .font(.system(size: 11))
                    .foregroundStyle(coral.opacity(0.7))
            }
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
            // Complete → draw line first, then move row to completed section
            guard !isAnimating else { return }
            isAnimating = true

            // 1. Draw the strikethrough line left → right
            withAnimation(.linear(duration: 0.38)) {
                strikeProgress = 1.0
            }

            // 2. After the line lands, trigger the section move
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
