//
//  ParticipationEditorView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct ParticipationEditorView: View {

    let entry: ParticipationEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var date = Date()
    @State private var hours: Double = 1
    @State private var activity: ParticipationActivity = .guestCommunication
    @State private var property: Property?
    @State private var descriptionText = ""
    @State private var performedBySpouse = false
    @State private var contractorHours: Double = 0
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool { entry != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LiveSummaryStrip(items: [
                        .init(label: "Hours", value: Fmt.number(hours)),
                        .init(
                            label: "Counts",
                            value: activity.isInvestorActivity ? "No" : "Yes",
                            tint: activity.isInvestorActivity ? .secondary : .green
                        ),
                        .init(
                            label: "QBI safe harbor",
                            value: activity.countsForQBISafeHarbor ? "Yes" : "No"
                        )
                    ])
                }

                Section("Work") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    NumberField("Hours", value: $hours, unit: "h", fractionDigits: 2)
                    Picker("Activity", selection: $activity) {
                        ForEach(ParticipationActivity.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    if activity.isInvestorActivity {
                        InfoCallout(
                            level: .info,
                            message: "Studying financials and arranging finance are investor activities. They are excluded from the §469 tests unless you are also involved in day-to-day management."
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    PropertyPickerField(
                        selection: $property,
                        properties: properties,
                        allowsNone: true,
                        noneLabel: "Whole portfolio"
                    )
                }

                Section {
                    TextField("What did you actually do?", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...6)
                    if descriptionText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Hours with no description are the first thing challenged, and the loss they unlock is usually the largest number on the return.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Description")
                }

                Section {
                    Toggle("Done by my spouse", isOn: $performedBySpouse)
                    Text("A spouse's work counts toward your participation, whether or not you file jointly.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    NumberField("Hours others worked that day", value: $contractorHours, unit: "h", fractionDigits: 1)
                    Text("Recording the cleaner's and the handyman's hours is what makes the “more than anyone else” test stand up.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Other people")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                        }
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle(isEditing ? "Edit hours" : "Log hours")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(hours <= 0)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteEntry() }
            }
        }
    }

    private func load() {
        guard let entry else {
            property = properties.first { $0.id == settings.defaultPropertyID } ?? properties.first
            return
        }
        date = entry.date
        hours = entry.hours
        activity = entry.activity
        property = entry.property
        descriptionText = entry.descriptionText
        performedBySpouse = entry.performedBySpouse
        contractorHours = entry.contractorHoursSameDay
    }

    private func save() {
        let target = entry ?? ParticipationEntry()
        if entry == nil { context.insert(target) }

        target.date = date
        target.hours = hours
        target.activity = activity
        target.property = property
        target.descriptionText = descriptionText
        target.performedBySpouse = performedBySpouse
        target.contractorHoursSameDay = contractorHours
        target.loggedSameDay = DateMath.startOfDay(date) == DateMath.startOfDay(Date())

        try? context.save()
        Haptics.play(.success)
        dismiss()
    }

    private func deleteEntry() {
        guard let entry else { return }
        context.delete(entry)
        try? context.save()
        dismiss()
    }
}
