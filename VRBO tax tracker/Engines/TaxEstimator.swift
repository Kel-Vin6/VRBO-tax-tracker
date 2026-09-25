//
//  TaxEstimator.swift
//  VRBO tax tracker
//
//  A planning estimate, not a filed return. Every rate table the app ships with
//  is visible and editable in Settings, and any year the build has no published
//  table for is carried forward and clearly marked as an estimate.
//

import Foundation

// MARK: - Rate tables

public struct TaxBracket: Codable, Hashable, Sendable {
    /// Upper bound of the bracket. `nil` means the top bracket.
    public var upperBound: Decimal?
    public var ratePercent: Double

    public init(upperBound: Decimal?, ratePercent: Double) {
        self.upperBound = upperBound
        self.ratePercent = ratePercent
    }
}

public struct FederalRateTable: Codable, Hashable, Sendable {
    public var year: Int
    public var brackets: [FilingStatus: [TaxBracket]]
    public var standardDeduction: [FilingStatus: Decimal]
    /// True when the table was carried forward rather than published for `year`.
    public var isCarriedForward: Bool = false

    public func brackets(for status: FilingStatus) -> [TaxBracket] {
        brackets[status] ?? brackets[.single] ?? []
    }

    public func standardDeduction(for status: FilingStatus) -> Decimal {
        standardDeduction[status] ?? 0
    }
}

public enum FederalRates {

    /// Published inflation-adjusted figures the app ships with.
    public static let tables: [Int: FederalRateTable] = [
        2024: FederalRateTable(
            year: 2024,
            brackets: [
                .single: bracketList([11_600, 47_150, 100_525, 191_950, 243_725, 609_350]),
                .marriedFilingJointly: bracketList([23_200, 94_300, 201_050, 383_900, 487_450, 731_200]),
                .marriedFilingSeparately: bracketList([11_600, 47_150, 100_525, 191_950, 243_725, 365_600]),
                .headOfHousehold: bracketList([16_550, 63_100, 100_500, 191_950, 243_700, 609_350])
            ],
            standardDeduction: [
                .single: 14_600,
                .marriedFilingJointly: 29_200,
                .marriedFilingSeparately: 14_600,
                .headOfHousehold: 21_900
            ]
        ),
        2025: FederalRateTable(
            year: 2025,
            brackets: [
                .single: bracketList([11_925, 48_475, 103_350, 197_300, 250_525, 626_350]),
                .marriedFilingJointly: bracketList([23_850, 96_950, 206_700, 394_600, 501_050, 751_600]),
                .marriedFilingSeparately: bracketList([11_925, 48_475, 103_350, 197_300, 250_525, 375_800]),
                .headOfHousehold: bracketList([17_000, 64_850, 103_350, 197_300, 250_500, 626_350])
            ],
            standardDeduction: [
                .single: 15_750,
                .marriedFilingJointly: 31_500,
                .marriedFilingSeparately: 15_750,
                .headOfHousehold: 23_625
            ]
        )
    ]

    public static let latestPublishedYear = 2025
    public static let ordinaryRates: [Double] = [10, 12, 22, 24, 32, 35, 37]

    private static func bracketList(_ upperBounds: [Decimal]) -> [TaxBracket] {
        var result: [TaxBracket] = []
        for (index, bound) in upperBounds.enumerated() {
            result.append(TaxBracket(upperBound: bound, ratePercent: ordinaryRates[index]))
        }
        result.append(TaxBracket(upperBound: nil, ratePercent: ordinaryRates[upperBounds.count]))
        return result
    }

    public static func table(for year: Int) -> FederalRateTable {
        if let table = tables[year] { return table }
        let fallbackYear = year < 2024 ? 2024 : latestPublishedYear
        guard var table = tables[fallbackYear] ?? tables[latestPublishedYear] else {
            return FederalRateTable(
                year: year,
                brackets: [:],
                standardDeduction: [:],
                isCarriedForward: true
            )
        }
        table.year = year
        table.isCarriedForward = true
        return table
    }

    /// Net investment income tax thresholds. These are not indexed for inflation.
    public static func niitThreshold(for status: FilingStatus) -> Decimal {
        switch status {
        case .marriedFilingJointly: 250_000
        case .marriedFilingSeparately: 125_000
        case .single, .headOfHousehold: 200_000
        }
    }

    public static let niitRatePercent: Double = 3.8
}

// MARK: - Inputs and results

public struct TaxEstimateInput: Hashable, Sendable {
    public var year: Int
    public var filingStatus: FilingStatus = .single
    /// Wages, self-employment and every other source outside the rentals.
    public var otherOrdinaryIncome: Decimal = 0
    /// Federal income tax already withheld from wages.
    public var federalWithholding: Decimal = 0
    /// Itemised deductions, if they beat the standard deduction.
    public var itemizedDeductions: Decimal = 0
    public var useItemizedDeductions: Bool = false
    /// Net rental income or loss from Schedule E.
    public var rentalNetIncome: Decimal = 0
    /// Rental losses allowed against other income this year.
    public var allowedRentalLoss: Decimal = 0
    /// True when the activity is non-passive, so losses are not suspended.
    public var lossIsNonPassive: Bool = false
    /// §199A qualified business income deduction is claimed on the rental.
    public var claimQBIDeduction: Bool = false
    public var stateRatePercent: Double = 0
    /// Prior year total tax, for the estimated-payment safe harbor.
    public var priorYearTotalTax: Decimal = 0
    public var priorYearAGI: Decimal = 0
    public var estimatedPaymentsMade: Decimal = 0
    /// Rental income is normally net investment income unless the owner is a
    /// real estate professional or the activity is a non-passive trade or business.
    public var subjectToNIIT: Bool = true

    public init(year: Int) { self.year = year }
}

public struct TaxEstimateResult: Hashable, Sendable {
    public var year: Int
    public var table: FederalRateTable

    public var grossIncome: Decimal
    public var deduction: Decimal
    public var qbiDeduction: Decimal
    public var taxableIncome: Decimal

    public var federalTax: Decimal
    public var netInvestmentIncomeTax: Decimal
    public var stateTax: Decimal
    public var totalTax: Decimal

    public var marginalRatePercent: Double
    public var effectiveRatePercent: Double

    /// Federal tax with the rentals removed, so the rental's true cost is visible.
    public var federalTaxWithoutRentals: Decimal
    public var taxAttributableToRentals: Decimal

    public var withholdingAndPayments: Decimal
    public var balanceDue: Decimal

    public var safeHarborRequirement: Decimal
    public var safeHarborBasis: String
    public var quarterlyPayment: Decimal
    public var isTableEstimated: Bool { table.isCarriedForward }

    public var isRefund: Bool { balanceDue < 0 }
}

public struct QuarterlyDueDate: Identifiable, Hashable, Sendable {
    public var id: Int { quarter }
    public var quarter: Int
    public var dueDate: Date
    public var periodLabel: String
    public var suggestedAmount: Decimal
    public var amountPaid: Decimal

    public var remaining: Decimal { max(0, suggestedAmount - amountPaid) }
    public var isPaid: Bool { amountPaid >= suggestedAmount && suggestedAmount > 0 }
    public var isOverdue: Bool { !isPaid && dueDate < Date() }

    public var daysUntilDue: Int {
        DateMath.calendar.dateComponents(
            [.day],
            from: DateMath.startOfDay(Date()),
            to: DateMath.startOfDay(dueDate)
        ).day ?? 0
    }
}

// MARK: - Engine

public enum TaxEstimator {

    public static func tax(on taxableIncome: Decimal, brackets: [TaxBracket]) -> Decimal {
        guard taxableIncome > 0, !brackets.isEmpty else { return 0 }
        var remaining = taxableIncome
        var lowerBound = Decimal.zero
        var total = Decimal.zero

        for bracket in brackets {
            guard remaining > 0 else { break }
            let width: Decimal
            if let upper = bracket.upperBound {
                width = max(0, upper - lowerBound)
                lowerBound = upper
            } else {
                width = remaining
            }
            let taxedHere = min(remaining, width)
            total += taxedHere.applying(percent: bracket.ratePercent)
            remaining -= taxedHere
        }
        return total.rounded(2)
    }

    public static func marginalRate(for taxableIncome: Decimal, brackets: [TaxBracket]) -> Double {
        var lowerBound = Decimal.zero
        for bracket in brackets {
            guard let upper = bracket.upperBound else { return bracket.ratePercent }
            if taxableIncome > lowerBound && taxableIncome <= upper { return bracket.ratePercent }
            lowerBound = upper
        }
        return brackets.last?.ratePercent ?? 0
    }

    public static func estimate(_ input: TaxEstimateInput, table: FederalRateTable? = nil) -> TaxEstimateResult {
        let rateTable = table ?? FederalRates.table(for: input.year)
        let brackets = rateTable.brackets(for: input.filingStatus)

        // A passive loss that is not allowed this year does not reduce income.
        let rentalContribution: Decimal
        if input.rentalNetIncome >= 0 {
            rentalContribution = input.rentalNetIncome
        } else {
            rentalContribution = input.lossIsNonPassive
                ? input.rentalNetIncome
                : -min(abs(input.rentalNetIncome), input.allowedRentalLoss)
        }

        let grossIncome = input.otherOrdinaryIncome + rentalContribution
        let standard = rateTable.standardDeduction(for: input.filingStatus)
        let deduction = input.useItemizedDeductions
            ? max(input.itemizedDeductions, 0)
            : standard

        // §199A is 20% of qualified business income, limited by taxable income
        // before the deduction. Only positive rental income qualifies.
        let incomeBeforeQBI = max(0, grossIncome - deduction)
        let qbiBase = max(0, rentalContribution)
        let qbiDeduction: Decimal = input.claimQBIDeduction
            ? min(qbiBase.applying(percent: 20), incomeBeforeQBI.applying(percent: 20))
            : 0

        let taxableIncome = max(0, incomeBeforeQBI - qbiDeduction)
        let federalTax = tax(on: taxableIncome, brackets: brackets)

        // Baseline without the rentals, to isolate what they cost.
        let baseTaxable = max(0, input.otherOrdinaryIncome - deduction)
        let federalWithoutRentals = tax(on: baseTaxable, brackets: brackets)

        // NIIT applies to the lesser of net investment income and the excess of
        // MAGI over the threshold.
        var niit = Decimal.zero
        if input.subjectToNIIT, rentalContribution > 0 {
            let threshold = FederalRates.niitThreshold(for: input.filingStatus)
            let excess = max(0, grossIncome - threshold)
            niit = min(rentalContribution, excess).applying(percent: FederalRates.niitRatePercent)
        }

        let stateTax = max(0, taxableIncome).applying(percent: input.stateRatePercent.clampedPercent)
        let totalTax = (federalTax + niit + stateTax).rounded(2)

        let payments = input.federalWithholding + input.estimatedPaymentsMade
        let balance = (totalTax - payments).rounded(2)

        // Safe harbor: 100% of last year's tax, or 110% when prior-year AGI
        // exceeded $150,000, otherwise 90% of this year's.
        let highIncome = input.priorYearAGI > 150_000
        let priorYearTarget = input.priorYearTotalTax.applying(percent: highIncome ? 110 : 100)
        let currentYearTarget = totalTax.applying(percent: 90)
        let safeHarbor: Decimal
        let basis: String
        if input.priorYearTotalTax > 0 && priorYearTarget < currentYearTarget {
            safeHarbor = priorYearTarget
            basis = highIncome
                ? "110% of your \(input.year - 1) tax, because prior-year AGI exceeded $150,000."
                : "100% of your \(input.year - 1) tax."
        } else {
            safeHarbor = currentYearTarget
            basis = "90% of your projected \(input.year) tax."
        }

        let stillOwed = max(0, safeHarbor - payments)

        return TaxEstimateResult(
            year: input.year,
            table: rateTable,
            grossIncome: grossIncome,
            deduction: deduction,
            qbiDeduction: qbiDeduction,
            taxableIncome: taxableIncome,
            federalTax: federalTax,
            netInvestmentIncomeTax: niit,
            stateTax: stateTax,
            totalTax: totalTax,
            marginalRatePercent: marginalRate(for: taxableIncome, brackets: brackets),
            effectiveRatePercent: grossIncome > 0 ? (totalTax / grossIncome).doubleValue * 100 : 0,
            federalTaxWithoutRentals: federalWithoutRentals,
            taxAttributableToRentals: (federalTax + niit - federalWithoutRentals).rounded(2),
            withholdingAndPayments: payments,
            balanceDue: balance,
            safeHarborRequirement: safeHarbor,
            safeHarborBasis: basis,
            quarterlyPayment: (stillOwed / 4).rounded(2)
        )
    }

    // MARK: Quarterly schedule

    /// Estimated tax instalments are due in April, June and September of the tax
    /// year and in January of the year after.
    public static func dueDates(for year: Int) -> [Date] {
        let calendar = DateMath.calendar
        let components: [DateComponents] = [
            DateComponents(year: year, month: 4, day: 15),
            DateComponents(year: year, month: 6, day: 15),
            DateComponents(year: year, month: 9, day: 15),
            DateComponents(year: year + 1, month: 1, day: 15)
        ]
        return components.map { calendar.date(from: $0) ?? Date() }
    }

    public static func quarterlySchedule(
        year: Int,
        requirement: Decimal,
        payments: [EstimatedTaxPayment]
    ) -> [QuarterlyDueDate] {
        let dates = dueDates(for: year)
        let labels = [
            "1 January – 31 March",
            "1 April – 31 May",
            "1 June – 31 August",
            "1 September – 31 December"
        ]
        let perQuarter = (requirement / 4).rounded(2)

        return (1...4).map { quarter in
            let paid = payments
                .filter { $0.taxYear == year && $0.quarter == quarter }
                .map(\.amount)
                .total
            return QuarterlyDueDate(
                quarter: quarter,
                dueDate: dates[quarter - 1],
                periodLabel: labels[quarter - 1],
                suggestedAmount: perQuarter,
                amountPaid: paid
            )
        }
    }

    public static func nextDueDate(for year: Int = DateMath.currentYear) -> QuarterlyDueDate? {
        let schedule = quarterlySchedule(year: year, requirement: 0, payments: [])
        return schedule.first { $0.dueDate >= DateMath.startOfDay(Date()) }
            ?? quarterlySchedule(year: year + 1, requirement: 0, payments: []).first
    }

    // MARK: Substantial services warning

    /// Rental income belongs on Schedule E and is not subject to self-employment
    /// tax — unless the host provides services beyond those customary for
    /// occupancy, which can push the whole activity onto Schedule C.
    public static func substantialServicesWarning(providesHotelLikeServices: Bool) -> String? {
        guard providesHotelLikeServices else { return nil }
        return "You have indicated you provide services beyond those customary for occupancy — daily housekeeping during a stay, meals, tours or concierge work. That can move the activity from Schedule E to Schedule C, where the net profit is also subject to 15.3% self-employment tax. Confirm the treatment with your accountant before filing."
    }
}
