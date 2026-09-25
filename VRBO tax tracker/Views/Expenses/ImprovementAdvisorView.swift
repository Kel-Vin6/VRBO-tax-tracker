//
//  ImprovementAdvisorView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

/// The guided repair-versus-improvement decision, reachable both from an
/// expense being edited and on its own from the tax centre. It has no
/// navigation container of its own so it can be pushed; the sheet that
/// presents it supplies one.
struct ImprovementAdvisorView: View {

    var amount: Decimal
    var descriptionText: String
    var property: Property?
    var buildingSpendThisYear: Decimal
    var onDecision: ((Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var workAmount: Decimal = 0
    @State private var isBetterment = false
    @State private var isAdaptation = false
    @State private var isRestoration = false
    @State private var expectedToRecur = false
    @State private var grossReceipts: Decimal = 0
    @State private var buildingSpend: Decimal = 0

    private var input: ImprovementAssessment {
        var assessment = ImprovementAssessment()
        assessment.amount = workAmount
        assessment.description = descriptionText
        assessment.buildingUnadjustedBasis = property?.buildingBasis ?? 0
        assessment.averageAnnualGrossReceipts = grossReceipts
        assessment.totalBuildingSpendThisYear = buildingSpend
        assessment.isBetterment = isBetterment
        assessment.isAdaptation = isAdaptation
        assessment.isRestoration = isRestoration
        assessment.expectedToRecurWithinTenYears = expectedToRecur
        assessment.hasAuditedFinancialStatements = settings.hasAuditedFinancialStatements
        assessment.deMinimisElectionInPlace = settings.deMinimisElectionInPlace
        return assessment
    }

    private var marginalRate: Double {
        settings.useMarginalRateOverride && settings.marginalRateOverride > 0
            ? settings.marginalRateOverride
            : 22
    }

    private var verdict: ImprovementVerdict {
        RepairVsImprovementAdvisor.assess(
            input,
            marginalRatePercent: marginalRate,
            recoveryYears: property?.realPropertyRecoveryYears ?? 27.5
        )
    }

    var body: some View {
        Form {
            verdictSection
            workSection
            testsSection
            safeHarborSection
            ruleResultsSection
            decisionSection
        }
        .platformFormStyle()
        .navigationTitle("Repair or improvement")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            if workAmount == 0 { workAmount = amount }
            if buildingSpend == 0 { buildingSpend = buildingSpendThisYear }
        }
    }

    // MARK: - Sections

    private var verdictSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: verdict.outcome.symbol)
                        .font(.title2)
                        .foregroundStyle(verdict.outcome == .capitalize ? .orange : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verdict.headline)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verdict.outcome.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(verdict.reasoning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                DetailRow("Deducted this year", value: settings.formatted(verdict.deductionIfExpensed))
                DetailRow(
                    "If capitalised, year one",
                    value: settings.formatted(verdict.deductionIfCapitalized),
                    caption: "Over \(Fmt.number(verdict.yearsToRecover)) years, mid-month."
                )
                DetailRow(
                    "Cash difference this year",
                    value: settings.formatted(verdict.firstYearTaxDifference),
                    caption: "At a \(Fmt.percent(marginalRate)) marginal rate.",
                    isEmphasised: true,
                    valueColor: .green
                )

                if let suggested = verdict.suggestedAssetClass {
                    InfoCallout(
                        level: .info,
                        message: "If you capitalise this, add it as a \(suggested.title.lowercased()) asset on the property — \(Fmt.number(suggested.recoveryYears)) years rather than 27.5 for anything that is not the structure itself."
                    )
                }
            }
        }
    }

    private var workSection: some View {
        Section("The work") {
            CurrencyField("Cost", amount: $workAmount, isProminent: true)
            if !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty {
                DetailRow("Description", value: descriptionText)
            }
        }
    }

    private var testsSection: some View {
        Section {
            Toggle(isOn: $isBetterment) {
                toggleLabel(
                    "Betterment",
                    "Fixes a defect that was there when you bought it, is a material addition, or materially increases capacity, strength or quality."
                )
            }
            Toggle(isOn: $isAdaptation) {
                toggleLabel(
                    "Adaptation",
                    "Puts the property to a new or different use — converting a garage into a studio, for instance."
                )
            }
            Toggle(isOn: $isRestoration) {
                toggleLabel(
                    "Restoration",
                    "Replaces a major component or substantial structural part, rebuilds to like-new condition, or repairs damage after a casualty loss."
                )
            }
        } header: {
            Text("Does any of this apply?")
        } footer: {
            Text("These three tests are the whole question. If none of them is met, it is a repair.")
                .font(.caption2)
        }
    }

    private var safeHarborSection: some View {
        Section("Safe harbors") {
            Toggle(isOn: $expectedToRecur) {
                toggleLabel(
                    "You expect to do this again within ten years",
                    "Servicing the HVAC, resealing a deck, repainting. Recurring work is routine maintenance."
                )
            }
            CurrencyField(
                "All building spend this year",
                amount: $buildingSpend,
                caption: "Repairs, maintenance and improvements together, for the small taxpayer safe harbor."
            )
            CurrencyField(
                "Average annual gross receipts",
                amount: $grossReceipts,
                caption: "Across the last three years, all your businesses combined. The limit is $10 million."
            )
        }
    }

    private var ruleResultsSection: some View {
        Section("Tests") {
            ForEach(verdict.rules) { rule in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: rule.passed ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(rule.passed ? .green : .secondary)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name).font(.subheadline.weight(.medium))
                        Text(rule.explanation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var decisionSection: some View {
        if let onDecision {
            Section {
                Button {
                    onDecision(verdict.outcome == .capitalize)
                    dismiss()
                } label: {
                    Label(
                        verdict.outcome == .capitalize ? "Capitalise this expense" : "Deduct it this year",
                        systemImage: verdict.outcome.symbol
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func toggleLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The same advisor, opened from the tax centre with nothing pre-filled.
struct ImprovementAdvisorStandaloneView: View {

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @State private var property: Property?

    var body: some View {
        ImprovementAdvisorView(
            amount: 0,
            descriptionText: "",
            property: property,
            buildingSpendThisYear: 0,
            onDecision: nil
        )
        .onAppear {
            if property == nil { property = properties.first }
        }
    }
}
