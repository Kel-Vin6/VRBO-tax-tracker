//
//  TaxCentreView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct TaxCentreView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]
    @Query private var participationEntries: [ParticipationEntry]
    @Query private var payments: [EstimatedTaxPayment]
    @Query private var forms: [PlatformTaxForm]

    private var year: Int { appState.taxYear }

    private var report: ScheduleEReport {
        Workspace.report(year: year, properties: properties, expenses: expenses, trips: trips, settings: settings)
    }

    private var participation: MaterialParticipationAnalysis {
        Workspace.participation(year: year, properties: properties, entries: participationEntries, settings: settings)
    }

    private var estimate: TaxEstimateResult {
        Workspace.estimate(year: year, report: report, participation: participation, payments: payments, settings: settings)
    }

    private var reconciliations: [PlatformReconciliation] {
        ReconciliationEngine.reconcile(
            year: year,
            bookings: properties.flatMap(\.bookingList),
            forms: forms
        )
    }

    private var unreconciled: Int {
        reconciliations.filter { $0.hasForm && !$0.isReconciled }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if properties.isEmpty {
                        EmptyStateView(
                            symbol: "doc.text.magnifyingglass",
                            title: "Nothing to report yet",
                            message: "Add a property and some bookings, and the tax centre fills in from your own records."
                        )
                        .frame(minHeight: 300)
                    } else {
                        headlineCard
                        toolsGrid
                        if settings.providesHotelLikeServices { substantialServicesCard }
                        if estimate.isTableEstimated { rateTableNotice }
                        qbiCard
                        TaxDisclaimer().padding(.bottom, 24)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("Tax centre")
            .toolbar { ToolbarItem(placement: .principal) { YearMenu() } }
        }
    }

    // MARK: - Headline

    private var headlineCard: some View {
        SectionCard(
            "\(year) position",
            subtitle: participation.lossIsNonPassive
                ? "Non-passive — losses can offset your other income"
                : "Passive rental activity",
            symbol: "chart.bar.doc.horizontal"
        ) {
            VStack(spacing: 10) {
                DetailRow("Rents received", value: settings.formatted(report.totalRents), isEmphasised: true)
                DetailRow("Total deductions", value: settings.formatted(report.totalExpenses))
                DetailRow(
                    "Net rental result",
                    value: settings.formatted(report.totalNet),
                    isEmphasised: true,
                    valueColor: Theme.resultColor(report.totalNet)
                )
                Divider()
                DetailRow(
                    "Tax caused by the rentals",
                    value: settings.formatted(estimate.taxAttributableToRentals),
                    caption: "Federal tax with the rentals, less federal tax without them.",
                    valueColor: .orange
                )
                DetailRow(
                    "Marginal rate",
                    value: Fmt.percent(estimate.marginalRatePercent),
                    caption: "Every extra dollar of rental profit is taxed at this rate — and every extra deduction saves it."
                )
                if estimate.netInvestmentIncomeTax > 0 {
                    DetailRow(
                        "Net investment income tax",
                        value: settings.formatted(estimate.netInvestmentIncomeTax),
                        caption: "3.8% on passive rental income above the threshold for your filing status.",
                        valueColor: .orange
                    )
                }
                if report.totalCarryforward > 0 {
                    DetailRow(
                        "Carried to \(year + 1)",
                        value: settings.formatted(report.totalCarryforward),
                        caption: "Deductions disallowed this year by the §280A income cap.",
                        valueColor: .secondary
                    )
                }
            }
        }
    }

    // MARK: - Tools

    private var toolsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
            toolLink(
                title: "Schedule E",
                detail: "Line by line, per property, ready to hand over.",
                symbol: "doc.text",
                tint: .blue,
                badge: nil
            ) { ScheduleEView() }

            toolLink(
                title: "Estimated tax",
                detail: estimate.safeHarborBasis,
                symbol: "calendar.badge.clock",
                tint: .orange,
                badge: quartersDueBadge
            ) { EstimatedTaxView() }

            toolLink(
                title: "Material participation",
                detail: participation.statusTitle,
                symbol: "clock.badge.checkmark",
                tint: participation.lossIsNonPassive ? .green : .purple,
                badge: nil
            ) { ParticipationTestsView() }

            toolLink(
                title: "Personal use radar",
                detail: personalUseSummary,
                symbol: "calendar.badge.exclamationmark",
                tint: personalUseTint,
                badge: nil
            ) { PersonalUseView() }

            toolLink(
                title: "Depreciation",
                detail: "\(settings.formattedCompact(report.totalDepreciation)) this year across every asset.",
                symbol: "chart.line.downtrend.xyaxis",
                tint: .teal,
                badge: nil
            ) { DepreciationView() }

            toolLink(
                title: "1099-K reconciliation",
                detail: unreconciled > 0
                    ? "\(unreconciled) platform\(unreconciled == 1 ? "" : "s") do not agree with your records."
                    : "Match the platforms' figures to yours before filing.",
                symbol: "arrow.left.arrow.right",
                tint: unreconciled > 0 ? .red : .indigo,
                badge: unreconciled > 0 ? "\(unreconciled)" : nil
            ) { ReconciliationView() }

            toolLink(
                title: "Scenario lab",
                detail: "What a purchase, a rate rise or a week of your own really costs.",
                symbol: "flask",
                tint: .pink,
                badge: nil
            ) { ScenarioLabView() }

            toolLink(
                title: "Repair or improvement",
                detail: "Deduct it now, or write it off over 27.5 years?",
                symbol: "arrow.triangle.branch",
                tint: .brown,
                badge: nil
            ) { ImprovementAdvisorStandaloneView() }
        }
    }

    private var quartersDueBadge: String? {
        let schedule = TaxEstimator.quarterlySchedule(
            year: year,
            requirement: estimate.safeHarborRequirement,
            payments: payments
        )
        let overdue = schedule.filter(\.isOverdue).count
        return overdue > 0 ? "\(overdue)" : nil
    }

    private var personalUseSummary: String {
        let flagged = properties.filter { property in
            PersonalUseEngine.analyze(
                bookings: property.bookingList,
                personalUse: property.personalUseList,
                year: year,
                propertyID: property.id,
                daysAvailable: property.daysAvailablePerYear
            ).classification != .rentalProperty
        }
        if flagged.isEmpty { return "Every property is within the §280A limit." }
        return "\(flagged.count) propert\(flagged.count == 1 ? "y is" : "ies are") outside the limit."
    }

    private var personalUseTint: Color {
        personalUseSummary.hasPrefix("Every") ? .green : .red
    }

    private func toolLink<Destination: View>(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        badge: String?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: symbol)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                        }
                    }
                    Text(detail)
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
            .padding(14)
            .cardSurface(radius: Theme.tileRadius)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notices

    private var substantialServicesCard: some View {
        InfoCallout(
            level: .caution,
            title: "You may belong on Schedule C",
            message: TaxEstimator.substantialServicesWarning(providesHotelLikeServices: true) ?? ""
        )
    }

    private var rateTableNotice: some View {
        InfoCallout(
            level: .info,
            title: "Rate table carried forward",
            message: "This build has no published bracket table for \(year), so \(FederalRates.latestPublishedYear) figures are being used. Check the brackets in Settings ▸ Tax profile before you rely on the estimate."
        )
    }

    private var qbiCard: some View {
        SectionCard(
            "Qualified business income (§199A)",
            subtitle: participation.meetsQBISafeHarbor ? "Safe harbor hours met" : "Safe harbor hours not met",
            symbol: "percent"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Rental services hours")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Fmt.hours(participation.qbiSafeHarborHours)) of \(Fmt.hours(MaterialParticipationEngine.qbiSafeHarborHours))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                ProgressView(
                    value: min(1, participation.qbiSafeHarborHours / MaterialParticipationEngine.qbiSafeHarborHours)
                )
                .tint(participation.meetsQBISafeHarbor ? .green : .orange)

                Text("The rental real estate safe harbor treats an enterprise as a trade or business for the 20% qualified business income deduction if 250 hours of rental services are performed, separate books are kept, and contemporaneous records are maintained. The safe harbor is not the only route — rentals can qualify without it — but it is the only one with a bright line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if estimate.qbiDeduction > 0 {
                    DetailRow(
                        "Deduction in this estimate",
                        value: settings.formatted(estimate.qbiDeduction),
                        isEmphasised: true,
                        valueColor: .green
                    )
                } else if !settings.claimQBIDeduction {
                    Text("The estimate does not currently claim this deduction. Turn it on in Settings ▸ Tax profile once you and your accountant agree it applies.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
