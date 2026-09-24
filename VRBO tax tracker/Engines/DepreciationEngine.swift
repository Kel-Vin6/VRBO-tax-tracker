//
//  DepreciationEngine.swift
//  VRBO tax tracker
//
//  A full MACRS implementation: mid-month straight line for real property,
//  declining balance with an automatic straight-line switch and the half-year
//  convention for personal property, plus §179 and bonus depreciation.
//
//  Everything is computed from first principles rather than looked up in a
//  table, so a 27.5-year building placed in service in any month, and a 5, 7 or
//  15-year asset in any year, all produce the same figures as IRS Pub. 946.
//

import Foundation

// MARK: - Spec

/// A normalized description of something that depreciates. Both a user-created
/// `DepreciableAsset` and the building implied by a property's cost basis are
/// turned into one of these, so the engine has a single input shape.
public struct DepreciationSpec: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var assetClass: AssetClass
    /// Basis after any business-use reduction, before §179 and bonus.
    public var basis: Decimal
    public var placedInService: Date
    public var recoveryYears: Double
    public var bonusPercent: Double
    public var section179: Decimal
    public var disposedDate: Date?
    public var dispositionProceeds: Decimal
    public var propertyID: UUID?
    public var isDerivedFromPropertyBasis: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        assetClass: AssetClass,
        basis: Decimal,
        placedInService: Date,
        recoveryYears: Double? = nil,
        bonusPercent: Double = 0,
        section179: Decimal = 0,
        disposedDate: Date? = nil,
        dispositionProceeds: Decimal = 0,
        propertyID: UUID? = nil,
        isDerivedFromPropertyBasis: Bool = false
    ) {
        self.id = id
        self.name = name
        self.assetClass = assetClass
        self.basis = basis
        self.placedInService = placedInService
        self.recoveryYears = recoveryYears ?? assetClass.recoveryYears
        self.bonusPercent = assetClass.isBonusEligible ? bonusPercent.clampedPercent : 0
        self.section179 = assetClass.isSection179Candidate ? section179 : 0
        self.disposedDate = disposedDate
        self.dispositionProceeds = dispositionProceeds
        self.propertyID = propertyID
        self.isDerivedFromPropertyBasis = isDerivedFromPropertyBasis
    }

    public var placedInServiceYear: Int { DateMath.year(of: placedInService) }
    public var isRealProperty: Bool { assetClass.isRealProperty }
}

// MARK: - Result types

public struct DepreciationYearRow: Identifiable, Hashable, Sendable {
    public var id: Int { year }
    public var year: Int
    public var openingBasis: Decimal
    public var section179: Decimal
    public var bonus: Decimal
    public var macrs: Decimal
    public var accumulated: Decimal
    public var closingBasis: Decimal
    public var methodLabel: String
    public var ratePercent: Double

    public var total: Decimal { section179 + bonus + macrs }
}

public struct DepreciationSchedule: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var spec: DepreciationSpec
    public var rows: [DepreciationYearRow]

    public func deduction(inYear year: Int) -> Decimal {
        rows.first(where: { $0.year == year })?.total ?? 0
    }

    public func accumulated(throughYear year: Int) -> Decimal {
        rows.filter { $0.year <= year }.map(\.total).total
    }

    public var totalClaimed: Decimal { rows.map(\.total).total }

    public var finalYear: Int { rows.last?.year ?? spec.placedInServiceYear }

    public func remainingBasis(afterYear year: Int) -> Decimal {
        max(0, spec.basis - accumulated(throughYear: year))
    }
}

// MARK: - Engine

public enum DepreciationEngine {

    /// Safety valve so a malformed recovery period can never loop forever.
    private static let maximumYears = 60

    // MARK: Bonus depreciation defaults

    /// The first-year bonus percentage generally available for property
    /// *acquired* on a given date. The phase-down that began in 2023 was ended
    /// by legislation in 2025, which restored 100% for property acquired after
    /// 19 January 2025. Users can override this per asset.
    public static func defaultBonusPercent(acquiredOn date: Date) -> Double {
        let year = DateMath.year(of: date)
        switch year {
        case ..<2023:
            return 100
        case 2023:
            return 80
        case 2024:
            return 60
        case 2025:
            let cutoff = DateMath.calendar.date(from: DateComponents(year: 2025, month: 1, day: 20)) ?? date
            return DateMath.startOfDay(date) >= DateMath.startOfDay(cutoff) ? 100 : 40
        default:
            return 100
        }
    }

    public static func bonusExplanation(acquiredOn date: Date) -> String {
        let year = DateMath.year(of: date)
        switch year {
        case ..<2023:
            return "Property acquired before 2023 qualified for 100% bonus depreciation."
        case 2023:
            return "Bonus depreciation stepped down to 80% for 2023 acquisitions."
        case 2024:
            return "Bonus depreciation stepped down to 60% for 2024 acquisitions."
        case 2025:
            return "2025 is a split year: 40% for property acquired before 20 January 2025, 100% on or after."
        default:
            return "100% bonus depreciation applies to qualifying property acquired in \(year)."
        }
    }

    // MARK: Schedule building

    public static func schedule(for spec: DepreciationSpec) -> DepreciationSchedule {
        guard spec.basis > 0, spec.recoveryYears > 0 else {
            return DepreciationSchedule(id: spec.id, spec: spec, rows: [])
        }
        return spec.isRealProperty
            ? DepreciationSchedule(id: spec.id, spec: spec, rows: realPropertyRows(spec))
            : DepreciationSchedule(id: spec.id, spec: spec, rows: personalPropertyRows(spec))
    }

    /// Mid-month convention, straight line. The month of service counts as half
    /// a month, which is why a January building gets 3.485% in year one.
    private static func realPropertyRows(_ spec: DepreciationSpec) -> [DepreciationYearRow] {
        let life = spec.recoveryYears
        let startYear = spec.placedInServiceYear
        let month = DateMath.month(of: spec.placedInService)
        let annual = spec.basis / Decimal(life)

        var rows: [DepreciationYearRow] = []
        var remaining = spec.basis
        var accumulated = Decimal.zero
        var index = 0

        while remaining > 0 && index < maximumYears {
            let year = startYear + index
            if let disposed = spec.disposedDate, year > DateMath.year(of: disposed) { break }

            var fraction: Double = 1
            if index == 0 {
                fraction = (12.5 - Double(month)) / 12.0
            }
            if let disposed = spec.disposedDate, DateMath.year(of: disposed) == year {
                // Mid-month convention also applies in the year of disposition.
                let disposalMonth = Double(DateMath.month(of: disposed))
                let disposalFraction = (disposalMonth - 0.5) / 12.0
                fraction = index == 0
                    ? max(0, disposalFraction - (Double(month) - 0.5) / 12.0)
                    : disposalFraction
            }

            var amount = (annual * Decimal.fromDouble(fraction, scale: 6)).rounded(2)
            if amount > remaining { amount = remaining }
            if amount < 0 { amount = 0 }

            accumulated += amount
            let opening = remaining
            remaining -= amount

            rows.append(
                DepreciationYearRow(
                    year: year,
                    openingBasis: opening,
                    section179: 0,
                    bonus: 0,
                    macrs: amount,
                    accumulated: accumulated,
                    closingBasis: remaining,
                    methodLabel: "SL \(life.formatted(.number.precision(.fractionLength(0...1))))yr, mid-month",
                    ratePercent: spec.basis > 0 ? (amount / spec.basis).doubleValue * 100 : 0
                )
            )

            if let disposed = spec.disposedDate, DateMath.year(of: disposed) == year { break }
            index += 1
        }
        return rows
    }

    /// Declining balance with an automatic switch to straight line in the first
    /// year straight line gives the larger deduction, under the half-year
    /// convention. Reproduces the Pub. 946 Table A-1 percentages exactly.
    private static func personalPropertyRows(_ spec: DepreciationSpec) -> [DepreciationYearRow] {
        let life = spec.recoveryYears
        let startYear = spec.placedInServiceYear
        let factor = spec.assetClass.decliningBalanceFactor
        let dbRate = factor / life

        let section179 = min(spec.section179, spec.basis)
        let afterSection179 = spec.basis - section179
        let bonus = afterSection179.applying(percent: spec.bonusPercent)
        var remaining = afterSection179 - bonus

        var rows: [DepreciationYearRow] = []
        var accumulated = section179 + bonus
        var switchedToStraightLine = false
        var straightLineAmount = Decimal.zero
        var index = 0

        // First year carries §179 and bonus even when MACRS is zero.
        while index < maximumYears {
            let year = startYear + index
            if let disposed = spec.disposedDate, year > DateMath.year(of: disposed) { break }

            let opening = remaining
            var amount = Decimal.zero
            var label = "200% DB, half-year"

            if remaining > 0 {
                let halfFactor: Double = index == 0 ? 0.5 : 1.0
                let remainingLife: Double = index == 0 ? life : life - (Double(index + 1) - 1.5)
                let dbAmount = (remaining * Decimal.fromDouble(dbRate * halfFactor, scale: 8)).rounded(2)
                let slCandidate = remainingLife > 0
                    ? (remaining * Decimal.fromDouble(halfFactor / remainingLife, scale: 8)).rounded(2)
                    : remaining

                if switchedToStraightLine {
                    amount = straightLineAmount
                    label = "SL switch, half-year"
                } else if slCandidate > dbAmount {
                    switchedToStraightLine = true
                    straightLineAmount = slCandidate
                    amount = slCandidate
                    label = "SL switch, half-year"
                } else {
                    amount = dbAmount
                    label = "\(Int(factor * 100))% DB, half-year"
                }

                // Half-year convention in the year of disposal.
                if let disposed = spec.disposedDate, DateMath.year(of: disposed) == year {
                    amount = (amount / 2).rounded(2)
                    label += ", disposed"
                }

                if amount > remaining { amount = remaining }
                if amount < 0 { amount = 0 }
                remaining -= amount
                accumulated += amount
            } else if index > 0 {
                break
            }

            rows.append(
                DepreciationYearRow(
                    year: year,
                    openingBasis: index == 0 ? spec.basis : opening,
                    section179: index == 0 ? section179 : 0,
                    bonus: index == 0 ? bonus : 0,
                    macrs: amount,
                    accumulated: accumulated,
                    closingBasis: remaining,
                    methodLabel: index == 0 && (section179 > 0 || bonus > 0)
                        ? "§179 / bonus + \(label)"
                        : label,
                    ratePercent: spec.basis > 0 ? (amount / spec.basis).doubleValue * 100 : 0
                )
            )

            if let disposed = spec.disposedDate, DateMath.year(of: disposed) == year { break }
            if remaining <= 0 && index > 0 { break }
            if remaining <= 0 && index == 0 && amount == 0 && bonus == 0 && section179 == 0 { break }
            if remaining <= 0 { break }
            index += 1
        }
        return rows
    }

    // MARK: Mid-quarter convention check

    /// If more than 40% of the year's personal-property basis is placed in
    /// service in the fourth quarter, the half-year convention is replaced by
    /// the mid-quarter convention. The app does not silently apply mid-quarter —
    /// it tells the user their figures need an accountant's review.
    public static func midQuarterConventionApplies(specs: [DepreciationSpec], year: Int) -> Bool {
        let personal = specs.filter { !$0.isRealProperty && $0.placedInServiceYear == year }
        let total = personal.map(\.basis).total
        guard total > 0 else { return false }
        let fourthQuarter = personal
            .filter { DateMath.month(of: $0.placedInService) >= 10 }
            .map(\.basis)
            .total
        return (fourthQuarter / total).doubleValue > 0.40
    }

    // MARK: Recapture

    public struct RecaptureEstimate: Hashable, Sendable {
        public var accumulatedDepreciation: Decimal
        public var adjustedBasis: Decimal
        public var estimatedSalePrice: Decimal
        public var totalGain: Decimal
        /// Unrecaptured §1250 gain, taxed at up to 25%.
        public var section1250Gain: Decimal
        public var capitalGain: Decimal
        public var estimatedRecaptureTax: Decimal
        public var estimatedCapitalGainsTax: Decimal

        public var estimatedTotalTax: Decimal { estimatedRecaptureTax + estimatedCapitalGainsTax }
        public var netProceedsAfterTax: Decimal { estimatedSalePrice - estimatedTotalTax }
    }

    /// Back-of-envelope exit maths. Depreciation is not optional — the IRS
    /// recaptures what you were *allowed* to take, whether or not you took it,
    /// which is exactly why hosts need this number years before they sell.
    public static func estimateRecapture(
        accumulatedDepreciation: Decimal,
        originalBasis: Decimal,
        salePrice: Decimal,
        sellingCosts: Decimal,
        recaptureRate: Double = 25,
        capitalGainsRate: Double = 15
    ) -> RecaptureEstimate {
        let adjustedBasis = max(0, originalBasis - accumulatedDepreciation)
        let netSale = max(0, salePrice - sellingCosts)
        let totalGain = max(0, netSale - adjustedBasis)
        let section1250 = min(accumulatedDepreciation, totalGain)
        let capitalGain = max(0, totalGain - section1250)

        return RecaptureEstimate(
            accumulatedDepreciation: accumulatedDepreciation,
            adjustedBasis: adjustedBasis,
            estimatedSalePrice: salePrice,
            totalGain: totalGain,
            section1250Gain: section1250,
            capitalGain: capitalGain,
            estimatedRecaptureTax: section1250.applying(percent: recaptureRate),
            estimatedCapitalGainsTax: capitalGain.applying(percent: capitalGainsRate)
        )
    }
}

// MARK: - Bridging

public extension DepreciableAsset {
    var depreciationSpec: DepreciationSpec {
        DepreciationSpec(
            id: id,
            name: displayName,
            assetClass: assetClass,
            basis: depreciableBasis,
            placedInService: placedInService,
            recoveryYears: recoveryYears,
            bonusPercent: effectiveBonusPercent,
            section179: effectiveSection179,
            disposedDate: disposedDate,
            dispositionProceeds: dispositionProceeds,
            propertyID: property?.id,
            isDerivedFromPropertyBasis: isDerivedFromPropertyBasis
        )
    }
}

public extension Property {
    /// The building itself, derived from the cost basis the user entered on the
    /// property rather than requiring them to create an asset by hand.
    var buildingDepreciationSpec: DepreciationSpec? {
        guard let placedInServiceDate, buildingBasis > 0, kind != .land else { return nil }
        return DepreciationSpec(
            id: id,
            name: "\(displayName) — building",
            assetClass: kind == .commercial || kind == .selfRental
                ? .nonresidentialBuilding
                : .residentialBuilding,
            basis: buildingBasis,
            placedInService: placedInServiceDate,
            recoveryYears: realPropertyRecoveryYears,
            propertyID: id,
            isDerivedFromPropertyBasis: true
        )
    }

    /// Building plus every separately tracked asset.
    var allDepreciationSpecs: [DepreciationSpec] {
        var specs: [DepreciationSpec] = []
        if let building = buildingDepreciationSpec { specs.append(building) }
        specs.append(contentsOf: assetList.filter { !$0.isDerivedFromPropertyBasis }.map(\.depreciationSpec))
        return specs
    }
}
