//
//  AppState.swift
//  VRBO tax tracker
//

import Foundation
import Observation
import SwiftData
import SwiftUI

public enum AppTab: String, Hashable, CaseIterable, Identifiable, Sendable {
    case dashboard
    case bookings
    case expenses
    case taxes
    case more

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .bookings: "Bookings"
        case .expenses: "Expenses"
        case .taxes: "Tax centre"
        case .more: "More"
        }
    }

    public var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .bookings: "calendar"
        case .expenses: "creditcard"
        case .taxes: "doc.text.magnifyingglass"
        case .more: "ellipsis.circle"
        }
    }
}

/// Sheets that can be raised from anywhere, including the quick-add menu.
public enum QuickAction: String, Identifiable, CaseIterable, Sendable {
    case booking
    case expense
    case scanReceipt
    case mileage
    case personalUse
    case participation
    case property

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .booking: "Booking"
        case .expense: "Expense"
        case .scanReceipt: "Scan a receipt"
        case .mileage: "Mileage"
        case .personalUse: "Personal use"
        case .participation: "Hours worked"
        case .property: "Property"
        }
    }

    public var symbol: String {
        switch self {
        case .booking: "calendar.badge.plus"
        case .expense: "creditcard"
        case .scanReceipt: "doc.viewfinder"
        case .mileage: "car"
        case .personalUse: "figure.and.child.holdinghands"
        case .participation: "clock"
        case .property: "house"
        }
    }
}

@Observable
public final class AppState {

    public var selectedTab: AppTab = .dashboard
    public var taxYear: Int
    public var quickAction: QuickAction?

    /// Set when the persistent store could not be opened as intended.
    public var storageWarning: String?
    public var transientMessage: String?

    public init(taxYear: Int = DateMath.currentYear) {
        self.taxYear = taxYear
    }

    public func show(_ message: String) {
        transientMessage = message
    }

    public func open(_ action: QuickAction) {
        quickAction = action
        Haptics.play(.selection)
    }
}

/// Builds the inputs the engines need out of what SwiftData hands the views.
public enum Workspace {

    public static func dataSet(
        year: Int,
        properties: [Property],
        expenses: [Expense],
        trips: [MileageTrip],
        settings: AppSettings
    ) -> TaxDataSet {
        TaxDataSet(
            year: year,
            properties: properties,
            expenses: expenses,
            trips: trips,
            mileageRates: settings.mileageRates,
            useBoltonAllocation: settings.useBoltonAllocation
        )
    }

    public static func report(
        year: Int,
        properties: [Property],
        expenses: [Expense],
        trips: [MileageTrip],
        settings: AppSettings
    ) -> ScheduleEReport {
        ScheduleEEngine.build(
            dataSet(year: year, properties: properties, expenses: expenses, trips: trips, settings: settings)
        )
    }

    public static func participation(
        year: Int,
        properties: [Property],
        entries: [ParticipationEntry],
        settings: AppSettings
    ) -> MaterialParticipationAnalysis {
        MaterialParticipationEngine.analyze(
            bookings: properties.flatMap(\.bookingList),
            entries: entries,
            year: year,
            propertyID: nil,
            priorYearsMateriallyParticipated: settings.priorYearsMateriallyParticipated
        )
    }

    /// The tax estimate that the whole planning surface of the app is built on.
    public static func estimate(
        year: Int,
        report: ScheduleEReport,
        participation: MaterialParticipationAnalysis,
        payments: [EstimatedTaxPayment],
        settings: AppSettings
    ) -> TaxEstimateResult {
        var input = settings.baseEstimateInput(for: year)
        input.rentalNetIncome = report.totalNet
        input.lossIsNonPassive = participation.lossIsNonPassive || settings.isRealEstateProfessional
        input.allowedRentalLoss = specialAllowance(
            modifiedAGI: settings.modifiedAGI > 0 ? settings.modifiedAGI : settings.otherOrdinaryIncome,
            filingStatus: settings.filingStatus
        )
        input.estimatedPaymentsMade = payments
            .filter { $0.taxYear == year && $0.jurisdiction == .federal }
            .map(\.amount)
            .total
        input.subjectToNIIT = settings.subjectToNIIT
            && !settings.isRealEstateProfessional
            && !participation.lossIsNonPassive
        return TaxEstimator.estimate(input)
    }

    /// The $25,000 special allowance for active participation in rental real
    /// estate, phased out between $100,000 and $150,000 of modified AGI.
    public static func specialAllowance(modifiedAGI: Decimal, filingStatus: FilingStatus) -> Decimal {
        let maximum: Decimal = filingStatus == .marriedFilingSeparately ? 12_500 : 25_000
        let phaseOutStart: Decimal = filingStatus == .marriedFilingSeparately ? 50_000 : 100_000
        guard modifiedAGI > phaseOutStart else { return maximum }
        let excess = modifiedAGI - phaseOutStart
        let reduction = excess.applying(percent: 50)
        return max(0, maximum - reduction)
    }
}
