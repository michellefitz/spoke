import SwiftUI

/// Half sheet that rises behind the voice orb when the assistant has something
/// to say: a summary of a braindump to confirm, or a clarifying question.
/// The task list stays visible above it; the orb stays live on top of it.
struct AssistantSheetView: View {
    enum Mode {
        case summary(remark: String?, actions: [ParsedAction])
        case clarify(text: String, options: [String])
    }

    let mode: Mode
    let bottomInset: CGFloat
    let onConfirm: () -> Void
    let onAdjust: () -> Void
    let onOption: (String) -> Void
    let onClose: () -> Void

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 14)

            switch mode {
            case .summary(let remark, let actions):
                summaryBody(remark: remark, actions: actions)
            case .clarify(let text, let options):
                clarifyBody(text: text, options: options)
            }
        }
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 24, y: -6)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 26, height: 26)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .padding(.top, 10)
            .padding(.trailing, 14)
        }
    }

    // MARK: - Summary mode

    @ViewBuilder
    private func summaryBody(remark: String?, actions: [ParsedAction]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(remark ?? "Got \(actions.count) task\(actions.count == 1 ? "" : "s").")
                .font(.system(size: 16))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)
                .padding(.trailing, 52) // clear the ✕ button

            previewList(actions)
                .padding(.top, 10)

            footerSeparator

            HStack(spacing: 10) {
                Button(action: onAdjust) {
                    footerLabel("Adjust", fill: Color(.tertiarySystemFill), foreground: .primary)
                }
                Button(action: onConfirm) {
                    footerLabel("Looks good", fill: coral, foreground: .white)
                }
            }
            .buttonStyle(PressScaleButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 12)

            voiceHint("…or just say \u{201C}yep\u{201D}")
        }
    }

    // MARK: - Clarify mode

    @ViewBuilder
    private func clarifyBody(text: String, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 16))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)
                .padding(.trailing, 52) // clear the ✕ button

            HStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button { onOption(option) } label: {
                        footerLabel(
                            option,
                            fill: index == options.count - 1 ? coral : Color(.tertiarySystemFill),
                            foreground: index == options.count - 1 ? .white : .primary
                        )
                    }
                }
            }
            .buttonStyle(PressScaleButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 18)

            voiceHint("…or just answer out loud")
        }
    }

    // MARK: - Preview list

    /// All parsed tasks are always visible — no click-to-expand. Small braindumps
    /// keep the sheet short; larger ones grow it toward full screen and scroll inside.
    @ViewBuilder
    private func previewList(_ actions: [ParsedAction]) -> some View {
        if actions.count > 4 {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        previewRow(action)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 460)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    previewRow(action)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func previewRow(_ action: ParsedAction) -> some View {
        let task: ParsedTask
        let isEdit: Bool
        switch action {
        case .create(let t): task = t; isEdit = false
        case .edit(_, let updates): task = updates; isEdit = true
        }

        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .strokeBorder(Color(.systemGray4), lineWidth: 1.8)
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 15))
                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineSpacing(2)
                        .lineLimit(8)
                }
                HStack(spacing: 6) {
                    if isEdit {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                            Text("updating existing task")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(coral)
                    }
                    if task.deadline != nil {
                        chip(deadlineLabel(task), tinted: true)
                    }
                    if let tag = task.tag {
                        chip(tag.uppercased(), tinted: false)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    // MARK: - Pieces

    private func chip(_ label: String, tinted: Bool) -> some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tinted ? coral.opacity(0.14) : Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(tinted ? coral : Color(.secondaryLabel))
    }

    private var footerSeparator: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(height: 0.5)
            .padding(.top, 14)
    }

    private func footerLabel(_ text: String, fill: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(fill, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(foreground)
    }

    private func voiceHint(_ label: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(coral.opacity(0.7))
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func deadlineLabel(_ task: ParsedTask) -> String {
        guard let date = task.deadline else { return "" }
        let cal = Calendar.current
        if task.deadlineIsWeek {
            let week = cal.weekStart(for: date)
            let thisWeek = cal.weekStart(for: .now)
            if week == thisWeek { return "This week" }
            if let next = cal.date(byAdding: .weekOfYear, value: 1, to: thisWeek), week == next { return "Next week" }
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            return "Week of " + formatter.string(from: week)
        }
        if cal.isDateInToday(date) { return "Due today" }
        if cal.isDateInTomorrow(date) { return "Due tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return "Due " + formatter.string(from: date)
    }
}
