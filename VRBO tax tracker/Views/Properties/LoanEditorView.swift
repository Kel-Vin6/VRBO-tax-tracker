//
//  LoanEditorView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct LoanEditorView: View {

    let loan: LoanAccount?
    let property: Property

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState

    @State private var lender = ""
    @State private var accountReference = ""
    @State private var originalPrincipal: Decimal = 0
    @State private var annualRate: Double = 0
    @State private var termMonths = 360
    @State private var firstPaymentDate = Date()
    @State private var isPrimary = true
    @State private var pointsPaid: Decimal = 0
    @State private var monthlyEscrow: Decimal = 0
    @State private var extraPrincipal: Decimal = 0
    @State private var autoDeductInterest = true
    @State private var notes = ""
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool { loan != nil }

    private var draft: LoanAccount {
        let candidate = LoanAccount(
            lender: lender,
            originalPrincipal: originalPrincipal,
            annualRatePercent: annualRate,
            termMonths: max(1, termMonths),
            firstPaymentDate: firstPaymentDate
        )
        candidate.pointsPaid = pointsPaid
        candidate.monthlyEscrow = monthlyEscrow
        candidate.extraMonthlyPrincipal = extraPrincipal
        candidate.autoDeductInterest = autoDeductInterest
        return candidate
    }

    private var summaries: [LoanYearSummary] {
        LoanAmortizationEngine.yearSummaries(for: draft)
    }

    private var currentYearSummary: LoanYearSummary? {
        summaries.first { $0.year == appState.taxYear }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LiveSummaryStrip(items: [
                        .init(label: "Payment", value: settings.formatted(draft.scheduledPayment)),
                        .init(
                            label: "\(appState.taxYear) interest",
                            value: settings.formatted(currentYearSummary?.deductible ?? 0),
                            tint: .green
                        ),
                        .init(
                            label: "Balance",
                            value: settings.formattedCompact(LoanAmortizationEngine.balance(for: draft))
                        )
                    ])
                }

                Section("Loan") {
                    TextField("Lender", text: $lender)
                    TextField("Account reference", text: $accountReference)
                    CurrencyField("Original principal", amount: $originalPrincipal)
                    PercentField("Interest rate", value: $annualRate, range: 0...20)
                    IntegerField("Term", value: $termMonths, unit: "months")
                    DatePicker("First payment", selection: $firstPaymentDate, displayedComponents: .date)
                    Toggle("Primary mortgage", isOn: $isPrimary)
                }

                Section {
                    CurrencyField("Monthly escrow", amount: $monthlyEscrow, caption: "Taxes and insurance collected with the payment. Not interest, and deducted on their own lines.")
                    CurrencyField("Extra principal each month", amount: $extraPrincipal)
                    CurrencyField(
                        "Points paid at closing",
                        amount: $pointsPaid,
                        caption: pointsPaid > 0
                            ? "Amortised at \(settings.formatted(draft.annualPointsAmortization)) a year over the life of the loan — rental points are not deducted all at once."
                            : "Points on a rental loan are written off over the loan term, not in the year paid."
                    )
                } header: {
                    Text("Payment detail")
                }

                Section {
                    Toggle("Deduct the interest automatically", isOn: $autoDeductInterest)
                    Text(autoDeductInterest
                         ? "The interest portion of each scheduled payment flows to Schedule E line 12. Do not also enter a mortgage interest expense, or it will be counted twice."
                         : "Interest is not deducted from this schedule. Record it as an expense instead, from your Form 1098.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Schedule E")
                }

                if !summaries.isEmpty {
                    Section("Interest by year") {
                        ForEach(summaries.prefix(10)) { summary in
                            HStack {
                                Text(verbatim: "\(summary.year)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .frame(width: 52, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(settings.formatted(summary.interest))
                                        .font(.subheadline)
                                        .monospacedDigit()
                                    Text("principal \(settings.formatted(summary.principal))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(settings.formattedCompact(summary.endingBalance))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete loan", systemImage: "trash")
                        }
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle(isEditing ? "Edit loan" : "New loan")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(originalPrincipal <= 0)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete this loan?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete loan", role: .destructive) { deleteLoan() }
            }
        }
    }

    private func load() {
        guard let loan else { return }
        lender = loan.lender
        accountReference = loan.accountReference
        originalPrincipal = loan.originalPrincipal
        annualRate = loan.annualRatePercent
        termMonths = loan.termMonths
        firstPaymentDate = loan.firstPaymentDate
        isPrimary = loan.isPrimaryMortgage
        pointsPaid = loan.pointsPaid
        monthlyEscrow = loan.monthlyEscrow
        extraPrincipal = loan.extraMonthlyPrincipal
        autoDeductInterest = loan.autoDeductInterest
        notes = loan.notes
    }

    private func save() {
        let target = loan ?? LoanAccount()
        if loan == nil { context.insert(target) }

        target.lender = lender
        target.accountReference = accountReference
        target.originalPrincipal = originalPrincipal
        target.annualRatePercent = annualRate
        target.termMonths = max(1, termMonths)
        target.firstPaymentDate = firstPaymentDate
        target.isPrimaryMortgage = isPrimary
        target.pointsPaid = pointsPaid
        target.monthlyEscrow = monthlyEscrow
        target.extraMonthlyPrincipal = extraPrincipal
        target.autoDeductInterest = autoDeductInterest
        target.notes = notes
        target.property = property

        try? context.save()
        Haptics.play(.success)
        dismiss()
    }

    private func deleteLoan() {
        guard let loan else { return }
        context.delete(loan)
        try? context.save()
        dismiss()
    }
}
