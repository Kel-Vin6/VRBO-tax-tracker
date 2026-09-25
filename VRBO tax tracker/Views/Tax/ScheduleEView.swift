//
//  ScheduleEView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct ScheduleEView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]

    @State private var expandedLine: ScheduleELine?

    private var year: Int { appState.taxYear }

    private var report: ScheduleEReport {
        Workspace.report(year: year, properties: properties, expenses: expenses, trips: trips, settings: settings)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if report.columns.isEmpty {
                    EmptyStateView(
                        symbol: "doc.text",
                        title: "Nothing to report",
                        message: "Schedule E is built from your properties, bookings and expenses. Add some and it fills in here."
                    )
                    .frame(minHeight: 280)
                } else {
                    headerCard
                    ForEach(report.columns) { column in
                        columnCard(column)
                    }
                    if report.columns.count > 1 { totalsCard }
                    if report.unassignedExpenses > 0 { unassignedCard }
                    methodCard
                }
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Schedule E")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { YearMenu() }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ExportView()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var headerCard: some View {
        SectionCard(
            "Supplemental Income and Loss",
            subtitle: "Form 1040, Schedule E, Part I — \(year)",
            symbol: "doc.text"
        ) {
            VStack(spacing: 10) {
                DetailRow("Total rents received", value: settings.formatted(report.totalRents), isEmphasised: true)
                DetailRow("Total expenses", value: settings.formatted(report.totalExpenses))
                DetailRow(
                    "Income or loss",
                    value: settings.formatted(report.totalNet),
                    isEmphasised: true,
                    valueColor: Theme.resultColor(report.totalNet)
                )
                Text("Generated \(Fmt.mediumDate(report.generatedAt)) from \(properties.count) propert\(properties.count == 1 ? "y" : "ies").")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func columnCard(_ column: ScheduleEColumn) -> some View {
        SectionCard(
            column.propertyName,
            subtitle: column.address.isEmpty ? nil : column.address,
            symbol: "house"
        ) {
            VStack(spacing: 8) {
                lineRow("1b", "Type of property", value: column.propertyKindCode)
                lineRow("2", "Fair rental days", value: "\(column.fairRentalDays)")
                lineRow("2", "Personal use days", value: "\(column.personalUseDays)")

                Divider()

                lineRow(
                    "3",
                    "Rents received",
                    value: settings.formatted(column.rentsReceived),
                    emphasised: true
                )

                ForEach(column.lines) { line in
                    VStack(spacing: 4) {
                        Button {
                            expandedLine = expandedLine == line.line ? nil : line.line
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(verbatim: "\(line.line.rawValue)")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .leading)
                                Text(line.line.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if line.wasReduced {
                                    Image(systemName: "scissors")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Text(settings.formatted(line.reportedAmount))
                                    .font(.subheadline)
                                    .monospacedDigit()
                                Image(systemName: expandedLine == line.line ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        if expandedLine == line.line {
                            VStack(spacing: 4) {
                                if line.wasReduced {
                                    HStack {
                                        Text("Before §280A allocation")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(settings.formatted(line.grossAmount))
                                            .font(.caption2)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                ForEach(line.details) { detail in
                                    HStack {
                                        Text(detail.label)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        if detail.isAutoDerived {
                                            Image(systemName: "wand.and.stars")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.tint)
                                        }
                                        Spacer(minLength: 8)
                                        Text(settings.formatted(detail.amount))
                                            .font(.caption2)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Theme.nestedFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                Divider()

                lineRow("20", "Total expenses", value: settings.formatted(column.totalExpenses), emphasised: true)
                lineRow(
                    "21",
                    "Income or loss",
                    value: settings.formatted(column.netIncomeOrLoss),
                    emphasised: true,
                    tint: Theme.resultColor(column.netIncomeOrLoss)
                )

                if column.allocationPercentApplied < 100 {
                    InfoCallout(
                        level: .caution,
                        title: "§280A allocation applied",
                        message: "Expenses reduced to \(Fmt.percent(column.allocationPercentApplied)) because of personal use\(column.interestAllocationPercentApplied != column.allocationPercentApplied ? ", with interest and taxes at \(Fmt.percent(column.interestAllocationPercentApplied)) under the Tax Court method" : "")."
                    )
                }
                ForEach(column.notes, id: \.self) { note in
                    InfoCallout(level: .info, message: note)
                }
            }
        }
    }

    private func lineRow(
        _ number: String,
        _ title: String,
        value: String,
        emphasised: Bool = false,
        tint: Color? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            Text(title)
                .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
            Spacer(minLength: 8)
            Text(value)
                .font(emphasised ? .subheadline.weight(.bold) : .subheadline)
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
        }
    }

    private var totalsCard: some View {
        SectionCard("Portfolio totals", symbol: "sum") {
            VStack(spacing: 8) {
                lineRow("3", "Rents received", value: settings.formatted(report.totalRents), emphasised: true)
                ForEach(report.allLines) { line in
                    lineRow("\(line.line.rawValue)", line.line.title, value: settings.formatted(line.reportedAmount))
                }
                Divider()
                lineRow("20", "Total expenses", value: settings.formatted(report.totalExpenses), emphasised: true)
                lineRow(
                    "21",
                    "Income or loss",
                    value: settings.formatted(report.totalNet),
                    emphasised: true,
                    tint: Theme.resultColor(report.totalNet)
                )
            }
        }
    }

    private var unassignedCard: some View {
        InfoCallout(
            level: .caution,
            title: "\(settings.formatted(report.unassignedExpenses)) not on the form",
            message: "These expenses are charged to a single property, but no property is set on them. Open the expense list, assign them, and they will appear here."
        )
    }

    private var methodCard: some View {
        SectionCard("How this was built", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                FeatureLine(
                    symbol: "arrow.triangle.merge",
                    title: "Fees are expenses, not netting",
                    detail: "Gross rents include the cleaning and other fees you charge guests; the platform's cut is deducted on line 8. That is how the 1099-K reads, and how the return has to reconcile to it."
                )
                FeatureLine(
                    symbol: "car",
                    title: "Mileage is folded into line 6",
                    detail: "Your mileage log is converted at the statutory rate and reported with the rest of auto and travel."
                )
                FeatureLine(
                    symbol: "banknote",
                    title: "Mortgage interest is amortised",
                    detail: "Where a loan is set to deduct automatically, line 12 comes from the amortisation schedule rather than a Form 1098."
                )
                FeatureLine(
                    symbol: "chart.line.downtrend.xyaxis",
                    title: "Depreciation is computed, not estimated",
                    detail: "Line 18 is real MACRS: mid-month straight line on the building, declining balance on the contents."
                )
            }
        }
    }
}
