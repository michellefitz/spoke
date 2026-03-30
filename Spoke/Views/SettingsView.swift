import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var tagStore: TagStore
    private let settings = AppSettings.shared

    @State private var isAddingTag = false
    @State private var newTagName = ""
    @FocusState private var isNewTagFieldFocused: Bool

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    var body: some View {
        NavigationStack {
            List {
                // MARK: Mode
                Section {
                    Picker("Mode", selection: Binding(
                        get: { settings.appMode },
                        set: { settings.appMode = $0 }
                    )) {
                        Text("Simple").tag(AppMode.simple)
                        Text("Organized").tag(AppMode.organized)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    sectionHeader("Mode")
                } footer: {
                    Text(settings.appMode == .simple
                         ? "Just capture tasks. No tags, dates, or categories."
                         : "Full features with customisable display options.")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                }

                // MARK: Display (Organized only)
                if settings.appMode == .organized {
                    Section {
                        Toggle(isOn: Binding(
                            get: { settings.showTags },
                            set: { settings.showTags = $0 }
                        )) {
                            Text("Show tags")
                        }
                        .tint(coral)

                        Toggle(isOn: Binding(
                            get: { settings.showDueDates },
                            set: { settings.showDueDates = $0 }
                        )) {
                            Text("Show due dates")
                        }
                        .tint(coral)

                        Toggle(isOn: Binding(
                            get: { settings.expandSubtasks },
                            set: { settings.expandSubtasks = $0 }
                        )) {
                            Text("Expand subtasks in list")
                        }
                        .tint(coral)
                    } header: {
                        sectionHeader("Display")
                    }

                    // MARK: Tags (Organized only)
                    Section {
                        ForEach(tagStore.tags, id: \.self) { tag in
                            HStack {
                                Button {
                                    withAnimation { tagStore.removeTag(tag) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(coral)
                                }
                                .buttonStyle(.plain)

                                Text(tag.uppercased())
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary.opacity(0.8))

                                Spacer()
                            }
                        }
                        .onMove { tagStore.moveTag(from: $0, to: $1) }

                        if isAddingTag {
                            HStack {
                                TextField("New tag", text: $newTagName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($isNewTagFieldFocused)
                                    .onSubmit { commitNewTag() }

                                Button { commitNewTag() } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(coral)
                                }
                                .buttonStyle(.plain)
                                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else {
                            Button {
                                withAnimation { isAddingTag = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isNewTagFieldFocused = true
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Add Tag")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(coral)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        sectionHeader("Tags")
                    }
                }

                // MARK: Data
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.autoDeleteCompleted },
                        set: { settings.autoDeleteCompleted = $0 }
                    )) {
                        Text("Auto-delete completed tasks")
                    }
                    .tint(coral)
                } header: {
                    sectionHeader("Data")
                } footer: {
                    Text("Completed tasks older than 14 days are removed automatically.")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(coral)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.7))
    }

    private func commitNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            tagStore.addTag(trimmed)
            newTagName = ""
            isAddingTag = false
        }
    }
}
