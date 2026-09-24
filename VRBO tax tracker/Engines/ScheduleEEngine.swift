//
//  ScheduleEEngine.swift
//  VRBO tax tracker
//
//  Turns bookings, expenses, mileage, loans and depreciation into Schedule E
//  (Form 1040) Part I, one column per property, with §280A allocation and the
//  income limitation applied where they belong.
//

import Foundation

// MARK: - Input

public struct TaxDataSet {
    public var year: Int
    public var properties: [Property]
    /// Every expense in the year, including portfolio-wide ones with no property.
    public var expenses: [Expense]
    public var trips: [MileageTrip]
    public var mileageRates: MileageRateTable
    /// Applies the Tax Court allocation to interest and taxes, which usually
    /// frees up more of the other expenses to offset rent.
    public var useBoltonAllocation: Bool

    public init(
        year: Int,
        properties: [Property],
        expenses: [Expense],
        trips: [MileageTrip],
        mileageRates: MileageRateTable = MileageRateTable(),
        useBoltonAllocation: Bool = false
    ) {
        self.year = year
        self.properties = properties
        self.expenses = expenses
        self.trips = trips
        self.mileageRates = mileageRates
        self.useBoltonAllocation = useBoltonAllocation
    }
}

// MARK: - Output

public struct ScheduleELineDetail: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var label: String
    public var amount: Decimal
    public var isAutoDerived: Bool = false
}

public struct ScheduleELineResult: Identifiable, Hashable, Sendable {
    public var id: Int { line.rawValue }
    public var line: ScheduleELine
    /// Before §280A allocation.
    public var grossAmount: Decimal
    /// After §280A allocation but before the income cap.
    public var allocatedAmount: Decimal
    /// What actually appears on the form.
    public var reportedAmount: Decimal
    public var details: [ScheduleELineDetail]

    public var wasReduced: Bool { reportedAmount < grossAmount }
}

public struct ScheduleEColumn: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var propertyName: String
    public var address: String
    public var propertyKindCode: String
    public var colorHex: String

    public var fairRentalDays: Int
    public var personalUseDays: Int
    public var ownershipPercent: Double

    /// Line 3.
    public var rentsReceived: Decimal
    /// Lines 5 through 19.
    public var lines: [ScheduleELineResult]
    /// Line 20.
    public var totalExpenses: Decimal
    /// Line 21.
    public var netIncomeOrLoss: Decimal

    public var analysis: PersonalUseAnalysis
    public var allocationPercentApplied: Double
    public var interestAllocationPercentApplied: Double
    /// Deductions disallowed by the §280A income cap, carried to next year.
    public var section280ACarryforward: Decimal
    public var excludedUnder280Ag: Bool
    public var notes: [String]

    public var depreciationAmount: Decimal {
        lines.first(where: { $0.line == .depreciation })?.reportedAmount ?? 0
    }

    /// Cash result before the non-cash depreciation deduction — what the host
    /// actually banked.
    public var cashFlow: Decimal {
        netIncomeOrLoss + depreciationAmount
    }
}

public struct ScheduleEReport: Sendable {
    public var year: Int
    public var columns: [ScheduleEColumn]
    public var unassignedExpenses: Decimal
    public var generatedAt: Date = Date()

    public var totalRents: Decimal { columns.map(\.rentsReceived).total }
    public var totalExpenses: Decimal { columns.map(\.totalExpenses).total }
    public var totalNet: Decimal { columns.map(\.netIncomeOrLoss).total }
    public var totalDepreciation: Decimal { columns.map(\.depreciationAmount).total }
    public var totalCashFlow: Decimal { columns.map(\.cashFlow).total }
    public var totalCarryforward: Decimal { columns.map(\.section280ACarryforward).total }

    public func amount(for line: ScheduleELine) -> Decimal {
        columns.compactMap { column in
            column.lines.first(where: { $0.line == line })?.reportedAmount
        }.total
    }

    public var allLines: [ScheduleELineResult] {
        ScheduleELine.allCases.compactMap { line in
            let matching = columns.compactMap { $0.lines.first(where: { $0.line == line }) }
            guard !matching.isEmpty else { return nil }
            return ScheduleELineResult(
                line: line,
                grossAmount: matching.map(\.grossAmount).total,
                allocatedAmount: matching.map(\.allocatedAmount).total,
                reportedAmount: matching.map(\.reportedAmount).total,
                details: matching.flatMap(\.details)
            )
        }
    }
}

// MARK: - Engine

public enum ScheduleEEngine {

    public static func build(_ data: TaxDataSet) -> ScheduleEReport {
        let activeProperties = data.properties.filter { $0.kind != .land }
        guard !activeProperties.isEmpty else {
            return ScheduleEReport(year: data.year, columns: [], unassignedExpenses: 0)
        }

        // Revenue first — portfolio-wide expenses are apportioned by it.
        var rentsByProperty: [UUID: Decimal] = [:]
        for property in activeProperties {
            rentsByProperty[property.id] = grossRents(for: property, year: data.year)
        }
        let portfolioRents = rentsByProperty.values.reduce(Decimal.zero, +)

        var columns: [ScheduleEColumn] = []
        var unassigned = Decimal.zero

        for property in activeProperties {
            let column = buildColumn(
                property: property,
                data: data,
                rentsByProperty: rentsByProperty,
                portfolioRents: portfolioRents,
                activePropertyCount: activeProperties.count
            )
            columns.append(column)
        }

        // Expenses tied to one property that no longer points anywhere never
        // reach a column, so they are surfaced instead of silently dropped.
        unassigned = data.expenses
            .filter { $0.allocation == .singleProperty && $0.property == nil }
            .filter { DateMath.contains($0.date, inYear: data.year) }
            .map(\.deductibleAmount)
            .total

        return ScheduleEReport(year: data.year, columns: columns, unassignedExpenses: unassigned)
    }

    // MARK: Revenue

    public static func grossRents(for property: Property, year: Int) -> Decimal {
        let hostCollectsTax = !property.lodgingTaxRemittedByPlatform
        return property.bookingList.reduce(Decimal.zero) { running, booking in
            let fraction = booking.yearFraction(year)
            guard fraction > 0 else { return running }
            var amount = booking.grossRents * fraction
            if hostCollectsTax {
                // Tax the host collects is rental income, and the remittance is
                // deducted on line 16 when it is recorded as an expense.
                amount += booking.lodgingTaxCollected * fraction
            }
            return running + amount
        }.rounded(2)
    }

    // MARK: Column

    private static func buildColumn(
        property: Property,
        data: TaxDataSet,
        rentsByProperty: [UUID: Decimal],
        portfolioRents: Decimal,
        activePropertyCount: Int
    ) -> ScheduleEColumn {

        let year = data.year
        let rents = rentsByProperty[property.id] ?? 0

        let analysis = PersonalUseEngine.analyze(
            bookings: property.bookingList,
            personalUse: property.personalUseList,
            year: year,
            propertyID: property.id,
            daysAvailable: property.daysAvailablePerYear
        )

        // Gather gross amounts per Schedule E line.
        var gross: [ScheduleELine: Decimal] = [:]
        var details: [ScheduleELine: [ScheduleELineDetail]] = [:]

        func add(_ line: ScheduleELine, _ amount: Decimal, label: String, auto: Bool = false) {
            guard amount != 0 else { return }
            gross[line, default: 0] += amount
            details[line, default: []].append(
                ScheduleELineDetail(label: label, amount: amount, isAutoDerived: auto)
            )
        }

        // 1. Direct and apportioned expenses.
        for expense in data.expenses {
            guard DateMath.contains(expense.date, inYear: year) else { continue }
            let share = allocationShare(
                expense: expense,
                property: property,
                rentsByProperty: rentsByProperty,
                portfolioRents: portfolioRents,
                activePropertyCount: activePropertyCount
            )
            guard share > 0 else { continue }
            let amount = (expense.deductibleAmount * share).rounded(2)
            guard amount != 0 else { continue }
            let label = expense.isSplitAcrossPortfolio
                ? "\(expense.displayVendor) (portfolio share)"
                : expense.displayVendor
            add(expense.scheduleELine, amount, label: label)
        }

        // 2. Mileage at the standard rate.
        let propertyTrips = data.trips.filter {
            $0.property?.id == property.id && DateMath.contains($0.date, inYear: year)
        }
        let mileageDeduction = propertyTrips
            .map { $0.deduction(using: data.mileageRates) }
            .total
        if mileageDeduction != 0 {
            let miles = propertyTrips.map(\.effectiveMiles).reduce(0, +)
            add(
                .autoAndTravel,
                mileageDeduction,
                label: "Mileage log — \(Fmt.miles(miles))",
                auto: true
            )
        }

        // 3. Mortgage interest straight from the amortisation schedule.
        for loan in property.loanList where loan.autoDeductInterest {
            let interest = LoanAmortizationEngine.interest(for: loan, inYear: year)
            if interest != 0 {
                add(
                    .mortgageInterest,
                    interest,
                    label: "\(loan.displayName) — amortised interest",
                    auto: true
                )
            }
        }

        // 4. Depreciation.
        let specs = property.allDepreciationSpecs
        for spec in specs {
            let amount = DepreciationEngine.schedule(for: spec).deduction(inYear: year)
            if amount != 0 {
                add(.depreciation, amount, label: spec.name, auto: true)
            }
        }

        // 5. Apply §280A.
        let excluded = analysis.classification == .minimalRentalExcluded
        let hasPersonalUse = analysis.personalUseDays > 0

        let generalPercent: Double
        let interestPercent: Double
        if excluded {
            generalPercent = 0
            interestPercent = 0
        } else if hasPersonalUse {
            generalPercent = analysis.irsAllocationPercent
            interestPercent = data.useBoltonAllocation
                ? analysis.boltonAllocationPercent
                : analysis.irsAllocationPercent
        } else {
            generalPercent = 100
            interestPercent = 100
        }

        var allocated: [ScheduleELine: Decimal] = [:]
        for (line, amount) in gross {
            let percent = (line == .mortgageInterest || line == .taxes) ? interestPercent : generalPercent
            allocated[line] = amount.applying(percent: percent)
        }

        let reportedRents = excluded ? Decimal.zero : rents

        // 6. Income cap for a dwelling used as a residence. Deductions are
        //    taken in a fixed order so the most valuable ones survive: interest
        //    and taxes first, then operating costs, then depreciation.
        var reported: [ScheduleELine: Decimal] = allocated
        var carryforward = Decimal.zero

        if analysis.isDeductionCappedAtIncome && !excluded {
            let tierOne: [ScheduleELine] = [.mortgageInterest, .taxes, .otherInterest]
            let tierThree: [ScheduleELine] = [.depreciation]
            let tierTwo = ScheduleELine.allCases.filter {
                !tierOne.contains($0) && !tierThree.contains($0)
            }

            var budget = reportedRents
            for tier in [tierOne, tierTwo, tierThree] {
                let tierTotal = tier.map { allocated[$0] ?? 0 }.total
                if tierTotal <= budget {
                    budget -= tierTotal
                    continue
                }
                // Prorate what is left across the tier.
                let ratio = tierTotal > 0 ? budget / tierTotal : 0
                for line in tier {
                    let full = allocated[line] ?? 0
                    guard full > 0 else { continue }
                    let allowed = (full * ratio).rounded(2)
                    reported[line] = allowed
                    carryforward += full - allowed
                }
                budget = 0
            }
        } else if excluded {
            reported = reported.mapValues { _ in Decimal.zero }
        }

        let lineResults: [ScheduleELineResult] = ScheduleELine.allCases.compactMap { line in
            let grossValue = gross[line] ?? 0
            let allocatedValue = allocated[line] ?? 0
            let reportedValue = reported[line] ?? 0
            guard grossValue != 0 || reportedValue != 0 else { return nil }
            return ScheduleELineResult(
                line: line,
                grossAmount: grossValue,
                allocatedAmount: allocatedValue,
                reportedAmount: reportedValue,
                details: (details[line] ?? []).sorted { $0.amount > $1.amount }
            )
        }

        let totalExpenses = lineResults.map(\.reportedAmount).total
        let net = (reportedRents - totalExpenses).rounded(2)

        var notes: [String] = []
        if excluded {
            notes.append("Rented \(analysis.fairRentalDays) day\(analysis.fairRentalDays == 1 ? "" : "s") while used as a residence — §280A(g) excludes this income and disallows the expenses.")
        }
        if analysis.isDeductionCappedAtIncome {
            notes.append("Personal use of \(analysis.personalUseDays) days exceeded the \(analysis.personalUseThreshold)-day limit. Expenses allocated at \(Fmt.percent(generalPercent)) and capped at rental income.")
        }
        if data.useBoltonAllocation && hasPersonalUse && interestPercent != generalPercent {
            notes.append("Tax Court method applied to interest and taxes at \(Fmt.percent(interestPercent)) instead of \(Fmt.percent(generalPercent)).")
        }
        if carryforward > 0 {
            notes.append("\(Fmt.currency(carryforward)) of disallowed deductions carries forward to \(year + 1).")
        }
        if DepreciationEngine.midQuarterConventionApplies(specs: specs, year: year) {
            notes.append("More than 40% of this year's personal property was placed in service in the fourth quarter. The mid-quarter convention applies — have these depreciation figures reviewed.")
        }
        if analysis.hasDataQualityIssues {
            notes.append("\(analysis.conflictingDays.count + analysis.doubleBookedDays.count) calendar day(s) are double-counted. Resolve them before filing.")
        }

        return ScheduleEColumn(
            id: property.id,
            propertyName: property.displayName,
            address: property.shortAddress,
            propertyKindCode: property.kind.scheduleECode,
            colorHex: property.colorHex,
            fairRentalDays: analysis.fairRentalDays,
            personalUseDays: analysis.personalUseDays,
            ownershipPercent: property.ownershipPercent,
            rentsReceived: reportedRents,
            lines: lineResults,
            totalExpenses: totalExpenses,
            netIncomeOrLoss: net,
            analysis: analysis,
            allocationPercentApplied: generalPercent,
            interestAllocationPercentApplied: interestPercent,
            section280ACarryforward: carryforward,
            excludedUnder280Ag: excluded,
            notes: notes
        )
    }

    // MARK: Allocation

    /// The fraction of an expense that belongs to one property.
    private static func allocationShare(
        expense: Expense,
        property: Property,
        rentsByProperty: [UUID: Decimal],
        portfolioRents: Decimal,
        activePropertyCount: Int
    ) -> Decimal {
        switch expense.allocation {
        case .singleProperty:
            return expense.property?.id == property.id ? 1 : 0
        case .splitEvenly:
            guard activePropertyCount > 0 else { return 0 }
            return 1 / Decimal(activePropertyCount)
        case .splitByRevenue:
            guard portfolioRents > 0 else {
                guard activePropertyCount > 0 else { return 0 }
                return 1 / Decimal(activePropertyCount)
            }
            return (rentsByProperty[property.id] ?? 0) / portfolioRents
        }
    }
}
