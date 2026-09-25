//
//  PropertiesView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct PropertiesView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]

    @State private var editing: Property?
    @State private var showingNew = false

    private var report: ScheduleEReport {
        Workspace.report(
            year: appState.taxYear,
            properties: properties,
            expenses: expenses,
            trips: trips,
            settings: settings
        )
    }

    var body: some View {
        Group {
            if properties.isEmpty {
                EmptyStateView(
                    symbol: "house.and.flag",
                    title: "No properties",
                    message: "Add the rental you want to track. You can add its purchase price and land value later, but doing it now unlocks depreciation.",
                    actionTitle: "Add a property"
                ) { showingNew = true }
            } else {
                List {
                    ForEach(properties) { property in
                        NavigationLink {
                            PropertyDetailView(property: property)
                        } label: {
                            PropertySummaryRow(
                                property: property,
                                column: report.columns.first { $0.id == property.id },
                                settings: settings
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                context.delete(property)
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editing = property
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove(perform: move)
                }
                .platformListStyle()
            }
        }
        .navigationTitle("Properties")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNew = true
                } label: {
                    Label("Add property", systemImage: "plus")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            #endif
        }
        .sheet(isPresented: $showingNew) {
            PropertyEditorView(property: nil)
        }
        .sheet(item: $editing) { property in
            PropertyEditorView(property: property)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = properties
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, property) in ordered.enumerated() {
            property.sortIndex = index
        }
        try? context.save()
    }
}

struct PropertySummaryRow: View {
    let property: Property
    let column: ScheduleEColumn?
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PropertyBadge(
                    name: property.displayName,
                    monogram: property.monogram,
                    color: property.color,
                    showsName: false
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(property.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(property.shortAddress.isEmpty ? property.kind.title : property.shortAddress)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !property.isActive {
                    TagChip("Inactive", tint: .secondary)
                }
            }

            if let column {
                HStack(spacing: 14) {
                    miniStat("Rents", settings.formattedCompact(column.rentsReceived), .green)
                    miniStat("Net", settings.formattedCompact(column.netIncomeOrLoss), Theme.resultColor(column.netIncomeOrLoss))
                    miniStat("Rental days", "\(column.fairRentalDays)", .blue)
                    miniStat("Personal", "\(column.personalUseDays)", column.analysis.classification == .rentalProperty ? .secondary : .orange)
                }
            }

            let flags = property.complianceFlags()
            if !flags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(flags.prefix(2)) { flag in
                        TagChip(
                            flag.message,
                            symbol: flag.symbol,
                            tint: flag.isCritical ? .red : .orange
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func miniStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
