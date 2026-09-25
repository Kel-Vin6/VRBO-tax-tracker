//
//  NotificationService.swift
//  VRBO tax tracker
//
//  Deadlines a host cannot afford to miss: estimated tax instalments, permit
//  and insurance renewals, and the weekly nudge that keeps the mileage and
//  participation logs contemporaneous.
//

import Foundation
import UserNotifications

public enum NotificationCategoryID {
    public static let quarterlyTax = "quarterlyTax"
    public static let permitExpiry = "permitExpiry"
    public static let weeklyLog = "weeklyLog"
    public static let personalUseThreshold = "personalUseThreshold"
    public static let missingReceipts = "missingReceipts"
}

@Observable
public final class NotificationService {

    public static let shared = NotificationService()

    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    public private(set) var pendingCount: Int = 0
    public private(set) var lastError: String?

    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        pendingCount = await center.pendingNotificationRequests().count
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func cancelAll() {
        center.removeAllPendingNotificationRequests()
        pendingCount = 0
    }

    public func cancel(withPrefix prefix: String) async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        await refreshStatus()
    }

    // MARK: - Scheduling

    private func schedule(
        id: String,
        title: String,
        body: String,
        date: Date,
        categoryID: String
    ) async {
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryID

        let components = DateMath.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reminders a week before and on the morning of each instalment.
    public func scheduleQuarterlyTaxReminders(
        year: Int,
        amounts: [QuarterlyDueDate],
        currencyCode: String
    ) async {
        await cancel(withPrefix: NotificationCategoryID.quarterlyTax)

        for quarter in amounts where !quarter.isPaid {
            let amountText = quarter.suggestedAmount > 0
                ? " of about \(Fmt.currency(quarter.suggestedAmount, code: currencyCode, hideCents: true))"
                : ""

            if let warning = DateMath.calendar.date(byAdding: .day, value: -7, to: quarter.dueDate),
               let morning = at(hour: 9, on: warning) {
                await schedule(
                    id: "\(NotificationCategoryID.quarterlyTax).\(year).\(quarter.quarter).warning",
                    title: "Estimated tax due in a week",
                    body: "Your Q\(quarter.quarter) \(year) instalment\(amountText) is due on \(Fmt.mediumDate(quarter.dueDate)).",
                    date: morning,
                    categoryID: NotificationCategoryID.quarterlyTax
                )
            }

            if let morning = at(hour: 8, on: quarter.dueDate) {
                await schedule(
                    id: "\(NotificationCategoryID.quarterlyTax).\(year).\(quarter.quarter).due",
                    title: "Estimated tax due today",
                    body: "Q\(quarter.quarter) \(year)\(amountText) is due today. Paying the safe harbor amount avoids the underpayment penalty even if the year turns out better than expected.",
                    date: morning,
                    categoryID: NotificationCategoryID.quarterlyTax
                )
            }
        }
        await refreshStatus()
    }

    /// Permits and policies, warned at 60, 30 and 7 days. Only the reminders
    /// belonging to the properties passed in are replaced, so rescheduling one
    /// property never silently clears another's.
    public func schedulePermitReminders(for properties: [Property]) async {
        for property in properties {
            await cancel(withPrefix: "\(NotificationCategoryID.permitExpiry).\(property.id.uuidString)")
            let items: [(String, Date?)] = [
                ("short-term rental permit", property.permitExpiration),
                ("insurance policy", property.insuranceExpiration)
            ]
            for (label, expiry) in items {
                guard let expiry else { continue }
                for daysBefore in [60, 30, 7] {
                    guard let fireDate = DateMath.calendar.date(byAdding: .day, value: -daysBefore, to: expiry),
                          let morning = at(hour: 9, on: fireDate) else { continue }
                    await schedule(
                        id: "\(NotificationCategoryID.permitExpiry).\(property.id.uuidString).\(label).\(daysBefore)",
                        title: "\(property.displayName): \(label) expiring",
                        body: "The \(label) expires on \(Fmt.mediumDate(expiry)), in \(daysBefore) days. Renewing late can mean losing the listing altogether.",
                        date: morning,
                        categoryID: NotificationCategoryID.permitExpiry
                    )
                }
            }
        }
        await refreshStatus()
    }

    /// A weekly nudge, because a contemporaneous log is worth far more than an
    /// accurate one reconstructed in April.
    public func scheduleWeeklyLogReminder(weekday: Int, hour: Int) async {
        await cancel(withPrefix: NotificationCategoryID.weeklyLog)

        let content = UNMutableNotificationContent()
        content.title = "Weekly log check"
        content.body = "Add this week's mileage, hours worked on the property and any receipts while you still remember them."
        content.sound = .default
        content.categoryIdentifier = NotificationCategoryID.weeklyLog

        var components = DateComponents()
        components.weekday = max(1, min(7, weekday))
        components.hour = max(0, min(23, hour))
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "\(NotificationCategoryID.weeklyLog).recurring",
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            lastError = error.localizedDescription
        }
        await refreshStatus()
    }

    /// Fired when a property gets close to the §280A personal-use limit.
    public func notifyPersonalUseThreshold(
        propertyName: String,
        headroomDays: Int
    ) async {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(propertyName): personal use limit close"
        content.body = headroomDays > 0
            ? "You have \(headroomDays) personal day\(headroomDays == 1 ? "" : "s") left before this property is treated as a residence and the rental loss disappears."
            : "Personal use has passed the limit. This property is now treated as a residence for the year, which caps deductions at rental income."
        content.sound = .default
        content.categoryIdentifier = NotificationCategoryID.personalUseThreshold

        let request = UNNotificationRequest(
            identifier: "\(NotificationCategoryID.personalUseThreshold).\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        try? await center.add(request)
    }

    /// A next-morning nudge to photograph a receipt while it still exists.
    public func remindMissingReceipt(
        vendor: String,
        amount: Decimal,
        currencyCode: String
    ) async {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Receipt still needed"
        content.body = "\(Fmt.currency(amount, code: currencyCode, hideCents: true)) to \(vendor.isEmpty ? "a vendor" : vendor) has no receipt attached. Substantiation is required at $75 and above."
        content.sound = .default
        content.categoryIdentifier = NotificationCategoryID.missingReceipts

        let tomorrow = DateMath.adding(days: 1, to: Date())
        guard let fireDate = at(hour: 10, on: tomorrow) else { return }
        let components = DateMath.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)

        let request = UNNotificationRequest(
            identifier: "\(NotificationCategoryID.missingReceipts).\(UUID().uuidString)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
        await refreshStatus()
    }

    private func at(hour: Int, on date: Date) -> Date? {
        DateMath.calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: date
        )
    }
}
