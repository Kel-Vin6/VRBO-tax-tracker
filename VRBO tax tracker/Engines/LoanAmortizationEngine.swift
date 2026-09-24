//
//  LoanAmortizationEngine.swift
//  VRBO tax tracker
//
//  Amortises a mortgage so the deductible interest for any tax year is known
//  immediately, rather than in February when Form 1098 arrives.
//

import Foundation

public struct LoanPeriod: Identifiable, Hashable, Sendable {
    public var id: Int { number }
    public var number: Int
    public var date: Date
    public var payment: Decimal
    public var interest: Decimal
    public var principal: Decimal
    public var extraPrincipal: Decimal
    public var endingBalance: Decimal
}

public struct LoanYearSummary: Identifiable, Hashable, Sendable {
    public var id: Int { year }
    public var year: Int
    public var interest: Decimal
    public var principal: Decimal
    public var escrow: Decimal
    public var endingBalance: Decimal
    public var pointsAmortized: Decimal

    public var totalPaid: Decimal { interest + principal + escrow }
    /// Only the interest and the amortised points reach Schedule E line 12.
    public var deductible: Decimal { interest + pointsAmortized }
}

public enum LoanAmortizationEngine {

    private static let maximumPeriods = 720

    public static func schedule(for loan: LoanAccount) -> [LoanPeriod] {
        var balance = loan.originalPrincipal
        guard balance > 0, loan.termMonths > 0 else { return [] }

        let payment = loan.scheduledPayment
        let monthlyRate = Decimal.fromDouble(loan.monthlyRate, scale: 10)
        var periods: [LoanPeriod] = []
        var number = 1
        var date = loan.firstPaymentDate

        while balance > 0 && number <= min(loan.termMonths * 2, maximumPeriods) {
            let interest = (balance * monthlyRate).rounded(2)
            var principal = payment - interest
            if principal < 0 { principal = 0 }

            var extra = loan.extraMonthlyPrincipal
            if principal > balance {
                principal = balance
                extra = 0
            } else if principal + extra > balance {
                extra = balance - principal
            }

            balance = (balance - principal - extra).rounded(2)
            if balance < 0.01 { balance = 0 }

            periods.append(
                LoanPeriod(
                    number: number,
                    date: date,
                    payment: payment,
                    interest: interest,
                    principal: principal,
                    extraPrincipal: extra,
                    endingBalance: balance
                )
            )

            date = DateMath.adding(months: 1, to: date)
            number += 1
        }
        return periods
    }

    public static func yearSummaries(for loan: LoanAccount) -> [LoanYearSummary] {
        let periods = schedule(for: loan)
        guard !periods.isEmpty else { return [] }

        let grouped = Dictionary(grouping: periods) { DateMath.year(of: $0.date) }
        return grouped.keys.sorted().map { year in
            let rows = grouped[year] ?? []
            return LoanYearSummary(
                year: year,
                interest: rows.map(\.interest).total,
                principal: rows.map { $0.principal + $0.extraPrincipal }.total,
                escrow: loan.monthlyEscrow * Decimal(rows.count),
                endingBalance: rows.last?.endingBalance ?? 0,
                pointsAmortized: loan.annualPointsAmortization
            )
        }
    }

    public static func interest(for loan: LoanAccount, inYear year: Int) -> Decimal {
        guard loan.autoDeductInterest else { return 0 }
        return yearSummaries(for: loan).first(where: { $0.year == year })?.deductible ?? 0
    }

    public static func balance(for loan: LoanAccount, asOf date: Date = Date()) -> Decimal {
        let periods = schedule(for: loan)
        guard let last = periods.last(where: { $0.date <= date }) else { return loan.originalPrincipal }
        return last.endingBalance
    }

    /// Total interest still to be paid over the remaining life of the loan.
    public static func remainingInterest(for loan: LoanAccount, asOf date: Date = Date()) -> Decimal {
        schedule(for: loan).filter { $0.date > date }.map(\.interest).total
    }
}
