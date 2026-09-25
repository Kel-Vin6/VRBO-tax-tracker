//
//  TaxEnums.swift
//  VRBO tax tracker
//
//  The vocabulary of the app. Every expense a host records ultimately has to
//  land on a numbered line of IRS Schedule E (Form 1040), Part I — so the
//  category list is built backwards from that form rather than invented.
//

import Foundation
import SwiftUI

// MARK: - Schedule E

/// Line numbers on Schedule E (Form 1040), Part I.
public enum ScheduleELine: Int, Codable, CaseIterable, Identifiable, Sendable {
    case advertising = 5
    case autoAndTravel = 6
    case cleaningAndMaintenance = 7
    case commissions = 8
    case insurance = 9
    case legalAndProfessional = 10
    case managementFees = 11
    case mortgageInterest = 12
    case otherInterest = 13
    case repairs = 14
    case supplies = 15
    case taxes = 16
    case utilities = 17
    case depreciation = 18
    case other = 19

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .advertising: "Advertising"
        case .autoAndTravel: "Auto and travel"
        case .cleaningAndMaintenance: "Cleaning and maintenance"
        case .commissions: "Commissions"
        case .insurance: "Insurance"
        case .legalAndProfessional: "Legal and other professional fees"
        case .managementFees: "Management fees"
        case .mortgageInterest: "Mortgage interest paid to banks, etc."
        case .otherInterest: "Other interest"
        case .repairs: "Repairs"
        case .supplies: "Supplies"
        case .taxes: "Taxes"
        case .utilities: "Utilities"
        case .depreciation: "Depreciation expense or depletion"
        case .other: "Other"
        }
    }

    public var label: String { "Line \(rawValue) — \(title)" }
}

// MARK: - Expense categories

/// Host-facing categories. Each one knows the Schedule E line it rolls up to,
/// so the tax form is generated rather than hand-maintained.
public enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {

    // Line 5
    case advertising
    case listingPhotography
    case websiteAndDomain

    // Line 6
    case autoMileage
    case autoActualExpenses
    case travelAirfare
    case travelLodging
    case travelMeals

    // Line 7
    case cleaningService
    case laundry
    case landscaping
    case poolAndHotTubService
    case pestControl
    case snowRemoval
    case trashService

    // Line 8
    case platformHostFee
    case paymentProcessingFee
    case bookingCommission

    // Line 9
    case insuranceProperty
    case insuranceLiability
    case insuranceFlood
    case insuranceUmbrella

    // Line 10
    case legalFees
    case accountingAndTaxPrep
    case bookkeepingSoftware
    case consultingFees

    // Line 11
    case propertyManagementFee
    case coHostFee

    // Line 12
    case mortgageInterest

    // Line 13
    case otherLoanInterest
    case creditCardInterest

    // Line 14
    case repairsGeneral
    case applianceRepair
    case hvacRepair
    case plumbingRepair
    case electricalRepair

    // Line 15
    case suppliesGuest
    case suppliesCleaning
    case linensAndTowels
    case kitchenSupplies
    case toiletriesAndConsumables
    case smallFurnishings

    // Line 16
    case propertyTax
    case lodgingOccupancyTax
    case businessLicenseAndPermits

    // Line 17
    case electricity
    case gas
    case waterAndSewer
    case internet
    case streamingAndCable
    case phone

    // Line 19
    case hoaDues
    case securityMonitoring
    case smartLockAndTech
    case bankFees
    case education
    case duesAndSubscriptions
    case guestRefundOrGoodwill
    case otherExpense

    public var id: String { rawValue }

    public var scheduleELine: ScheduleELine {
        switch self {
        case .advertising, .listingPhotography, .websiteAndDomain:
            return .advertising
        case .autoMileage, .autoActualExpenses, .travelAirfare, .travelLodging, .travelMeals:
            return .autoAndTravel
        case .cleaningService, .laundry, .landscaping, .poolAndHotTubService,
             .pestControl, .snowRemoval, .trashService:
            return .cleaningAndMaintenance
        case .platformHostFee, .paymentProcessingFee, .bookingCommission:
            return .commissions
        case .insuranceProperty, .insuranceLiability, .insuranceFlood, .insuranceUmbrella:
            return .insurance
        case .legalFees, .accountingAndTaxPrep, .bookkeepingSoftware, .consultingFees:
            return .legalAndProfessional
        case .propertyManagementFee, .coHostFee:
            return .managementFees
        case .mortgageInterest:
            return .mortgageInterest
        case .otherLoanInterest, .creditCardInterest:
            return .otherInterest
        case .repairsGeneral, .applianceRepair, .hvacRepair, .plumbingRepair, .electricalRepair:
            return .repairs
        case .suppliesGuest, .suppliesCleaning, .linensAndTowels, .kitchenSupplies,
             .toiletriesAndConsumables, .smallFurnishings:
            return .supplies
        case .propertyTax, .lodgingOccupancyTax, .businessLicenseAndPermits:
            return .taxes
        case .electricity, .gas, .waterAndSewer, .internet, .streamingAndCable, .phone:
            return .utilities
        case .hoaDues, .securityMonitoring, .smartLockAndTech, .bankFees,
             .education, .duesAndSubscriptions, .guestRefundOrGoodwill, .otherExpense:
            return .other
        }
    }

    public var title: String {
        switch self {
        case .advertising: "Advertising & marketing"
        case .listingPhotography: "Listing photography"
        case .websiteAndDomain: "Website & domain"
        case .autoMileage: "Vehicle mileage"
        case .autoActualExpenses: "Vehicle actual expenses"
        case .travelAirfare: "Travel — airfare"
        case .travelLodging: "Travel — lodging"
        case .travelMeals: "Travel — meals"
        case .cleaningService: "Cleaning service"
        case .laundry: "Laundry"
        case .landscaping: "Landscaping & yard"
        case .poolAndHotTubService: "Pool & hot tub service"
        case .pestControl: "Pest control"
        case .snowRemoval: "Snow removal"
        case .trashService: "Trash & recycling"
        case .platformHostFee: "Platform host service fee"
        case .paymentProcessingFee: "Payment processing fee"
        case .bookingCommission: "Booking commission"
        case .insuranceProperty: "Property insurance"
        case .insuranceLiability: "Liability insurance"
        case .insuranceFlood: "Flood insurance"
        case .insuranceUmbrella: "Umbrella policy"
        case .legalFees: "Legal fees"
        case .accountingAndTaxPrep: "Accounting & tax prep"
        case .bookkeepingSoftware: "Bookkeeping software"
        case .consultingFees: "Consulting fees"
        case .propertyManagementFee: "Property management fee"
        case .coHostFee: "Co-host fee"
        case .mortgageInterest: "Mortgage interest"
        case .otherLoanInterest: "Other loan interest"
        case .creditCardInterest: "Business credit card interest"
        case .repairsGeneral: "Repairs — general"
        case .applianceRepair: "Appliance repair"
        case .hvacRepair: "HVAC repair"
        case .plumbingRepair: "Plumbing repair"
        case .electricalRepair: "Electrical repair"
        case .suppliesGuest: "Guest supplies"
        case .suppliesCleaning: "Cleaning supplies"
        case .linensAndTowels: "Linens & towels"
        case .kitchenSupplies: "Kitchen supplies"
        case .toiletriesAndConsumables: "Toiletries & consumables"
        case .smallFurnishings: "Small furnishings"
        case .propertyTax: "Property tax"
        case .lodgingOccupancyTax: "Lodging / occupancy tax"
        case .businessLicenseAndPermits: "Licenses & permits"
        case .electricity: "Electricity"
        case .gas: "Gas"
        case .waterAndSewer: "Water & sewer"
        case .internet: "Internet"
        case .streamingAndCable: "Streaming & cable"
        case .phone: "Phone"
        case .hoaDues: "HOA dues"
        case .securityMonitoring: "Security monitoring"
        case .smartLockAndTech: "Smart locks & tech"
        case .bankFees: "Bank fees"
        case .education: "Education & training"
        case .duesAndSubscriptions: "Dues & subscriptions"
        case .guestRefundOrGoodwill: "Guest refund / goodwill"
        case .otherExpense: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .advertising, .listingPhotography, .websiteAndDomain: "megaphone"
        case .autoMileage, .autoActualExpenses: "car"
        case .travelAirfare: "airplane"
        case .travelLodging: "bed.double"
        case .travelMeals: "fork.knife"
        case .cleaningService, .suppliesCleaning: "sparkles"
        case .laundry, .linensAndTowels: "washer"
        case .landscaping: "leaf"
        case .poolAndHotTubService: "drop.circle"
        case .pestControl: "ant"
        case .snowRemoval: "snowflake"
        case .trashService: "trash"
        case .platformHostFee, .paymentProcessingFee, .bookingCommission: "percent"
        case .insuranceProperty, .insuranceLiability, .insuranceFlood, .insuranceUmbrella: "shield"
        case .legalFees: "building.columns"
        case .accountingAndTaxPrep, .bookkeepingSoftware: "doc.text.magnifyingglass"
        case .consultingFees: "person.2"
        case .propertyManagementFee, .coHostFee: "key"
        case .mortgageInterest, .otherLoanInterest, .creditCardInterest: "banknote"
        case .repairsGeneral: "wrench.and.screwdriver"
        case .applianceRepair: "dishwasher"
        case .hvacRepair: "fan"
        case .plumbingRepair: "pipe.and.drop"
        case .electricalRepair: "bolt"
        case .suppliesGuest, .toiletriesAndConsumables: "shippingbox"
        case .kitchenSupplies: "cooktop"
        case .smallFurnishings: "sofa"
        case .propertyTax, .lodgingOccupancyTax: "building.2"
        case .businessLicenseAndPermits: "checkmark.seal"
        case .electricity: "bolt.fill"
        case .gas: "flame"
        case .waterAndSewer: "drop"
        case .internet: "wifi"
        case .streamingAndCable: "tv"
        case .phone: "phone"
        case .hoaDues: "house.lodge"
        case .securityMonitoring: "video"
        case .smartLockAndTech: "lock.shield"
        case .bankFees: "creditcard"
        case .education: "graduationcap"
        case .duesAndSubscriptions: "repeat"
        case .guestRefundOrGoodwill: "arrow.uturn.backward"
        case .otherExpense: "ellipsis.circle"
        }
    }

    /// Categories that usually signal a capital improvement rather than a
    /// current-year deduction. Drives the repair-vs-improvement prompt.
    public var invitesImprovementReview: Bool {
        switch self {
        case .repairsGeneral, .applianceRepair, .hvacRepair, .plumbingRepair,
             .electricalRepair, .smallFurnishings, .smartLockAndTech:
            return true
        default:
            return false
        }
    }

    /// Meals are 50% limited for most taxpayers.
    public var statutoryDeductiblePercent: Double {
        self == .travelMeals ? 50 : 100
    }

    /// Categories bundled under the Schedule E line they report on, which is
    /// how the category picker is organised.
    public struct Group: Identifiable, Hashable, Sendable {
        public var line: ScheduleELine
        public var categories: [ExpenseCategory]
        public var id: Int { line.rawValue }
    }

    public static var grouped: [Group] {
        ScheduleELine.allCases.compactMap { line in
            let matches = ExpenseCategory.allCases.filter { $0.scheduleELine == line }
            return matches.isEmpty ? nil : Group(line: line, categories: matches)
        }
    }
}

// MARK: - Platforms

public enum RentalPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case airbnb
    case vrbo
    case bookingCom
    case furnishedFinder
    case direct
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .airbnb: "Airbnb"
        case .vrbo: "Vrbo"
        case .bookingCom: "Booking.com"
        case .furnishedFinder: "Furnished Finder"
        case .direct: "Direct booking"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .airbnb: "a.circle"
        case .vrbo: "v.circle"
        case .bookingCom: "b.circle"
        case .furnishedFinder: "f.circle"
        case .direct: "person.crop.circle.badge.checkmark"
        case .other: "questionmark.circle"
        }
    }

    public var tintHex: String {
        switch self {
        case .airbnb: "C05B4D"
        case .vrbo: "2E7D8F"
        case .bookingCom: "4A6FA5"
        case .furnishedFinder: "7A8B3F"
        case .direct: "3A7D5D"
        case .other: "5C6B8A"
        }
    }

    /// Platforms that file a Form 1099-K for US hosts.
    public var issues1099K: Bool {
        switch self {
        case .airbnb, .vrbo, .bookingCom: true
        case .furnishedFinder, .direct, .other: false
        }
    }
}

// MARK: - Property classification

/// Matches the property type codes printed on Schedule E line 1b.
public enum PropertyKind: Int, Codable, CaseIterable, Identifiable, Sendable {
    case singleFamily = 1
    case multiFamily = 2
    case vacationOrShortTerm = 3
    case commercial = 4
    case land = 5
    case royalties = 6
    case selfRental = 7
    case other = 8

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .singleFamily: "Single family residence"
        case .multiFamily: "Multi-family residence"
        case .vacationOrShortTerm: "Vacation / short-term rental"
        case .commercial: "Commercial"
        case .land: "Land"
        case .royalties: "Royalties"
        case .selfRental: "Self-rental"
        case .other: "Other"
        }
    }

    public var scheduleECode: String { "\(rawValue)" }

    /// Residential rental property depreciates over 27.5 years; commercial
    /// nonresidential real property over 39.
    public var realPropertyRecoveryYears: Double {
        switch self {
        case .commercial, .selfRental: 39
        case .land: 0
        default: 27.5
        }
    }
}

// MARK: - Personal use

/// IRC §280A day classification. Getting this wrong is the single most common
/// way a short-term-rental return falls apart in an audit.
public enum PersonalUseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case owner
    case familyMember
    case friendBelowMarket
    case donatedCharityUse
    case tradeOrSwap
    case repairAndMaintenanceDay
    case vacantNotAvailable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .owner: "Owner stay"
        case .familyMember: "Family member stay"
        case .friendBelowMarket: "Friend below market rate"
        case .donatedCharityUse: "Donated / charity use"
        case .tradeOrSwap: "Home swap or trade"
        case .repairAndMaintenanceDay: "Repair & maintenance day"
        case .vacantNotAvailable: "Held off market"
        }
    }

    public var detail: String {
        switch self {
        case .owner:
            "Any day you or a co-owner used the home for personal purposes counts."
        case .familyMember:
            "Use by a sibling, spouse, ancestor or descendant counts as your personal use — even if they paid full market rent."
        case .friendBelowMarket:
            "Renting to anyone at less than a fair rental price makes the day a personal-use day."
        case .donatedCharityUse:
            "A stay donated to a charity auction is personal use to you."
        case .tradeOrSwap:
            "Swapping with another owner counts as personal use of your own property."
        case .repairAndMaintenanceDay:
            "A day spent substantially full time on repairs and maintenance is NOT a personal-use day, even if family are present."
        case .vacantNotAvailable:
            "Vacant days are neither rental days nor personal-use days, but they do reduce your occupancy rate."
        }
    }

    /// Whether the day is counted in the §280A personal-use numerator.
    public var countsAsPersonalUse: Bool {
        switch self {
        case .owner, .familyMember, .friendBelowMarket, .donatedCharityUse, .tradeOrSwap:
            true
        case .repairAndMaintenanceDay, .vacantNotAvailable:
            false
        }
    }

    public var symbol: String {
        switch self {
        case .owner: "person.fill"
        case .familyMember: "figure.2.and.child.holdinghands"
        case .friendBelowMarket: "hand.wave"
        case .donatedCharityUse: "heart"
        case .tradeOrSwap: "arrow.left.arrow.right"
        case .repairAndMaintenanceDay: "hammer"
        case .vacantNotAvailable: "moon.zzz"
        }
    }
}

// MARK: - Participation

/// Activity types for the §469 material-participation hour log.
public enum ParticipationActivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case guestCommunication
    case cleaningAndTurnover
    case maintenanceAndRepairs
    case listingManagement
    case suppliesAndShopping
    case bookkeeping
    case travelToProperty
    case propertyImprovements
    case researchAndEducation
    case financingAndInvesting

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .guestCommunication: "Guest communication"
        case .cleaningAndTurnover: "Cleaning & turnover"
        case .maintenanceAndRepairs: "Maintenance & repairs"
        case .listingManagement: "Listing & pricing management"
        case .suppliesAndShopping: "Supplies & shopping"
        case .bookkeeping: "Bookkeeping & admin"
        case .travelToProperty: "Travel to property"
        case .propertyImprovements: "Improvements & projects"
        case .researchAndEducation: "Research & education"
        case .financingAndInvesting: "Financing & investing"
        }
    }

    public var symbol: String {
        switch self {
        case .guestCommunication: "bubble.left.and.bubble.right"
        case .cleaningAndTurnover: "sparkles"
        case .maintenanceAndRepairs: "wrench.and.screwdriver"
        case .listingManagement: "chart.line.uptrend.xyaxis"
        case .suppliesAndShopping: "cart"
        case .bookkeeping: "list.clipboard"
        case .travelToProperty: "car"
        case .propertyImprovements: "hammer"
        case .researchAndEducation: "books.vertical"
        case .financingAndInvesting: "dollarsign.bank.building"
        }
    }

    /// Investor-type work (studying financials, arranging financing) does not
    /// count toward material participation unless you manage day to day.
    public var isInvestorActivity: Bool {
        switch self {
        case .researchAndEducation, .financingAndInvesting: true
        default: false
        }
    }

    /// Whether the hours qualify as "rental services" for the §199A safe harbor.
    public var countsForQBISafeHarbor: Bool {
        switch self {
        case .financingAndInvesting, .researchAndEducation, .travelToProperty: false
        default: true
        }
    }
}

// MARK: - Misc

public enum PaymentMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case businessCreditCard
    case personalCreditCard
    case businessDebit
    case bankTransfer
    case cash
    case check
    case platformWithheld
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .businessCreditCard: "Business credit card"
        case .personalCreditCard: "Personal credit card"
        case .businessDebit: "Business debit"
        case .bankTransfer: "Bank transfer"
        case .cash: "Cash"
        case .check: "Check"
        case .platformWithheld: "Withheld by platform"
        case .other: "Other"
        }
    }

    /// Cash and personal-card spending is the weakest documentation trail.
    var auditRisk: Int {
        switch self {
        case .cash: 2
        case .personalCreditCard: 1
        default: 0
        }
    }
}

public enum EntrySource: String, Codable, CaseIterable, Sendable {
    case manual
    case receiptScan
    case csvImport
    case recurringRule
    case mileageEngine
    case loanAmortization

    public var title: String {
        switch self {
        case .manual: "Entered manually"
        case .receiptScan: "Scanned receipt"
        case .csvImport: "Imported from CSV"
        case .recurringRule: "Recurring rule"
        case .mileageEngine: "Mileage log"
        case .loanAmortization: "Loan schedule"
        }
    }
}

public enum FilingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case marriedFilingJointly
    case marriedFilingSeparately
    case headOfHousehold

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .single: "Single"
        case .marriedFilingJointly: "Married filing jointly"
        case .marriedFilingSeparately: "Married filing separately"
        case .headOfHousehold: "Head of household"
        }
    }

    public var shortTitle: String {
        switch self {
        case .single: "Single"
        case .marriedFilingJointly: "MFJ"
        case .marriedFilingSeparately: "MFS"
        case .headOfHousehold: "HOH"
        }
    }
}
