import SwiftUI
import SwiftData

/// Lists documents with a detected expiry date. Users confirm/correct the
/// auto-detected date, toggle reminders, or dismiss false positives.
struct ExpiringDocumentsView: View {
    let vaultService: VaultService
    var targetReminderID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DocumentReminder.expiryDate, order: .forward)
    private var reminders: [DocumentReminder]

    @State private var editingReminder: DocumentReminder?
    @State private var handledTargetReminderID: UUID?

    private var activeReminders: [DocumentReminder] {
        reminders.filter { !$0.isDismissed }
    }
    private var unconfirmed: [DocumentReminder] { activeReminders.filter { !$0.isConfirmed } }
    private var confirmed: [DocumentReminder] { activeReminders.filter { $0.isConfirmed } }

    var body: some View {
        Group {
            if activeReminders.isEmpty {
                EmptyStateView(
                    systemImage: "calendar.badge.checkmark",
                    title: "No Expiring Documents",
                    subtitle: "When you add IDs, cards, or other documents with an expiry date, they'll show up here so you never miss a renewal."
                )
                .padding()
            } else {
                List {
                    if !unconfirmed.isEmpty {
                        Section {
                            ForEach(unconfirmed) { reminder in
                                reminderRow(reminder)
                            }
                        } header: {
                            Text("Needs Review")
                        } footer: {
                            Text("We detected these dates automatically. Confirm or correct each one to turn on reminders.")
                        }
                    }

                    if !confirmed.isEmpty {
                        Section("Reminders On") {
                            ForEach(confirmed) { reminder in
                                reminderRow(reminder)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Expiring Documents")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vaultService.backfillDocumentReminders()
            openTargetReminderIfNeeded()
        }
        .onChange(of: targetReminderID) { _, _ in
            openTargetReminderIfNeeded()
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditSheet(reminder: reminder, vaultService: vaultService)
        }
    }

    // MARK: - Row

    private func reminderRow(_ reminder: DocumentReminder) -> some View {
        Button {
            editingReminder = reminder
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: reminder.documentType))
                    .font(.title3)
                    .foregroundStyle(Color.vaultAccent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.documentType)
                        .font(.body)
                        .foregroundStyle(Color.vaultTextPrimary)
                    Text(reminder.expiryDate, format: .dateTime.day().month(.wide).year())
                        .font(.caption)
                        .foregroundStyle(Color.vaultTextSecondary)
                }

                Spacer()

                statusBadge(reminder)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                vaultService.dismissReminder(reminder)
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ reminder: DocumentReminder) -> some View {
        let days = reminder.daysUntilExpiry
        let (text, color): (String, Color) = {
            if days < 0 { return ("Expired", Color.vaultDestructive) }
            if days == 0 { return ("Today", Color.vaultDestructive) }
            if days <= 30 { return ("\(days)d", Color.vaultPremium) }
            return ("\(days)d", Color.vaultTextSecondary)
        }()

        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }

    private func icon(for type: String) -> String {
        switch type {
        case "Passport": "globe"
        case "Driver's License": "car"
        case "Payment Card": "creditcard"
        case "Insurance": "cross.case"
        case "Vehicle Registration": "doc.text"
        case "Visa", "Residence Permit": "airplane"
        case "ID Card", "Membership Card": "person.text.rectangle"
        default: "doc"
        }
    }

    private func openTargetReminderIfNeeded() {
        guard let targetReminderID,
              handledTargetReminderID != targetReminderID,
              let reminder = activeReminders.first(where: { $0.id == targetReminderID }) else {
            return
        }
        handledTargetReminderID = targetReminderID
        editingReminder = reminder
    }
}

// MARK: - Reminder Edit Sheet

private struct ReminderEditSheet: View {
    let reminder: DocumentReminder
    let vaultService: VaultService

    @Environment(\.dismiss) private var dismiss

    @State private var expiryDate: Date
    @State private var leadSelections: Set<Int>
    @State private var isSaving = false

    private let leadOptions = [1, 7, 30, 60, 90]

    init(reminder: DocumentReminder, vaultService: VaultService) {
        self.reminder = reminder
        self.vaultService = vaultService
        _expiryDate = State(initialValue: reminder.expiryDate)
        _leadSelections = State(initialValue: Set(reminder.leadDays))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Document") {
                    LabeledContent("Type", value: reminder.documentType)
                }

                Section("Expiry Date") {
                    DatePicker(
                        "Expires",
                        selection: $expiryDate,
                        displayedComponents: .date
                    )
                }

                Section {
                    ForEach(leadOptions, id: \.self) { days in
                        Button {
                            toggleLead(days)
                        } label: {
                            HStack {
                                Text(leadLabel(days))
                                    .foregroundStyle(Color.vaultTextPrimary)
                                Spacer()
                                if leadSelections.contains(days) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.vaultAccent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Remind Me")
                } footer: {
                    Text("Notifications are private — they never reveal the document type or its contents.")
                }
            }
            .navigationTitle(reminder.isConfirmed ? "Edit Reminder" : "Confirm Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(reminder.isConfirmed ? "Save" : "Confirm") {
                        save()
                    }
                    .disabled(isSaving || leadSelections.isEmpty)
                }
            }
        }
    }

    private func toggleLead(_ days: Int) {
        if leadSelections.contains(days) {
            leadSelections.remove(days)
        } else {
            leadSelections.insert(days)
        }
    }

    private func leadLabel(_ days: Int) -> String {
        switch days {
        case 1: "1 day before"
        case 7: "1 week before"
        case 30: "1 month before"
        case 60: "2 months before"
        case 90: "3 months before"
        default: "\(days) days before"
        }
    }

    private func save() {
        isSaving = true
        let leads = Array(leadSelections).sorted()
        let date = expiryDate
        Task {
            await vaultService.confirmReminder(reminder, expiryDate: date, leadDays: leads)
            dismiss()
        }
    }
}
