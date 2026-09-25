//
//  AppSettings.swift
//  VRBO tax tracker
//
//  Every user preference in one observable store, persisted as JSON in
//  UserDefaults so the whole thing can be exported, imported and reset.
//

import Foundation
import Observation
import SwiftUI

public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

public enum LockTimeout: Int, Codable, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case oneHour = 60

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        case .fifteenMinutes: "After 15 minutes"
        case .oneHour: "After 1 hour"
        }
    }
}

/// The serialisable shape of every preference.
public struct SettingsSnapshot: Codable, Equatable, Sendable {

    // Profile
    public var ownerName: String = ""
    public var businessName: String = ""
    public var accountantName: String = ""
    public var accountantEmail: String = ""

    // Presentation
    public var themeRaw: String = AppTheme.system.rawValue
    public var accentHex: String = "2E7D8F"
    public var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    public var hideCents: Bool = false
    public var followsCurrentYear: Bool = true
    public var pinnedTaxYear: Int = DateMath.currentYear

    // Tax profile
    public var filingStatusRaw: String = FilingStatus.single.rawValue
    public var stateCode: String = ""
    public var stateRatePercent: Double = 0
    public var marginalRateOverride: Double = 0
    public var useMarginalRateOverride: Bool = false
    public var otherOrdinaryIncome: Decimal = 0
    public var federalWithholding: Decimal = 0
    public var itemizedDeductions: Decimal = 0
    public var useItemizedDeductions: Bool = false
    public var priorYearTotalTax: Decimal = 0
    public var priorYearAGI: Decimal = 0
    public var modifiedAGI: Decimal = 0
    public var subjectToNIIT: Bool = true
    public var claimQBIDeduction: Bool = false
    public var providesHotelLikeServices: Bool = false
    public var isRealEstateProfessional: Bool = false
    public var priorYearsMateriallyParticipated: Int = 0

    // Method elections
    public var useBoltonAllocation: Bool = false
    public var deMinimisElectionInPlace: Bool = true
    public var hasAuditedFinancialStatements: Bool = false
    public var defaultBonusPercentOverride: Double = -1
    public var mileageRateOverrides: [Int: Double] = [:]

    // Security
    public var appLockEnabled: Bool = false
    public var lockTimeoutRaw: Int = LockTimeout.fiveMinutes.rawValue
    public var iCloudSyncEnabled: Bool = false

    // Notifications
    public var notifyQuarterlyTaxes: Bool = true
    public var notifyPermitExpiry: Bool = true
    public var notifyWeeklyLogReminder: Bool = false
    public var weeklyReminderWeekday: Int = 1
    public var weeklyReminderHour: Int = 18
    public var notifyPersonalUseThreshold: Bool = true
    public var notifyMissingReceipts: Bool = true

    // Capture defaults
    public var defaultPropertyID: String = ""
    public var defaultPaymentMethodRaw: String = PaymentMethod.businessCreditCard.rawValue
    public var autoRunRecurringRules: Bool = true
    public var promptImprovementReview: Bool = true

    // First run
    public var hasCompletedOnboarding: Bool = false
    public var hasAcceptedDisclaimer: Bool = false

    public init() {}
}

@Observable
public final class AppSettings {

    public static let shared = AppSettings()

    private static let storageKey = "com.kelvin.vrbotaxtracker.settings.v1"

    /// The single tracked property. Observation instruments stored properties,
    /// and a property observer would prevent that, so persistence is driven
    /// through `write(_:)` rather than a `didSet`.
    private var snapshot: SettingsSnapshot

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(SettingsSnapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = SettingsSnapshot()
        }
    }

    /// Applies a change, publishes it to observers and writes it to disk.
    private func write(_ change: (inout SettingsSnapshot) -> Void) {
        var updated = snapshot
        change(&updated)
        snapshot = updated
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public func exportSnapshot() -> SettingsSnapshot { snapshot }

    public func importSnapshot(_ new: SettingsSnapshot) {
        write { $0 = new }
    }

    public func resetToDefaults() {
        write { $0 = SettingsSnapshot() }
    }

    // MARK: - Profile

    public var ownerName: String {
        get { snapshot.ownerName }
        set { write { $0.ownerName = newValue } }
    }
    public var businessName: String {
        get { snapshot.businessName }
        set { write { $0.businessName = newValue } }
    }
    public var accountantName: String {
        get { snapshot.accountantName }
        set { write { $0.accountantName = newValue } }
    }
    public var accountantEmail: String {
        get { snapshot.accountantEmail }
        set { write { $0.accountantEmail = newValue } }
    }

    // MARK: - Presentation

    public var theme: AppTheme {
        get { AppTheme(rawValue: snapshot.themeRaw) ?? .system }
        set { write { $0.themeRaw = newValue.rawValue } }
    }
    public var accentHex: String {
        get { snapshot.accentHex }
        set { write { $0.accentHex = newValue } }
    }
    public var accentColor: Color { PropertyPalette.color(for: accentHex) }
    public var currencyCode: String {
        get { snapshot.currencyCode }
        set { write { $0.currencyCode = newValue } }
    }
    public var hideCents: Bool {
        get { snapshot.hideCents }
        set { write { $0.hideCents = newValue } }
    }
    public var followsCurrentYear: Bool {
        get { snapshot.followsCurrentYear }
        set { write { $0.followsCurrentYear = newValue } }
    }
    public var pinnedTaxYear: Int {
        get { snapshot.pinnedTaxYear }
        set { write { $0.pinnedTaxYear = newValue } }
    }
    /// The tax year every screen defaults to.
    public var activeTaxYear: Int {
        followsCurrentYear ? DateMath.currentYear : pinnedTaxYear
    }

    // MARK: - Tax profile

    public var filingStatus: FilingStatus {
        get { FilingStatus(rawValue: snapshot.filingStatusRaw) ?? .single }
        set { write { $0.filingStatusRaw = newValue.rawValue } }
    }
    public var stateCode: String {
        get { snapshot.stateCode }
        set { write { $0.stateCode = newValue } }
    }
    public var stateRatePercent: Double {
        get { snapshot.stateRatePercent }
        set { write { $0.stateRatePercent = newValue } }
    }
    public var marginalRateOverride: Double {
        get { snapshot.marginalRateOverride }
        set { write { $0.marginalRateOverride = newValue } }
    }
    public var useMarginalRateOverride: Bool {
        get { snapshot.useMarginalRateOverride }
        set { write { $0.useMarginalRateOverride = newValue } }
    }
    public var otherOrdinaryIncome: Decimal {
        get { snapshot.otherOrdinaryIncome }
        set { write { $0.otherOrdinaryIncome = newValue } }
    }
    public var federalWithholding: Decimal {
        get { snapshot.federalWithholding }
        set { write { $0.federalWithholding = newValue } }
    }
    public var itemizedDeductions: Decimal {
        get { snapshot.itemizedDeductions }
        set { write { $0.itemizedDeductions = newValue } }
    }
    public var useItemizedDeductions: Bool {
        get { snapshot.useItemizedDeductions }
        set { write { $0.useItemizedDeductions = newValue } }
    }
    public var priorYearTotalTax: Decimal {
        get { snapshot.priorYearTotalTax }
        set { write { $0.priorYearTotalTax = newValue } }
    }
    public var priorYearAGI: Decimal {
        get { snapshot.priorYearAGI }
        set { write { $0.priorYearAGI = newValue } }
    }
    public var modifiedAGI: Decimal {
        get { snapshot.modifiedAGI }
        set { write { $0.modifiedAGI = newValue } }
    }
    public var subjectToNIIT: Bool {
        get { snapshot.subjectToNIIT }
        set { write { $0.subjectToNIIT = newValue } }
    }
    public var claimQBIDeduction: Bool {
        get { snapshot.claimQBIDeduction }
        set { write { $0.claimQBIDeduction = newValue } }
    }
    public var providesHotelLikeServices: Bool {
        get { snapshot.providesHotelLikeServices }
        set { write { $0.providesHotelLikeServices = newValue } }
    }
    public var isRealEstateProfessional: Bool {
        get { snapshot.isRealEstateProfessional }
        set { write { $0.isRealEstateProfessional = newValue } }
    }
    public var priorYearsMateriallyParticipated: Int {
        get { snapshot.priorYearsMateriallyParticipated }
        set { write { $0.priorYearsMateriallyParticipated = newValue } }
    }

    // MARK: - Elections

    public var useBoltonAllocation: Bool {
        get { snapshot.useBoltonAllocation }
        set { write { $0.useBoltonAllocation = newValue } }
    }
    public var deMinimisElectionInPlace: Bool {
        get { snapshot.deMinimisElectionInPlace }
        set { write { $0.deMinimisElectionInPlace = newValue } }
    }
    public var hasAuditedFinancialStatements: Bool {
        get { snapshot.hasAuditedFinancialStatements }
        set { write { $0.hasAuditedFinancialStatements = newValue } }
    }
    /// −1 means "use the statutory default for the acquisition year".
    public var defaultBonusPercentOverride: Double {
        get { snapshot.defaultBonusPercentOverride }
        set { write { $0.defaultBonusPercentOverride = newValue } }
    }
    public var mileageRates: MileageRateTable {
        MileageRateTable(overrides: snapshot.mileageRateOverrides)
    }
    public func setMileageRate(_ rate: Double, forYear year: Int) {
        write { snapshot in
            if rate <= 0 {
                snapshot.mileageRateOverrides.removeValue(forKey: year)
            } else {
                snapshot.mileageRateOverrides[year] = rate
            }
        }
    }
    public var mileageRateOverrides: [Int: Double] { snapshot.mileageRateOverrides }

    // MARK: - Security

    public var appLockEnabled: Bool {
        get { snapshot.appLockEnabled }
        set { write { $0.appLockEnabled = newValue } }
    }
    public var lockTimeout: LockTimeout {
        get { LockTimeout(rawValue: snapshot.lockTimeoutRaw) ?? .fiveMinutes }
        set { write { $0.lockTimeoutRaw = newValue.rawValue } }
    }
    public var iCloudSyncEnabled: Bool {
        get { snapshot.iCloudSyncEnabled }
        set { write { $0.iCloudSyncEnabled = newValue } }
    }

    // MARK: - Notifications

    public var notifyQuarterlyTaxes: Bool {
        get { snapshot.notifyQuarterlyTaxes }
        set { write { $0.notifyQuarterlyTaxes = newValue } }
    }
    public var notifyPermitExpiry: Bool {
        get { snapshot.notifyPermitExpiry }
        set { write { $0.notifyPermitExpiry = newValue } }
    }
    public var notifyWeeklyLogReminder: Bool {
        get { snapshot.notifyWeeklyLogReminder }
        set { write { $0.notifyWeeklyLogReminder = newValue } }
    }
    public var weeklyReminderWeekday: Int {
        get { snapshot.weeklyReminderWeekday }
        set { write { $0.weeklyReminderWeekday = newValue } }
    }
    public var weeklyReminderHour: Int {
        get { snapshot.weeklyReminderHour }
        set { write { $0.weeklyReminderHour = newValue } }
    }
    public var notifyPersonalUseThreshold: Bool {
        get { snapshot.notifyPersonalUseThreshold }
        set { write { $0.notifyPersonalUseThreshold = newValue } }
    }
    public var notifyMissingReceipts: Bool {
        get { snapshot.notifyMissingReceipts }
        set { write { $0.notifyMissingReceipts = newValue } }
    }

    // MARK: - Capture defaults

    public var defaultPropertyID: UUID? {
        get { UUID(uuidString: snapshot.defaultPropertyID) }
        set { write { $0.defaultPropertyID = newValue?.uuidString ?? "" } }
    }
    public var defaultPaymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: snapshot.defaultPaymentMethodRaw) ?? .businessCreditCard }
        set { write { $0.defaultPaymentMethodRaw = newValue.rawValue } }
    }
    public var autoRunRecurringRules: Bool {
        get { snapshot.autoRunRecurringRules }
        set { write { $0.autoRunRecurringRules = newValue } }
    }
    public var promptImprovementReview: Bool {
        get { snapshot.promptImprovementReview }
        set { write { $0.promptImprovementReview = newValue } }
    }

    // MARK: - First run

    public var hasCompletedOnboarding: Bool {
        get { snapshot.hasCompletedOnboarding }
        set { write { $0.hasCompletedOnboarding = newValue } }
    }
    public var hasAcceptedDisclaimer: Bool {
        get { snapshot.hasAcceptedDisclaimer }
        set { write { $0.hasAcceptedDisclaimer = newValue } }
    }

    // MARK: - Derived

    /// The marginal rate used across the planning tools: either the user's
    /// override or the rate implied by their bracket.
    public func effectiveMarginalRate(taxableIncome: Decimal, year: Int) -> Double {
        if useMarginalRateOverride, marginalRateOverride > 0 {
            return marginalRateOverride
        }
        let table = FederalRates.table(for: year)
        return TaxEstimator.marginalRate(
            for: taxableIncome,
            brackets: table.brackets(for: filingStatus)
        )
    }

    public func formatted(_ amount: Decimal) -> String {
        Fmt.currency(amount, code: currencyCode, hideCents: hideCents)
    }

    public func formattedCompact(_ amount: Decimal) -> String {
        Fmt.compactCurrency(amount, code: currencyCode)
    }

    public func baseEstimateInput(for year: Int) -> TaxEstimateInput {
        var input = TaxEstimateInput(year: year)
        input.filingStatus = filingStatus
        input.otherOrdinaryIncome = otherOrdinaryIncome
        input.federalWithholding = federalWithholding
        input.itemizedDeductions = itemizedDeductions
        input.useItemizedDeductions = useItemizedDeductions
        input.claimQBIDeduction = claimQBIDeduction
        input.stateRatePercent = stateRatePercent
        input.priorYearTotalTax = priorYearTotalTax
        input.priorYearAGI = priorYearAGI
        input.subjectToNIIT = subjectToNIIT && !isRealEstateProfessional
        return input
    }
}
