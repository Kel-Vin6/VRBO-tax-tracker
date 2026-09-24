//
//  MileageRates.swift
//  VRBO tax tracker
//
//  The IRS publishes the standard business mileage rate each December. Rates
//  the app ships with are the published figures; any year the app has no
//  published figure for carries the most recent rate forward and is flagged as
//  unconfirmed so the user knows to check and override it in Settings.
//

import Foundation

public struct MileageRateTable: Codable, Equatable, Sendable {

    /// Published IRS standard mileage rates for business use, in dollars per mile.
    /// 2022 is split mid-year and handled separately below.
    public static let published: [Int: Double] = [
        2018: 0.545,
        2019: 0.58,
        2020: 0.575,
        2021: 0.56,
        2023: 0.655,
        2024: 0.67,
        2025: 0.70
    ]

    /// The IRS raised the rate mid-way through 2022 in response to fuel prices.
    public static let rate2022FirstHalf = 0.585
    public static let rate2022SecondHalf = 0.625

    public static let latestPublishedYear = 2025

    /// User overrides keyed by tax year, set in Settings.
    public var overrides: [Int: Double] = [:]

    public init(overrides: [Int: Double] = [:]) {
        self.overrides = overrides
    }

    public func rate(on date: Date) -> Double {
        let year = DateMath.year(of: date)
        if let override = overrides[year], override > 0 { return override }
        if year == 2022 {
            return DateMath.month(of: date) <= 6
                ? Self.rate2022FirstHalf
                : Self.rate2022SecondHalf
        }
        return Self.publishedRate(for: year)
    }

    /// Representative rate for a whole tax year, used in projections.
    public func rate(forYear year: Int) -> Double {
        if let override = overrides[year], override > 0 { return override }
        if year == 2022 { return (Self.rate2022FirstHalf + Self.rate2022SecondHalf) / 2 }
        return Self.publishedRate(for: year)
    }

    public static func publishedRate(for year: Int) -> Double {
        if let rate = published[year] { return rate }
        if year == 2022 { return (rate2022FirstHalf + rate2022SecondHalf) / 2 }
        if year < 2018 { return published[2018] ?? 0.545 }
        // Carry the most recent published rate forward.
        return published[latestPublishedYear] ?? 0.70
    }

    /// True when the rate in use is a carry-forward rather than a figure the
    /// app shipped with, which means the user should confirm it.
    public func isUnconfirmed(forYear year: Int) -> Bool {
        if overrides[year] != nil { return false }
        if year == 2022 { return false }
        return Self.published[year] == nil
    }

    public func sourceNote(forYear year: Int) -> String {
        if let override = overrides[year], override > 0 {
            return "Your override: \(override.formatted(.number.precision(.fractionLength(3))))/mile."
        }
        if year == 2022 {
            return "2022 used two rates: 58.5¢ through June and 62.5¢ from July."
        }
        if Self.published[year] != nil {
            return "IRS published rate for \(year)."
        }
        return "No published rate for \(year) yet — carried forward from \(Self.latestPublishedYear). Confirm it in Settings."
    }
}
