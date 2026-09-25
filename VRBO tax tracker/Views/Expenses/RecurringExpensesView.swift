//
//  RecurringExpensesView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct RecurringExpensesView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \RecurringExpenseRule.nextDueDate) private var rules: [RecurringExpenseRule]
    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var editing: RecurringExpenseRule?
    @State private var showingNew = false

    private var annualTotal: Decimal {
        rules.filter(\.isEnabled).map(\.annualizedAmount).total
    }

    var body: some View {
        Group {
            if rules.isEmpty {
                EmptyStateView(
                    symbol: "repeat",
                    title: "No recurring bills",
                    message: "Internet, insurance, HOA dues, your pricing tool — anything you pay on a schedule. The app posts each one when it comes due so nothing is quietly forgotten in December.",
                    actionTitle: "Add a recurring bill"
                ) { showingNew = true }
            } else {
                List {
                    Section {
                        DetailRow(
                            "Committed each year",
                            value: settings.formatted(annualTotal),
                            caption: "Across \(rules.filter(\.isEnabled).count) active rule\(rules.filter(\.isEnabled).count == 1 ? "" : "s").",
                            isEmphasised: true
                        )
                    }
                    Section("Rules") {
                        ForEach(rules) { rule in
                            Button { editing = rule } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: rule.category.symbol)
                                        .font(.footnote)
                                        .foregroundStyle(rule.isEnabled ? .tint : .secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rule.vendor.isEmpty ? rule.category.title : rule.vendor)
                                            .font(.subheadline.weight(.medium))
                                        HStack(spacing: 5) {
                                            Text(rule.cadence.title)
                                            Text("· next \(Fmt.shortDate(rule.nextDueDate))")
                                            if rule.autoPost { Text("· auto") }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(settings.formatted(rule.amount))
                                            .font(.subheadline)
                                            .monospacedDigit()
                                        Text("\(settings.formattedCompact(rule.annualizedAmount))/yr")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .opacity(rule.isEnabled ? 1 : 0.5)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(rule)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    rule.isEnabled.toggle()
                                    try? context.save()
                                } label: {
                                    Label(rule.isEnabled ? "Pause" : "Resume", systemImage: rule.isEnabled ? "pause" : "play")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
                .platformListStyle()
            }
        }
        .navigationTitle("Recurring bills")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNew) { RecurringExpenseEditorView(rule: nil) }
        .sheet(item: $editing) { rule in RecurringExpenseEditorView(rule: rule) }
    }
}

struct RecurringExpenseEditorView: View {

    let rule: RecurringExpenseRule?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var vendor = ""
    @State private var amount: Decimal = 0
    @State private var category: ExpenseCategory = .internet
    @State private var cadence: RecurrenceCadence = .monthly
    @State private var property: Property?
    @State private var allocation: ExpenseAllocation = .singleProperty
    @State private var businessUsePercent: Double = 100
    @State private var startDate = Date()
    @State private var nextDueDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var isEnabled = true
    @State private var autoPost = false
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LiveSummaryStrip(items: [
                        .init(label: "Each time", value: settings.formatted(amount)),
                        .init(
                            label: "Per year",
                            value: settings.formatted(amount * Decimal(cadence.occurrencesPerYear)),
                            tint: .orange
                        ),
                        .init(label: "Line", value: "\(category.scheduleELine.rawValue)")
                    ])
                }

                Section("Bill") {
                    TextField("Vendor", text: $vendor)
                    CurrencyField("Amount", amount: $amount, isProminent: true)
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.grouped) { group in
                            Section(group.line.label) {
                                ForEach(group.categories) { option in
                                    Label(option.title, systemImage: option.symbol).tag(option)
                                }
                            }
                        }
                    }
                    Picker("How often", selection: $cadence) {
                        ForEach(RecurrenceCadence.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                Section("Schedule") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    DatePicker("Next due", selection: $nextDueDate, displayedComponents: .date)
                    Toggle("Has an end date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                    Toggle("Active", isOn: $isEnabled)
                    Toggle("Post automatically when due", isOn: $autoPost)
                    Text(autoPost
                         ? "The expense is created for you when the date arrives."
                         : "The bill appears in your expense list to confirm, so nothing is invented on your behalf.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Allocation") {
                    Picker("Charge to", selection: $allocation) {
                        ForEach(ExpenseAllocation.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    if allocation == .singleProperty {
                        PropertyPickerField(selection: $property, properties: properties)
                    }
                    PercentField("Business use", value: $businessUsePercent)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
                }

                if rule != nil {
                    Section {
                        Button(role: .destructive) {
                            if let rule { context.delete(rule) }
                            try? context.save()
                            dismiss()
                        } label: {
                            Label("Delete rule", systemImage: "trash")
                        }
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle(rule == nil ? "New recurring bill" : "Edit recurring bill")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount <= 0)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let rule else {
            property = properties.first { $0.id == settings.defaultPropertyID } ?? properties.first
            return
        }
        vendor = rule.vendor
        amount = rule.amount
        category = rule.category
        cadence = rule.cadence
        property = rule.property
        allocation = rule.allocation
        businessUsePercent = rule.businessUsePercent
        startDate = rule.startDate
        nextDueDate = rule.nextDueDate
        if let date = rule.endDate {
            endDate = date
            hasEndDate = true
        }
        isEnabled = rule.isEnabled
        autoPost = rule.autoPost
        notes = rule.notes
    }

    private func save() {
        let target = rule ?? RecurringExpenseRule()
        if rule == nil { context.insert(target) }
        target.vendor = vendor
        target.amount = amount
        target.category = category
        target.cadence = cadence
        target.property = allocation == .singleProperty ? property : nil
        target.allocation = allocation
        target.businessUsePercent = businessUsePercent.clampedPercent
        target.startDate = startDate
        target.nextDueDate = nextDueDate
        target.endDate = hasEndDate ? endDate : nil
        target.isEnabled = isEnabled
        target.autoPost = autoPost
        target.notes = notes
        try? context.save()
        Haptics.play(.success)
        dismiss()
    }
}
