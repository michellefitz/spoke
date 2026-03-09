import SwiftUI

struct TaskRowView: View {
    let task: SpokeTask
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    @State private var strikeProgress: CGFloat = 0
    @State private var isAnimating = false

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

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
                    // Animated line that draws left → right before the row moves
                    Rectangle()
                        .fill(Color.primary.opacity(0.45))
                        .frame(height: 1.5)
                        .scaleEffect(x: strikeProgress, anchor: .leading)
                }

            Spacer()

            if !task.isCompleted,
               let desc = task.taskDescription, !desc.isEmpty {
                Circle()
                    .fill(coral)
                    .frame(width: 6, height: 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        // Swipe right → complete / uncomplete (immediate, no pre-animation)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onToggleComplete) {
                if task.isCompleted {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                } else {
                    Label("Done", systemImage: "checkmark")
                }
            }
            .tint(task.isCompleted ? .orange : .green)
        }
        // Swipe left → delete
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !task.isCompleted {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
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
