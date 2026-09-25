//
//  Expense.swift
//  VRBO tax tracker
//

import Foundation
import SwiftData

/// How an expense is spread across the portfolio.
public enum ExpenseAllocation: String, Codable, CaseIterable, Identifiable, Sendable {
    case singleProperty
    case splitByRevenue
    case splitEvenly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .singleProperty: "One property"
        case .splitByRevenue: "Split across portfolio by revenue"
        case .splitEvenly: "Split evenly across portfolio"
        }
    }

    public var detail: String {
        switch self {
        case .singleProperty: "Charged entirely to the property you pick."
        case .splitByRevenue: "Overhead like software or insurance, apportioned to each property's share of gross rents."
        case .splitEvenly: "Divided in equal parts between every active property."
        }
    }
}

@Model
public final class Expense {

    public var id: UUID = UUID()
    public var date: Date = Date()
    public var vendor: String = ""
    public var amount: Decimal = 0
    public var categoryRaw: String = ExpenseCategory.otherExpense.rawValue
    public var customCategoryName: String = ""
    public var paymentMethodRaw: String = PaymentMethod.businessCreditCard.rawValue
    public var allocationRaw: String = ExpenseAllocation.singleProperty.rawValue

    /// 0–100. A phone bill used 40% for the rental is entered at full cost with
    /// 40 here, which keeps the receipt total matching the statement.
    public var businessUsePercent: Double = 100

    /// Marked true, the cost is capitalised instead of deducted and the app
    /// offers to create a depreciable asset from it.
    public var isCapitalImprovement: Bool = false
    /// Set when the user elects the de minimis safe harbor for this item.
    public var deMinimisElected: Bool = false

    public var notes: String = ""
    public var isTaxDeductible: Bool = true
    public var isReconciled: Bool = false

    @Attribute(.externalStorage) public var receiptData: Data?
    public var receiptFileName: String = ""
    public var receiptContentType: String = ""
    /// Raw OCR text kept alongside the image so the receipt stays searchable.
    public var receiptRecognizedText: String = ""

    public var sourceRaw: String = EntrySource.manual.rawValue
    public var externalReference: String = ""
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var property: Property?
    /// Present when this expense created, or was created by, a capital asset.
    public var linkedAssetID: UUID?
    /// Present when generated from a recurring rule.
    public var recurringRuleID: UUID?

    public init(
        date: Date = Date(),
        vendor: String = "",
        amount: Decimal = 0,
        category: ExpenseCategory = .otherExpense,
        property: Property? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.vendor = vendor
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.property = property
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Derived

    public var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .otherExpense }
        set { categoryRaw = newValue.rawValue }
    }

    public var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .other }
        set { paymentMethodRaw = newValue.rawValue }
    }

    public var allocation: ExpenseAllocation {
        get { ExpenseAllocation(rawValue: allocationRaw) ?? .singleProperty }
        set { allocationRaw = newValue.rawValue }
    }

    public var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var scheduleELine: ScheduleELine { category.scheduleELine }

    public var displayCategory: String {
        customCategoryName.isEmpty ? category.title : customCategoryName
    }

    public var displayVendor: String {
        vendor.trimmingCharacters(in: .whitespaces).isEmpty ? displayCategory : vendor
    }

    public var hasReceipt: Bool { receiptData != nil }

    /// The portion that actually reaches Schedule E after the business-use
    /// split and any statutory limit such as the 50% meals haircut.
    public var deductibleAmount: Decimal {
        guard isTaxDeductible, !isCapitalImprovement else { return 0 }
        let businessPortion = amount.applying(percent: businessUsePercent.clampedPercent)
        return businessPortion.applying(percent: category.statutoryDeductiblePercent)
    }

    /// The amount excluded from the deduction, shown so the number is never a
    /// mystery to the user or their accountant.
    public var disallowedAmount: Decimal {
        max(0, amount - deductibleAmount)
    }

    public var isSplitAcrossPortfolio: Bool { allocation != .singleProperty }

    public var needsImprovementReview: Bool {
        !isCapitalImprovement
            && !deMinimisElected
            && category.invitesImprovementReview
            && amount >= 2_500
    }

    public func touch() { updatedAt = Date() }
}
