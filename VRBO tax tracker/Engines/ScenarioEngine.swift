//
//  ScenarioEngine.swift
//  VRBO tax tracker
//
//  "If I buy the hot tub in December instead of January, what does it actually
//  save me?" Hosts ask this every autumn and almost never get a number. This
//  answers it against their real figures.
//

import Foundation

public enum ScenarioKind: String, CaseIterable, Identifiable, Sendable {
    case deductibleExpense
    case capitalPurchase
    case extraBookings
    case rateIncrease
    case personalUseDays
    case sellProperty

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .deductibleExpense: "Spend on a deductible expense"
        case .capitalPurchase: "Buy a capital asset"
        case .extraBookings: "Book more nights"
        case .rateIncrease: "Raise the nightly rate"
        case .personalUseDays: "Take personal days"
        case .sellProperty: "Sell the property"
        }
    }

    public var symbol: String {
        switch self {
        case .deductibleExpense: "cart.badge.minus"
        case .capitalPurchase: "shippingbox"
        case .extraBookings: "calendar.badge.plus"
        case .rateIncrease: "arrow.up.right"
        case .personalUseDays: "figure.and.child.holdinghands"
        case .sellProperty: "house.badge.minus"
        }
    }

    public var detail: String {
        switch self {
        case .deductibleExpense: "See the after-tax cost of a purchase before you make it."
        case .capitalPurchase: "Compare bonus depreciation against a full MACRS schedule."
        case .extraBookings: "Work out what filling the calendar is worth after tax."
        case .rateIncrease: "Every extra dollar of rent is taxed — see what you keep."
        case .personalUseDays: "Check what blocking the calendar costs before you block it."
        case .sellProperty: "Estimate depreciation recapture and the tax on the gain."
        }
    }
}

public struct ScenarioResult: Hashable, Sendable {
    public var headline: String
    public var netIncomeChange: Decimal
    public var taxChange: Decimal
    public var afterTaxChange: Decimal
    public var effectiveCostOrBenefit: Decimal
    public var explanation: String
    public var warnings: [String]
    public var breakdown: [ReconciliationLine]
}

public enum ScenarioEngine {

    /// A deductible expense costs the marginal rate less than its sticker price.
    public static func deductibleExpense(
        amount: Decimal,
        marginalRatePercent: Double,
        stateRatePercent: Double
    ) -> ScenarioResult {
        let combinedRate = (marginalRatePercent + stateRatePercent).clampedPercent
        let saving = amount.applying(percent: combinedRate)
        let afterTaxCost = amount - saving

        return ScenarioResult(
            headline: "\(Fmt.currency(amount)) of spending costs you \(Fmt.currency(afterTaxCost))",
            netIncomeChange: -amount,
            taxChange: -saving,
            afterTaxChange: -afterTaxCost,
            effectiveCostOrBenefit: afterTaxCost,
            explanation: "At a combined marginal rate of \(Fmt.percent(combinedRate)), the deduction returns \(Fmt.currency(saving)) of the \(Fmt.currency(amount)) you spend. That only holds if the rental can actually absorb the deduction this year — a suspended passive loss defers the benefit rather than delivering it.",
            warnings: combinedRate <= 0
                ? ["Set your marginal tax rate in Settings for a meaningful figure."]
                : [],
            breakdown: [
                ReconciliationLine(id: "cost", label: "Cash out", amount: amount, detail: "What leaves your account."),
                ReconciliationLine(id: "saving", label: "Tax saved", amount: saving, detail: "Deduction × \(Fmt.percent(combinedRate))."),
                ReconciliationLine(id: "net", label: "True cost", amount: afterTaxCost, detail: "What the purchase really costs you.", isSubtotal: true)
            ]
        )
    }

    /// Bonus depreciation versus a normal schedule, in year-one cash.
    public static func capitalPurchase(
        amount: Decimal,
        assetClass: AssetClass,
        purchaseDate: Date,
        marginalRatePercent: Double,
        stateRatePercent: Double,
        bonusPercentOverride: Double? = nil
    ) -> ScenarioResult {
        let combinedRate = (marginalRatePercent + stateRatePercent).clampedPercent
        let bonus = bonusPercentOverride
            ?? (assetClass.isBonusEligible ? DepreciationEngine.defaultBonusPercent(acquiredOn: purchaseDate) : 0)

        let withBonus = DepreciationSpec(
            name: "Scenario",
            assetClass: assetClass,
            basis: amount,
            placedInService: purchaseDate,
            bonusPercent: bonus
        )
        let withoutBonus = DepreciationSpec(
            name: "Scenario",
            assetClass: assetClass,
            basis: amount,
            placedInService: purchaseDate,
            bonusPercent: 0
        )

        let year = DateMath.year(of: purchaseDate)
        let bonusYearOne = DepreciationEngine.schedule(for: withBonus).deduction(inYear: year)
        let normalYearOne = DepreciationEngine.schedule(for: withoutBonus).deduction(inYear: year)

        let bonusSaving = bonusYearOne.applying(percent: combinedRate)
        let normalSaving = normalYearOne.applying(percent: combinedRate)
        let difference = bonusSaving - normalSaving

        var warnings: [String] = []
        if !assetClass.isBonusEligible {
            warnings.append("Real property is not eligible for bonus depreciation. Only a cost segregation study can accelerate a building, and that needs a professional.")
        }
        if DateMath.month(of: purchaseDate) >= 10 && assetClass.isBonusEligible {
            warnings.append("A fourth-quarter purchase can trigger the mid-quarter convention if it makes up more than 40% of the year's personal property. Bonus depreciation usually sidesteps this, but check the whole year together.")
        }

        return ScenarioResult(
            headline: bonus > 0
                ? "Bonus depreciation frees up \(Fmt.currency(difference)) in year one"
                : "Year-one deduction of \(Fmt.currency(normalYearOne))",
            netIncomeChange: -bonusYearOne,
            taxChange: -bonusSaving,
            afterTaxChange: -(amount - bonusSaving),
            effectiveCostOrBenefit: amount - bonusSaving,
            explanation: "\(DepreciationEngine.bonusExplanation(acquiredOn: purchaseDate)) A \(Fmt.currency(amount)) \(assetClass.title.lowercased()) placed in service in \(Fmt.mediumDate(purchaseDate)) yields \(Fmt.currency(bonusYearOne)) of depreciation in \(year) with bonus, against \(Fmt.currency(normalYearOne)) without. This is timing, not free money — the total written off over the asset's life is the same.",
            warnings: warnings,
            breakdown: [
                ReconciliationLine(id: "bonus", label: "Year-one deduction with bonus", amount: bonusYearOne, detail: "\(Fmt.percent(bonus)) bonus plus first-year MACRS."),
                ReconciliationLine(id: "normal", label: "Year-one deduction without bonus", amount: normalYearOne, detail: "\(assetClass.title), \(Fmt.number(assetClass.recoveryYears))-year MACRS."),
                ReconciliationLine(id: "delta", label: "Extra tax deferred this year", amount: difference, detail: "Cash kept in your pocket now.", isSubtotal: true)
            ]
        )
    }

    /// The after-tax value of filling more nights.
    public static func extraBookings(
        nights: Int,
        averageDailyRate: Decimal,
        variableCostPerNight: Decimal,
        platformFeePercent: Double,
        marginalRatePercent: Double,
        stateRatePercent: Double
    ) -> ScenarioResult {
        let combinedRate = (marginalRatePercent + stateRatePercent).clampedPercent
        let grossRevenue = averageDailyRate * Decimal(nights)
        let fees = grossRevenue.applying(percent: platformFeePercent.clampedPercent)
        let variable = variableCostPerNight * Decimal(nights)
        let pretax = grossRevenue - fees - variable
        let tax = max(0, pretax).applying(percent: combinedRate)
        let afterTax = pretax - tax

        return ScenarioResult(
            headline: "\(nights) more night\(nights == 1 ? "" : "s") is \(Fmt.currency(afterTax)) after tax",
            netIncomeChange: pretax,
            taxChange: tax,
            afterTaxChange: afterTax,
            effectiveCostOrBenefit: afterTax,
            explanation: "At \(Fmt.currency(averageDailyRate)) a night, \(nights) extra night\(nights == 1 ? "" : "s") brings in \(Fmt.currency(grossRevenue)). Platform fees take \(Fmt.currency(fees)), turnover costs take \(Fmt.currency(variable)) and tax takes \(Fmt.currency(tax)), leaving \(Fmt.currency(afterTax)).",
            warnings: [],
            breakdown: [
                ReconciliationLine(id: "gross", label: "Additional gross rent", amount: grossRevenue, detail: "\(nights) × \(Fmt.currency(averageDailyRate))."),
                ReconciliationLine(id: "fees", label: "Platform fees", amount: -fees, detail: "\(Fmt.percent(platformFeePercent)) of gross."),
                ReconciliationLine(id: "variable", label: "Turnover and supplies", amount: -variable, detail: "\(Fmt.currency(variableCostPerNight)) per night."),
                ReconciliationLine(id: "tax", label: "Income tax", amount: -tax, detail: "\(Fmt.percent(combinedRate)) marginal."),
                ReconciliationLine(id: "net", label: "Kept", amount: afterTax, detail: "What actually stays with you.", isSubtotal: true)
            ]
        )
    }

    /// What blocking the calendar for yourself costs — in lost rent, and in the
    /// deductions the §280A allocation takes away.
    public static func personalUse(
        days: Int,
        current: PersonalUseAnalysis,
        averageDailyRate: Decimal,
        totalAllocableExpenses: Decimal,
        marginalRatePercent: Double
    ) -> ScenarioResult {
        let projected = PersonalUseEngine.projectedClassification(current: current, addingPersonalDays: days)
        let lostRent = averageDailyRate * Decimal(days)

        let newPersonal = current.personalUseDays + days
        let newUsedDays = current.fairRentalDays + newPersonal
        let newAllocation = newUsedDays > 0
            ? Double(current.fairRentalDays) / Double(newUsedDays) * 100
            : 0
        let currentAllocation = current.personalUseDays > 0 ? current.irsAllocationPercent : 100

        let deductionsNow = totalAllocableExpenses.applying(percent: currentAllocation)
        let deductionsAfter = totalAllocableExpenses.applying(percent: newAllocation)
        let lostDeductions = max(0, deductionsNow - deductionsAfter)
        let taxCost = lostDeductions.applying(percent: marginalRatePercent.clampedPercent)

        var warnings: [String] = []
        if projected == .residenceWithRentalUse && current.classification == .rentalProperty {
            warnings.append("These \(days) day\(days == 1 ? "" : "s") would push personal use past the \(current.personalUseThreshold)-day limit. The property becomes a residence for the year: expenses get allocated and no rental loss can be claimed at all.")
        }
        if current.headroomDays > 0 && days > current.headroomDays {
            warnings.append("You have \(current.headroomDays) personal day\(current.headroomDays == 1 ? "" : "s") of headroom left this year. Staying within it keeps rental-property treatment.")
        }

        return ScenarioResult(
            headline: "\(days) personal day\(days == 1 ? "" : "s") costs about \(Fmt.currency(lostRent + taxCost))",
            netIncomeChange: -lostRent,
            taxChange: -taxCost,
            afterTaxChange: -(lostRent + taxCost),
            effectiveCostOrBenefit: lostRent + taxCost,
            explanation: "Blocking \(days) night\(days == 1 ? "" : "s") forgoes \(Fmt.currency(lostRent)) of rent and moves the §280A allocation from \(Fmt.percent(currentAllocation)) to \(Fmt.percent(newAllocation)), costing \(Fmt.currency(lostDeductions)) of deductions and roughly \(Fmt.currency(taxCost)) in tax. The property would be classified as: \(projected.title).",
            warnings: warnings,
            breakdown: [
                ReconciliationLine(id: "rent", label: "Rent forgone", amount: lostRent, detail: "\(days) × \(Fmt.currency(averageDailyRate))."),
                ReconciliationLine(id: "deductions", label: "Deductions lost to allocation", amount: lostDeductions, detail: "\(Fmt.percent(currentAllocation)) → \(Fmt.percent(newAllocation))."),
                ReconciliationLine(id: "tax", label: "Extra tax", amount: taxCost, detail: "At \(Fmt.percent(marginalRatePercent))."),
                ReconciliationLine(id: "total", label: "Total cost of the stay", amount: lostRent + taxCost, detail: "Before you decide whether it is worth it.", isSubtotal: true)
            ]
        )
    }
}
