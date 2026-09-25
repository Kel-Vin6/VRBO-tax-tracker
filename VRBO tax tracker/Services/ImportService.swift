//
//  ImportService.swift
//  VRBO tax tracker
//
//  Imports the CSV files hosts already have: Airbnb transaction history, Vrbo
//  payout reports, and plain bank or card statements. Column names differ
//  between platforms and change between exports, so the importer auto-detects
//  what it can and hands the rest to the user to map.
//

import Foundation

public enum ImportKind: String, CaseIterable, Identifiable, Sendable {
    case bookings
    case expenses

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bookings: "Bookings & payouts"
        case .expenses: "Expenses & statements"
        }
    }

    public var detail: String {
        switch self {
        case .bookings: "Airbnb transaction history, Vrbo payout reports, or any CSV with a check-in date and an amount."
        case .expenses: "A bank or card statement, or an export from your bookkeeping tool."
        }
    }

    public var symbol: String {
        switch self {
        case .bookings: "calendar.badge.plus"
        case .expenses: "creditcard"
        }
    }
}

/// A field the importer needs to fill from a CSV column.
public struct ImportField: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var isRequired: Bool
    public var candidates: [String]
    public var hint: String
}

public struct ColumnMapping: Hashable, Sendable {
    public var assignments: [String: Int] = [:]

    public func index(for field: String) -> Int? { assignments[field] }

    public func isComplete(for fields: [ImportField]) -> Bool {
        fields.filter(\.isRequired).allSatisfy { assignments[$0.id] != nil }
    }
}

public struct ImportPreviewRow: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var summary: String
    public var detail: String
    public var amount: Decimal
    public var date: Date?
    public var isValid: Bool
    public var problems: [String]
}

public struct ImportOutcome: Sendable {
    public var imported: Int
    public var skipped: Int
    public var duplicates: Int
    public var problems: [String]

    public var summary: String {
        var parts = ["\(imported) record\(imported == 1 ? "" : "s") imported"]
        if duplicates > 0 { parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s") skipped") }
        if skipped > 0 { parts.append("\(skipped) row\(skipped == 1 ? "" : "s") could not be read") }
        return parts.joined(separator: ", ") + "."
    }
}

public enum ImportService {

    // MARK: - Field definitions

    public static let bookingFields: [ImportField] = [
        ImportField(id: "checkIn", title: "Check-in date", isRequired: true,
                    candidates: ["check in", "checkin", "start date", "arrival", "arriving by date", "arrival date", "from"],
                    hint: "The first night of the stay."),
        ImportField(id: "checkOut", title: "Check-out date", isRequired: false,
                    candidates: ["check out", "checkout", "end date", "departure", "departure date", "to"],
                    hint: "Leave unmapped if the file only gives a nights count."),
        ImportField(id: "nights", title: "Nights", isRequired: false,
                    candidates: ["nights", "number of nights", "length of stay"],
                    hint: "Used to derive check-out when it is not in the file."),
        ImportField(id: "guest", title: "Guest name", isRequired: false,
                    candidates: ["guest", "guest name", "traveler", "traveller", "customer"],
                    hint: ""),
        ImportField(id: "confirmation", title: "Confirmation code", isRequired: false,
                    candidates: ["confirmation code", "confirmation", "reservation id", "booking id", "reference code"],
                    hint: "Used to spot rows you have already imported."),
        ImportField(id: "gross", title: "Gross earnings", isRequired: true,
                    candidates: ["gross earnings", "gross booking amount", "amount", "gross", "total", "rent"],
                    hint: "What the guest paid for the stay, before platform fees."),
        ImportField(id: "cleaning", title: "Cleaning fee", isRequired: false,
                    candidates: ["cleaning fee", "cleaning"],
                    hint: ""),
        ImportField(id: "serviceFee", title: "Host service fee", isRequired: false,
                    candidates: ["service fee", "host fee", "commission", "host service fee", "fast pay fee"],
                    hint: "The platform's cut. Deductible on Schedule E line 8."),
        ImportField(id: "taxes", title: "Occupancy taxes", isRequired: false,
                    candidates: ["occupancy taxes", "lodging tax", "taxes", "transient tax"],
                    hint: ""),
        ImportField(id: "payout", title: "Payout", isRequired: false,
                    candidates: ["paid out", "payout", "net", "net payout", "amount paid"],
                    hint: "What reached your bank. Used to check the other figures."),
        ImportField(id: "listing", title: "Listing name", isRequired: false,
                    candidates: ["listing", "property", "rental", "unit"],
                    hint: "Matched against your property names where possible.")
    ]

    public static let expenseFields: [ImportField] = [
        ImportField(id: "date", title: "Date", isRequired: true,
                    candidates: ["date", "transaction date", "posted date", "posting date"],
                    hint: ""),
        ImportField(id: "vendor", title: "Description", isRequired: true,
                    candidates: ["description", "vendor", "merchant", "payee", "name", "details"],
                    hint: "Used to guess the expense category."),
        ImportField(id: "amount", title: "Amount", isRequired: true,
                    candidates: ["amount", "debit", "withdrawal", "charge", "value"],
                    hint: "Negative or bracketed amounts are treated as spending."),
        ImportField(id: "category", title: "Category", isRequired: false,
                    candidates: ["category", "type", "classification"],
                    hint: "Matched against the app's categories where it can be.")
    ]

    public static func fields(for kind: ImportKind) -> [ImportField] {
        kind == .bookings ? bookingFields : expenseFields
    }

    // MARK: - Auto mapping

    public static func autoMap(table: CSVTable, kind: ImportKind) -> ColumnMapping {
        var mapping = ColumnMapping()
        for field in fields(for: kind) {
            if let index = table.columnIndex(matching: field.candidates + [field.title]) {
                mapping.assignments[field.id] = index
            }
        }
        return mapping
    }

    /// Recognises the shape of a known platform export, purely to tell the user
    /// what the app thinks it is looking at.
    public static func detectPlatform(table: CSVTable) -> RentalPlatform? {
        let joined = table.headers.map(CSVParser.normalize).joined(separator: "|")
        if joined.contains("grossearnings") || joined.contains("fastpayfee") { return .airbnb }
        if joined.contains("grossbookingamount") || joined.contains("reservationid") { return .vrbo }
        if joined.contains("bookingcom") { return .bookingCom }
        return nil
    }

    // MARK: - Booking rows

    public struct ParsedBooking: Sendable {
        public var checkIn: Date
        public var checkOut: Date
        public var guestName: String
        public var confirmationCode: String
        public var accommodationRevenue: Decimal
        public var cleaningFee: Decimal
        public var serviceFee: Decimal
        public var lodgingTax: Decimal
        public var payout: Decimal
        public var listingName: String
    }

    public static func parseBooking(
        row: [String],
        table: CSVTable,
        mapping: ColumnMapping
    ) -> (booking: ParsedBooking?, problems: [String]) {

        var problems: [String] = []

        guard let checkInRaw = mapping.index(for: "checkIn").map({ table.value(row, at: $0) }),
              let checkIn = CSVParser.date(checkInRaw) else {
            return (nil, ["Check-in date is missing or could not be read."])
        }

        var checkOut: Date?
        if let index = mapping.index(for: "checkOut") {
            checkOut = CSVParser.date(table.value(row, at: index))
        }
        if checkOut == nil, let index = mapping.index(for: "nights"),
           let nights = CSVParser.integer(table.value(row, at: index)), nights > 0 {
            checkOut = DateMath.adding(days: nights, to: checkIn)
        }
        if checkOut == nil {
            checkOut = DateMath.adding(days: 1, to: checkIn)
            problems.append("No check-out date or nights count — assumed a single night.")
        }

        let gross = mapping.index(for: "gross")
            .flatMap { CSVParser.decimal(table.value(row, at: $0)) } ?? 0
        let cleaning = mapping.index(for: "cleaning")
            .flatMap { CSVParser.decimal(table.value(row, at: $0)) } ?? 0
        let service = mapping.index(for: "serviceFee")
            .flatMap { CSVParser.decimal(table.value(row, at: $0)) } ?? 0
        let taxes = mapping.index(for: "taxes")
            .flatMap { CSVParser.decimal(table.value(row, at: $0)) } ?? 0
        let payout = mapping.index(for: "payout")
            .flatMap { CSVParser.decimal(table.value(row, at: $0)) } ?? 0

        if gross == 0 && payout == 0 {
            problems.append("No amount on this row.")
        }

        // Platform exports often bundle the cleaning fee inside gross earnings.
        let accommodation = gross > cleaning ? gross - cleaning : gross

        let parsed = ParsedBooking(
            checkIn: checkIn,
            checkOut: checkOut ?? DateMath.adding(days: 1, to: checkIn),
            guestName: mapping.index(for: "guest").map { table.value(row, at: $0) } ?? "",
            confirmationCode: mapping.index(for: "confirmation").map { table.value(row, at: $0) } ?? "",
            accommodationRevenue: max(0, accommodation),
            cleaningFee: max(0, cleaning),
            serviceFee: abs(service),
            lodgingTax: abs(taxes),
            payout: payout,
            listingName: mapping.index(for: "listing").map { table.value(row, at: $0) } ?? ""
        )
        return (parsed, problems)
    }

    // MARK: - Expense rows

    public struct ParsedExpense: Sendable {
        public var date: Date
        public var vendor: String
        public var amount: Decimal
        public var category: ExpenseCategory
        public var categoryWasGuessed: Bool
    }

    public static func parseExpense(
        row: [String],
        table: CSVTable,
        mapping: ColumnMapping
    ) -> (expense: ParsedExpense?, problems: [String]) {

        guard let dateRaw = mapping.index(for: "date").map({ table.value(row, at: $0) }),
              let date = CSVParser.date(dateRaw) else {
            return (nil, ["Date is missing or could not be read."])
        }
        guard let amountRaw = mapping.index(for: "amount").map({ table.value(row, at: $0) }),
              let rawAmount = CSVParser.decimal(amountRaw) else {
            return (nil, ["Amount is missing or could not be read."])
        }

        let vendor = mapping.index(for: "vendor").map { table.value(row, at: $0) } ?? ""
        // A statement writes spending as a negative; the app stores it positive.
        let amount = abs(rawAmount)

        var problems: [String] = []
        if rawAmount > 0 {
            problems.append("Positive amount — this may be a deposit rather than spending.")
        }

        let categoryText = mapping.index(for: "category").map { table.value(row, at: $0) } ?? ""
        let guess = CategoryGuesser.guess(vendor: vendor, hint: categoryText)

        return (
            ParsedExpense(
                date: date,
                vendor: vendor,
                amount: amount,
                category: guess ?? .otherExpense,
                categoryWasGuessed: guess != nil
            ),
            problems
        )
    }
}

// MARK: - Category guessing

/// Maps merchant names onto Schedule E categories. Deliberately conservative:
/// a wrong guess is worse than no guess, because a user who trusts the app
/// stops reading the category field.
public enum CategoryGuesser {

    private nonisolated static let rules: [(keywords: [String], category: ExpenseCategory)] = [
        (["airbnb service", "host service fee", "vrbo commission", "booking.com commission"], .platformHostFee),
        (["stripe", "square fee", "paypal fee", "processing fee"], .paymentProcessingFee),
        (["turno", "properly", "maid", "cleaning", "housekeep", "cleaner"], .cleaningService),
        (["laundry", "laundromat", "wash and fold"], .laundry),
        (["lawn", "landscap", "mowing", "tree service", "garden"], .landscaping),
        (["pool service", "hot tub", "spa chemical", "leslie"], .poolAndHotTubService),
        (["pest", "terminix", "orkin", "exterminator"], .pestControl),
        (["snow removal", "plowing"], .snowRemoval),
        (["waste management", "republic services", "trash", "recycling"], .trashService),
        (["state farm", "allstate", "geico", "progressive", "insurance", "proper insurance"], .insuranceProperty),
        (["flood insurance", "nfip"], .insuranceFlood),
        (["attorney", "law firm", "legal"], .legalFees),
        (["cpa", "accountant", "tax prep", "h&r block", "turbotax"], .accountingAndTaxPrep),
        (["quickbooks", "xero", "stessa", "wave accounting"], .bookkeepingSoftware),
        (["property management", "manager fee"], .propertyManagementFee),
        (["mortgage", "loan servicing", "rocket mortgage", "wells fargo home"], .mortgageInterest),
        (["home depot", "lowes", "ace hardware", "menards", "hardware"], .repairsGeneral),
        (["appliance repair", "sears repair"], .applianceRepair),
        (["hvac", "heating", "air conditioning", "furnace"], .hvacRepair),
        (["plumb", "roto-rooter", "drain"], .plumbingRepair),
        (["electric repair", "electrician"], .electricalRepair),
        (["costco", "sam's club", "amazon", "target", "walmart", "supplies"], .suppliesGuest),
        (["linen", "towel", "bedding", "sheets"], .linensAndTowels),
        (["county tax", "property tax", "tax collector", "treasurer"], .propertyTax),
        (["occupancy tax", "lodging tax", "transient tax", "tot payment"], .lodgingOccupancyTax),
        (["business license", "permit", "registration fee"], .businessLicenseAndPermits),
        (["electric", "power company", "duke energy", "pg&e", "con edison"], .electricity),
        (["gas company", "natural gas", "propane"], .gas),
        (["water", "sewer", "utilities district"], .waterAndSewer),
        (["comcast", "xfinity", "spectrum", "at&t internet", "starlink", "internet"], .internet),
        (["netflix", "hulu", "disney+", "cable", "roku"], .streamingAndCable),
        (["verizon", "t-mobile", "phone"], .phone),
        (["hoa", "homeowners association", "condo association"], .hoaDues),
        (["ring", "simplisafe", "adt", "security"], .securityMonitoring),
        (["schlage", "yale", "august lock", "smart lock", "nest", "ecobee"], .smartLockAndTech),
        (["bank fee", "wire fee", "monthly service charge"], .bankFees),
        (["course", "conference", "training", "seminar"], .education),
        (["pricelabs", "wheelhouse", "hospitable", "guesty", "ownerrez", "subscription"], .duesAndSubscriptions),
        (["refund", "goodwill", "guest compensation"], .guestRefundOrGoodwill),
        (["shell", "chevron", "exxon", "bp ", "fuel", "gas station"], .autoActualExpenses),
        (["delta air", "united air", "american air", "southwest", "airline"], .travelAirfare),
        (["marriott", "hilton", "hyatt", "motel"], .travelLodging)
    ]

    public nonisolated static func guess(vendor: String, hint: String = "") -> ExpenseCategory? {
        let haystack = "\(vendor) \(hint)".lowercased()
        guard !haystack.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        // An explicit category column that names one of ours wins outright.
        if !hint.isEmpty {
            let normalizedHint = CSVParser.normalize(hint)
            if let exact = ExpenseCategory.allCases.first(where: {
                CSVParser.normalize($0.title) == normalizedHint
            }) {
                return exact
            }
        }

        for rule in rules {
            for keyword in rule.keywords where haystack.contains(keyword) {
                return rule.category
            }
        }
        return nil
    }
}
