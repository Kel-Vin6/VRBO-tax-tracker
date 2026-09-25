//
//  PersonalUseView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct PersonalUseView: View {

    var focusedProperty: Property?

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \Property.sortIndex) private var allProperties: [Property]

    @State private var editing: PersonalUseEntry?
    @State private var showingNew = false
    @State private var whatIfDays: Double = 0

    private var year: Int { appState.taxYear }

    private var properties: [Property] {
        if let focusedProperty { return [focusedProperty] }
        return allProperties
    }

    private func analysis(for property: Property) -> PersonalUseAnalysis {
        PersonalUseEngine.analyze(
            bookings: property.bookingList,
            personalUse: property.personalUseList,
            year: year,
            propertyID: property.id,
            daysAvailable: property.daysAvailablePerYear
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if properties.isEmpty {
                    EmptyStateView(
                        symbol: "figure.and.child.holdinghands",
                        title: "No properties",
                        message: "Add a property first, then record the nights you or your family stay there."
                    )
                    .frame(minHeight: 260)
                } else {
                    ForEach(properties) { property in
                        propertyCard(property)
                    }
                    rulesCard
                }
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Personal use")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("Add days", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) { YearMenu() }
        }
        .sheet(isPresented: $showingNew) {
            PersonalUseEditorView(entry: nil, prefilledProperty: focusedProperty)
        }
        .sheet(item: $editing) { entry in
            PersonalUseEditorView(entry: entry, prefilledProperty: nil)
        }
    }

    // MARK: - Property card

    @ViewBuilder
    private func propertyCard(_ property: Property) -> some View {
        let result = analysis(for: property)

        SectionCard(
            property.displayName,
            subtitle: result.classification.title,
            symbol: result.classification.symbol
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ProgressRing(
                        progress: result.thresholdProgress,
                        tint: result.headroomDays >= 0 ? .green : .red,
                        label: "\(result.personalUseDays)",
                        caption: "of \(result.personalUseThreshold)"
                    )
                    .frame(width: 88, height: 88)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.headroomDays >= 0
                             ? "\(result.headroomDays) personal day\(result.headroomDays == 1 ? "" : "s") left"
                             : "\(abs(result.headroomDays)) day\(abs(result.headroomDays) == 1 ? "" : "s") over")
                            .font(.headline)
                            .foregroundStyle(result.headroomDays >= 0 ? .primary : .red)
                        Text("The limit is the greater of 14 days or 10% of the \(result.fairRentalDays) days rented at fair value.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Text(result.classification.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                allocationComparison(result)

                if result.hasDataQualityIssues {
                    InfoCallout(
                        level: .critical,
                        title: "Day counts do not reconcile",
                        message: "\(result.conflictingDays.count) day(s) are recorded as both rented and personal, and \(result.doubleBookedDays.count) are covered by more than one booking. Examiners start with the day counts."
                    )
                }

                if PersonalUseEngine.augustaRuleOpportunity(result) {
                    InfoCallout(
                        level: .success,
                        title: "The 14-day rule applies",
                        message: "You rented for fewer than 15 days while using the home as a residence, so under §280A(g) this rental income is not reported at all — and no rental expenses are deducted against it."
                    )
                }

                whatIfControl(property, result)

                entriesList(property)
            }
        }
    }

    private func allocationComparison(_ result: PersonalUseAnalysis) -> some View {
        VStack(spacing: 6) {
            DetailRow(
                "IRS allocation",
                value: Fmt.percent(result.irsAllocationPercent),
                caption: "Rental days ÷ total days used. Applies to every expense."
            )
            DetailRow(
                "Tax Court allocation",
                value: Fmt.percent(result.boltonAllocationPercent),
                caption: "Rental days ÷ days in the year. Courts have allowed this for mortgage interest and property taxes, which leaves more room for the other expenses.",
                valueColor: settings.useBoltonAllocation ? .green : .secondary
            )
            if result.personalUseDays > 0 && !settings.useBoltonAllocation {
                Text("The Tax Court method is switched off. You can turn it on in Settings ▸ Tax elections.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func whatIfControl(_ property: Property, _ result: PersonalUseAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("What if you stayed longer?")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(whatIfDays)) day\(Int(whatIfDays) == 1 ? "" : "s")")
                    .font(.subheadline)
                    .monospacedDigit()
            }
            Slider(value: $whatIfDays, in: 0...30, step: 1)

            if whatIfDays > 0 {
                let projected = PersonalUseEngine.projectedClassification(
                    current: result,
                    addingPersonalDays: Int(whatIfDays)
                )
                InfoCallout(
                    level: projected.isFavourable ? .success : .caution,
                    title: projected.title,
                    message: projected.isFavourable
                        ? "Still within the limit. You would have \(max(0, result.headroomDays - Int(whatIfDays))) day(s) of headroom left."
                        : "Those extra nights tip this property into residence treatment for the whole year."
                )
            }
        }
        .padding(12)
        .background(Theme.nestedFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func entriesList(_ property: Property) -> some View {
        let entries = property.personalUseList
            .filter { $0.dayCount(inYear: year) > 0 }
            .sorted { $0.startDate > $1.startDate }

        if entries.isEmpty {
            Text("No personal-use days recorded for \(year).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    Button { editing = entry } label: {
                        HStack(spacing: 10) {
                            Image(systemName: entry.kind.symbol)
                                .font(.caption)
                                .foregroundStyle(entry.countsAsPersonalUse ? .orange : .teal)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.kind.title)
                                    .font(.subheadline)
                                Text(entry.dateRangeLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text("\(entry.dayCount(inYear: year)) day\(entry.dayCount(inYear: year) == 1 ? "" : "s")")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(entry.countsAsPersonalUse ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Button { showingNew = true } label: {
            Label("Record days", systemImage: "plus.circle")
                .font(.subheadline)
        }
    }

    private var rulesCard: some View {
        SectionCard("What counts as personal use", symbol: "book") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PersonalUseKind.allCases) { kind in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: kind.symbol)
                            .font(.caption)
                            .foregroundStyle(kind.countsAsPersonalUse ? .orange : .teal)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(kind.title).font(.subheadline.weight(.medium))
                                TagChip(
                                    kind.countsAsPersonalUse ? "Counts" : "Does not count",
                                    tint: kind.countsAsPersonalUse ? .orange : .teal
                                )
                            }
                            Text(kind.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
