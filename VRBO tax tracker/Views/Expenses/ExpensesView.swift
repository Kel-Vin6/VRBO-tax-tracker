//
//  ExpensesView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct ExpensesView: View {

    enum Filter: String, CaseIterable, Identifiable {
        case all, missingReceipt, needsReview, capitalised, portfolio

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .missingReceipt: "No receipt"
            case .needsReview: "Needs review"
            case .capitalised: "Capitalised"
            case .portfolio: "Portfolio-wide"
            }
        }
    }

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query private var recurringRules: [RecurringExpenseRule]

    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var lineFilter: ScheduleELine?
    @State private var propertyFilter: UUID?
    @State private var editing: Expense?

    private var year: Int { appState.taxYear }

    private var yearExpenses: [Expense] {
        allExpenses.filter { DateMath.contains($0.date, inYear: year) }
    }

    private var filtered: [Expense] {
        yearExpenses.filter { expense in
            switch filter {
            case .all: break
            case .missingReceipt:
                if expense.hasReceipt || expense.amount < AuditReadinessEngine.receiptThreshold { return false }
            case .needsReview:
                if !expense.needsImprovementReview { return false }
            case .capitalised:
                if !expense.isCapitalImprovement { return false }
            case .portfolio:
                if !expense.isSplitAcrossPortfolio { return false }
            }
            if let lineFilter, expense.scheduleELine != lineFilter { return false }
            if let propertyFilter, expense.property?.id != propertyFilter { return false }
            if !searchText.isEmpty {
                let haystack = [
                    expense.vendor,
                    expense.displayCategory,
                    expense.notes,
                    expense.receiptRecognizedText
                ].joined(separator: " ").lowercased()
                if !haystack.contains(searchText.lowercased()) { return false }
            }
            return true
        }
    }

    private struct MonthGroup: Identifiable {
        let id: Date
        let expenses: [Expense]
        var month: Date { id }
    }

    private var grouped: [MonthGroup] {
        let groups = Dictionary(grouping: filtered) { expense -> Date in
            let components = DateMath.calendar.dateComponents([.year, .month], from: expense.date)
            return DateMath.calendar.date(from: components) ?? expense.date
        }
        return groups.keys.sorted(by: >).map { key in
            MonthGroup(id: key, expenses: groups[key]?.sorted { $0.date > $1.date } ?? [])
        }
    }

    private var pendingRules: [RecurringExpenseRule] {
        recurringRules.filter { $0.isDue && !$0.autoPost }
    }

    private var totalDeductible: Decimal { filtered.map(\.deductibleAmount).total }
    private var missingReceiptCount: Int {
        yearExpenses.filter { $0.amount >= AuditReadinessEngine.receiptThreshold && !$0.hasReceipt }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if allExpenses.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Expenses")
            .searchable(text: $searchText, prompt: "Vendor, note or receipt text")
            .toolbar { toolbar }
            .sheet(item: $editing) { expense in
                ExpenseEditorView(expense: expense)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        summaryPill("Deductible", settings.formattedCompact(totalDeductible), .orange)
                        summaryPill("Entries", "\(filtered.count)", .blue)
                        summaryPill("No receipt", "\(missingReceiptCount)", missingReceiptCount > 0 ? .red : .green)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases) { option in
                                Button {
                                    filter = option
                                    Haptics.play(.selection)
                                } label: {
                                    Text(option.title)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            filter == option ? Color.accentColor : Theme.nestedFill,
                                            in: Capsule()
                                        )
                                        .foregroundStyle(filter == option ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            }

            if !pendingRules.isEmpty {
                Section("Recurring bills due") {
                    ForEach(pendingRules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.vendor.isEmpty ? rule.category.title : rule.vendor)
                                    .font(.subheadline.weight(.medium))
                                Text("\(rule.cadence.title) · due \(Fmt.shortDate(rule.nextDueDate))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(settings.formatted(rule.amount))
                                .font(.subheadline)
                                .monospacedDigit()
                            Button("Post") {
                                RecurringExpenseRunner.post(rule, context: context)
                                Haptics.play(.success)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .swipeActions {
                            Button("Skip") {
                                RecurringExpenseRunner.skip(rule, context: context)
                            }
                            .tint(.gray)
                        }
                    }
                }
            }

            if filtered.isEmpty {
                Section {
                    Text("No expenses match the current filters for \(year).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(grouped) { group in
                Section {
                    ForEach(group.expenses) { expense in
                        Button { editing = expense } label: {
                            ExpenseRow(expense: expense, settings: settings)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                context.delete(expense)
                                try? context.save()
                                Haptics.play(.warning)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        Text(settings.formattedCompact(group.expenses.map(\.deductibleAmount).total))
                            .monospacedDigit()
                    }
                }
            }
        }
        .platformListStyle()
    }

    private func summaryPill(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardSurface(radius: 12)
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "creditcard",
            title: "No expenses yet",
            message: "Scan a receipt, add a cost by hand, or import a bank statement. Every expense lands on a numbered line of Schedule E automatically.",
            actionTitle: "Scan a receipt"
        ) {
            appState.open(.scanReceipt)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    appState.open(.scanReceipt)
                } label: {
                    Label("Scan a receipt", systemImage: "doc.viewfinder")
                }
                Button {
                    appState.open(.expense)
                } label: {
                    Label("Add manually", systemImage: "square.and.pencil")
                }
                NavigationLink {
                    ImportView(kind: .expenses)
                } label: {
                    Label("Import a statement", systemImage: "square.and.arrow.down")
                }
                NavigationLink {
                    RecurringExpensesView()
                } label: {
                    Label("Recurring bills", systemImage: "repeat")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .principal) { YearMenu() }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker("Schedule E line", selection: $lineFilter) {
                    Text("All lines").tag(ScheduleELine?.none)
                    ForEach(ScheduleELine.allCases) { line in
                        Text(line.label).tag(ScheduleELine?.some(line))
                    }
                }
                Picker("Property", selection: $propertyFilter) {
                    Text("All properties").tag(UUID?.none)
                    ForEach(properties) { property in
                        Text(property.displayName).tag(UUID?.some(property.id))
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.nestedFill)
                    .frame(width: 34, height: 34)
                Image(systemName: expense.category.symbol)
                    .font(.footnote)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.displayVendor)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(expense.displayCategory)
                    Text("· line \(expense.scheduleELine.rawValue)")
                    if let property = expense.property {
                        Text("· \(property.displayName)").lineLimit(1)
                    } else if expense.isSplitAcrossPortfolio {
                        Text("· portfolio")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(spacing: 6) {
                    if expense.businessUsePercent < 100 {
                        TagChip("\(Fmt.percent(expense.businessUsePercent, fractionDigits: 0)) business", tint: .blue)
                    }
                    if expense.isCapitalImprovement {
                        TagChip("Capitalised", symbol: "calendar.badge.clock", tint: .purple)
                    }
                    if expense.needsImprovementReview {
                        TagChip("Review", symbol: "questionmark.circle", tint: .orange)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(settings.formatted(expense.amount))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    Text(Fmt.dayMonth(expense.date))
                    Image(systemName: expense.hasReceipt ? "paperclip" : "paperclip.badge.ellipsis")
                        .foregroundStyle(expense.hasReceipt ? .green : .secondary)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
