//
//  PersonalUseEngine.swift
//  VRBO tax tracker
//
//  IRC §280A day counting. Whether a property is "used as a residence" decides
//  if a loss is allowed at all, so this is the most consequential arithmetic in
//  the app — and the arithmetic hosts most often get wrong.
//

import Foundation

public enum DwellingClassification: String, Sendable {
    /// Rented 15+ days and personal use within the limit. A loss can be claimed,
    /// subject to the passive activity rules.
    case rentalProperty
    /// Personal use exceeded the greater of 14 days or 10% of rental days.
    /// Expenses are allocated and deductions capped at rental income.
    case residenceWithRentalUse
    /// Rented fewer than 15 days while used as a residence. The income is not
    /// reported at all and no rental deductions are taken.
    case minimalRentalExcluded
    /// No rental days recorded in the year.
    case notRented

    public var title: String {
        switch self {
        case .rentalProperty: "Rental property"
        case .residenceWithRentalUse: "Residence with rental use"
        case .minimalRentalExcluded: "Excluded — 14-day rule"
        case .notRented: "Not rented this year"
        }
    }

    public var summary: String {
        switch self {
        case .rentalProperty:
            "Personal use stayed within the §280A limit, so expenses are fully allocable to the rental and a loss can be claimed if the passive activity rules allow it."
        case .residenceWithRentalUse:
            "Personal use exceeded the greater of 14 days or 10% of days rented at fair value. Expenses must be allocated, and rental deductions are capped at rental income — no loss this year."
        case .minimalRentalExcluded:
            "You rented for fewer than 15 days and used the home as a residence. Under §280A(g) the rental income is excluded from income entirely and no rental expenses are deducted."
        case .notRented:
            "No fair-rental days recorded, so there is nothing to report on Schedule E for this property and year."
        }
    }

    public var symbol: String {
        switch self {
        case .rentalProperty: "checkmark.circle.fill"
        case .residenceWithRentalUse: "exclamationmark.triangle.fill"
        case .minimalRentalExcluded: "gift.fill"
        case .notRented: "moon.zzz.fill"
        }
    }

    public var isFavourable: Bool { self == .rentalProperty }
}

public struct PersonalUseAnalysis: Hashable, Sendable {

    public var year: Int
    public var propertyID: UUID?

    /// Days rented at a fair rental price. Schedule E line 2.
    public var fairRentalDays: Int
    /// Days of personal use as §280A defines it. Schedule E line 2.
    public var personalUseDays: Int
    /// Days spent substantially full time on repairs, which are excluded from
    /// personal use even though you were there.
    public var repairDays: Int
    /// Days the unit sat empty and available.
    public var vacantDays: Int
    public var daysInYear: Int

    public var classification: DwellingClassification

    /// The greater of 14 days or 10% of fair rental days.
    public var personalUseThreshold: Int
    /// How many more personal days the owner can take before crossing the line.
    /// Negative means they are already over.
    public var headroomDays: Int

    /// IRS method: rental days ÷ total days actually used.
    public var irsAllocationPercent: Double
    /// Tax Court (Bolton) method: rental days ÷ days in the year. Applies only
    /// to mortgage interest and property taxes, and usually leaves more of the
    /// other expenses available to offset rent.
    public var boltonAllocationPercent: Double

    /// Days recorded as both rented and personally used.
    public var conflictingDays: [Date]
    /// Days covered by more than one confirmed booking.
    public var doubleBookedDays: [Date]

    public var occupancyPercent: Double
    public var isDeductionCappedAtIncome: Bool { classification == .residenceWithRentalUse }
    public var excludesIncomeEntirely: Bool { classification == .minimalRentalExcluded }

    public var totalDaysUsed: Int { fairRentalDays + personalUseDays }

    public var hasDataQualityIssues: Bool {
        !conflictingDays.isEmpty || !doubleBookedDays.isEmpty
    }

    /// How close the owner is to losing rental-property treatment, 0...1.
    public var thresholdProgress: Double {
        guard personalUseThreshold > 0 else { return personalUseDays > 0 ? 1 : 0 }
        return min(1.0, Double(personalUseDays) / Double(personalUseThreshold))
    }
}

public enum PersonalUseEngine {

    /// Builds the set of calendar days a booking occupies. A stay is counted by
    /// nights: arrive the 3rd, leave the 5th is the 3rd and the 4th.
    public static func rentedDays(from bookings: [Booking], inYear year: Int) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        let calendar = DateMath.calendar
        let yearStart = DateMath.startOfYear(year)
        let yearEnd = DateMath.endOfYearExclusive(year)

        for booking in bookings where !booking.isCancelled {
            var cursor = max(DateMath.startOfDay(booking.checkIn), yearStart)
            let stop = min(DateMath.startOfDay(booking.checkOut), yearEnd)
            var guardCounter = 0
            while cursor < stop && guardCounter < 400 {
                counts[cursor, default: 0] += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                guardCounter += 1
            }
        }
        return counts
    }

    /// Personal-use days are counted inclusively — the day you arrive and the
    /// day you leave are both days of use.
    public static func personalDays(
        from entries: [PersonalUseEntry],
        inYear year: Int
    ) -> (personal: Set<Date>, repair: Set<Date>, offMarket: Set<Date>) {
        var personal: Set<Date> = []
        var repair: Set<Date> = []
        var offMarket: Set<Date> = []
        let calendar = DateMath.calendar
        let yearStart = DateMath.startOfYear(year)
        let yearEndExclusive = DateMath.endOfYearExclusive(year)

        for entry in entries {
            var cursor = max(DateMath.startOfDay(entry.startDate), yearStart)
            let stop = min(
                calendar.date(byAdding: .day, value: 1, to: DateMath.startOfDay(entry.endDate)) ?? yearEndExclusive,
                yearEndExclusive
            )
            var guardCounter = 0
            while cursor < stop && guardCounter < 400 {
                switch entry.kind {
                case .repairAndMaintenanceDay: repair.insert(cursor)
                case .vacantNotAvailable: offMarket.insert(cursor)
                default: personal.insert(cursor)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                guardCounter += 1
            }
        }
        return (personal, repair, offMarket)
    }

    public static func analyze(
        bookings: [Booking],
        personalUse: [PersonalUseEntry],
        year: Int,
        propertyID: UUID? = nil,
        daysAvailable: Int = 365
    ) -> PersonalUseAnalysis {

        let rentedCounts = rentedDays(from: bookings, inYear: year)
        let rentedSet = Set(rentedCounts.keys)
        let (personalSet, repairSet, offMarketSet) = personalDays(from: personalUse, inYear: year)

        // A day claimed as both rented and personal is a bookkeeping conflict.
        // The conservative treatment is to count it as personal use.
        let conflicts = rentedSet.intersection(personalSet)
        let fairRentalDays = rentedSet.subtracting(personalSet).count
        let personalUseDays = personalSet.count
        let repairDays = repairSet.subtracting(personalSet).count

        let daysInYear = DateMath.daysInYear(year)
        let usedDays = fairRentalDays + personalUseDays
        let vacantDays = max(0, daysInYear - usedDays - repairDays - offMarketSet.count)

        let tenPercent = Int((Double(fairRentalDays) * 0.10).rounded(.down))
        let threshold = max(14, tenPercent)

        let classification: DwellingClassification
        if fairRentalDays == 0 {
            classification = .notRented
        } else if fairRentalDays < 15 && personalUseDays >= 15 {
            classification = .minimalRentalExcluded
        } else if personalUseDays > threshold {
            classification = .residenceWithRentalUse
        } else {
            classification = .rentalProperty
        }

        let irsPercent = usedDays > 0 ? Double(fairRentalDays) / Double(usedDays) * 100 : 0
        let boltonPercent = daysInYear > 0 ? Double(fairRentalDays) / Double(daysInYear) * 100 : 0

        let availableDenominator = max(1, min(daysAvailable, daysInYear))
        let occupancy = Double(fairRentalDays) / Double(availableDenominator) * 100

        let doubleBooked = rentedCounts.filter { $0.value > 1 }.keys.sorted()

        return PersonalUseAnalysis(
            year: year,
            propertyID: propertyID,
            fairRentalDays: fairRentalDays,
            personalUseDays: personalUseDays,
            repairDays: repairDays,
            vacantDays: vacantDays,
            daysInYear: daysInYear,
            classification: classification,
            personalUseThreshold: threshold,
            headroomDays: threshold - personalUseDays,
            irsAllocationPercent: min(100, irsPercent),
            boltonAllocationPercent: min(100, boltonPercent),
            conflictingDays: conflicts.sorted(),
            doubleBookedDays: doubleBooked,
            occupancyPercent: min(100, occupancy)
        )
    }

    /// What one more personal night would do to the classification. Shown as a
    /// live warning before an owner blocks a week on their own calendar.
    public static func projectedClassification(
        current: PersonalUseAnalysis,
        addingPersonalDays extra: Int
    ) -> DwellingClassification {
        let newPersonal = current.personalUseDays + extra
        if current.fairRentalDays == 0 { return .notRented }
        if current.fairRentalDays < 15 && newPersonal >= 15 { return .minimalRentalExcluded }
        return newPersonal > current.personalUseThreshold ? .residenceWithRentalUse : .rentalProperty
    }

    /// The most personal days that can still be taken without tipping over.
    public static func safePersonalDaysRemaining(_ analysis: PersonalUseAnalysis) -> Int {
        max(0, analysis.headroomDays)
    }

    /// The "Augusta rule": renting a dwelling you use as a residence for 14 days
    /// or fewer in a year makes that rental income tax free.
    public static func augustaRuleOpportunity(_ analysis: PersonalUseAnalysis) -> Bool {
        analysis.fairRentalDays > 0
            && analysis.fairRentalDays < 15
            && analysis.personalUseDays >= 15
    }
}
