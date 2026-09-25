//
//  RecurringExpenseRunner.swift
//  VRBO tax tracker
//
//  Posts recurring bills when they come due. Rules that are not marked
//  auto-post are left for the user to confirm, because an invented transaction
//  is worse than a missing one.
//

import Foundation
import SwiftData

public enum RecurringExpenseRunner {

    /// Guards against generating a runaway backlog from a rule that has been
    /// dormant for years.
    private static let maximumPostsPerRule = 24

    @discardableResult
    public static func runIfNeeded(context: ModelContext, settings: AppSettings) -> Int {
        guard settings.autoRunRecurringRules else { return 0 }

        let descriptor = FetchDescriptor<RecurringExpenseRule>(
            predicate: #Predicate { $0.isEnabled && $0.autoPost }
        )
        guard let rules = try? context.fetch(descriptor) else { return 0 }

        var posted = 0
        for rule in rules {
            var iterations = 0
            while rule.isDue && iterations < maximumPostsPerRule {
                let expense = rule.makeExpense(on: rule.nextDueDate)
                context.insert(expense)
                rule.advance()
                posted += 1
                iterations += 1
            }
        }

        if posted > 0 {
            try? context.save()
        }
        return posted
    }

    /// Rules that are due but waiting for the user to confirm them.
    public static func pendingRules(context: ModelContext) -> [RecurringExpenseRule] {
        let descriptor = FetchDescriptor<RecurringExpenseRule>(
            predicate: #Predicate { $0.isEnabled }
        )
        let rules = (try? context.fetch(descriptor)) ?? []
        return rules.filter { $0.isDue && !$0.autoPost }
    }

    @discardableResult
    public static func post(_ rule: RecurringExpenseRule, context: ModelContext) -> Expense {
        let expense = rule.makeExpense(on: rule.nextDueDate)
        context.insert(expense)
        rule.advance()
        try? context.save()
        return expense
    }

    public static func skip(_ rule: RecurringExpenseRule, context: ModelContext) {
        rule.advance()
        try? context.save()
    }
}
