//
//  DashboardCards.swift
//  VRBO tax tracker
//

import Charts
import SwiftUI

// MARK: - Hero

/// The number a host actually wants when they open the app: what the rentals
/// made, and how much of it belongs to the government.
struct HeroSummaryCard: View {

    let report: ScheduleEReport
    let estimate: TaxEstimateResult
    let metrics: PortfolioMetrics
    let year: Int

    @Environment(AppSettings.self) private var settings

    private var setAside: Decimal {
        max(0, estimate.taxAttributableToRentals + estimate.stateTax)
    }

    private var setAsidePercent: Double {
        guard report.totalRents > 0 else { return 0 }
        return (setAside / report.totalRents).doubleValue * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(year) rental result")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(settings.formatted(report.totalNet))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.resultColor(report.totalNet))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Set aside for tax")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(settings.formatted(setAside))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                    if setAsidePercent > 0 {
                        Text("\(Fmt.percent(setAsidePercent)) of gross rents")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            WaterfallBar(
                rents: report.totalRents,
                operating: report.totalExpenses - report.totalDepreciation,
                depreciation: report.totalDepreciation
            )

            HStack(spacing: 0) {
                heroStat("Gross rents", settings.formattedCompact(report.totalRents), .green)
                Divider().frame(height: 30)
                heroStat("Deductions", settings.formattedCompact(report.totalExpenses), .orange)
                Divider().frame(height: 30)
                heroStat("Margin", Fmt.percent(metrics.marginPercent), .blue)
            }
        }
        .padding(18)
        .cardSurface()
    }

    private func heroStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A single bar showing where the rent went, which reads faster than a pie.
struct WaterfallBar: View {
    let rents: Decimal
    let operating: Decimal
    let depreciation: Decimal

    private var total: Double { max(rents.doubleValue, (operating + depreciation).doubleValue, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let operatingWidth = width * min(1, operating.doubleValue / total)
                let depreciationWidth = width * min(1 - min(1, operating.doubleValue / total),
                                                    depreciation.doubleValue / total)

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.green.opacity(0.35))
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.orange)
                            .frame(width: max(0, operatingWidth))
                        Rectangle().fill(Color.purple.opacity(0.75))
                            .frame(width: max(0, depreciationWidth))
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 12)

            HStack(spacing: 12) {
                legend(.green.opacity(0.5), "Kept")
                legend(.orange, "Operating")
                legend(.purple.opacity(0.75), "Depreciation")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Of gross rents, operating costs and depreciation take the shaded portions.")
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Revenue chart

struct RevenueChartCard: View {

    let metrics: PortfolioMetrics
    @Environment(AppSettings.self) private var settings
    @State private var selectedMonth: Int?

    private var selectedPoint: MonthlyPoint? {
        guard let selectedMonth else { return nil }
        return metrics.monthly.first { $0.month == selectedMonth }
    }

    var body: some View {
        SectionCard(
            "Revenue and costs by month",
            subtitle: selectedPoint.map {
                "\($0.label): \(settings.formattedCompact($0.revenue)) in, \(settings.formattedCompact($0.expenses)) out"
            } ?? "Tap a month for the detail",
            symbol: "chart.bar"
        ) {
            Chart {
                ForEach(metrics.monthly) { point in
                    BarMark(
                        x: .value("Month", point.label),
                        y: .value("Revenue", point.revenue.doubleValue)
                    )
                    .foregroundStyle(by: .value("Series", "Revenue"))
                    .position(by: .value("Series", "Revenue"))
                    .opacity(selectedMonth == nil || selectedMonth == point.month ? 1 : 0.35)

                    BarMark(
                        x: .value("Month", point.label),
                        y: .value("Costs", point.expenses.doubleValue)
                    )
                    .foregroundStyle(by: .value("Series", "Costs"))
                    .position(by: .value("Series", "Costs"))
                    .opacity(selectedMonth == nil || selectedMonth == point.month ? 1 : 0.35)
                }
            }
            .chartForegroundStyleScale([
                "Revenue": Color.green,
                "Costs": Color.orange
            ])
            .chartLegend(position: .bottom, spacing: 8)
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
            .frame(height: 220)
            .chartXSelection(value: Binding(
                get: { selectedPoint?.label },
                set: { label in
                    selectedMonth = metrics.monthly.first { $0.label == label }?.month
                }
            ))
        }
    }
}

// MARK: - Deduction breakdown

struct DeductionBreakdownCard: View {

    let metrics: PortfolioMetrics
    @Environment(AppSettings.self) private var settings

    private var topSlices: [CategorySlice] { Array(metrics.expensesByLine.prefix(7)) }

    var body: some View {
        SectionCard(
            "Where the deductions are",
            subtitle: "Largest Schedule E lines this year",
            symbol: "chart.pie"
        ) {
            VStack(spacing: 10) {
                ForEach(topSlices) { slice in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(slice.label)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(settings.formattedCompact(slice.amount))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(PropertyPalette.color(for: slice.colorHex))
                                .frame(width: max(3, proxy.size.width * slice.share))
                        }
                        .frame(height: 6)
                        .background(Theme.nestedFill, in: Capsule())
                    }
                }
            }
        }
    }
}
