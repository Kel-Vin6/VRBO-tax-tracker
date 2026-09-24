//
//  MileageTrip.swift
//  VRBO tax tracker
//

import Foundation
import SwiftData

public enum MileageMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case standardRate
    case actualExpenses

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standardRate: "Standard mileage rate"
        case .actualExpenses: "Actual vehicle expenses"
        }
    }
}

public enum TripPurpose: String, Codable, CaseIterable, Identifiable, Sendable {
    case guestTurnover
    case maintenanceVisit
    case supplyRun
    case inspection
    case meetingContractor
    case bankingOrAdmin
    case propertyShopping
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .guestTurnover: "Guest turnover"
        case .maintenanceVisit: "Maintenance visit"
        case .supplyRun: "Supply run"
        case .inspection: "Property inspection"
        case .meetingContractor: "Meeting a contractor"
        case .bankingOrAdmin: "Banking or admin"
        case .propertyShopping: "Scouting a new property"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .guestTurnover: "sparkles"
        case .maintenanceVisit: "wrench.and.screwdriver"
        case .supplyRun: "cart"
        case .inspection: "magnifyingglass"
        case .meetingContractor: "person.2"
        case .bankingOrAdmin: "building.columns"
        case .propertyShopping: "house.and.flag"
        case .other: "car"
        }
    }

    /// Miles driven to scout a property you do not yet own are start-up costs,
    /// not a current deduction against an existing rental.
    public var isCurrentlyDeductible: Bool { self != .propertyShopping }
}

@Model
public final class MileageTrip {

    public var id: UUID = UUID()
    public var date: Date = Date()
    public var purposeRaw: String = TripPurpose.guestTurnover.rawValue
    public var fromLabel: String = ""
    public var toLabel: String = ""
    public var miles: Double = 0
    public var isRoundTrip: Bool = false
    public var odometerStart: Double = 0
    public var odometerEnd: Double = 0
    public var methodRaw: String = MileageMethod.standardRate.rawValue

    /// Set only when the user overrides the statutory rate for this trip.
    public var rateOverride: Double = 0
    /// Out-of-pocket tolls and parking are deductible on top of the standard rate.
    public var tollsAndParking: Decimal = 0

    public var wasAutoTracked: Bool = false
    public var notes: String = ""
    public var createdAt: Date = Date()
    /// Set when logged the same day as the drive, which is what "contemporaneous" means.
    public var loggedSameDay: Bool = true

    public var property: Property?

    public init(
        date: Date = Date(),
        purpose: TripPurpose = .guestTurnover,
        miles: Double = 0,
        property: Property? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.purposeRaw = purpose.rawValue
        self.miles = miles
        self.property = property
        self.createdAt = Date()
    }

    public var purpose: TripPurpose {
        get { TripPurpose(rawValue: purposeRaw) ?? .other }
        set { purposeRaw = newValue.rawValue }
    }

    public var method: MileageMethod {
        get { MileageMethod(rawValue: methodRaw) ?? .standardRate }
        set { methodRaw = newValue.rawValue }
    }

    /// One-way distance doubled when the user marks a round trip.
    public var effectiveMiles: Double {
        let base = miles > 0 ? miles : max(0, odometerEnd - odometerStart)
        return isRoundTrip ? base * 2 : base
    }

    public var routeLabel: String {
        let from = fromLabel.isEmpty ? "Start" : fromLabel
        let to = toLabel.isEmpty ? "Destination" : toLabel
        return isRoundTrip ? "\(from) ⇄ \(to)" : "\(from) → \(to)"
    }

    public func rate(using rates: MileageRateTable) -> Double {
        rateOverride > 0 ? rateOverride : rates.rate(on: date)
    }

    public func deduction(using rates: MileageRateTable) -> Decimal {
        guard purpose.isCurrentlyDeductible, method == .standardRate else { return tollsAndParking }
        let mileagePortion = Decimal.fromDouble(effectiveMiles * rate(using: rates))
        return (mileagePortion + tollsAndParking).rounded(2)
    }

    /// An IRS-compliant log needs the date, the mileage, the destination and a
    /// business purpose. A linked property serves as the purpose when the note
    /// is blank.
    public var isAuditComplete: Bool {
        guard effectiveMiles > 0, !toLabel.isEmpty else { return false }
        return !notes.isEmpty || property != nil
    }

    public var missingAuditFields: [String] {
        var missing: [String] = []
        if effectiveMiles <= 0 { missing.append("distance") }
        if toLabel.isEmpty { missing.append("destination") }
        if notes.isEmpty && property == nil { missing.append("business purpose") }
        return missing
    }
}
