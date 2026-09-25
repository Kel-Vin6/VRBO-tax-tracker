//
//  EstimatedTaxView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct EstimatedTaxView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationService.self) private var notifications
    @Environment(\.modelContext) private var context

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]
    @Query private var participationEntries: [ParticipationEntry]
    @Query(sort: \EstimatedTaxPayment.datePaid, order: .reverse) private var payments: [EstimatedTaxPayment]

    @State private var recordingPayment: Int?
    @State private var paymentAmount: Decimal = 0
    @State private var paymentDate = Date()
    @State private var paymentConfirmation = ""

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

    private var schedule: [QuarterlyDueDate] {
        TaxEstimator.quarterlySchedule(
            year: year,
            requirement: estimate.safeHarborRequirement,
            payments: payments
        )
    }

    private var paidToDate: Decimal {
        payments.filter { $0.taxYear == year }.map(\.amount).total
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                positionCard
                quartersCard
                breakdownCard
                safeHarborCard
                if !payments.filter({ $0.taxYear == year }).isEmpty { paymentsCard }
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Estimated tax")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { YearMenu() }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        if await notifications.requestAuthorization() {
                            await notifications.scheduleQuarterlyTaxReminders(
                                year: year,
                                amounts: schedule,
                                currencyCode: settings.currencyCode
                            )
                        }
                    }
                } label: {
                    Label("Remind me", systemImage: "bell")
                }
            }
        }
        .sheet(item: Binding(
            get: { recordingPayment.map { QuarterSelection(quarter: $0) } },
            set: { if $0 == nil { recordingPayment = nil } }
        )) { selection in
            recordPaymentSheet(quarter: selection.quarter)
        }
    }

    private struct QuarterSelection: Identifiable {
        let quarter: Int
        var id: Int { quarter }
    }

    // MARK: - Cards

    private var positionCard: some View {
        SectionCard("Where you stand", symbol: "scalemass") {
            VStack(spacing: 10) {
                DetailRow("Projected total tax", value: settings.formatted(estimate.totalTax), isEmphasised: true)
                DetailRow("Withholding and payments", value: settings.formatted(estimate.withholdingAndPayments))
                DetailRow(
                    estimate.isRefund ? "Projected refund" : "Projected balance due",
                    value: settings.formatted(abs(estimate.balanceDue)),
                    isEmphasised: true,
                    valueColor: estimate.isRefund ? .green : .orange
                )
                Divider()
                DetailRow(
                    "Safe harbor requirement",
                    value: settings.formatted(estimate.safeHarborRequirement),
                    caption: estimate.safeHarborBasis
                )
                DetailRow("Paid so far this year", value: settings.formatted(paidToDate))
            }
        }
    }

    private var quartersCard: some View {
        SectionCard("Instalments", subtitle: "Pay these and the underpayment penalty cannot apply", symbol: "calendar") {
            VStack(spacing: 12) {
                ForEach(schedule) { quarter in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(quarter.isPaid ? Color.green.opacity(0.18)
                                      : (quarter.isOverdue ? Color.red.opacity(0.18) : Theme.nestedFill))
                                .frame(width: 36, height: 36)
                            Image(systemName: quarter.isPaid ? "checkmark" : "\(quarter.quarter).circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(quarter.isPaid ? .green : (quarter.isOverdue ? .red : .secondary))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Q\(quarter.quarter) · due \(Fmt.mediumDate(quarter.dueDate))")
                                .font(.subheadline.weight(.medium))
                            Text(quarter.isPaid
                                 ? "Paid \(settings.formatted(quarter.amountPaid))"
                                 : (quarter.isOverdue
                                    ? "Overdue by \(abs(quarter.daysUntilDue)) day\(abs(quarter.daysUntilDue) == 1 ? "" : "s")"
                                    : "Covers \(quarter.periodLabel)"))
                                .font(.caption2)
                                .foregroundStyle(quarter.isOverdue && !quarter.isPaid ? .red : .secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(settings.formatted(quarter.remaining))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            if !quarter.isPaid {
                                Button("Record") {
                                    paymentAmount = quarter.remaining
                                    paymentDate = Date()
                                    recordingPayment = quarter.quarter
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                }
            }
        }
    }

    private var breakdownCard: some View {
        SectionCard("How the figure is built", symbol: "list.number") {
            VStack(spacing: 8) {
                DetailRow("Other income", value: settings.formatted(settings.otherOrdinaryIncome))
                DetailRow(
                    "Net rental result",
                    value: settings.formatted(report.totalNet),
                    valueColor: Theme.resultColor(report.totalNet)
                )
                if report.totalNet < 0 && !participation.lossIsNonPassive {
                    DetailRow(
                        "Loss allowed this year",
                        value: settings.formatted(Workspace.specialAllowance(
                            modifiedAGI: settings.modifiedAGI > 0 ? settings.modifiedAGI : settings.otherOrdinaryIncome,
                            filingStatus: settings.filingStatus
                        )),
                        caption: "The $25,000 special allowance for active participation, phased out between $100,000 and $150,000 of modified AGI. Anything beyond it is suspended until you have passive income or sell."
                    )
                }
                DetailRow("Gross income", value: settings.formatted(estimate.grossIncome), isEmphasised: true)
                DetailRow(
                    settings.useItemizedDeductions ? "Itemised deductions" : "Standard deduction",
                    value: settings.formatted(estimate.deduction)
                )
                if estimate.qbiDeduction > 0 {
                    DetailRow("§199A deduction", value: settings.formatted(estimate.qbiDeduction), valueColor: .green)
                }
                DetailRow("Taxable income", value: settings.formatted(estimate.taxableIncome), isEmphasised: true)
                Divider()
                DetailRow("Federal income tax", value: settings.formatted(estimate.federalTax))
                if estimate.netInvestmentIncomeTax > 0 {
                    DetailRow("Net investment income tax", value: settings.formatted(estimate.netInvestmentIncomeTax))
                }
                if estimate.stateTax > 0 {
                    DetailRow("State tax (\(Fmt.percent(settings.stateRatePercent)))", value: settings.formatted(estimate.stateTax))
                }
                DetailRow("Total tax", value: settings.formatted(estimate.totalTax), isEmphasised: true)
                DetailRow(
                    "Effective rate",
                    value: Fmt.percent(estimate.effectiveRatePercent),
                    caption: "Marginal rate \(Fmt.percent(estimate.marginalRatePercent))."
                )

                NavigationLink {
                    SettingsTaxProfileView()
                } label: {
                    Label("Edit your tax profile", systemImage: "person.text.rectangle")
                        .font(.subheadline)
                }
            }
        }
    }

    private var safeHarborCard: some View {
        SectionCard("Why the safe harbor matters", symbol: "shield.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 10) {
                Text("A short-term rental's income is lumpy and hard to predict. The safe harbor means you do not have to predict it: pay either 100% of last year's tax — 110% if your prior-year AGI was over $150,000 — or 90% of this year's, and the underpayment penalty cannot apply, however good the season turns out to be.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DetailRow(
                    "Your requirement",
                    value: settings.formatted(estimate.safeHarborRequirement),
                    caption: estimate.safeHarborBasis,
                    isEmphasised: true
                )
                if settings.priorYearTotalTax == 0 {
                    InfoCallout(
                        level: .info,
                        message: "Enter last year's total tax in Settings ▸ Tax profile and the app will use whichever safe harbor is cheaper."
                    )
                }
            }
        }
    }

    private var paymentsCard: some View {
        SectionCard("Payments recorded", symbol: "checkmark.circle") {
            VStack(spacing: 8) {
                ForEach(payments.filter { $0.taxYear == year }) { payment in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(payment.quarterLabel) · \(payment.jurisdiction.title)")
                                .font(.subheadline)
                            Text(Fmt.shortDate(payment.datePaid) + (payment.confirmationNumber.isEmpty ? "" : " · \(payment.confirmationNumber)"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(settings.formatted(payment.amount))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                        Button {
                            context.delete(payment)
                            try? context.save()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Record payment

    private func recordPaymentSheet(quarter: Int) -> some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    CurrencyField("Amount", amount: $paymentAmount, isProminent: true)
                    DatePicker("Paid on", selection: $paymentDate, displayedComponents: .date)
                    TextField("Confirmation number", text: $paymentConfirmation)
                }
            }
            .platformFormStyle()
            .navigationTitle("Record Q\(quarter) payment")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { recordingPayment = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let payment = EstimatedTaxPayment(
                            taxYear: year,
                            quarter: quarter,
                            jurisdiction: .federal,
                            amount: paymentAmount,
                            datePaid: paymentDate
                        )
                        payment.confirmationNumber = paymentConfirmation
                        context.insert(payment)
                        try? context.save()
                        paymentConfirmation = ""
                        recordingPayment = nil
                        Haptics.play(.success)
                    }
                    .disabled(paymentAmount <= 0)
                }
            }
        }
    }
}
