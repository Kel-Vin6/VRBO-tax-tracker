//
//  DepreciableAsset.swift
//  VRBO tax tracker
//

import Foundation
import SwiftData

/// MACRS asset classes a short-term-rental host actually owns.
public enum AssetClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case residentialBuilding
    case nonresidentialBuilding
    case landImprovement
    case applianceAndFurniture
    case carpetAndFlooring
    case computerAndTech
    case vehicle
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .residentialBuilding: "Residential building"
        case .nonresidentialBuilding: "Nonresidential building"
        case .landImprovement: "Land improvement"
        case .applianceAndFurniture: "Appliances & furniture"
        case .carpetAndFlooring: "Carpet & removable flooring"
        case .computerAndTech: "Computers & technology"
        case .vehicle: "Vehicle"
        case .other: "Other property"
        }
    }

    public var detail: String {
        switch self {
        case .residentialBuilding: "The structure itself. 27.5 years, straight line, mid-month."
        case .nonresidentialBuilding: "Commercial structure. 39 years, straight line, mid-month."
        case .landImprovement: "Driveways, fencing, landscaping, pools. 15 years, 150% declining balance."
        case .applianceAndFurniture: "Beds, sofas, refrigerators, washers. 7 years, 200% declining balance."
        case .carpetAndFlooring: "Carpet and other removable floor coverings. 5 years, 200% declining balance."
        case .computerAndTech: "Smart locks, routers, cameras, laptops. 5 years, 200% declining balance."
        case .vehicle: "Business vehicle under the actual-expense method. 5 years."
        case .other: "Anything else, with a recovery period you set."
        }
    }

    public var recoveryYears: Double {
        switch self {
        case .residentialBuilding: 27.5
        case .nonresidentialBuilding: 39
        case .landImprovement: 15
        case .applianceAndFurniture: 7
        case .carpetAndFlooring, .computerAndTech, .vehicle: 5
        case .other: 7
        }
    }

    public var isRealProperty: Bool {
        self == .residentialBuilding || self == .nonresidentialBuilding
    }

    /// Real property uses mid-month straight line; personal property uses a
    /// declining-balance method with the half-year convention.
    public var decliningBalanceFactor: Double {
        switch self {
        case .residentialBuilding, .nonresidentialBuilding: 1.0
        case .landImprovement: 1.5
        default: 2.0
        }
    }

    /// Only personal property with a recovery period of 20 years or less is
    /// eligible for bonus depreciation.
    public var isBonusEligible: Bool { !isRealProperty }

    /// Section 179 is unavailable for property used in a passive rental
    /// activity that does not rise to a trade or business.
    public var isSection179Candidate: Bool { !isRealProperty }

    public var symbol: String {
        switch self {
        case .residentialBuilding: "house"
        case .nonresidentialBuilding: "building.2"
        case .landImprovement: "tree"
        case .applianceAndFurniture: "sofa"
        case .carpetAndFlooring: "square.grid.3x3"
        case .computerAndTech: "laptopcomputer"
        case .vehicle: "car"
        case .other: "shippingbox"
        }
    }
}

@Model
public final class DepreciableAsset {

    public var id: UUID = UUID()
    public var name: String = ""
    public var assetClassRaw: String = AssetClass.applianceAndFurniture.rawValue
    public var cost: Decimal = 0
    public var placedInService: Date = Date()
    /// Overrides the class default when the user has a specific recovery period.
    public var recoveryYearsOverride: Double = 0
    /// 0–100. Applied before any depreciation is computed.
    public var businessUsePercent: Double = 100
    /// Bonus depreciation claimed in year one, as a percentage of basis.
    public var bonusPercent: Double = 0
    /// Section 179 expensing elected in year one, in dollars.
    public var section179Amount: Decimal = 0

    /// True when the asset is the building created from the property's basis,
    /// so the app never double-counts it against a manually added asset.
    public var isDerivedFromPropertyBasis: Bool = false

    public var disposedDate: Date?
    public var dispositionProceeds: Decimal = 0
    public var notes: String = ""
    public var createdAt: Date = Date()

    public var property: Property?

    public init(
        name: String = "",
        assetClass: AssetClass = .applianceAndFurniture,
        cost: Decimal = 0,
        placedInService: Date = Date(),
        property: Property? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.assetClassRaw = assetClass.rawValue
        self.cost = cost
        self.placedInService = placedInService
        self.property = property
        self.createdAt = Date()
    }

    public var assetClass: AssetClass {
        get { AssetClass(rawValue: assetClassRaw) ?? .other }
        set { assetClassRaw = newValue.rawValue }
    }

    public var recoveryYears: Double {
        recoveryYearsOverride > 0 ? recoveryYearsOverride : assetClass.recoveryYears
    }

    /// Cost reduced for any personal use of the item.
    public var depreciableBasis: Decimal {
        cost.applying(percent: businessUsePercent.clampedPercent)
    }

    public var isDisposed: Bool { disposedDate != nil }

    public var displayName: String {
        name.isEmpty ? assetClass.title : name
    }

    public var effectiveBonusPercent: Double {
        assetClass.isBonusEligible ? bonusPercent.clampedPercent : 0
    }

    public var effectiveSection179: Decimal {
        guard assetClass.isSection179Candidate else { return 0 }
        return min(section179Amount, depreciableBasis)
    }
}
