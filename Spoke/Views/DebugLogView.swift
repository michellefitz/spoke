import SwiftUI

struct DebugLogView: View {
    private let logger = TaskParserLogger.shared
    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            List {
                // Stats
                Section {
                    HStack {
                        Text("Total entries")
                        Spacer()
                        Text("\(logger.entries.count)")
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    let creates = logger.entries.filter { $0.mode == "create" }.count
                    let edits = logger.entries.filter { $0.mode == "edit" }.count
                    HStack {
                        Text("Creates / Edits")
                        Spacer()
                        Text("\(creates) / \(edits)")
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    let errors = logger.entries.filter { $0.error != nil }.count
                    HStack {
                        Text("Errors")
                        Spacer()
                        Text("\(errors)")
                            .foregroundStyle(errors > 0 ? coral : Color(.secondaryLabel))
                    }
                } header: {
                    Text("Overview")
                }

                // Entries
                Section {
                    if logger.entries.isEmpty {
                        Text("No logs yet. Create or edit a task to see entries.")
                            .font(.subheadline)
                            .foregroundStyle(Color(.secondaryLabel))
                    } else {
                        ForEach(logger.entries) { entry in
                            NavigationLink {
                                LogDetailView(entry: entry)
                            } label: {
                                logRow(entry)
                            }
                        }
                    }
                } header: {
                    Text("Recent (\(logger.entries.count))")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Parser Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            if let url = logger.exportCSV() {
                                shareURL = url
                                showShareSheet = true
                            }
                        } label: {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            logger.clearAll()
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(coral)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(url: url)
                }
            }
        }
    }

    private func logRow(_ entry: ParserLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.mode.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(entry.mode == "create" ? coral : Color(.secondaryLabel))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(entry.mode == "create" ? coral.opacity(0.12) : Color(.tertiarySystemFill))
                    )
                Text("\(entry.parsedTasks.count) task\(entry.parsedTasks.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.secondaryLabel))
                Spacer()
                Text("\(entry.durationMs)ms")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            Text(entry.transcript)
                .font(.system(size: 13))
                .lineLimit(2)
            if let error = entry.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            Text(entry.parsedTasks.map { $0.title }.joined(separator: " → "))
                .font(.system(size: 11))
                .foregroundStyle(Color(.tertiaryLabel))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Log detail

private struct LogDetailView: View {
    let entry: ParserLogEntry

    var body: some View {
        List {
            Section("Transcript") {
                Text(entry.transcript)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
            }

            Section("Parsed Tasks") {
                ForEach(Array(entry.parsedTasks.enumerated()), id: \.offset) { i, task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 14, weight: .semibold))
                        if let desc = task.description {
                            Text(desc)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                        HStack(spacing: 8) {
                            if let deadline = task.deadline {
                                Text(deadline)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                            if let tag = task.tag {
                                Text(tag.uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                        }
                    }
                }
            }

            Section("Claude Response") {
                Text(entry.claudeResponse ?? "(not captured)")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("System Prompt") {
                Text(entry.systemPrompt)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("Metadata") {
                LabeledContent("Mode", value: entry.mode)
                LabeledContent("Duration", value: "\(entry.durationMs)ms")
                LabeledContent("Timestamp", value: entry.timestamp.formatted())
                if let error = entry.error {
                    LabeledContent("Error", value: error)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Log Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Share sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
