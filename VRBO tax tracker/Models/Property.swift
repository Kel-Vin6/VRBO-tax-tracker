//
//  Property.swift
//  VRBO tax tracker
//

import Foundation
import SwiftData
import SwiftUI

@Model
public final class Property {

    public var id: UUID = UUID()
    public var name: String = ""
    public var street: String = ""
    public var city: String = ""
    public var state: String = ""
    public var postalCode: String = ""
    public var country: String = "United States"

    public var kindRaw: Int = PropertyKind.vacationOrShortTerm.rawValue
    public var colorHex: String = PropertyPalette.hexes[0]
    public var isActive: Bool = true
    public var sortIndex: Int = 0

    // Cost basis inputs
    public var purchaseDate: Date?
    public var placedInServiceDate: Date?
    public var purchasePrice: Decimal = 0
    public var landValue: Decimal = 0
    public var capitalizedClosingCosts: Decimal = 0
    public var ownershipPercent: Double = 100

    /// Percentage of the structure actually rented out. A host renting two of
    /// four bedrooms sets 50 here and every shared expense is prorated.
    public var rentedSpacePercent: Double = 100

    // Listing facts, used for occupancy and ADR analytics
    public var bedrooms: Int = 0
    public var bathrooms: Double = 0
    public var maxGuests: Int = 0
    public var squareFeet: Int = 0

    /// Days in the year the unit was genuinely on the market. Vacancy is
    /// measured against this rather than 365.
    public var daysAvailablePerYear: Int = 365
    public var targetNightlyRate: Decimal = 0

    // Compliance
    public var permitNumber: String = ""
    public var permitExpiration: Date?
    public var insurancePolicyNumber: String = ""
    public var insuranceExpiration: Date?
    public var lodgingTaxJurisdiction: String = ""
    public var lodgingTaxRatePercent: Double = 0
    public var lodgingTaxRemittedByPlatform: Bool = true

    public var notes: String = ""
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Booking.property)
    public var bookings: [Booking]? = []

    @Relationship(deleteRule: .nullify, inverse: \Expense.property)
    public var expenses: [Expense]? = []

    @Relationship(deleteRule: .cascade, inverse: \DepreciableAsset.property)
    public var assets: [DepreciableAsset]? = []

    @Relationship(deleteRule: .cascade, inverse: \PersonalUseEntry.property)
    public var personalUse: [PersonalUseEntry]? = []

    @Relationship(deleteRule: .nullify, inverse: \ParticipationEntry.property)
    public var participation: [ParticipationEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \LoanAccount.property)
    public var loans: [LoanAccount]? = []

    @Relationship(deleteRule: .nullify, inverse: \MileageTrip.property)
    public var trips: [MileageTrip]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredDocument.property)
    public var documents: [StoredDocument]? = []

    public init(
        name: String = "",
        kind: PropertyKind = .vacationOrShortTerm,
        colorHex: String = PropertyPalette.hexes[0]
    ) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorHex = colorHex
        self.createdAt = Date()
    }

    // MARK: - Derived

    public var kind: PropertyKind {
        get { PropertyKind(rawValue: kindRaw) ?? .vacationOrShortTerm }
        set { kindRaw = newValue.rawValue }
    }

    public var color: Color { PropertyPalette.color(for: colorHex) }

    public var displayName: String {
        name.isEmpty ? (street.isEmpty ? "Untitled property" : street) : name
    }

    public var shortAddress: String {
        [street, city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    public var fullAddress: String {
        let line2 = [city, state, postalCode].filter { !$0.isEmpty }.joined(separator: " ")
        return [street, line2, country].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Initials used by the avatar chip when no photo is set.
    public var monogram: String {
        let words = displayName.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    // MARK: - Basis

    /// Total acquisition basis before separating land.
    public var totalBasis: Decimal {
        purchasePrice + capitalizedClosingCosts
    }

    /// The depreciable basis of the building itself. Land is never depreciated,
    /// which is why the land allocation field is mandatory before the
    /// depreciation engine will produce a schedule.
    public var buildingBasis: Decimal {
        let raw = totalBasis - landValue
        guard raw > 0 else { return 0 }
        return raw.applying(percent: ownershipPercent).applying(percent: rentedSpacePercent)
    }

    public var landAllocationPercent: Double {
        guard totalBasis > 0 else { return 0 }
        return (landValue / totalBasis).doubleValue * 100
    }

    public var isDepreciationReady: Bool {
        placedInServiceDate != nil && buildingBasis > 0 && kind != .land
    }

    public var realPropertyRecoveryYears: Double { kind.realPropertyRecoveryYears }

    // MARK: - Relationship accessors

    public var bookingList: [Booking] { bookings ?? [] }
    public var expenseList: [Expense] { expenses ?? [] }
    public var assetList: [DepreciableAsset] { assets ?? [] }
    public var personalUseList: [PersonalUseEntry] { personalUse ?? [] }
    public var participationList: [ParticipationEntry] { participation ?? [] }
    public var loanList: [LoanAccount] { loans ?? [] }
    public var tripList: [MileageTrip] { trips ?? [] }
    public var documentList: [StoredDocument] { documents ?? [] }

    // MARK: - Compliance

    public enum ComplianceFlag: Identifiable, Hashable, Sendable {
        case permitExpiring(days: Int)
        case permitExpired
        case insuranceExpiring(days: Int)
        case insuranceExpired
        case missingLandAllocation
        case missingPlacedInService

        public var id: String {
            switch self {
            case .permitExpiring(let d): "permitExpiring\(d)"
            case .permitExpired: "permitExpired"
            case .insuranceExpiring(let d): "insuranceExpiring\(d)"
            case .insuranceExpired: "insuranceExpired"
            case .missingLandAllocation: "missingLand"
            case .missingPlacedInService: "missingPIS"
            }
        }

        public var message: String {
            switch self {
            case .permitExpiring(let d): "Short-term rental permit expires in \(d) day\(d == 1 ? "" : "s")."
            case .permitExpired: "Short-term rental permit has expired."
            case .insuranceExpiring(let d): "Insurance policy renews in \(d) day\(d == 1 ? "" : "s")."
            case .insuranceExpired: "Insurance policy has lapsed."
            case .missingLandAllocation: "No land value allocated — depreciation cannot be computed."
            case .missingPlacedInService: "No placed-in-service date — depreciation cannot start."
            }
        }

        public var isCritical: Bool {
            switch self {
            case .permitExpired, .insuranceExpired: true
            default: false
            }
        }

        public var symbol: String {
            switch self {
            case .permitExpiring, .permitExpired: "checkmark.seal.fill"
            case .insuranceExpiring, .insuranceExpired: "shield.fill"
            case .missingLandAllocation, .missingPlacedInService: "chart.line.downtrend.xyaxis"
            }
        }
    }

    public func complianceFlags(asOf date: Date = Date(), warningWindow: Int = 45) -> [ComplianceFlag] {
        var flags: [ComplianceFlag] = []
        let today = DateMath.startOfDay(date)

        if let expiry = permitExpiration {
            let days = DateMath.calendar.dateComponents([.day], from: today, to: DateMath.startOfDay(expiry)).day ?? 0
            if days < 0 { flags.append(.permitExpired) }
            else if days <= warningWindow { flags.append(.permitExpiring(days: days)) }
        }
        if let expiry = insuranceExpiration {
            let days = DateMath.calendar.dateComponents([.day], from: today, to: DateMath.startOfDay(expiry)).day ?? 0
            if days < 0 { flags.append(.insuranceExpired) }
            else if days <= warningWindow { flags.append(.insuranceExpiring(days: days)) }
        }
        if kind != .land {
            if placedInServiceDate == nil { flags.append(.missingPlacedInService) }
            if totalBasis > 0 && landValue <= 0 { flags.append(.missingLandAllocation) }
        }
        return flags
    }
}
