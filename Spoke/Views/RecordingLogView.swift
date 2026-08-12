import SwiftUI

/// Every recording, what Spoke heard, and what it made of it. Built for
/// answering "did it actually hear me?" — so a recording that produced
/// nothing still gets a row, with the reason attached.
struct RecordingLogView: View {
    private let logger = TaskParserLogger.shared
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    @Environment(\.dismiss) private var dismiss
    @State private var exportedURL: URL?
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if logger.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(logger.entries) { entry in
                                NavigationLink {
                                    RecordingDetailView(entry: entry)
                                } label: {
                                    row(entry)
                                }
                            }
                        } footer: {
                            Text("The last 100 recordings, kept on this iPhone only.")
                                .font(.footnote)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(coral)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let url = exportedURL {
                            ShareLink(item: url) {
                                Label("Share CSV", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button {
                            exportedURL = logger.exportCSV()
                        } label: {
                            Label("Prepare CSV", systemImage: "doc.text")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Clear history", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(coral)
                    }
                    .disabled(logger.entries.isEmpty)
                }
            }
            .confirmationDialog("Clear all recordings?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { logger.clearAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This only clears the history. Your tasks stay where they are.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 28))
                .foregroundStyle(Color(.tertiaryLabel))
            Text("Nothing recorded yet")
                .font(.system(size: 15, weight: .medium))
            Text("Every time you talk to Spoke, it'll show up here with what it heard.")
                .font(.system(size: 13))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func row(_ entry: ParserLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.secondaryLabel))
                if entry.recording?.endedEarly == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(taskSummary(entry))
                    .font(.system(size: 11))
                    .foregroundStyle(entry.parsedTasks.isEmpty ? .orange : Color(.secondaryLabel))
            }
            Text(entry.transcript.isEmpty ? "Nothing heard" : entry.transcript)
                .font(.system(size: 14))
                .foregroundStyle(entry.transcript.isEmpty ? Color(.tertiaryLabel) : .primary)
                .italic(entry.transcript.isEmpty)
                .lineLimit(2)
            if !entry.parsedTasks.isEmpty {
                Text(entry.parsedTasks.map(\.title).joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private func taskSummary(_ entry: ParserLogEntry) -> String {
        let count = entry.parsedTasks.count
        if count == 0 { return "no tasks" }
        return "\(count) task\(count == 1 ? "" : "s")"
    }
}

// MARK: - Detail

private struct RecordingDetailView: View {
    let entry: ParserLogEntry
    @State private var showTechnical = false

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    var body: some View {
        List {
            if let explanation = entry.recording?.explanation {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                        Text(explanation)
                            .font(.system(size: 13))
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("What you said") {
                if entry.transcript.isEmpty {
                    Text("Nothing was heard.")
                        .font(.system(size: 14))
                        .italic()
                        .foregroundStyle(Color(.secondaryLabel))
                } else {
                    Text(entry.transcript)
                        .font(.system(size: 15))
                        .textSelection(.enabled)
                }
            }

            Section("What Spoke created") {
                if entry.parsedTasks.isEmpty {
                    Text(entry.transcript.isEmpty
                         ? "Nothing, because nothing was heard."
                         : "Nothing — Spoke heard you but didn't find a task in it.")
                        .font(.system(size: 14))
                        .italic()
                        .foregroundStyle(Color(.secondaryLabel))
                } else {
                    ForEach(Array(entry.parsedTasks.enumerated()), id: \.offset) { _, task in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(.system(size: 15, weight: .medium))
                            if let desc = task.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                            HStack(spacing: 8) {
                                if let deadline = task.deadline {
                                    Label(deadline, systemImage: "calendar")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(coral)
                                }
                                if let tag = task.tag {
                                    Text(tag.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color(.secondaryLabel))
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let rec = entry.recording {
                Section("Recording") {
                    LabeledContent("Length", value: String(format: "%.1fs", Double(rec.durationMs) / 1000))
                    LabeledContent("Phrases heard", value: "\(rec.finalSegments)")
                    LabeledContent("Finished", value: rec.endedEarly ? "Cut short" : "Normally")
                }
            }

            Section {
                DisclosureGroup("Technical details", isExpanded: $showTechnical) {
                    VStack(alignment: .leading, spacing: 10) {
                        detail("When", entry.timestamp.formatted())
                        detail("Mode", entry.mode)
                        detail("Parse time", "\(entry.durationMs)ms")
                        if let error = entry.error {
                            detail("Error", error, tint: .red)
                        }
                        if let response = entry.claudeResponse {
                            detail("Response", response, monospaced: true)
                        }
                        if !entry.systemPrompt.isEmpty {
                            detail("System prompt", entry.systemPrompt, monospaced: true)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 13))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ label: String, _ value: String, monospaced: Bool = false, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(.secondaryLabel))
            Text(value)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
        }
    }
}
