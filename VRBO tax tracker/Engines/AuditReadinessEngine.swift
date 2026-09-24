//
//  AuditReadinessEngine.swift
//  VRBO tax tracker
//
//  Deductions are not won by being correct; they are won by being documented.
//  This scores the file the way an examiner would read it and says exactly what
//  to fix, in the order that recovers the most money.
//

import Foundation

public enum AuditSeverity: Int, Comparable, Sendable {
    case informational = 0
    case advisory = 1
    case important = 2
    case critical = 3

    public static func < (lhs: AuditSeverity, rhs: AuditSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .informational: "Note"
        case .advisory: "Worth doing"
        case .important: "Important"
        case .critical: "Fix before filing"
        }
    }

    public var symbol: String {
        switch self {
        case .informational: "info.circle.fill"
        case .advisory: "lightbulb.fill"
        case .important: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }
}

public struct AuditFinding: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var severity: AuditSeverity
    /// Deductions at risk if the finding is not addressed.
    public var amountAtRisk: Decimal
    public var affectedCount: Int
    public var actionLabel: String
    public var destination: AuditDestination
}

public enum AuditDestination: String, Hashable, Sendable {
    case expenses
    case mileage
    case bookings
    case personalUse
    case participation
    case properties
    case depreciation
    case documents
    case settings
}

public struct AuditReadinessReport: Hashable, Sendable {
    public var year: Int
    public var score: Int
    public var findings: [AuditFinding]

    public var totalAtRisk: Decimal { findings.map(\.amountAtRisk).total }
    public var criticalCount: Int { findings.filter { $0.severity == .critical }.count }

    public var grade: String {
        switch score {
        case 95...: "A+"
        case 90..<95: "A"
        case 85..<90: "A−"
        case 80..<85: "B+"
        case 75..<80: "B"
        case 70..<75: "B−"
        case 60..<70: "C"
        case 50..<60: "D"
        default: "F"
        }
    }

    public var headline: String {
        switch score {
        case 90...: "Filing-ready"
        case 75..<90: "Nearly there"
        case 60..<75: "Needs attention"
        default: "Significant gaps"
        }
    }

    public var summary: String {
        if findings.isEmpty {
            return "Every record for \(year) is complete. Receipts are attached, mileage logs carry a business purpose, and the day counts reconcile."
        }
        if criticalCount > 0 {
            return "\(criticalCount) item\(criticalCount == 1 ? "" : "s") would not survive an examination as recorded, putting \(Fmt.currency(totalAtRisk)) of deductions at risk."
        }
        return "\(findings.count) item\(findings.count == 1 ? "" : "s") to tidy up, covering \(Fmt.currency(totalAtRisk)) of deductions."
    }
}

public enum AuditReadinessEngine {

    /// Receipts are required for expenses of $75 or more; the app applies the
    /// same bar to anything it asks the user to photograph.
    public static let receiptThreshold: Decimal = 75

    public static func evaluate(
        year: Int,
        properties: [Property],
        expenses: [Expense],
        trips: [MileageTrip],
        participation: [ParticipationEntry],
        documents: [StoredDocument]
    ) -> AuditReadinessReport {

        var findings: [AuditFinding] = []
        var penalty = 0

        let yearExpenses = expenses.filter { DateMath.contains($0.date, inYear: year) }
        let yearTrips = trips.filter { DateMath.contains($0.date, inYear: year) }

        // 1. Missing receipts on material amounts.
        let missingReceipts = yearExpenses.filter { $0.amount >= receiptThreshold && !$0.hasReceipt }
        if !missingReceipts.isEmpty {
            let atRisk = missingReceipts.map(\.deductibleAmount).total
            findings.append(
                AuditFinding(
                    id: "missingReceipts",
                    title: "\(missingReceipts.count) expense\(missingReceipts.count == 1 ? "" : "s") over \(Fmt.currency(receiptThreshold, hideCents: true)) with no receipt",
                    detail: "Substantiation is required for expenses of $75 or more. Photograph the receipt or attach the invoice PDF and these deductions stop being contestable.",
                    severity: atRisk > 2_500 ? .critical : .important,
                    amountAtRisk: atRisk,
                    affectedCount: missingReceipts.count,
                    actionLabel: "Attach receipts",
                    destination: .expenses
                )
            )
            penalty += min(20, missingReceipts.count * 2)
        }

        // 2. Mileage logs missing a business purpose or destination.
        let weakTrips = yearTrips.filter { !$0.isAuditComplete }
        if !weakTrips.isEmpty {
            findings.append(
                AuditFinding(
                    id: "weakMileage",
                    title: "\(weakTrips.count) mileage entr\(weakTrips.count == 1 ? "y" : "ies") missing required detail",
                    detail: "A mileage log has to show the date, the miles, where you went and why. Entries without all four are routinely disallowed in full.",
                    severity: .important,
                    amountAtRisk: 0,
                    affectedCount: weakTrips.count,
                    actionLabel: "Complete the log",
                    destination: .mileage
                )
            )
            penalty += min(12, weakTrips.count)
        }

        // 3. Mileage recorded long after the fact.
        let staleTrips = yearTrips.filter { !$0.loggedSameDay }
        if staleTrips.count > yearTrips.count / 2 && yearTrips.count >= 6 {
            findings.append(
                AuditFinding(
                    id: "staleMileage",
                    title: "Most mileage was logged after the day of travel",
                    detail: "A contemporaneous log carries far more weight than one reconstructed at year end. Logging the drive the day it happens is the single cheapest thing you can do for this file.",
                    severity: .advisory,
                    amountAtRisk: 0,
                    affectedCount: staleTrips.count,
                    actionLabel: "Review mileage",
                    destination: .mileage
                )
            )
            penalty += 4
        }

        // 4. Cash spending without documentation.
        let undocumentedCash = yearExpenses.filter {
            $0.paymentMethod == .cash && !$0.hasReceipt && $0.amount > 0
        }
        if !undocumentedCash.isEmpty {
            findings.append(
                AuditFinding(
                    id: "cashNoReceipt",
                    title: "\(undocumentedCash.count) cash payment\(undocumentedCash.count == 1 ? "" : "s") with no receipt",
                    detail: "Cash leaves no bank trail. Without a receipt there is nothing at all to corroborate the deduction.",
                    severity: .important,
                    amountAtRisk: undocumentedCash.map(\.deductibleAmount).total,
                    affectedCount: undocumentedCash.count,
                    actionLabel: "Attach proof",
                    destination: .expenses
                )
            )
            penalty += min(10, undocumentedCash.count * 3)
        }

        // 5. Personal spending mixed into a full deduction.
        let suspiciousPersonalCard = yearExpenses.filter {
            $0.paymentMethod == .personalCreditCard && $0.businessUsePercent == 100 && $0.amount >= 250
        }
        if suspiciousPersonalCard.count >= 5 {
            findings.append(
                AuditFinding(
                    id: "personalCard",
                    title: "Frequent rental spending on a personal card",
                    detail: "Commingled accounts are the fastest way to turn a narrow examination into a broad one. A dedicated card for the rental costs nothing and settles the question.",
                    severity: .advisory,
                    amountAtRisk: 0,
                    affectedCount: suspiciousPersonalCard.count,
                    actionLabel: "Review expenses",
                    destination: .expenses
                )
            )
            penalty += 3
        }

        // 6. Property-level tax data gaps.
        for property in properties {
            let flags = property.complianceFlags()
            let blocking = flags.filter {
                $0 == .missingLandAllocation || $0 == .missingPlacedInService
            }
            if !blocking.isEmpty {
                findings.append(
                    AuditFinding(
                        id: "basis-\(property.id.uuidString)",
                        title: "\(property.displayName) cannot be depreciated yet",
                        detail: blocking.map(\.message).joined(separator: " ") + " Depreciation is not optional — the IRS reduces your basis on sale by the amount you were allowed to take, whether or not you took it.",
                        severity: .critical,
                        amountAtRisk: 0,
                        affectedCount: blocking.count,
                        actionLabel: "Complete the basis",
                        destination: .properties
                    )
                )
                penalty += 10
            }

            let expired = flags.filter(\.isCritical)
            if !expired.isEmpty {
                findings.append(
                    AuditFinding(
                        id: "compliance-\(property.id.uuidString)",
                        title: "\(property.displayName) has a lapsed permit or policy",
                        detail: expired.map(\.message).joined(separator: " "),
                        severity: .important,
                        amountAtRisk: 0,
                        affectedCount: expired.count,
                        actionLabel: "Open property",
                        destination: .properties
                    )
                )
                penalty += 5
            }
        }

        // 7. Day-count conflicts.
        var conflictTotal = 0
        for property in properties {
            let analysis = PersonalUseEngine.analyze(
                bookings: property.bookingList,
                personalUse: property.personalUseList,
                year: year,
                propertyID: property.id,
                daysAvailable: property.daysAvailablePerYear
            )
            conflictTotal += analysis.conflictingDays.count + analysis.doubleBookedDays.count
        }
        if conflictTotal > 0 {
            findings.append(
                AuditFinding(
                    id: "dayConflicts",
                    title: "\(conflictTotal) calendar day\(conflictTotal == 1 ? "" : "s") counted twice",
                    detail: "A day recorded as both rented and personally used, or covered by two bookings, makes the Schedule E day counts impossible to reconcile. Examiners start with the day counts.",
                    severity: .critical,
                    amountAtRisk: 0,
                    affectedCount: conflictTotal,
                    actionLabel: "Resolve conflicts",
                    destination: .personalUse
                )
            )
            penalty += min(15, conflictTotal * 2)
        }

        // 8. Participation hours recorded without any description.
        let yearParticipation = participation.filter { DateMath.contains($0.date, inYear: year) }
        let vagueHours = yearParticipation.filter { $0.descriptionText.trimmingCharacters(in: .whitespaces).isEmpty }
        if !vagueHours.isEmpty && yearParticipation.count >= 5 {
            findings.append(
                AuditFinding(
                    id: "vagueParticipation",
                    title: "\(vagueHours.count) participation entr\(vagueHours.count == 1 ? "y" : "ies") with no description",
                    detail: "Hours claimed toward material participation need to say what was actually done. A bare number is the first thing challenged, and the loss it unlocks is usually the largest item on the return.",
                    severity: .important,
                    amountAtRisk: 0,
                    affectedCount: vagueHours.count,
                    actionLabel: "Add detail",
                    destination: .participation
                )
            )
            penalty += min(10, vagueHours.count)
        }

        // 9. Bookings that do not add up.
        let brokenBookings = properties
            .flatMap(\.bookingList)
            .filter { $0.nights(inYear: year) > 0 && !$0.validationIssues.isEmpty }
        if !brokenBookings.isEmpty {
            findings.append(
                AuditFinding(
                    id: "brokenBookings",
                    title: "\(brokenBookings.count) booking\(brokenBookings.count == 1 ? "" : "s") with inconsistent figures",
                    detail: "Stays with no revenue, fees larger than the rent, or a check-out before check-in will not reconcile against your payout statements.",
                    severity: .important,
                    amountAtRisk: 0,
                    affectedCount: brokenBookings.count,
                    actionLabel: "Review bookings",
                    destination: .bookings
                )
            )
            penalty += min(10, brokenBookings.count)
        }

        // 10. No supporting paperwork stored at all.
        if documents.filter({ $0.taxYear == year }).isEmpty && !yearExpenses.isEmpty {
            findings.append(
                AuditFinding(
                    id: "noDocuments",
                    title: "No supporting documents stored for \(year)",
                    detail: "Closing statements, 1099-Ks, Form 1098s and permits belong in the file with the receipts. Keeping them here means the whole year travels as one package.",
                    severity: .advisory,
                    amountAtRisk: 0,
                    affectedCount: 0,
                    actionLabel: "Add documents",
                    destination: .documents
                )
            )
            penalty += 4
        }

        let score = max(0, 100 - penalty)
        let ordered = findings.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.amountAtRisk > $1.amountAtRisk
        }

        return AuditReadinessReport(year: year, score: score, findings: ordered)
    }
}
