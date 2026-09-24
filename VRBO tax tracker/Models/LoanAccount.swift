//
//  LoanAccount.swift
//  VRBO tax tracker
//

import Foundation
import SwiftData

/// A mortgage or other property loan. The app amortises it so that the
/// interest portion of every payment can be deducted without the host having
/// to wait for a Form 1098.
@Model
public final class LoanAccount {

    public var id: UUID = UUID()
    public var lender: String = ""
    public var accountReference: String = ""
    public var originalPrincipal: Decimal = 0
    public var annualRatePercent: Double = 0
    public var termMonths: Int = 360
    public var firstPaymentDate: Date = Date()
    public var isPrimaryMortgage: Bool = true
    /// Points paid at closing, amortised over the life of the loan for a
    /// rental property rather than deducted all at once.
    public var pointsPaid: Decimal = 0
    /// Escrowed taxes and insurance are not interest and are tracked separately.
    public var monthlyEscrow: Decimal = 0
    /// Extra principal the borrower pays each month.
    public var extraMonthlyPrincipal: Decimal = 0
    /// When on, the interest portion of each scheduled payment flows straight
    /// to Schedule E line 12 without waiting for a Form 1098.
    public var autoDeductInterest: Bool = true
    public var notes: String = ""
    public var createdAt: Date = Date()

    public var property: Property?

    public init(
        lender: String = "",
        originalPrincipal: Decimal = 0,
        annualRatePercent: Double = 0,
        termMonths: Int = 360,
        firstPaymentDate: Date = Date(),
        property: Property? = nil
    ) {
        self.id = UUID()
        self.lender = lender
        self.originalPrincipal = originalPrincipal
        self.annualRatePercent = annualRatePercent
        self.termMonths = termMonths
        self.firstPaymentDate = firstPaymentDate
        self.property = property
        self.createdAt = Date()
    }

    public var displayName: String {
        lender.isEmpty ? "Loan" : lender
    }

    public var monthlyRate: Double { annualRatePercent / 100.0 / 12.0 }

    /// Standard amortising payment, principal and interest only.
    public var scheduledPayment: Decimal {
        let principal = originalPrincipal.doubleValue
        guard principal > 0, termMonths > 0 else { return 0 }
        guard monthlyRate > 0 else { return Decimal.fromDouble(principal / Double(termMonths)) }
        let factor = pow(1 + monthlyRate, Double(termMonths))
        let payment = principal * monthlyRate * factor / (factor - 1)
        return Decimal.fromDouble(payment)
    }

    public var totalMonthlyOutlay: Decimal {
        scheduledPayment + monthlyEscrow + extraMonthlyPrincipal
    }

    /// Annual amortisation of loan points over the loan term.
    public var annualPointsAmortization: Decimal {
        guard pointsPaid > 0, termMonths > 0 else { return 0 }
        return (pointsPaid / Decimal(termMonths) * 12).rounded(2)
    }
}
