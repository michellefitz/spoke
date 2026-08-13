import SwiftUI

/// Detail sheet for a calendar appointment, mirroring TaskDetailView's
/// Cancel / Delete / Close header. Edits are held locally and written back to
/// EventKit on Close; the week view refreshes itself via EKEventStoreChanged.
struct EventDetailView: View {
    let event: DayEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay: Bool
    @State private var location: String
    @State private var notes: String
    @State private var showDeleteConfirmation = false
    @State private var saveFailed = false

    private let coral = Color(red: 1.0, green: 0.38, blue: 0.28)

    init(event: DayEvent) {
        self.event = event
        _title = State(initialValue: event.title)
        _start = State(initialValue: event.start)
        _end = State(initialValue: event.end)
        _isAllDay = State(initialValue: event.isAllDay)
        _location = State(initialValue: event.location ?? "")
        _notes = State(initialValue: event.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header buttons
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(.secondaryLabel))
                }

                Spacer()

                HStack(spacing: 20) {
                    if event.allowsEditing {
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }

                    Button("Close") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(coral)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: Title
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(event.color)
                            .frame(width: 3, height: 26)
                            .padding(.top, 4)

                        TextField("Event title", text: $title, axis: .vertical)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .disabled(!event.allowsEditing)
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 24)

                    if let calendarTitle = event.calendarTitle {
                        HStack(spacing: 6) {
                            Text(calendarTitle.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(event.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(event.color.opacity(0.12)))
                            if !event.allowsEditing {
                                Text("Read-only calendar")
                                    .font(.caption)
                                    .italic()
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                        }
                        .padding(.top, 10)
                        .padding(.horizontal, 24)
                    }

                    // MARK: When
                    VStack(spacing: 0) {
                        Toggle("All day", isOn: $isAllDay)
                            .padding(.vertical, 10)

                        Divider()

                        DatePicker(
                            "Starts",
                            selection: $start,
                            displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                        )
                        .padding(.vertical, 6)
                        .onChange(of: start) { oldValue, newValue in
                            // Keep the duration when the start moves
                            end = end.addingTimeInterval(newValue.timeIntervalSince(oldValue))
                        }

                        if !isAllDay {
                            Divider()
                            DatePicker("Ends", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                                .padding(.vertical, 6)
                        }
                    }
                    .font(.system(size: 15))
                    .tint(coral)
                    .disabled(!event.allowsEditing)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                    // MARK: Location + notes
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(.secondaryLabel))
                                .frame(width: 20)
                            TextField("Add a location", text: $location)
                                .font(.system(size: 15))
                        }
                        .padding(.vertical, 12)

                        Divider()

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(.secondaryLabel))
                                .frame(width: 20)
                                .padding(.top, 2)
                            TextField("Add notes", text: $notes, axis: .vertical)
                                .font(.system(size: 15))
                                .lineLimit(1...8)
                        }
                        .padding(.vertical, 12)
                    }
                    .disabled(!event.allowsEditing)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                    // MARK: Open in Calendar
                    Button {
                        if let url = URL(string: "calshow:\(Int(event.start.timeIntervalSinceReferenceDate))") {
                            openURL(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13))
                            Text("Open in Calendar")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(Color(.secondaryLabel))
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 24)

                    if saveFailed {
                        Text("Couldn't save the changes — the event may have moved or been deleted.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 12)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .background(Color(.systemBackground))
        .confirmationDialog("Delete this event?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete event", role: .destructive) {
                CalendarService.shared.deleteEvent(event)
                dismiss()
            }
        } message: {
            Text("This removes it from your calendar.")
        }
    }

    private func saveAndDismiss() {
        guard event.allowsEditing, hasChanges else {
            dismiss()
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = CalendarService.shared.updateEvent(
            event,
            title: trimmedTitle.isEmpty ? event.title : trimmedTitle,
            start: start,
            end: max(end, start),
            isAllDay: isAllDay,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if saved {
            dismiss()
        } else {
            saveFailed = true
        }
    }

    private var hasChanges: Bool {
        title != event.title
            || start != event.start
            || end != event.end
            || isAllDay != event.isAllDay
            || location != (event.location ?? "")
            || notes != (event.notes ?? "")
    }
}
