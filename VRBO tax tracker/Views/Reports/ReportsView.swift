//
//  ReportsView.swift
//  VRBO tax tracker
//

import Charts
import SwiftData
import SwiftUI

struct ReportsView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]

    private var year: Int { appState.taxYear }

    private var report: ScheduleEReport {
        Workspace.report(year: year, properties: properties, expenses: expenses, trips: trips, settings: settings)
    }

    private var priorReport: ScheduleEReport {
        Workspace.report(year: year - 1, properties: properties, expenses: expenses, trips: trips, settings: settings)
    }

    private var metrics: PortfolioMetrics {
        AnalyticsEngine.metrics(
            year: year,
            properties: properties,
            expenses: expenses,
            trips: trips,
            mileageRates: settings.mileageRates,
            report: report
        )
    }

    private var priorMetrics: PortfolioMetrics {
        AnalyticsEngine.metrics(
            year: year - 1,
            properties: properties,
            expenses: expenses,
            trips: trips,
            mileageRates: settings.mileageRates,
            report: priorReport
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if metrics.nightsBooked == 0 && report.totalRents == 0 {
                    EmptyStateView(
                        symbol: "chart.xyaxis.line",
                        title: "No activity in \(year)",
                        message: "Once there are bookings and expenses for this year, the operating metrics appear here."
                    )
                    .frame(minHeight: 280)
                } else {
                    kpiGrid
                    occupancyCard
                    breakEvenCard
                    if metrics.revenueByPlatform.count > 1 { platformCard }
                    if metrics.revenueByProperty.count > 1 { propertyCard }
                    feeDragCard
                    yearOverYearCard
                }
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Reports")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .primaryAction) { YearMenu() } }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(
                label: "Gross rents",
                value: settings.formattedCompact(metrics.grossRevenue),
                symbol: "dollarsign.circle",
                tint: .green,
                trend: AnalyticsEngine.percentChange(from: priorMetrics.grossRevenue, to: metrics.grossRevenue)
            )
            StatTile(
                label: "Occupancy",
                value: Fmt.percent(metrics.occupancyPercent),
                caption: "\(metrics.nightsBooked) of \(metrics.nightsAvailable) nights",
                symbol: "chart.pie",
                tint: .blue
            )
            StatTile(
                label: "Average daily rate",
                value: settings.formattedCompact(metrics.averageDailyRate),
                symbol: "tag",
                tint: .indigo,
                trend: AnalyticsEngine.percentChange(from: priorMetrics.averageDailyRate, to: metrics.averageDailyRate)
            )
            StatTile(
                label: "RevPAR",
                value: settings.formattedCompact(metrics.revPAR),
                caption: "Revenue per available night",
                symbol: "moon.stars",
                tint: .purple
            )
            StatTile(
                label: "Profit per night",
                value: settings.formattedCompact(metrics.profitPerNight),
                symbol: "equal.circle",
                tint: Theme.resultColor(metrics.profitPerNight)
            )
            StatTile(
                label: "Margin",
                value: Fmt.percent(metrics.marginPercent),
                caption: "Net ÷ gross rents",
                symbol: "percent",
                tint: metrics.marginPercent > 0 ? .green : .red
            )
            StatTile(
                label: "Average stay",
                value: "\(Fmt.number(metrics.averageStayNights)) nights",
                caption: metrics.averageStayNights <= 7 && metrics.averageStayNights > 0
                    ? "Within the §469 seven-day exception"
                    : "Over the seven-day threshold",
                symbol: "bed.double",
                tint: .teal
            )
            StatTile(
                label: "Booking lead time",
                value: "\(Fmt.number(metrics.averageLeadTimeDays, fractionDigits: 0)) days",
                caption: "\(Fmt.percent(metrics.cancellationRatePercent)) cancelled",
                symbol: "calendar.badge.clock",
                tint: .orange
            )
        }
    }

    private var occupancyCard: some View {
        SectionCard("Nights booked by month", symbol: "calendar") {
            Chart(metrics.monthly) { point in
                BarMark(
                    x: .value("Month", point.label),
                    y: .value("Nights", point.nightsBooked)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
        }
    }

    private var breakEvenCard: some View {
        SectionCard(
            "Break-even",
            subtitle: "The point at which the property stops costing you money",
            symbol: "scalemass"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.percent(metrics.breakEvenOccupancyPercent))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(metrics.occupancyPercent >= metrics.breakEvenOccupancyPercent ? .green : .orange)
                    Text("occupancy needed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.nestedFill)
                        Capsule()
                            .fill(metrics.occupancyPercent >= metrics.breakEvenOccupancyPercent ? Color.green : Color.orange)
                            .frame(width: max(4, proxy.size.width * min(1, metrics.occupancyPercent / 100)))
                        if metrics.breakEvenOccupancyPercent > 0 && metrics.breakEvenOccupancyPercent <= 100 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.6))
                                .frame(width: 2)
                                .offset(x: proxy.size.width * (metrics.breakEvenOccupancyPercent / 100))
                        }
                    }
                }
                .frame(height: 12)

                DetailRow(
                    "Nights needed",
                    value: "\(metrics.breakEvenNights)",
                    caption: "You sold \(metrics.nightsBooked)."
                )
                Text("Fixed costs — interest, taxes, insurance and depreciation — divided by what each night contributes after cleaning, supplies and commission. It is the single most useful number for deciding whether to drop the rate to fill a gap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var platformCard: some View {
        SectionCard("Revenue by platform", symbol: "square.stack.3d.up") {
            Chart(metrics.revenueByPlatform) { slice in
                SectorMark(
                    angle: .value("Revenue", slice.amount.doubleValue),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(PropertyPalette.color(for: slice.colorHex))
                .cornerRadius(3)
            }
            .frame(height: 200)

            VStack(spacing: 6) {
                ForEach(metrics.revenueByPlatform) { slice in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(PropertyPalette.color(for: slice.colorHex))
                            .frame(width: 8, height: 8)
                        Text(slice.label).font(.caption)
                        Spacer()
                        Text(Fmt.ratioPercent(slice.share))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(settings.formattedCompact(slice.amount))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var propertyCard: some View {
        SectionCard("Revenue by property", symbol: "house") {
            Chart(metrics.revenueByProperty) { slice in
                BarMark(
                    x: .value("Revenue", slice.amount.doubleValue),
                    y: .value("Property", slice.label)
                )
                .foregroundStyle(PropertyPalette.color(for: slice.colorHex))
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Fmt.compactCurrency(Decimal(amount), code: settings.currencyCode))
                        }
                    }
                }
            }
            .frame(height: CGFloat(max(120, metrics.revenueByProperty.count * 44)))
        }
    }

    private var feeDragCard: some View {
        SectionCard("What the platforms take", symbol: "percent") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.percent(metrics.feeDragPercent))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                    Text("of gross rents")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                DetailRow("Fees paid", value: settings.formatted(metrics.platformFees))
                Text("Every dollar of this is deductible on Schedule E line 8. It never reaches your bank account, so it is the easiest deduction in the whole return to miss — and the one most likely to leave your 1099-K disagreeing with your return.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var yearOverYearCard: some View {
        SectionCard("\(year) against \(year - 1)", symbol: "arrow.left.arrow.right") {
            VStack(spacing: 8) {
                comparisonRow("Gross rents", metrics.grossRevenue, priorMetrics.grossRevenue)
                comparisonRow("Deductions", metrics.operatingExpenses + metrics.depreciation, priorMetrics.operatingExpenses + priorMetrics.depreciation)
                comparisonRow("Net result", metrics.netIncome, priorMetrics.netIncome)
                comparisonRow("Nights booked", Decimal(metrics.nightsBooked), Decimal(priorMetrics.nightsBooked), isCurrency: false)
            }
        }
    }

    private func comparisonRow(
        _ label: String,
        _ current: Decimal,
        _ prior: Decimal,
        isCurrency: Bool = true
    ) -> some View {
        let change = AnalyticsEngine.percentChange(from: prior, to: current)
        return HStack {
            Text(label).font(.subheadline)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(isCurrency ? settings.formatted(current) : "\(current)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                if let change {
                    Label(
                        Fmt.percent(abs(change)),
                        systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.caption2)
                    .foregroundStyle(change >= 0 ? .green : .red)
                } else {
                    Text("no prior-year data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
