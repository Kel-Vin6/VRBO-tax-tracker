//
//  DashboardView.swift
//  VRBO tax tracker
//

import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \MileageTrip.date, order: .reverse) private var trips: [MileageTrip]
    @Query(sort: \ParticipationEntry.date, order: .reverse) private var participationEntries: [ParticipationEntry]
    @Query private var payments: [EstimatedTaxPayment]
    @Query private var documents: [StoredDocument]

    @State private var showingYearPicker = false

    private var year: Int { appState.taxYear }

    private var report: ScheduleEReport {
        Workspace.report(
            year: year,
            properties: properties,
            expenses: expenses,
            trips: trips,
            settings: settings
        )
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

    private var participation: MaterialParticipationAnalysis {
        Workspace.participation(
            year: year,
            properties: properties,
            entries: participationEntries,
            settings: settings
        )
    }

    private var estimate: TaxEstimateResult {
        Workspace.estimate(
            year: year,
            report: report,
            participation: participation,
            payments: payments,
            settings: settings
        )
    }

    private var audit: AuditReadinessReport {
        AuditReadinessEngine.evaluate(
            year: year,
            properties: properties,
            expenses: expenses,
            trips: trips,
            participation: participationEntries,
            documents: documents
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if properties.isEmpty {
                    firstRunState
                } else {
                    content
                }
            }
            .navigationTitle("Dashboard")
            .toolbar { toolbarContent }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeroSummaryCard(
                    report: report,
                    estimate: estimate,
                    metrics: metrics,
                    year: year
                )

                alertsSection

                statsGrid

                if metrics.monthly.contains(where: { $0.revenue > 0 || $0.expenses > 0 }) {
                    RevenueChartCard(metrics: metrics)
                }

                taxTimelineCard

                propertiesSection

                if !metrics.expensesByLine.isEmpty {
                    DeductionBreakdownCard(metrics: metrics)
                }

                auditCard

                TaxDisclaimer()
                    .padding(.horizontal, 4)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.automatic)
    }

    // MARK: - Alerts

    private var alerts: [DashboardAlert] {
        var items: [DashboardAlert] = []

        for property in properties {
            for flag in property.complianceFlags() where flag.isCritical || flag.id.contains("Expiring") {
                items.append(
                    DashboardAlert(
                        id: "\(property.id)-\(flag.id)",
                        title: property.displayName,
                        message: flag.message,
                        symbol: flag.symbol,
                        tint: flag.isCritical ? .red : .orange,
                        tab: .more
                    )
                )
            }

            let analysis = PersonalUseEngine.analyze(
                bookings: property.bookingList,
                personalUse: property.personalUseList,
                year: year,
                propertyID: property.id,
                daysAvailable: property.daysAvailablePerYear
            )
            if analysis.classification == .residenceWithRentalUse {
                items.append(
                    DashboardAlert(
                        id: "\(property.id)-280a",
                        title: "\(property.displayName) is a residence this year",
                        message: "Personal use of \(analysis.personalUseDays) days passed the \(analysis.personalUseThreshold)-day limit. Deductions are capped at rental income and no loss can be claimed.",
                        symbol: "exclamationmark.triangle.fill",
                        tint: .red,
                        tab: .taxes
                    )
                )
            } else if (1...5).contains(analysis.headroomDays) {
                items.append(
                    DashboardAlert(
                        id: "\(property.id)-280a-close",
                        title: "\(property.displayName): \(analysis.headroomDays) personal days left",
                        message: "One more week of owner stays turns this into a residence for tax purposes.",
                        symbol: "calendar.badge.exclamationmark",
                        tint: .orange,
                        tab: .taxes
                    )
                )
            }
        }

        if let critical = audit.findings.first(where: { $0.severity == .critical }) {
            items.append(
                DashboardAlert(
                    id: "audit-\(critical.id)",
                    title: critical.title,
                    message: critical.detail,
                    symbol: critical.severity.symbol,
                    tint: .red,
                    tab: .more
                )
            )
        }

        return Array(items.prefix(4))
    }

    @ViewBuilder
    private var alertsSection: some View {
        if !alerts.isEmpty {
            VStack(spacing: 10) {
                ForEach(alerts) { alert in
                    Button {
                        appState.selectedTab = alert.tab
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: alert.symbol)
                                .foregroundStyle(alert.tint)
                                .font(.subheadline)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(alert.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(alert.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
            spacing: 12
        ) {
            StatTile(
                label: "Gross rents",
                value: settings.formattedCompact(report.totalRents),
                caption: "\(metrics.completedStays) stay\(metrics.completedStays == 1 ? "" : "s"), \(metrics.nightsBooked) nights",
                symbol: "dollarsign.circle",
                tint: .green
            )
            StatTile(
                label: "Deductions",
                value: settings.formattedCompact(report.totalExpenses),
                caption: "Including \(settings.formattedCompact(report.totalDepreciation)) depreciation",
                symbol: "minus.circle",
                tint: .orange
            )
            StatTile(
                label: "Net for Schedule E",
                value: settings.formattedCompact(report.totalNet),
                caption: report.totalNet < 0 ? "A loss — see whether it is deductible" : "Taxable rental income",
                symbol: "equal.circle",
                tint: report.totalNet < 0 ? .red : .blue
            )
            StatTile(
                label: "Cash kept",
                value: settings.formattedCompact(report.totalCashFlow),
                caption: "Before the non-cash depreciation deduction",
                symbol: "banknote",
                tint: .teal
            )
            StatTile(
                label: "Occupancy",
                value: Fmt.percent(metrics.occupancyPercent),
                caption: "Break-even at \(Fmt.percent(metrics.breakEvenOccupancyPercent))",
                symbol: "chart.pie",
                tint: .purple
            )
            StatTile(
                label: "Average nightly rate",
                value: settings.formattedCompact(metrics.averageDailyRate),
                caption: "RevPAR \(settings.formattedCompact(metrics.revPAR))",
                symbol: "moon.stars",
                tint: .indigo
            )
        }
    }

    // MARK: - Tax timeline

    private var quarters: [QuarterlyDueDate] {
        TaxEstimator.quarterlySchedule(
            year: year,
            requirement: estimate.safeHarborRequirement,
            payments: payments
        )
    }

    @ViewBuilder
    private var taxTimelineCard: some View {
        if let next = quarters.first(where: { !$0.isPaid }) {
            SectionCard(
                "Next estimated payment",
                subtitle: estimate.safeHarborBasis,
                symbol: "calendar.badge.clock"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.formatted(next.remaining))
                                .font(.title.weight(.semibold))
                                .monospacedDigit()
                            Text("Q\(next.quarter) \(year) · due \(Fmt.mediumDate(next.dueDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(next.isOverdue ? "Overdue" : "\(next.daysUntilDue) days")
                                .font(.headline)
                                .foregroundStyle(next.isOverdue ? .red : .primary)
                            Text(next.periodLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        EstimatedTaxView()
                    } label: {
                        Label("Open the estimator", systemImage: "arrow.right.circle")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Properties

    private var propertiesSection: some View {
        SectionCard("Properties", subtitle: "\(properties.count) tracked", symbol: "house") {
            VStack(spacing: 10) {
                ForEach(properties) { property in
                    NavigationLink {
                        PropertyDetailView(property: property)
                    } label: {
                        PropertyRow(
                            property: property,
                            column: report.columns.first(where: { $0.id == property.id }),
                            settings: settings
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    PropertiesView()
                } label: {
                    Label("Manage properties", systemImage: "slider.horizontal.3")
                        .font(.subheadline)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Audit

    private var auditCard: some View {
        NavigationLink {
            AuditReadinessView()
        } label: {
            SectionCard("Audit readiness", subtitle: audit.headline, symbol: "checkmark.shield") {
                HStack(spacing: 16) {
                    ProgressRing(
                        progress: Double(audit.score) / 100,
                        tint: audit.score >= 85 ? .green : (audit.score >= 65 ? .orange : .red),
                        label: "\(audit.score)",
                        caption: audit.grade
                    )
                    .frame(width: 84, height: 84)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(audit.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if audit.totalAtRisk > 0 {
                            TagChip(
                                "\(settings.formatted(audit.totalAtRisk)) at risk",
                                symbol: "exclamationmark.triangle",
                                tint: .orange
                            )
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - First run

    private var firstRunState: some View {
        ScrollView {
            VStack(spacing: 20) {
                EmptyStateView(
                    symbol: "house.and.flag",
                    title: "Add your first property",
                    message: "Everything else — bookings, receipts, mileage, depreciation and Schedule E — hangs off a property. It takes about a minute to set one up.",
                    actionTitle: "Add a property"
                ) {
                    appState.open(.property)
                }
                .frame(minHeight: 320)

                SectionCard("What this app does for you", symbol: "sparkles") {
                    VStack(alignment: .leading, spacing: 12) {
                        FeatureLine(symbol: "doc.text", title: "Builds Schedule E for you", detail: "Every expense you log lands on a numbered line of the form, per property.")
                        FeatureLine(symbol: "calendar.badge.exclamationmark", title: "Watches the 14-day rule", detail: "Tells you how many personal nights you have left before the loss disappears.")
                        FeatureLine(symbol: "chart.line.downtrend.xyaxis", title: "Runs real MACRS depreciation", detail: "27.5-year mid-month for the building, with bonus and §179 on the contents.")
                        FeatureLine(symbol: "clock.badge.checkmark", title: "Tracks material participation", detail: "The hours that decide whether your loss is passive or not.")
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(QuickAction.allCases) { action in
                    Button {
                        appState.open(action)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .principal) {
            YearMenu()
        }
    }
}

// MARK: - Supporting views

private struct DashboardAlert: Identifiable {
    let id: String
    let title: String
    let message: String
    let symbol: String
    let tint: Color
    let tab: AppTab
}

struct FeatureLine: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct PropertyRow: View {
    let property: Property
    let column: ScheduleEColumn?
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            PropertyBadge(
                name: property.displayName,
                monogram: property.monogram,
                color: property.color,
                showsName: false
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(property.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(column.map { "\($0.fairRentalDays) rental days · \($0.personalUseDays) personal" } ?? property.shortAddress)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(settings.formattedCompact(column?.netIncomeOrLoss ?? 0))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.resultColor(column?.netIncomeOrLoss ?? 0))
                Text("net")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

/// The year selector that every screen shares.
struct YearMenu: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            ForEach(DateMath.selectableYears(), id: \.self) { year in
                Button {
                    appState.taxYear = year
                    Haptics.play(.selection)
                } label: {
                    if year == appState.taxYear {
                        Label("\(year)", systemImage: "checkmark")
                    } else {
                        Text(verbatim: "\(year)")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: "\(appState.taxYear)")
                    .font(.headline)
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
        }
        .accessibilityLabel("Tax year, currently \(appState.taxYear)")
    }
}
