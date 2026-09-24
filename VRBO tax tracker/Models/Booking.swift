//
//  Booking.swift
//  VRBO tax tracker
//

import Foundation
import SwiftData

@Model
public final class Booking {

    public var id: UUID = UUID()
    public var confirmationCode: String = ""
    public var guestName: String = ""
    public var guestCount: Int = 1
    public var platformRaw: String = RentalPlatform.airbnb.rawValue

    public var checkIn: Date = Date()
    public var checkOut: Date = Date()
    public var bookedOn: Date?

    /// What the guest paid for the nights themselves.
    public var accommodationRevenue: Decimal = 0
    /// Cleaning fee charged to the guest. Taxable rental income, not a netting
    /// item — the cleaner you pay is a separate deductible expense.
    public var cleaningFeeRevenue: Decimal = 0
    /// Pet fees, extra-guest fees, early check-in, resort fees.
    public var otherFeeRevenue: Decimal = 0
    /// Occupancy / lodging / transient tax added to the guest's bill.
    public var lodgingTaxCollected: Decimal = 0

    /// Host service fee retained by the platform. Deductible on line 8.
    public var platformHostFee: Decimal = 0
    /// Card processing fee, where the platform itemises it separately.
    public var paymentProcessingFee: Decimal = 0

    /// What actually landed in the bank, as reported by the platform. Left at
    /// zero the app uses the computed figure; entered, it powers reconciliation.
    public var reportedPayout: Decimal = 0

    public var isCancelled: Bool = false
    /// Amount kept under the cancellation policy. Still taxable income.
    public var cancellationRetainedAmount: Decimal = 0

    /// Refundable damage deposits are not income while they are held.
    public var securityDepositHeld: Decimal = 0

    public var notes: String = ""
    public var sourceRaw: String = EntrySource.manual.rawValue
    public var externalReference: String = ""
    public var createdAt: Date = Date()

    public var property: Property?

    public init(
        platform: RentalPlatform = .airbnb,
        checkIn: Date = Date(),
        checkOut: Date = Date(),
        property: Property? = nil
    ) {
        self.id = UUID()
        self.platformRaw = platform.rawValue
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.property = property
        self.createdAt = Date()
    }

    // MARK: - Derived

    public var platform: RentalPlatform {
        get { RentalPlatform(rawValue: platformRaw) ?? .other }
        set { platformRaw = newValue.rawValue }
    }

    public var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var nights: Int { DateMath.nights(from: checkIn, to: checkOut) }

    public func nights(inYear year: Int) -> Int {
        DateMath.nights(from: checkIn, to: checkOut, inYear: year)
    }

    /// Fraction of the stay that belongs to a given tax year. Income is
    /// recognised when received for cash-basis filers, but a stay straddling
    /// New Year is still reported per the year it was paid; the app reports on
    /// the check-out year by default and exposes this for accrual users.
    public func yearFraction(_ year: Int) -> Decimal {
        guard nights > 0 else { return DateMath.year(of: checkIn) == year ? 1 : 0 }
        return Decimal(nights(inYear: year)) / Decimal(nights)
    }

    /// Schedule E line 3, "Rents received", for this stay. Fees charged to the
    /// guest are rent; the platform's cut is an expense, not a reduction.
    public var grossRents: Decimal {
        if isCancelled { return cancellationRetainedAmount }
        return accommodationRevenue + cleaningFeeRevenue + otherFeeRevenue
    }

    public var totalPlatformFees: Decimal {
        platformHostFee + paymentProcessingFee
    }

    /// What should hit the bank account if the platform remits lodging tax.
    public var computedPayout: Decimal {
        grossRents - totalPlatformFees
    }

    /// Total charged to the guest's card, which is what a 1099-K reports.
    public var guestTotalCharged: Decimal {
        grossRents + lodgingTaxCollected
    }

    public var payoutVariance: Decimal {
        guard reportedPayout != 0 else { return 0 }
        return (reportedPayout - computedPayout).rounded(2)
    }

    public var hasPayoutVariance: Bool { abs(payoutVariance) >= 1 }

    public var averageNightlyRate: Decimal {
        guard nights > 0 else { return 0 }
        return (accommodationRevenue / Decimal(nights)).rounded(2)
    }

    public var effectiveFeeRate: Double {
        guard grossRents > 0 else { return 0 }
        return (totalPlatformFees / grossRents).doubleValue * 100
    }

    public var leadTimeDays: Int? {
        guard let bookedOn else { return nil }
        return DateMath.calendar.dateComponents(
            [.day],
            from: DateMath.startOfDay(bookedOn),
            to: DateMath.startOfDay(checkIn)
        ).day
    }

    public var isFutureStay: Bool { checkIn > Date() }
    public var isInProgress: Bool {
        let now = DateMath.startOfDay(Date())
        return checkIn.startOfDay <= now && now < checkOut.startOfDay
    }

    public var displayGuest: String {
        guestName.trimmingCharacters(in: .whitespaces).isEmpty ? "Guest" : guestName
    }

    public var dateRangeLabel: String {
        "\(Fmt.dayMonth(checkIn)) – \(Fmt.dayMonth(checkOut))"
    }

    // MARK: - Validation

    public enum ValidationIssue: String, Identifiable, Sendable {
        case checkOutBeforeCheckIn
        case zeroRevenue
        case feeExceedsRevenue
        case suspiciousNightlyRate

        public var id: String { rawValue }

        public var message: String {
            switch self {
            case .checkOutBeforeCheckIn: "Check-out is on or before check-in."
            case .zeroRevenue: "This stay has no revenue recorded."
            case .feeExceedsRevenue: "Platform fees exceed the gross rent."
            case .suspiciousNightlyRate: "Nightly rate looks unusually high — check for a typo."
            }
        }
    }

    public var validationIssues: [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if nights <= 0 && !isCancelled { issues.append(.checkOutBeforeCheckIn) }
        if grossRents <= 0 { issues.append(.zeroRevenue) }
        if totalPlatformFees > grossRents && grossRents > 0 { issues.append(.feeExceedsRevenue) }
        if averageNightlyRate > 10_000 { issues.append(.suspiciousNightlyRate) }
        return issues
    }
}
