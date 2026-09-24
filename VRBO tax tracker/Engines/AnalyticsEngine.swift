//
//  AnalyticsEngine.swift
//  VRBO tax tracker
//
//  Operating metrics a host actually manages the business on: occupancy, ADR,
//  RevPAR, fee drag, and the occupancy level at which the property stops losing
//  money.
//

import Foundation

public struct MonthlyPoint: Identifiable, Hashable, Sendable {
    public var id: Int { month }
    public var month: Int
    public var revenue: Decimal
    public var expenses: Decimal
    public var nightsBooked: Int

    public var net: Decimal { revenue - expenses }
    public var label: String {
        let symbols = DateMath.calendar.shortMonthSymbols
        let index = max(0, min(symbols.count - 1, month - 1))
        return symbols.isEmpty ? "\(month)" : symbols[index]
    }
}

public struct CategorySlice: Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var amount: Decimal
    public var colorHex: String
    public var share: Double
}

public struct PortfolioMetrics: Hashable, Sendable {

    public var year: Int

    public var grossRevenue: Decimal
    public var platformFees: Decimal
    public var operatingExpenses: Decimal
    public var depreciation: Decimal
    public var netIncome: Decimal
    public var cashFlow: Decimal

    public var nightsBooked: Int
    public var nightsAvailable: Int
    public var personalUseDays: Int
    public var occupancyPercent: Double

    /// Average daily rate: accommodation revenue per night booked.
    public var averageDailyRate: Decimal
    /// Revenue per available night — the metric that survives comparison
    /// between a full expensive property and a busy cheap one.
    public var revPAR: Decimal

    public var completedStays: Int
    public var cancelledStays: Int
    public var averageStayNights: Double
    public var averageLeadTimeDays: Double
    public var cancellationRatePercent: Double

    /// Share of gross rent the platforms keep.
    public var feeDragPercent: Double
    public var profitPerNight: Decimal
    public var breakEvenOccupancyPercent: Double
    public var breakEvenNights: Int

    public var monthly: [MonthlyPoint]
    public var revenueByPlatform: [CategorySlice]
    public var expensesByLine: [CategorySlice]
    public var revenueByProperty: [CategorySlice]

    public var marginPercent: Double {
        guard grossRevenue > 0 else { return 0 }
        return (netIncome / grossRevenue).doubleValue * 100
    }
}

public enum AnalyticsEngine {

    /// Expense lines that keep running whether or not anyone is staying.
    private static let fixedLines: Set<ScheduleELine> = [
        .mortgageInterest, .otherInterest, .insurance, .taxes, .depreciation, .legalAndProfessional
    ]

    public static func metrics(
        year: Int,
        properties: [Property],
        expenses: [Expense],
        trips: [MileageTrip],
        mileageRates: MileageRateTable,
        report: ScheduleEReport
    ) -> PortfolioMetrics {

        let bookings = properties.flatMap(\.bookingList)
        let yearBookings = bookings.filter { $0.nights(inYear: year) > 0 }
        let active = yearBookings.filter { !$0.isCancelled }
        let cancelled = bookings.filter {
            $0.isCancelled && DateMath.contains($0.checkIn, inYear: year)
        }

        let nightsBooked = active.map { $0.nights(inYear: year) }.reduce(0, +)
        let nightsAvailable = properties.reduce(0) { $0 + min($1.daysAvailablePerYear, DateMath.daysInYear(year)) }

        let accommodation = active.reduce(Decimal.zero) { running, booking in
            running + booking.accommodationRevenue * booking.yearFraction(year)
        }
        let grossRevenue = report.totalRents
        let platformFees = report.amount(for: .commissions)
        let depreciation = report.totalDepreciation
        let operatingExpenses = report.totalExpenses - depreciation
        let netIncome = report.totalNet

        let personalUseDays = properties.reduce(0) { running, property in
            running + PersonalUseEngine.analyze(
                bookings: property.bookingList,
                personalUse: property.personalUseList,
                year: year,
                propertyID: property.id,
                daysAvailable: property.daysAvailablePerYear
            ).personalUseDays
        }

        let adr = nightsBooked > 0 ? (accommodation / Decimal(nightsBooked)).rounded(2) : 0
        let revPAR = nightsAvailable > 0 ? (grossRevenue / Decimal(nightsAvailable)).rounded(2) : 0
        let occupancy = nightsAvailable > 0 ? Double(nightsBooked) / Double(nightsAvailable) * 100 : 0

        let leadTimes = active.compactMap(\.leadTimeDays).map(Double.init)
        let averageLead = leadTimes.isEmpty ? 0 : leadTimes.reduce(0, +) / Double(leadTimes.count)
        let averageStay = active.isEmpty ? 0 : Double(nightsBooked) / Double(active.count)
        let totalAttempted = active.count + cancelled.count
        let cancellationRate = totalAttempted > 0 ? Double(cancelled.count) / Double(totalAttempted) * 100 : 0

        // Break-even: fixed costs divided by the contribution each night makes.
        var fixedCosts = Decimal.zero
        var variableCosts = Decimal.zero
        for line in report.allLines {
            if fixedLines.contains(line.line) {
                fixedCosts += line.reportedAmount
            } else {
                variableCosts += line.reportedAmount
            }
        }
        let variablePerNight = nightsBooked > 0 ? variableCosts / Decimal(nightsBooked) : 0
        let contributionPerNight = adr - variablePerNight
        let breakEvenNights: Int
        if contributionPerNight > 0 {
            breakEvenNights = Int(ceil((fixedCosts / contributionPerNight).doubleValue))
        } else {
            breakEvenNights = 0
        }
        let breakEvenOccupancy = nightsAvailable > 0 && breakEvenNights > 0
            ? min(200, Double(breakEvenNights) / Double(nightsAvailable) * 100)
            : 0

        return PortfolioMetrics(
            year: year,
            grossRevenue: grossRevenue,
            platformFees: platformFees,
            operatingExpenses: operatingExpenses,
            depreciation: depreciation,
            netIncome: netIncome,
            cashFlow: report.totalCashFlow,
            nightsBooked: nightsBooked,
            nightsAvailable: nightsAvailable,
            personalUseDays: personalUseDays,
            occupancyPercent: min(100, occupancy),
            averageDailyRate: adr,
            revPAR: revPAR,
            completedStays: active.count,
            cancelledStays: cancelled.count,
            averageStayNights: averageStay,
            averageLeadTimeDays: averageLead,
            cancellationRatePercent: cancellationRate,
            feeDragPercent: grossRevenue > 0 ? (platformFees / grossRevenue).doubleValue * 100 : 0,
            profitPerNight: nightsBooked > 0 ? (netIncome / Decimal(nightsBooked)).rounded(2) : 0,
            breakEvenOccupancyPercent: breakEvenOccupancy,
            breakEvenNights: breakEvenNights,
            monthly: monthlySeries(year: year, bookings: active, expenses: expenses, trips: trips, rates: mileageRates),
            revenueByPlatform: platformSlices(year: year, bookings: active),
            expensesByLine: lineSlices(report: report),
            revenueByProperty: propertySlices(report: report)
        )
    }

    /// Revenue is spread across the nights of the stay so a long booking does
    /// not spike a single month.
    public static func monthlySeries(
        year: Int,
        bookings: [Booking],
        expenses: [Expense],
        trips: [MileageTrip],
        rates: MileageRateTable
    ) -> [MonthlyPoint] {

        var revenue = Array(repeating: Decimal.zero, count: 12)
        var nights = Array(repeating: 0, count: 12)
        var costs = Array(repeating: Decimal.zero, count: 12)
        let calendar = DateMath.calendar

        for booking in bookings {
            let totalNights = booking.nights
            guard totalNights > 0 else {
                let month = DateMath.month(of: booking.checkIn)
                if DateMath.contains(booking.checkIn, inYear: year) {
                    revenue[month - 1] += booking.grossRents
                }
                continue
            }
            let perNight = booking.grossRents / Decimal(totalNights)
            var cursor = DateMath.startOfDay(booking.checkIn)
            let stop = DateMath.startOfDay(booking.checkOut)
            var iterations = 0
            while cursor < stop && iterations < 400 {
                if DateMath.contains(cursor, inYear: year) {
                    let month = DateMath.month(of: cursor) - 1
                    revenue[month] += perNight
                    nights[month] += 1
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                iterations += 1
            }
        }

        for expense in expenses where DateMath.contains(expense.date, inYear: year) {
            costs[DateMath.month(of: expense.date) - 1] += expense.deductibleAmount
        }
        for trip in trips where DateMath.contains(trip.date, inYear: year) {
            costs[DateMath.month(of: trip.date) - 1] += trip.deduction(using: rates)
        }

        return (1...12).map { month in
            MonthlyPoint(
                month: month,
                revenue: revenue[month - 1].rounded(2),
                expenses: costs[month - 1].rounded(2),
                nightsBooked: nights[month - 1]
            )
        }
    }

    public static func platformSlices(year: Int, bookings: [Booking]) -> [CategorySlice] {
        var totals: [RentalPlatform: Decimal] = [:]
        for booking in bookings {
            let amount = booking.grossRents * booking.yearFraction(year)
            totals[booking.platform, default: 0] += amount
        }
        let grand = totals.values.reduce(Decimal.zero, +)
        return totals
            .map { platform, amount in
                CategorySlice(
                    id: platform.rawValue,
                    label: platform.title,
                    amount: amount.rounded(2),
                    colorHex: platform.tintHex,
                    share: grand > 0 ? (amount / grand).doubleValue : 0
                )
            }
            .sorted { $0.amount > $1.amount }
    }

    public static func lineSlices(report: ScheduleEReport) -> [CategorySlice] {
        let lines = report.allLines.filter { $0.reportedAmount > 0 }
        let grand = lines.map(\.reportedAmount).total
        return lines
            .map { line in
                CategorySlice(
                    id: "line\(line.line.rawValue)",
                    label: line.line.title,
                    amount: line.reportedAmount,
                    colorHex: PropertyPalette.hex(forIndex: line.line.rawValue),
                    share: grand > 0 ? (line.reportedAmount / grand).doubleValue : 0
                )
            }
            .sorted { $0.amount > $1.amount }
    }

    public static func propertySlices(report: ScheduleEReport) -> [CategorySlice] {
        let grand = report.totalRents
        return report.columns
            .map { column in
                CategorySlice(
                    id: column.id.uuidString,
                    label: column.propertyName,
                    amount: column.rentsReceived,
                    colorHex: column.colorHex,
                    share: grand > 0 ? (column.rentsReceived / grand).doubleValue : 0
                )
            }
            .sorted { $0.amount > $1.amount }
    }

    /// Year-over-year change, positive meaning growth.
    public static func percentChange(from previous: Decimal, to current: Decimal) -> Double? {
        guard previous != 0 else { return nil }
        return ((current - previous) / abs(previous)).doubleValue * 100
    }
}
