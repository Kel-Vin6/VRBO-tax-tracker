//
//  MileageEditorView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct MileageEditorView: View {

    let trip: MileageTrip?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var date = Date()
    @State private var purpose: TripPurpose = .guestTurnover
    @State private var property: Property?
    @State private var fromLabel = ""
    @State private var toLabel = ""
    @State private var miles: Double = 0
    @State private var isRoundTrip = true
    @State private var useOdometer = false
    @State private var odometerStart: Double = 0
    @State private var odometerEnd: Double = 0
    @State private var tolls: Decimal = 0
    @State private var notes = ""
    @State private var useCustomRate = false
    @State private var customRate: Double = 0
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool { trip != nil }
    private var rates: MileageRateTable { settings.mileageRates }

    private var effectiveMiles: Double {
        let base = useOdometer ? max(0, odometerEnd - odometerStart) : miles
        return isRoundTrip ? base * 2 : base
    }

    private var rate: Double {
        useCustomRate && customRate > 0 ? customRate : rates.rate(on: date)
    }

    private var deduction: Decimal {
        guard purpose.isCurrentlyDeductible else { return tolls }
        return (Decimal.fromDouble(effectiveMiles * rate) + tolls).rounded(2)
    }

    private var missingFields: [String] {
        var missing: [String] = []
        if effectiveMiles <= 0 { missing.append("distance") }
        if toLabel.isEmpty { missing.append("destination") }
        if notes.isEmpty && property == nil { missing.append("business purpose") }
        return missing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LiveSummaryStrip(items: [
                        .init(label: "Miles", value: Fmt.number(effectiveMiles)),
                        .init(label: "Rate", value: Fmt.number(rate, fractionDigits: 3)),
                        .init(label: "Deduction", value: settings.formatted(deduction), tint: .green)
                    ])
                    if !missingFields.isEmpty {
                        InfoCallout(
                            level: .caution,
                            title: "Incomplete log",
                            message: "An IRS-compliant mileage log shows the date, the miles, where you went and why. Still missing: \(missingFields.joined(separator: ", "))."
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                }

                Section("Trip") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Purpose", selection: $purpose) {
                        ForEach(TripPurpose.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    if !purpose.isCurrentlyDeductible {
                        InfoCallout(
                            level: .info,
                            message: "Miles driven looking at properties you do not yet own are start-up costs, not a deduction against an existing rental. They are recorded but not claimed."
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    PropertyPickerField(
                        selection: $property,
                        properties: properties,
                        allowsNone: true,
                        noneLabel: "Whole portfolio"
                    )
                    TextField("From", text: $fromLabel)
                    TextField("To", text: $toLabel)
                    Toggle("Round trip", isOn: $isRoundTrip)
                }

                Section("Distance") {
                    Toggle("Use odometer readings", isOn: $useOdometer)
                    if useOdometer {
                        NumberField("Start", value: $odometerStart, unit: "mi", fractionDigits: 1)
                        NumberField("End", value: $odometerEnd, unit: "mi", fractionDigits: 1)
                    } else {
                        NumberField(isRoundTrip ? "One-way miles" : "Miles", value: $miles, unit: "mi")
                    }
                    CurrencyField("Tolls and parking", amount: $tolls, caption: "Deductible on top of the standard rate.")
                }

                Section {
                    Toggle("Override the rate", isOn: $useCustomRate)
                    if useCustomRate {
                        NumberField("Rate per mile", value: $customRate, fractionDigits: 3)
                    }
                    Text(rates.sourceNote(forYear: DateMath.year(of: date)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Rate")
                }

                Section("Business purpose") {
                    TextField("What the trip was for", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete trip", systemImage: "trash")
                        }
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle(isEditing ? "Edit trip" : "Log a trip")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(effectiveMiles <= 0 && tolls <= 0)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete this trip?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete trip", role: .destructive) { deleteTrip() }
            }
        }
    }

    private func load() {
        guard let trip else {
            property = properties.first { $0.id == settings.defaultPropertyID } ?? properties.first
            if let property { toLabel = property.displayName }
            return
        }
        date = trip.date
        purpose = trip.purpose
        property = trip.property
        fromLabel = trip.fromLabel
        toLabel = trip.toLabel
        miles = trip.miles
        isRoundTrip = trip.isRoundTrip
        useOdometer = trip.odometerEnd > 0
        odometerStart = trip.odometerStart
        odometerEnd = trip.odometerEnd
        tolls = trip.tollsAndParking
        notes = trip.notes
        useCustomRate = trip.rateOverride > 0
        customRate = trip.rateOverride
    }

    private func save() {
        let target = trip ?? MileageTrip()
        if trip == nil { context.insert(target) }

        target.date = date
        target.purpose = purpose
        target.property = property
        target.fromLabel = fromLabel
        target.toLabel = toLabel
        target.miles = useOdometer ? 0 : miles
        target.odometerStart = useOdometer ? odometerStart : 0
        target.odometerEnd = useOdometer ? odometerEnd : 0
        target.isRoundTrip = isRoundTrip
        target.tollsAndParking = tolls
        target.notes = notes
        target.rateOverride = useCustomRate ? customRate : 0
        target.loggedSameDay = DateMath.startOfDay(date) == DateMath.startOfDay(Date())

        try? context.save()
        Haptics.play(.success)
        dismiss()
    }

    private func deleteTrip() {
        guard let trip else { return }
        context.delete(trip)
        try? context.save()
        dismiss()
    }
}
