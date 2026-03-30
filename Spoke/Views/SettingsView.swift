import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var tagStore: TagStore

    @State private var isAddingTag = false
    @State private var newTagName = ""
    @FocusState private var isNewTagFieldFocused: Bool

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tagStore.tags, id: \.self) { tag in
                        HStack {
                            Button {
                                withAnimation {
                                    tagStore.removeTag(tag)
                                }
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

                            Button {
                                commitNewTag()
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(coral)
                            }
                            .buttonStyle(.plain)
                            .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        Button {
                            withAnimation {
                                isAddingTag = true
                            }
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
                    Text("Tags")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(coral)
                }
            }
        }
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
