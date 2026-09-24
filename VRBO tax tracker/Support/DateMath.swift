//
//  DateMath.swift
//  VRBO tax tracker
//
//  Tax work is day-counting work. Everything here is calendar-day based and
//  time-zone stable so that a stay never gains or loses a night.
//

import Foundation

public enum DateMath {

    /// The calendar used for every day count in the app. Fixed to the user's
    /// calendar but normalized to their current time zone at call time.
    public static var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal
    }

    public static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Nights between two dates, which is what a lodging platform bills.
    /// A same-day check-in/check-out counts as zero nights.
    public static func nights(from checkIn: Date, to checkOut: Date) -> Int {
        let a = startOfDay(checkIn)
        let b = startOfDay(checkOut)
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    /// Inclusive day count, which is how the IRS counts days of *use*.
    public static func inclusiveDays(from start: Date, to end: Date) -> Int {
        let a = startOfDay(start)
        let b = startOfDay(end)
        return max(0, (calendar.dateComponents([.day], from: a, to: b).day ?? 0) + 1)
    }

    public static func year(of date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    public static func month(of date: Date) -> Int {
        calendar.component(.month, from: date)
    }

    public static func startOfYear(_ year: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
    }

    /// Exclusive upper bound: midnight on January 1 of the following year.
    public static func endOfYearExclusive(_ year: Int) -> Date {
        calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? Date()
    }

    public static func yearInterval(_ year: Int) -> DateInterval {
        DateInterval(start: startOfYear(year), end: endOfYearExclusive(year))
    }

    public static func contains(_ date: Date, inYear year: Int) -> Bool {
        self.year(of: date) == year
    }

    /// Number of nights of a stay that fall inside a given tax year. Used to
    /// split a stay that straddles New Year's Eve across two returns.
    public static func nights(from checkIn: Date, to checkOut: Date, inYear year: Int) -> Int {
        let stayStart = startOfDay(checkIn)
        let stayEnd = startOfDay(checkOut)
        guard stayEnd > stayStart else { return 0 }
        let bounds = yearInterval(year)
        let lower = max(stayStart, bounds.start)
        let upper = min(stayEnd, bounds.end)
        guard upper > lower else { return 0 }
        return max(0, calendar.dateComponents([.day], from: lower, to: upper).day ?? 0)
    }

    /// Inclusive days of an occupancy range falling inside a tax year.
    public static func days(from start: Date, to end: Date, inYear year: Int) -> Int {
        let rangeStart = startOfDay(start)
        let rangeEnd = startOfDay(end)
        guard rangeEnd >= rangeStart else { return 0 }
        let yearStart = startOfYear(year)
        let yearEndInclusive = calendar.date(byAdding: .day, value: -1, to: endOfYearExclusive(year)) ?? yearStart
        let lower = max(rangeStart, yearStart)
        let upper = min(rangeEnd, yearEndInclusive)
        guard upper >= lower else { return 0 }
        return inclusiveDays(from: lower, to: upper)
    }

    public static func daysInYear(_ year: Int) -> Int {
        let start = startOfYear(year)
        let end = endOfYearExclusive(year)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 365
    }

    public static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public static func adding(months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    /// Two ranges overlap if they share at least one calendar day.
    public static func rangesOverlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        startOfDay(aStart) <= startOfDay(bEnd) && startOfDay(bStart) <= startOfDay(aEnd)
    }

    public static var currentYear: Int { year(of: Date()) }

    /// Tax years the app offers for selection: a decade back through next year.
    public static func selectableYears(around year: Int = currentYear) -> [Int] {
        Array((year - 9)...(year + 1)).reversed()
    }
}

public extension Date {
    var taxYear: Int { DateMath.year(of: self) }
    var startOfDay: Date { DateMath.startOfDay(self) }
}
