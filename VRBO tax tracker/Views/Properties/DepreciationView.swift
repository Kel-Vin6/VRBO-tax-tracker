//
//  DepreciationView.swift
//  VRBO tax tracker
//

import Charts
import SwiftData
import SwiftUI

struct DepreciationView: View {

    var property: Property?

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Property.sortIndex) private var allProperties: [Property]

    @State private var expandedSpecID: UUID?

    private var properties: [Property] {
        if let property { return [property] }
        return allProperties
    }

    private var year: Int { appState.taxYear }

    private var entries: [(property: Property, schedule: DepreciationSchedule)] {
        properties.flatMap { property in
            property.allDepreciationSpecs.map { (property, DepreciationEngine.schedule(for: $0)) }
        }
    }

    private var yearTotal: Decimal {
        entries.map { $0.schedule.deduction(inYear: year) }.total
    }

    private var accumulatedTotal: Decimal {
        entries.map { $0.schedule.accumulated(throughYear: year) }.total
    }

    private var remainingTotal: Decimal {
        entries.map { $0.schedule.remainingBasis(afterYear: year) }.total
    }

    private var midQuarterWarnings: [String] {
        properties.compactMap { property in
            DepreciationEngine.midQuarterConventionApplies(specs: property.allDepreciationSpecs, year: year)
                ? "\(property.displayName): more than 40% of this year's personal property was placed in service in the fourth quarter, so the mid-quarter convention applies. The app computes on the half-year convention — have these figures reviewed."
                : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if entries.isEmpty {
                    EmptyStateView(
                        symbol: "chart.line.downtrend.xyaxis",
                        title: "No depreciation yet",
                        message: "Give a property its purchase price, land value and placed-in-service date and the building starts depreciating. Add furniture and appliances as assets to write them off far faster."
                    )
                    .frame(minHeight: 280)
                } else {
                    summaryCard
                    ForEach(midQuarterWarnings, id: \.self) { warning in
                        InfoCallout(level: .caution, title: "Mid-quarter convention", message: warning)
                    }
                    projectionCard
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        scheduleCard(entry.property, entry.schedule)
                    }
                    methodNotes
                }
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Depreciation")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .principal) { YearMenu() } }
    }

    private var summaryCard: some View {
        SectionCard("\(year) depreciation", symbol: "chart.line.downtrend.xyaxis") {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    StatTile(
                        label: "This year",
                        value: settings.formattedCompact(yearTotal),
                        caption: "Schedule E line 18",
                        symbol: "calendar",
                        tint: .green
                    )
                    StatTile(
                        label: "Claimed to date",
                        value: settings.formattedCompact(accumulatedTotal),
                        caption: "Recaptured on sale",
                        symbol: "tray.full",
                        tint: .orange
                    )
                    StatTile(
                        label: "Still to come",
                        value: settings.formattedCompact(remainingTotal),
                        caption: "Remaining basis",
                        symbol: "hourglass",
                        tint: .blue
                    )
                }
            }
        }
    }

    private var projectionYears: [Int] { Array(year...(year + 9)) }

    private var projectionCard: some View {
        SectionCard(
            "The next ten years",
            subtitle: "What you can count on deducting",
            symbol: "chart.bar.xaxis"
        ) {
            Chart {
                ForEach(projectionYears, id: \.self) { projectedYear in
                    let amount = entries
                        .map { $0.schedule.deduction(inYear: projectedYear) }
                        .total
                    BarMark(
                        x: .value("Year", String(projectedYear)),
                        y: .value("Deduction", amount.doubleValue)
                    )
                    .foregroundStyle(projectedYear == year ? Color.accentColor : Color.accentColor.opacity(0.45))
                    .cornerRadius(4)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Fmt.compactCurrency(Decimal(amount), code: settings.currencyCode))
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }

    private func scheduleCard(_ property: Property, _ schedule: DepreciationSchedule) -> some View {
        SectionCard(
            schedule.spec.name,
            subtitle: "\(property.displayName) · \(Fmt.number(schedule.spec.recoveryYears))-year \(schedule.spec.assetClass.title.lowercased())",
            symbol: schedule.spec.assetClass.symbol
        ) {
            VStack(spacing: 10) {
                DetailRow("Basis", value: settings.formatted(schedule.spec.basis))
                DetailRow("Placed in service", value: Fmt.mediumDate(schedule.spec.placedInService))
                DetailRow(
                    "\(year) deduction",
                    value: settings.formatted(schedule.deduction(inYear: year)),
                    isEmphasised: true,
                    valueColor: .green
                )
                DetailRow("Fully written off by", value: String(schedule.finalYear))

                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedSpecID == schedule.spec.id },
                        set: { expandedSpecID = $0 ? schedule.spec.id : nil }
                    )
                ) {
                    VStack(spacing: 0) {
                        headerRow
                        ForEach(schedule.rows) { row in
                            HStack {
                                Text(verbatim: "\(row.year)")
                                    .frame(width: 48, alignment: .leading)
                                Text(settings.formatted(row.total))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                Text(Fmt.percent(row.ratePercent, fractionDigits: 3))
                                    .frame(width: 70, alignment: .trailing)
                                Text(settings.formattedCompact(row.closingBasis))
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .font(.caption)
                            .monospacedDigit()
                            .padding(.vertical, 4)
                            .background(row.year == year ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                    }
                } label: {
                    Text("Year-by-year schedule")
                        .font(.subheadline)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Text("Year").frame(width: 48, alignment: .leading)
            Text("Deduction").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Rate").frame(width: 70, alignment: .trailing)
            Text("Basis left").frame(width: 80, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private var methodNotes: some View {
        SectionCard("How these figures are worked out", symbol: "function") {
            VStack(alignment: .leading, spacing: 10) {
                FeatureLine(
                    symbol: "building",
                    title: "Buildings: 27.5 or 39 years, mid-month",
                    detail: "The month you place the property in service counts as half a month, which is why a January start gives 3.485% in year one rather than the full 3.636%."
                )
                FeatureLine(
                    symbol: "sofa",
                    title: "Contents: declining balance, half-year",
                    detail: "Furniture over 7 years and technology over 5, at 200% declining balance, switching to straight line in the first year that gives more. Land improvements use 150% over 15 years."
                )
                FeatureLine(
                    symbol: "bolt",
                    title: "Bonus and §179 come first",
                    detail: "Both are applied to basis before MACRS, so the remaining basis depreciates normally from year one."
                )
                InfoCallout(
                    level: .info,
                    message: "The mid-quarter convention and cost segregation studies are outside what the app computes. Where either applies, it says so rather than producing a figure quietly."
                )
            }
        }
    }
}
