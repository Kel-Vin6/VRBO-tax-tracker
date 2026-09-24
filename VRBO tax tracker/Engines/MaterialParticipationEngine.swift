//
//  MaterialParticipationEngine.swift
//  VRBO tax tracker
//
//  Whether a rental loss is passive or non-passive is usually worth more than
//  every deduction on the return put together. Two things decide it:
//
//    1. Average period of customer use. Seven days or fewer and the activity is
//       not a "rental activity" under Reg. §1.469-1(e)(3)(ii)(A) at all.
//    2. Material participation under Reg. §1.469-5T.
//
//  The engine measures both from the data the host is already recording.
//

import Foundation

public struct ParticipationTestResult: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var requirement: String
    public var currentValue: Double
    public var targetValue: Double
    public var isMet: Bool
    public var isSelfAssessed: Bool
    public var detail: String

    public var progress: Double {
        guard targetValue > 0 else { return isMet ? 1 : 0 }
        return min(1.0, currentValue / targetValue)
    }

    public var remaining: Double { max(0, targetValue - currentValue) }
}

public struct MaterialParticipationAnalysis: Hashable, Sendable {

    public var year: Int
    public var propertyID: UUID?

    public var totalLoggedHours: Double
    public var qualifyingHours: Double
    public var spouseHours: Double
    public var otherIndividualHours: Double

    public var completedStays: Int
    public var totalRentedNights: Int
    /// Total nights ÷ number of stays.
    public var averageStayNights: Double

    public var tests: [ParticipationTestResult]
    public var meetsMaterialParticipation: Bool

    /// Rental services hours counted for the §199A safe harbor.
    public var qbiSafeHarborHours: Double
    public var meetsQBISafeHarbor: Bool

    /// Share of logged hours that were written down the same day.
    public var contemporaneousPercent: Double

    public var isShortTermRentalException: Bool { averageStayNights > 0 && averageStayNights <= 7 }
    public var isThirtyDayException: Bool { averageStayNights > 7 && averageStayNights <= 30 }

    /// The headline: a loss escapes the passive rules when the seven-day
    /// exception applies and the owner materially participates.
    public var lossIsNonPassive: Bool {
        isShortTermRentalException && meetsMaterialParticipation
    }

    public var statusTitle: String {
        if lossIsNonPassive { return "Non-passive" }
        if isShortTermRentalException { return "Seven-day exception met, participation not yet" }
        if averageStayNights == 0 { return "No completed stays yet" }
        return "Passive rental activity"
    }

    public var statusDetail: String {
        if lossIsNonPassive {
            return "Average stay is \(Fmt.number(averageStayNights)) nights and you meet a material participation test, so a loss from this activity can offset your other income this year."
        }
        if isShortTermRentalException {
            return "Average stay of \(Fmt.number(averageStayNights)) nights clears the seven-day exception, but no material participation test is met yet. Meeting one converts the loss from passive to non-passive."
        }
        if isThirtyDayException {
            return "Average stay is \(Fmt.number(averageStayNights)) nights. Stays of 30 days or fewer can escape the rental classification, but only if you also provide significant personal services — check this with your accountant."
        }
        if averageStayNights == 0 {
            return "Record completed stays and the average period of customer use appears here."
        }
        return "Average stay of \(Fmt.number(averageStayNights)) nights exceeds 30, so this is a rental activity and any loss is passive unless you qualify as a real estate professional."
    }
}

public enum MaterialParticipationEngine {

    public static let materialParticipationHours: Double = 500
    public static let significantParticipationHours: Double = 100
    public static let qbiSafeHarborHours: Double = 250
    public static let realEstateProfessionalHours: Double = 750

    public static func analyze(
        bookings: [Booking],
        entries: [ParticipationEntry],
        year: Int,
        propertyID: UUID? = nil,
        priorYearsMateriallyParticipated: Int = 0
    ) -> MaterialParticipationAnalysis {

        let yearEntries = entries.filter { DateMath.contains($0.date, inYear: year) }
        let totalHours = yearEntries.map(\.hours).reduce(0, +)
        let qualifying = yearEntries.map(\.qualifyingHours).reduce(0, +)
        let spouse = yearEntries.filter(\.performedBySpouse).map(\.qualifyingHours).reduce(0, +)
        let others = yearEntries.map(\.contractorHoursSameDay).reduce(0, +)

        let sameDay = yearEntries.filter(\.loggedSameDay).map(\.hours).reduce(0, +)
        let contemporaneous = totalHours > 0 ? sameDay / totalHours * 100 : 100

        // Average period of customer use, measured over stays that actually
        // happened in the year.
        let relevant = bookings.filter { !$0.isCancelled && $0.nights(inYear: year) > 0 }
        let nights = relevant.map { $0.nights(inYear: year) }.reduce(0, +)
        let stays = relevant.count
        let averageStay = stays > 0 ? Double(nights) / Double(stays) : 0

        let qbiHours = yearEntries
            .filter(\.countsForQBISafeHarbor)
            .map(\.hours)
            .reduce(0, +)

        var tests: [ParticipationTestResult] = []

        tests.append(
            ParticipationTestResult(
                id: "test1",
                title: "500-hour test",
                requirement: "More than 500 hours of participation in the activity during the year.",
                currentValue: qualifying,
                targetValue: materialParticipationHours,
                isMet: qualifying > materialParticipationHours,
                isSelfAssessed: false,
                detail: qualifying > materialParticipationHours
                    ? "Met with \(Fmt.hours(qualifying)) logged."
                    : "\(Fmt.hours(max(0, materialParticipationHours - qualifying + 0.1))) more needed."
            )
        )

        let substantiallyAll = qualifying > 0 && others <= qualifying * 0.05
        tests.append(
            ParticipationTestResult(
                id: "test2",
                title: "Substantially-all test",
                requirement: "Your participation is substantially all of the participation of everyone involved.",
                currentValue: qualifying,
                targetValue: max(qualifying, others),
                isMet: substantiallyAll,
                isSelfAssessed: false,
                detail: others > 0
                    ? "You logged \(Fmt.hours(qualifying)); others logged \(Fmt.hours(others))."
                    : "No hours recorded for anyone else, which supports this test. Record cleaner and contractor hours to make it stand up."
            )
        )

        let test3Met = qualifying > significantParticipationHours && qualifying >= others
        tests.append(
            ParticipationTestResult(
                id: "test3",
                title: "100-hour test",
                requirement: "More than 100 hours, and no other individual participated more than you.",
                currentValue: qualifying,
                targetValue: significantParticipationHours,
                isMet: test3Met,
                isSelfAssessed: false,
                detail: qualifying <= significantParticipationHours
                    ? "\(Fmt.hours(max(0, significantParticipationHours - qualifying + 0.1))) more needed."
                    : (qualifying >= others
                        ? "Met — you out-worked every other individual by \(Fmt.hours(qualifying - others))."
                        : "You are \(Fmt.hours(others - qualifying)) behind the most active other individual.")
            )
        )

        let test5Met = priorYearsMateriallyParticipated >= 5
        tests.append(
            ParticipationTestResult(
                id: "test5",
                title: "Five-of-ten-years test",
                requirement: "You materially participated in any 5 of the 10 preceding tax years.",
                currentValue: Double(priorYearsMateriallyParticipated),
                targetValue: 5,
                isMet: test5Met,
                isSelfAssessed: true,
                detail: "Set the number of qualifying prior years in Settings. Recorded: \(priorYearsMateriallyParticipated)."
            )
        )

        let test7Met = qualifying > significantParticipationHours
            && yearEntries.count >= 24
            && contemporaneous >= 50
        tests.append(
            ParticipationTestResult(
                id: "test7",
                title: "Facts and circumstances",
                requirement: "More than 100 hours on a regular, continuous and substantial basis.",
                currentValue: Double(yearEntries.count),
                targetValue: 24,
                isMet: test7Met,
                isSelfAssessed: true,
                detail: "\(yearEntries.count) log entries across the year, \(Fmt.percent(contemporaneous)) written up the same day. This test is judgement-based — the log is your evidence."
            )
        )

        let met = tests.contains { $0.isMet }

        return MaterialParticipationAnalysis(
            year: year,
            propertyID: propertyID,
            totalLoggedHours: totalHours,
            qualifyingHours: qualifying,
            spouseHours: spouse,
            otherIndividualHours: others,
            completedStays: stays,
            totalRentedNights: nights,
            averageStayNights: averageStay,
            tests: tests,
            meetsMaterialParticipation: met,
            qbiSafeHarborHours: qbiHours,
            meetsQBISafeHarbor: qbiHours >= qbiSafeHarborHours,
            contemporaneousPercent: contemporaneous
        )
    }

    /// Hours still needed to reach the nearest test that is purely a matter of
    /// putting in the time.
    public static func hoursToNearestTest(_ analysis: MaterialParticipationAnalysis) -> (hours: Double, testTitle: String)? {
        guard !analysis.meetsMaterialParticipation else { return nil }
        let hundred = max(0, significantParticipationHours - analysis.qualifyingHours)
        let fiveHundred = max(0, materialParticipationHours - analysis.qualifyingHours)

        if analysis.qualifyingHours >= analysis.otherIndividualHours, hundred > 0 {
            return (hundred + 0.1, "100-hour test")
        }
        return (fiveHundred + 0.1, "500-hour test")
    }
}
