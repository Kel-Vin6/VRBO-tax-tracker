//
//  RepairVsImprovementAdvisor.swift
//  VRBO tax tracker
//
//  The most expensive judgement call a host makes every year: is this a repair
//  deducted today, or an improvement written off over 27.5 years? The tangible
//  property regulations give three safe harbors and one test. This walks them
//  in the order that gets the money soonest.
//

import Foundation

public struct ImprovementAssessment: Hashable, Sendable {
    public var amount: Decimal = 0
    public var description: String = ""
    /// Unadjusted basis of the building the work was done on.
    public var buildingUnadjustedBasis: Decimal = 0
    /// Average annual gross receipts over the last three years.
    public var averageAnnualGrossReceipts: Decimal = 0
    /// Everything spent on repairs, maintenance and improvements on this
    /// building during the year, including this item.
    public var totalBuildingSpendThisYear: Decimal = 0

    /// Betterment: fixes a defect that existed when you bought it, is a material
    /// addition, or materially increases capacity, strength or quality.
    public var isBetterment: Bool = false
    /// Adaptation: puts the property to a new or different use.
    public var isAdaptation: Bool = false
    /// Restoration: replaces a major component, rebuilds to like-new, or
    /// restores after a casualty loss.
    public var isRestoration: Bool = false

    /// Work you reasonably expect to do more than once in a ten-year period.
    public var expectedToRecurWithinTenYears: Bool = false
    public var hasAuditedFinancialStatements: Bool = false
    /// The annual de minimis election is attached to the return.
    public var deMinimisElectionInPlace: Bool = true

    public init() {}
}

public enum ImprovementOutcome: String, Sendable {
    case deductNow
    case capitalize
    case ownerChoice

    public var title: String {
        switch self {
        case .deductNow: "Deduct this year"
        case .capitalize: "Capitalise and depreciate"
        case .ownerChoice: "Your call"
        }
    }

    public var symbol: String {
        switch self {
        case .deductNow: "arrow.down.circle.fill"
        case .capitalize: "calendar.badge.clock"
        case .ownerChoice: "arrow.triangle.branch"
        }
    }
}

public struct ImprovementRuleResult: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var passed: Bool
    public var explanation: String
}

public struct ImprovementVerdict: Hashable, Sendable {
    public var outcome: ImprovementOutcome
    public var headline: String
    public var reasoning: String
    public var rules: [ImprovementRuleResult]
    public var suggestedAssetClass: AssetClass?
    /// First-year deduction if expensed.
    public var deductionIfExpensed: Decimal
    /// First-year deduction if capitalised over the building's life.
    public var deductionIfCapitalized: Decimal
    /// Cash value of the timing difference in year one at the user's rate.
    public var firstYearTaxDifference: Decimal
    public var yearsToRecover: Double
}

public enum RepairVsImprovementAdvisor {

    public static let deMinimisLimitWithoutAFS: Decimal = 2_500
    public static let deMinimisLimitWithAFS: Decimal = 5_000
    public static let smallTaxpayerReceiptsLimit: Decimal = 10_000_000
    public static let smallTaxpayerBasisLimit: Decimal = 1_000_000
    public static let smallTaxpayerSpendCap: Decimal = 10_000

    public static func assess(
        _ input: ImprovementAssessment,
        marginalRatePercent: Double,
        recoveryYears: Double = 27.5
    ) -> ImprovementVerdict {

        var rules: [ImprovementRuleResult] = []

        // 1. De minimis safe harbor.
        let deMinimisLimit = input.hasAuditedFinancialStatements
            ? deMinimisLimitWithAFS
            : deMinimisLimitWithoutAFS
        let deMinimisPasses = input.deMinimisElectionInPlace && input.amount <= deMinimisLimit
        rules.append(
            ImprovementRuleResult(
                id: "deMinimis",
                name: "De minimis safe harbor",
                passed: deMinimisPasses,
                explanation: !input.deMinimisElectionInPlace
                    ? "The annual election is not attached to your return, so this safe harbor is unavailable. It costs nothing to make and it is the simplest of the three."
                    : (input.amount <= deMinimisLimit
                        ? "At \(Fmt.currency(input.amount)) this is within the \(Fmt.currency(deMinimisLimit, hideCents: true)) per-item limit, so it can be expensed regardless of the improvement tests."
                        : "\(Fmt.currency(input.amount)) exceeds the \(Fmt.currency(deMinimisLimit, hideCents: true)) per-item limit.")
            )
        )

        // 2. Routine maintenance safe harbor.
        let routinePasses = input.expectedToRecurWithinTenYears && !input.isAdaptation
        rules.append(
            ImprovementRuleResult(
                id: "routine",
                name: "Routine maintenance safe harbor",
                passed: routinePasses,
                explanation: routinePasses
                    ? "Work you expect to repeat within ten years keeps the building in ordinary operating condition, so it is maintenance rather than an improvement."
                    : (input.isAdaptation
                        ? "Work that adapts the property to a new use never qualifies as routine maintenance."
                        : "You do not expect to repeat this within ten years, so it falls outside routine maintenance.")
            )
        )

        // 3. Small taxpayer safe harbor.
        let spendCap = min(smallTaxpayerSpendCap, input.buildingUnadjustedBasis.applying(percent: 2))
        let smallTaxpayerPasses = input.averageAnnualGrossReceipts <= smallTaxpayerReceiptsLimit
            && input.buildingUnadjustedBasis > 0
            && input.buildingUnadjustedBasis <= smallTaxpayerBasisLimit
            && input.totalBuildingSpendThisYear <= spendCap
        rules.append(
            ImprovementRuleResult(
                id: "smallTaxpayer",
                name: "Small taxpayer safe harbor",
                passed: smallTaxpayerPasses,
                explanation: input.buildingUnadjustedBasis <= 0
                    ? "Enter the building's unadjusted basis to test this safe harbor."
                    : (smallTaxpayerPasses
                        ? "Total building spend of \(Fmt.currency(input.totalBuildingSpendThisYear)) is within your \(Fmt.currency(spendCap)) cap — the lesser of $10,000 and 2% of unadjusted basis — so everything spent on this building this year can be expensed."
                        : "Total building spend of \(Fmt.currency(input.totalBuildingSpendThisYear)) exceeds your \(Fmt.currency(spendCap)) cap, so this safe harbor is unavailable for the year.")
            )
        )

        // 4. The BAR test.
        let barTriggered = input.isBetterment || input.isAdaptation || input.isRestoration
        var barReasons: [String] = []
        if input.isBetterment { barReasons.append("betterment") }
        if input.isAdaptation { barReasons.append("adaptation to a new use") }
        if input.isRestoration { barReasons.append("restoration") }
        rules.append(
            ImprovementRuleResult(
                id: "bar",
                name: "Betterment, adaptation or restoration",
                passed: !barTriggered,
                explanation: barTriggered
                    ? "You identified this as \(barReasons.joined(separator: ", ")), which makes it an improvement unless a safe harbor rescues it."
                    : "None of the three improvement tests are met, so this is a deductible repair."
            )
        )

        // Decide.
        let outcome: ImprovementOutcome
        let headline: String
        let reasoning: String

        if deMinimisPasses {
            outcome = .deductNow
            headline = "Deduct it in full this year"
            reasoning = "The de minimis safe harbor applies, and it overrides the improvement tests entirely. Keep the invoice showing the per-item cost."
        } else if smallTaxpayerPasses {
            outcome = .deductNow
            headline = "Deduct it under the small taxpayer safe harbor"
            reasoning = "Your building qualifies and total spend for the year is under the cap. Watch the cap — one more invoice can push the whole year out of the safe harbor."
        } else if routinePasses && !input.isRestoration {
            outcome = .deductNow
            headline = "Deduct it as routine maintenance"
            reasoning = "Recurring work that keeps the building in its ordinary operating condition is maintenance, not an improvement."
        } else if barTriggered {
            outcome = .capitalize
            headline = "Capitalise and depreciate it"
            reasoning = "This is \(barReasons.joined(separator: ", ")) and no safe harbor applies. Add it as an asset so the depreciation schedule picks it up from the month the work was finished."
        } else {
            outcome = .ownerChoice
            headline = "Defensible either way — take the deduction"
            reasoning = "No improvement test is met and no safe harbor is needed, so this is an ordinary repair. Record what was done and why it restored rather than improved the property."
        }

        // The timing difference, which is the whole point of the question.
        let expensed = outcome == .capitalize ? Decimal.zero : input.amount
        let firstYearCapitalized = recoveryYears > 0
            ? (input.amount / Decimal(recoveryYears) / 2).rounded(2)
            : 0
        let difference = max(0, input.amount - firstYearCapitalized)

        return ImprovementVerdict(
            outcome: outcome,
            headline: headline,
            reasoning: reasoning,
            rules: rules,
            suggestedAssetClass: outcome == .capitalize ? suggestedClass(for: input) : nil,
            deductionIfExpensed: expensed == 0 ? input.amount : expensed,
            deductionIfCapitalized: firstYearCapitalized,
            firstYearTaxDifference: difference.applying(percent: marginalRatePercent.clampedPercent),
            yearsToRecover: recoveryYears
        )
    }

    private static func suggestedClass(for input: ImprovementAssessment) -> AssetClass {
        let text = input.description.lowercased()
        if text.contains("carpet") || text.contains("flooring") || text.contains("rug") {
            return .carpetAndFlooring
        }
        if text.contains("fence") || text.contains("driveway") || text.contains("landscap")
            || text.contains("pool") || text.contains("patio") || text.contains("deck") {
            return .landImprovement
        }
        if text.contains("lock") || text.contains("camera") || text.contains("router")
            || text.contains("thermostat") || text.contains("wifi") {
            return .computerAndTech
        }
        if text.contains("sofa") || text.contains("bed") || text.contains("furnitur")
            || text.contains("appliance") || text.contains("fridge") || text.contains("washer") {
            return .applianceAndFurniture
        }
        return .residentialBuilding
    }

    /// Builds an assessment pre-filled from an expense and its property, so the
    /// user only answers the three judgement questions.
    public static func assessment(
        for expense: Expense,
        property: Property?,
        yearBuildingSpend: Decimal,
        annualGrossReceipts: Decimal,
        hasAuditedFinancials: Bool,
        deMinimisElection: Bool
    ) -> ImprovementAssessment {
        var input = ImprovementAssessment()
        input.amount = expense.amount
        input.description = "\(expense.displayVendor) \(expense.notes)"
        input.buildingUnadjustedBasis = property?.buildingBasis ?? 0
        input.averageAnnualGrossReceipts = annualGrossReceipts
        input.totalBuildingSpendThisYear = yearBuildingSpend
        input.hasAuditedFinancialStatements = hasAuditedFinancials
        input.deMinimisElectionInPlace = deMinimisElection
        return input
    }
}
