//
//  DecimalMath.swift
//  VRBO tax tracker
//
//  Money math helpers. All monetary values in this app are `Decimal` so that
//  cent-level rounding is exact and reproducible across reports.
//

import Foundation

public extension Decimal {

    /// Lossy conversion used only for charting and ratio math, never for money storage.
    nonisolated var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// Bankers-safe rounding to a fixed number of fraction digits.
    nonisolated func rounded(_ scale: Int = 2, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }

    /// Whole-dollar rounding used on tax forms (the IRS permits dollar rounding).
    nonisolated var wholeDollars: Decimal { rounded(0) }

    nonisolated var isPositive: Bool { self > 0 }
    nonisolated var isNegative: Bool { self < 0 }

    /// `self` as a percentage of `total`, guarding against divide-by-zero.
    nonisolated func share(of total: Decimal) -> Decimal {
        guard total != 0 else { return 0 }
        return (self / total)
    }

    /// Multiplies by a 0...100 percentage without floating point drift.
    nonisolated func applying(percent: Double) -> Decimal {
        guard percent != 100 else { return self }
        let factor = Decimal(percent) / 100
        return (self * factor).rounded(2)
    }

    nonisolated static func fromDouble(_ value: Double, scale: Int = 2) -> Decimal {
        Decimal(value).rounded(scale)
    }
}

public extension Sequence where Element == Decimal {
    nonisolated var total: Decimal { reduce(Decimal.zero, +) }
}

public extension Double {
    /// Clamps a percentage entered by a user into a sane 0...100 range.
    nonisolated var clampedPercent: Double { Swift.min(Swift.max(self, 0), 100) }
}
