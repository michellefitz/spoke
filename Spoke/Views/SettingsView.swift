import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var tagStore: TagStore
    private let settings = AppSettings.shared

    @State private var isAddingTag = false
    @State private var newTagName = ""
    @State private var showRecordingLog = false
    @FocusState private var isNewTagFieldFocused: Bool

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    var body: some View {
        NavigationStack {
            List {
                // MARK: Display
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

                    Toggle(isOn: Binding(
                        get: { settings.showUndatedInCalendar },
                        set: { settings.showUndatedInCalendar = $0 }
                    )) {
                        Text("Show undated tasks in calendar view")
                    }
                    .tint(coral)

                    Toggle(isOn: Binding(
                        get: { settings.showCompletedInCalendar },
                        set: { settings.showCompletedInCalendar = $0 }
                    )) {
                        Text("Show completed tasks in calendar view")
                    }
                    .tint(coral)

                    Toggle(isOn: Binding(
                        get: { settings.showCalendarEvents },
                        set: { newValue in
                            settings.showCalendarEvents = newValue
                            if newValue && CalendarService.shared.canRequestAccess {
                                Task { await CalendarService.shared.requestAccess() }
                            }
                        }
                    )) {
                        Text("Show calendar events in calendar view")
                    }
                    .tint(coral)
                } header: {
                    sectionHeader("Display")
                } footer: {
                    if settings.showCalendarEvents && CalendarService.shared.isDenied {
                        Text("Calendar access is turned off for Spoke. Allow it in iOS Settings → Privacy & Security → Calendars.")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }

                // MARK: Calendars
                if settings.showCalendarEvents && CalendarService.shared.isConnected {
                    Section {
                        ForEach(CalendarService.shared.availableCalendars()) { calendar in
                            Toggle(isOn: Binding(
                                get: { !settings.hiddenCalendarIDs.contains(calendar.id) },
                                set: { visible in
                                    if visible {
                                        settings.hiddenCalendarIDs.remove(calendar.id)
                                    } else {
                                        settings.hiddenCalendarIDs.insert(calendar.id)
                                    }
                                }
                            )) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(calendar.color)
                                        .frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(calendar.title)
                                        Text(calendar.source)
                                            .font(.footnote)
                                            .foregroundStyle(Color(.secondaryLabel))
                                    }
                                }
                            }
                            .tint(coral)
                        }
                    } header: {
                        sectionHeader("Calendars")
                    } footer: {
                        Text("Appointments from unticked calendars stay out of the week view. If everything shows up twice, the same calendar is probably syncing through two accounts — untick one.")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }

                    Section {
                        Picker(selection: Binding(
                            get: { settings.defaultEventCalendarID ?? "" },
                            set: { settings.defaultEventCalendarID = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("System default").tag("")
                            ForEach(CalendarService.shared.writableCalendars()) { calendar in
                                Text("\(calendar.title) (\(calendar.source))").tag(calendar.id)
                            }
                        } label: {
                            Text("New events go to")
                        }
                        .tint(coral)
                    } footer: {
                        Text("Events you create with your voice are added to this calendar, always after you confirm them.")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }

                // MARK: Tags
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
                    Text("Completed tasks are cleared after 14 days.")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                }

                // MARK: Recordings
                Section {
                    Button {
                        showRecordingLog = true
                    } label: {
                        HStack {
                            Text("Recording history")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                } header: {
                    sectionHeader("Recordings")
                } footer: {
                    Text("Everything you've said to Spoke and what it made of it. Useful when something didn't come out the way you expected.")
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
            .sheet(isPresented: $showRecordingLog) {
                RecordingLogView()
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
