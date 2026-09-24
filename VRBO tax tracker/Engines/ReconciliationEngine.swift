//
//  ReconciliationEngine.swift
//  VRBO tax tracker
//
//  The IRS receives a copy of every Form 1099-K a platform files. If the gross
//  on that form is larger than the rents on Schedule E — and it almost always
//  is, because the form reports what the guest paid, not what you banked — the
//  return needs to explain the difference. This works out that explanation.
//

import Foundation

public struct ReconciliationLine: Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var amount: Decimal
    public var detail: String
    public var isSubtotal: Bool = false
}

public struct PlatformReconciliation: Identifiable, Hashable, Sendable {
    public var id: String
    public var platform: RentalPlatform
    public var year: Int

    public var reportedOnForm: Decimal
    public var recordedGuestCharges: Decimal
    public var recordedGrossRents: Decimal
    public var lodgingTaxCollected: Decimal
    public var platformFees: Decimal
    public var bookingCount: Int

    public var lines: [ReconciliationLine]
    public var variance: Decimal
    public var hasForm: Bool

    public var isReconciled: Bool { abs(variance) < 1 }

    public var status: String {
        if !hasForm { return "No 1099-K entered" }
        if isReconciled { return "Reconciled" }
        return variance > 0 ? "Income may be missing" : "More recorded than reported"
    }

    public var guidance: String {
        if !hasForm {
            return "Enter the gross amount from box 1a of the \(platform.title) 1099-K to reconcile \(Fmt.currency(recordedGuestCharges)) of recorded guest charges against it."
        }
        if isReconciled {
            return "Your records agree with the 1099-K. Keep this reconciliation with the return — it is the answer to the only question the matching program asks."
        }
        if variance > 0 {
            return "The 1099-K reports \(Fmt.currency(abs(variance))) more than you recorded. The usual causes are bookings never entered, a payout that spans the year end, or resolution payments and damage claims the platform passed through."
        }
        return "You recorded \(Fmt.currency(abs(variance))) more than the 1099-K reports. Check for stays entered twice, direct bookings tagged to this platform, or refunds the platform netted before reporting."
    }
}

public enum ReconciliationEngine {

    public static func reconcile(
        year: Int,
        bookings: [Booking],
        forms: [PlatformTaxForm]
    ) -> [PlatformReconciliation] {

        let relevant = bookings.filter { $0.nights(inYear: year) > 0 || DateMath.contains($0.checkIn, inYear: year) }
        let byPlatform = Dictionary(grouping: relevant, by: \.platform)

        var platforms = Set(byPlatform.keys)
        for form in forms where form.taxYear == year {
            platforms.insert(form.platform)
        }

        return platforms.sorted { $0.title < $1.title }.map { platform in
            let platformBookings = (byPlatform[platform] ?? []).filter { !$0.isCancelled }
            let form = forms.first { $0.taxYear == year && $0.platform == platform }

            let grossRents = platformBookings.reduce(Decimal.zero) {
                $0 + $1.grossRents * $1.yearFraction(year)
            }.rounded(2)
            let lodgingTax = platformBookings.reduce(Decimal.zero) {
                $0 + $1.lodgingTaxCollected * $1.yearFraction(year)
            }.rounded(2)
            let fees = platformBookings.reduce(Decimal.zero) {
                $0 + $1.totalPlatformFees * $1.yearFraction(year)
            }.rounded(2)

            // Rebuild the figure the platform would have put on the form.
            var expected = grossRents
            var lines: [ReconciliationLine] = [
                ReconciliationLine(
                    id: "rents",
                    label: "Gross rents recorded",
                    amount: grossRents,
                    detail: "Nightly revenue, cleaning fees and other guest fees across \(platformBookings.count) stay\(platformBookings.count == 1 ? "" : "s")."
                )
            ]

            if form?.includesLodgingTax ?? true, lodgingTax != 0 {
                expected += lodgingTax
                lines.append(
                    ReconciliationLine(
                        id: "lodgingTax",
                        label: "Lodging tax collected from guests",
                        amount: lodgingTax,
                        detail: "\(platform.title) reports the gross the guest paid, which includes occupancy tax it remitted on your behalf. It is not your income — deduct it or exclude it, but explain it."
                    )
                )
            }

            lines.append(
                ReconciliationLine(
                    id: "expected",
                    label: "Expected on Form 1099-K",
                    amount: expected.rounded(2),
                    detail: "What the platform should have reported based on your records.",
                    isSubtotal: true
                )
            )

            if let form {
                lines.append(
                    ReconciliationLine(
                        id: "reported",
                        label: "Box 1a as filed by \(platform.title)",
                        amount: form.grossAmountReported,
                        detail: form.payerName.isEmpty ? "As entered from your 1099-K." : "Payer: \(form.payerName)."
                    )
                )
            }

            if fees != 0 {
                lines.append(
                    ReconciliationLine(
                        id: "fees",
                        label: "Host service fees deducted on line 8",
                        amount: fees,
                        detail: "The platform kept this before paying you, so it never appears in your bank account — but it is reported in the gross and it is deductible. Missing it is the most common overpayment on a host return."
                    )
                )
            }

            let variance = ((form?.grossAmountReported ?? expected) - expected).rounded(2)

            return PlatformReconciliation(
                id: "\(platform.rawValue)-\(year)",
                platform: platform,
                year: year,
                reportedOnForm: form?.grossAmountReported ?? 0,
                recordedGuestCharges: expected.rounded(2),
                recordedGrossRents: grossRents,
                lodgingTaxCollected: lodgingTax,
                platformFees: fees,
                bookingCount: platformBookings.count,
                lines: lines,
                variance: variance,
                hasForm: form != nil
            )
        }
    }
}
