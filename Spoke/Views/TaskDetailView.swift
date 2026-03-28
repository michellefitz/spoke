import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let task: SpokeTask

    @State private var recorder = VoiceRecorder()
    @State private var showPermissionAlert = false
    @State private var tapModeActive = false

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
    @AppStorage("hasEditedTask") private var hasEditedTask = false

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(task.title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 28)
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.3), value: task.title)

            if let deadline = task.deadline {
                Text(Self.deadlineFormatter.string(from: deadline).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(coral)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(coral.opacity(0.12))
                    )
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
                    .animation(.easeInOut(duration: 0.2), value: deadline)
            }

            if let desc = task.taskDescription, !desc.isEmpty {
                DescriptionItemsView(description: desc) { updated in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        task.taskDescription = updated
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .padding(.top, 20)
                .padding(.horizontal, 24)
                .transition(.opacity)
            }

            Spacer()

            VStack(spacing: 6) {
                if task.isCompleted, let completedAt = task.completedAt {
                    Text("Completed \(relativeFormatter.localizedString(for: completedAt, relativeTo: .now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Added \(task.createdAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            VStack(spacing: 8) {
                VoiceButton(
                    state: voiceButtonState,
                    audioLevel: recorder.audioLevel,
                    onStart: handleStart,
                    onRelease: handleRelease
                )
                .frame(maxWidth: .infinity)

                Group {
                    if recorder.recordingState == .recording {
                        Text("Listening...")
                            .font(.caption)
                            .foregroundStyle(coral)
                    } else if recorder.recordingState == .idle && !hasEditedTask {
                        Text("Tap or hold to edit task")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: recorder.recordingState)
            }
            .padding(.bottom, 24)
        }
        .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Spoke needs microphone and speech recognition access. Please enable them in Settings.")
        }
    }

    // MARK: - Voice

    private var voiceButtonState: VoiceButtonState {
        switch recorder.recordingState {
        case .idle:       .idle
        case .recording:  .recording
        case .processing: .processing
        }
    }

    private func handleStart() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard recorder.recordingState == .idle else { return }
        Task {
            let granted = await recorder.requestPermissionsIfNeeded()
            guard granted else {
                showPermissionAlert = true
                return
            }
            do {
                try recorder.startRecording()
            } catch {
                recorder.finishProcessing()
            }
        }
    }

    private func handleRelease(elapsed: TimeInterval) {
        switch recorder.recordingState {
        case .recording:
            if tapModeActive {
                tapModeActive = false
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                stopAndProcess()
            } else if elapsed < 0.3 {
                tapModeActive = true
            } else {
                tapModeActive = false
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                stopAndProcess()
            }
        default:
            tapModeActive = false
        }
    }

    private func stopAndProcess() {
        let transcript = recorder.stopRecording()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recorder.finishProcessing()
            return
        }
        Task {
            let parsed = await TaskParser.parseEdit(
                transcript: transcript,
                currentTitle: task.title,
                currentDescription: task.taskDescription,
                currentDeadline: task.deadline,
                currentTag: task.tag
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                task.title = parsed.title
                task.taskDescription = parsed.description
                task.deadline = parsed.deadline
                task.tag = parsed.tag
            }
            recorder.finishProcessing()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            hasEditedTask = true
        }
    }
}

// MARK: - Description items

/// Renders a description string as interactive checkmark rows.
/// Bullet lines start with "• " (unchecked) or "✓ " (checked).
/// Plain-prose lines are shown as non-interactive text.
private struct DescriptionItemsView: View {
    let description: String
    let onToggle: (String) -> Void

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    private struct Item {
        let lineIndex: Int   // index in original \n-split array
        let text: String
        let checked: Bool
        let isBullet: Bool
    }

    private var items: [Item] {
        description
            .components(separatedBy: "\n")
            .enumerated()
            .compactMap { i, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return nil }
                if line.hasPrefix("✓ ") {
                    return Item(lineIndex: i, text: String(line.dropFirst(2)), checked: true,  isBullet: true)
                } else if line.hasPrefix("• ") {
                    return Item(lineIndex: i, text: String(line.dropFirst(2)), checked: false, isBullet: true)
                } else {
                    return Item(lineIndex: i, text: line, checked: false, isBullet: false)
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.lineIndex) { item in
                if item.isBullet {
                    Button {
                        onToggle(toggled(at: item.lineIndex))
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(item.checked ? coral : Color(.tertiaryLabel))
                                .animation(.easeInOut(duration: 0.2), value: item.checked)

                            Text(item.text)
                                .font(.body)
                                .foregroundStyle(.primary.opacity(0.75))
                                .strikethrough(item.checked, color: .secondary)
                                .opacity(item.checked ? 0.4 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: item.checked)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(item.text)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.75))
                }
            }
        }
    }

    /// Returns a new description string with the item at `lineIndex` toggled.
    private func toggled(at lineIndex: Int) -> String {
        var lines = description.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return description }
        let line = lines[lineIndex]
        if line.hasPrefix("✓ ") {
            lines[lineIndex] = "• " + line.dropFirst(2)
        } else if line.hasPrefix("• ") {
            lines[lineIndex] = "✓ " + line.dropFirst(2)
        }
        return lines.joined(separator: "\n")
    }
}
