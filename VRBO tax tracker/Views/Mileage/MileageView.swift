//
//  MileageView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct MileageView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \MileageTrip.date, order: .reverse) private var allTrips: [MileageTrip]
    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var editing: MileageTrip?
    @State private var showingNew = false

    private var year: Int { appState.taxYear }
    private var rates: MileageRateTable { settings.mileageRates }

    private var trips: [MileageTrip] {
        allTrips.filter { DateMath.contains($0.date, inYear: year) }
    }

    private var totalMiles: Double { trips.map(\.effectiveMiles).reduce(0, +) }
    private var totalDeduction: Decimal { trips.map { $0.deduction(using: rates) }.total }
    private var incompleteCount: Int { trips.filter { !$0.isAuditComplete }.count }

    var body: some View {
        Group {
            if trips.isEmpty {
                EmptyStateView(
                    symbol: "car",
                    title: "No mileage logged for \(year)",
                    message: "Every drive to the property — turnovers, supply runs, meeting a contractor — is deductible at \(Fmt.number(rates.rate(forYear: year), fractionDigits: 3)) a mile. A log written the same day is worth far more than one reconstructed in April.",
                    actionTitle: "Log a trip"
                ) { showingNew = true }
            } else {
                List {
                    Section {
                        HStack(spacing: 12) {
                            pill("Miles", Fmt.number(totalMiles, fractionDigits: 0), .blue)
                            pill("Deduction", settings.formattedCompact(totalDeduction), .green)
                            pill("Incomplete", "\(incompleteCount)", incompleteCount > 0 ? .orange : .green)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                    }

                    if rates.isUnconfirmed(forYear: year) {
                        Section {
                            InfoCallout(
                                level: .caution,
                                title: "Rate not confirmed for \(year)",
                                message: rates.sourceNote(forYear: year)
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }
                    }

                    Section("Trips") {
                        ForEach(trips) { trip in
                            Button { editing = trip } label: {
                                MileageRow(trip: trip, rates: rates, settings: settings)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(trip)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    duplicate(trip)
                                } label: {
                                    Label("Repeat", systemImage: "plus.square.on.square")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
                .platformListStyle()
            }
        }
        .navigationTitle("Mileage")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("Log a trip", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) { YearMenu() }
        }
        .sheet(isPresented: $showingNew) { MileageEditorView(trip: nil) }
        .sheet(item: $editing) { trip in MileageEditorView(trip: trip) }
    }

    private func pill(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardSurface(radius: 12)
    }

    /// Turnover drives repeat constantly, so repeating one is a single tap.
    private func duplicate(_ trip: MileageTrip) {
        let copy = MileageTrip(date: Date(), purpose: trip.purpose, miles: trip.miles, property: trip.property)
        copy.fromLabel = trip.fromLabel
        copy.toLabel = trip.toLabel
        copy.isRoundTrip = trip.isRoundTrip
        copy.notes = trip.notes
        copy.tollsAndParking = trip.tollsAndParking
        context.insert(copy)
        try? context.save()
        Haptics.play(.success)
    }
}

struct MileageRow: View {
    let trip: MileageTrip
    let rates: MileageRateTable
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.nestedFill)
                    .frame(width: 34, height: 34)
                Image(systemName: trip.purpose.symbol)
                    .font(.footnote)
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.purpose.title)
                    .font(.subheadline.weight(.medium))
                Text(trip.routeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !trip.isAuditComplete {
                    Text("Missing \(trip.missingAuditFields.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(settings.formatted(trip.deduction(using: rates)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("\(Fmt.miles(trip.effectiveMiles)) · \(Fmt.dayMonth(trip.date))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
