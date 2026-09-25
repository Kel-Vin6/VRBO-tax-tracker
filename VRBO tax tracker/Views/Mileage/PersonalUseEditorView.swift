//
//  PersonalUseEditorView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct PersonalUseEditorView: View {

    let entry: PersonalUseEntry?
    var prefilledProperty: Property?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationService.self) private var notifications

    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var property: Property?
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var kind: PersonalUseKind = .owner
    @State private var occupantName = ""
    @State private var rentCollected: Decimal = 0
    @State private var notes = ""
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool { entry != nil }
    private var days: Int { DateMath.inclusiveDays(from: startDate, to: endDate) }

    private var currentAnalysis: PersonalUseAnalysis? {
        guard let property else { return nil }
        return PersonalUseEngine.analyze(
            bookings: property.bookingList,
            personalUse: property.personalUseList.filter { $0.id != entry?.id },
            year: appState.taxYear,
            propertyID: property.id,
            daysAvailable: property.daysAvailablePerYear
        )
    }

    private var projection: DwellingClassification? {
        guard let currentAnalysis, kind.countsAsPersonalUse else { return nil }
        return PersonalUseEngine.projectedClassification(
            current: currentAnalysis,
            addingPersonalDays: DateMath.days(from: startDate, to: endDate, inYear: appState.taxYear)
        )
    }

    private var bookingConflicts: [String] {
        guard let property else { return [] }
        return property.bookingList
            .filter { !$0.isCancelled }
            .filter {
                DateMath.rangesOverlap(
                    startDate, endDate,
                    $0.checkIn, DateMath.adding(days: -1, to: $0.checkOut)
                )
            }
            .map { "Overlaps \($0.displayGuest)'s stay (\($0.dateRangeLabel))." }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LiveSummaryStrip(items: [
                        .init(label: "Days", value: "\(days)"),
                        .init(
                            label: "Counts",
                            value: kind.countsAsPersonalUse ? "Yes" : "No",
                            tint: kind.countsAsPersonalUse ? .orange : .teal
                        ),
                        .init(
                            label: "Headroom left",
                            value: currentAnalysis.map {
                                "\(max(0, $0.headroomDays - (kind.countsAsPersonalUse ? DateMath.days(from: startDate, to: endDate, inYear: appState.taxYear) : 0)))"
                            } ?? "—"
                        )
                    ])
                    if let projection, projection == .residenceWithRentalUse {
                        InfoCallout(
                            level: .critical,
                            title: "This would cross the §280A limit",
                            message: "Recording these days makes the property a residence for \(appState.taxYear). Expenses get allocated and no rental loss can be claimed."
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                }

                Section("Stay") {
                    PropertyPickerField(selection: $property, properties: properties)
                    DatePicker("First day", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { _, newValue in
                            if endDate < newValue { endDate = newValue }
                        }
                    DatePicker("Last day", selection: $endDate, in: startDate..., displayedComponents: .date)
                    Text("Days of use are counted inclusively — arriving Friday and leaving Sunday is three days, even though it is two nights.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Kind of use", selection: $kind) {
                        ForEach(PersonalUseKind.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    Text(kind.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("Who stayed", text: $occupantName)
                    if kind == .familyMember || kind == .friendBelowMarket {
                        CurrencyField(
                            "Rent collected",
                            amount: $rentCollected,
                            caption: "Recorded for completeness. Renting to family counts as personal use even at full market rent."
                        )
                    }
                } header: {
                    Text("Classification")
                }

                if !bookingConflicts.isEmpty {
                    Section("Conflicts") {
                        ForEach(bookingConflicts, id: \.self) { message in
                            InfoCallout(level: .caution, message: message)
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete these days", systemImage: "trash")
                        }
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle(isEditing ? "Edit personal use" : "Record personal use")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(property == nil)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete these days?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteEntry() }
            }
        }
    }

    private func load() {
        guard let entry else {
            property = prefilledProperty
                ?? properties.first { $0.id == settings.defaultPropertyID }
                ?? properties.first
            return
        }
        property = entry.property
        startDate = entry.startDate
        endDate = entry.endDate
        kind = entry.kind
        occupantName = entry.occupantName
        rentCollected = entry.rentCollected
        notes = entry.notes
    }

    private func save() {
        let target = entry ?? PersonalUseEntry()
        if entry == nil { context.insert(target) }

        target.property = property
        target.startDate = startDate
        target.endDate = endDate
        target.kind = kind
        target.occupantName = occupantName
        target.rentCollected = rentCollected
        target.notes = notes

        try? context.save()
        warnIfNearingLimit()
        Haptics.play(.success)
        dismiss()
    }

    /// Fires once the property is within a few days of losing rental-property
    /// treatment, which is the point at which a cancelled owner stay is still
    /// worth more than the stay itself.
    private func warnIfNearingLimit() {
        guard settings.notifyPersonalUseThreshold, kind.countsAsPersonalUse, let property else { return }

        let updated = PersonalUseEngine.analyze(
            bookings: property.bookingList,
            personalUse: property.personalUseList,
            year: appState.taxYear,
            propertyID: property.id,
            daysAvailable: property.daysAvailablePerYear
        )
        guard updated.fairRentalDays > 0, updated.headroomDays <= 5 else { return }

        let name = property.displayName
        let headroom = updated.headroomDays
        Task {
            await notifications.notifyPersonalUseThreshold(
                propertyName: name,
                headroomDays: headroom
            )
        }
    }

    private func deleteEntry() {
        guard let entry else { return }
        context.delete(entry)
        try? context.save()
        dismiss()
    }
}
