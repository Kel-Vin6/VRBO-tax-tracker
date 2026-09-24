//
//  SupportingRecords.swift
//  VRBO tax tracker
//
//  Smaller records that round out the return: estimated payments, stored
//  paperwork, recurring bills and the platform forms you reconcile against.
//

import Foundation
import SwiftData

// MARK: - Estimated tax payments

public enum TaxJurisdiction: String, Codable, CaseIterable, Identifiable, Sendable {
    case federal
    case state
    case local

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .federal: "Federal"
        case .state: "State"
        case .local: "Local"
        }
    }
}

@Model
public final class EstimatedTaxPayment {

    public var id: UUID = UUID()
    public var taxYear: Int = DateMath.currentYear
    public var quarter: Int = 1
    public var jurisdictionRaw: String = TaxJurisdiction.federal.rawValue
    public var stateCode: String = ""
    public var amount: Decimal = 0
    public var datePaid: Date = Date()
    public var confirmationNumber: String = ""
    public var notes: String = ""
    public var createdAt: Date = Date()

    public init(
        taxYear: Int = DateMath.currentYear,
        quarter: Int = 1,
        jurisdiction: TaxJurisdiction = .federal,
        amount: Decimal = 0,
        datePaid: Date = Date()
    ) {
        self.id = UUID()
        self.taxYear = taxYear
        self.quarter = quarter
        self.jurisdictionRaw = jurisdiction.rawValue
        self.amount = amount
        self.datePaid = datePaid
        self.createdAt = Date()
    }

    public var jurisdiction: TaxJurisdiction {
        get { TaxJurisdiction(rawValue: jurisdictionRaw) ?? .federal }
        set { jurisdictionRaw = newValue.rawValue }
    }

    public var quarterLabel: String { "Q\(quarter) \(taxYear)" }
}

// MARK: - Stored documents

public enum DocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case rentalPermit
    case insurancePolicy
    case closingStatement
    case form1099K
    case form1098
    case propertyTaxBill
    case contractorInvoice
    case hoaDocument
    case leaseAgreement
    case priorYearReturn
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rentalPermit: "Short-term rental permit"
        case .insurancePolicy: "Insurance policy"
        case .closingStatement: "Closing statement"
        case .form1099K: "Form 1099-K"
        case .form1098: "Form 1098 (mortgage interest)"
        case .propertyTaxBill: "Property tax bill"
        case .contractorInvoice: "Contractor invoice"
        case .hoaDocument: "HOA document"
        case .leaseAgreement: "Lease or rental agreement"
        case .priorYearReturn: "Prior year tax return"
        case .other: "Other document"
        }
    }

    public var symbol: String {
        switch self {
        case .rentalPermit: "checkmark.seal"
        case .insurancePolicy: "shield"
        case .closingStatement: "doc.text"
        case .form1099K, .form1098, .priorYearReturn: "doc.richtext"
        case .propertyTaxBill: "building.columns"
        case .contractorInvoice: "hammer"
        case .hoaDocument: "house.lodge"
        case .leaseAgreement: "signature"
        case .other: "doc"
        }
    }

    /// Documents worth nagging the user about before they lapse.
    public var tracksExpiration: Bool {
        switch self {
        case .rentalPermit, .insurancePolicy, .leaseAgreement: true
        default: false
        }
    }
}

@Model
public final class StoredDocument {

    public var id: UUID = UUID()
    public var title: String = ""
    public var kindRaw: String = DocumentKind.other.rawValue
    @Attribute(.externalStorage) public var data: Data?
    public var fileName: String = ""
    public var contentType: String = ""
    public var taxYear: Int = DateMath.currentYear
    public var issueDate: Date?
    public var expirationDate: Date?
    public var recognizedText: String = ""
    public var notes: String = ""
    public var createdAt: Date = Date()

    public var property: Property?

    public init(
        title: String = "",
        kind: DocumentKind = .other,
        data: Data? = nil,
        property: Property? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.data = data
        self.property = property
        self.createdAt = Date()
    }

    public var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    public var displayTitle: String {
        title.isEmpty ? kind.title : title
    }

    public var daysUntilExpiration: Int? {
        guard let expirationDate else { return nil }
        return DateMath.calendar.dateComponents(
            [.day],
            from: DateMath.startOfDay(Date()),
            to: DateMath.startOfDay(expirationDate)
        ).day
    }

    public var isExpired: Bool {
        guard let days = daysUntilExpiration else { return false }
        return days < 0
    }
}

// MARK: - Recurring expenses

public enum RecurrenceCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case monthly
    case quarterly
    case semiAnnual
    case annual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .semiAnnual: "Twice a year"
        case .annual: "Yearly"
        }
    }

    public var monthStep: Int {
        switch self {
        case .monthly: 1
        case .quarterly: 3
        case .semiAnnual: 6
        case .annual: 12
        }
    }

    public var occurrencesPerYear: Int { 12 / monthStep }
}

/// A bill that repeats. The app posts each occurrence as a real expense when
/// it comes due, so nothing is silently assumed — the user confirms or edits it.
@Model
public final class RecurringExpenseRule {

    public var id: UUID = UUID()
    public var vendor: String = ""
    public var amount: Decimal = 0
    public var categoryRaw: String = ExpenseCategory.internet.rawValue
    public var cadenceRaw: String = RecurrenceCadence.monthly.rawValue
    public var businessUsePercent: Double = 100
    public var startDate: Date = Date()
    public var endDate: Date?
    public var nextDueDate: Date = Date()
    public var isEnabled: Bool = true
    public var autoPost: Bool = false
    public var allocationRaw: String = ExpenseAllocation.singleProperty.rawValue
    public var notes: String = ""
    public var createdAt: Date = Date()

    public var property: Property?

    public init(
        vendor: String = "",
        amount: Decimal = 0,
        category: ExpenseCategory = .internet,
        cadence: RecurrenceCadence = .monthly,
        startDate: Date = Date(),
        property: Property? = nil
    ) {
        self.id = UUID()
        self.vendor = vendor
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.cadenceRaw = cadence.rawValue
        self.startDate = startDate
        self.nextDueDate = startDate
        self.property = property
        self.createdAt = Date()
    }

    public var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .otherExpense }
        set { categoryRaw = newValue.rawValue }
    }

    public var cadence: RecurrenceCadence {
        get { RecurrenceCadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    public var allocation: ExpenseAllocation {
        get { ExpenseAllocation(rawValue: allocationRaw) ?? .singleProperty }
        set { allocationRaw = newValue.rawValue }
    }

    public var annualizedAmount: Decimal {
        amount * Decimal(cadence.occurrencesPerYear)
    }

    public var isDue: Bool {
        guard isEnabled else { return false }
        if let endDate, DateMath.startOfDay(endDate) < DateMath.startOfDay(Date()) { return false }
        return DateMath.startOfDay(nextDueDate) <= DateMath.startOfDay(Date())
    }

    public func advance() {
        nextDueDate = DateMath.adding(months: cadence.monthStep, to: nextDueDate)
    }

    /// Builds the expense for the current due date without saving it.
    public func makeExpense(on date: Date) -> Expense {
        let expense = Expense(
            date: date,
            vendor: vendor,
            amount: amount,
            category: category,
            property: property
        )
        expense.businessUsePercent = businessUsePercent
        expense.allocationRaw = allocationRaw
        expense.notes = notes
        expense.source = .recurringRule
        expense.recurringRuleID = id
        return expense
    }
}

// MARK: - Platform tax forms

/// The 1099-K a platform files with the IRS. Reconciling against it is the
/// fastest way to find income you forgot to record — or fees you forgot to deduct.
@Model
public final class PlatformTaxForm {

    public var id: UUID = UUID()
    public var taxYear: Int = DateMath.currentYear
    public var platformRaw: String = RentalPlatform.airbnb.rawValue
    /// Box 1a gross amount of payment transactions.
    public var grossAmountReported: Decimal = 0
    /// Some platforms report gross including the lodging tax they collected.
    public var includesLodgingTax: Bool = true
    /// Some platforms report gross before deducting their host service fee.
    public var includesPlatformFees: Bool = true
    public var payerName: String = ""
    public var payerTIN: String = ""
    public var notes: String = ""
    public var createdAt: Date = Date()

    public init(
        taxYear: Int = DateMath.currentYear,
        platform: RentalPlatform = .airbnb,
        grossAmountReported: Decimal = 0
    ) {
        self.id = UUID()
        self.taxYear = taxYear
        self.platformRaw = platform.rawValue
        self.grossAmountReported = grossAmountReported
        self.createdAt = Date()
    }

    public var platform: RentalPlatform {
        get { RentalPlatform(rawValue: platformRaw) ?? .other }
        set { platformRaw = newValue.rawValue }
    }
}
