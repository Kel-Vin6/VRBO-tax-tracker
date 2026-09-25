//
//  ExpenseEditorView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct ExpenseEditorView: View {

    let expense: Expense?
    var startWithScanner: Bool = false
    var prefilledProperty: Property?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var allExpenses: [Expense]

    @State private var date = Date()
    @State private var vendor = ""
    @State private var amount: Decimal = 0
    @State private var category: ExpenseCategory = .suppliesGuest
    @State private var customCategoryName = ""
    @State private var property: Property?
    @State private var allocation: ExpenseAllocation = .singleProperty
    @State private var businessUsePercent: Double = 100
    @State private var paymentMethod: PaymentMethod = .businessCreditCard
    @State private var isCapitalImprovement = false
    @State private var deMinimisElected = false
    @State private var notes = ""
    @State private var receiptData: Data?
    @State private var receiptFileName = ""
    @State private var recognizedText = ""
    @State private var source: EntrySource = .manual

    @State private var showingDeleteConfirmation = false
    @State private var showingImprovementAdvisor = false
    @State private var scannerHint: String?

    private var isEditing: Bool { expense != nil }

    private var deductible: Decimal {
        guard !isCapitalImprovement else { return 0 }
        return amount
            .applying(percent: businessUsePercent.clampedPercent)
            .applying(percent: category.statutoryDeductiblePercent)
    }

    private var taxSaving: Decimal {
        let rate = settings.useMarginalRateOverride && settings.marginalRateOverride > 0
            ? settings.marginalRateOverride
            : 22
        return deductible.applying(percent: (rate + settings.stateRatePercent).clampedPercent)
    }

    /// Total already spent on this property's building this year, which the
    /// small taxpayer safe harbor is measured against.
    private var buildingSpendThisYear: Decimal {
        guard let property else { return amount }
        let year = DateMath.year(of: date)
        let existing = allExpenses
            .filter {
                $0.property?.id == property.id
                && DateMath.contains($0.date, inYear: year)
                && ($0.category.invitesImprovementReview || $0.isCapitalImprovement)
                && $0.id != expense?.id
            }
            .map(\.amount)
            .total
        return existing + amount
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                amountSection
                categorySection
                allocationSection
                if category.invitesImprovementReview || isCapitalImprovement {
                    improvementSection
                }
                receiptSection
                notesSection
                if isEditing { deleteSection }
            }
            .platformFormStyle()
            .navigationTitle(isEditing ? "Edit expense" : "New expense")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amount <= 0)
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showingImprovementAdvisor) {
                NavigationStack {
                    ImprovementAdvisorView(
                        amount: amount,
                        descriptionText: "\(vendor) \(notes)",
                        property: property,
                        buildingSpendThisYear: buildingSpendThisYear
                    ) { shouldCapitalize in
                        isCapitalImprovement = shouldCapitalize
                        if !shouldCapitalize { deMinimisElected = amount <= 2_500 }
                    }
                }
            }
            .confirmationDialog(
                "Delete this expense?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete expense", role: .destructive) { deleteExpense() }
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            LiveSummaryStrip(items: [
                .init(label: "Deductible", value: settings.formatted(deductible), tint: .orange),
                .init(label: "Schedule E", value: "Line \(category.scheduleELine.rawValue)"),
                .init(label: "Tax saved", value: settings.formatted(taxSaving), tint: .green)
            ])
            if isCapitalImprovement {
                InfoCallout(
                    level: .info,
                    message: "Capitalised costs are not deducted this year. Save this, then add it as an asset on the property so the depreciation schedule picks it up."
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            if category == .travelMeals {
                InfoCallout(
                    level: .caution,
                    message: "Business meals are 50% deductible, so half of what you enter reaches Schedule E."
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
    }

    private var amountSection: some View {
        Section("Amount") {
            CurrencyField("Total paid", amount: $amount, isProminent: true)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Vendor or description", text: $vendor)
                .onChange(of: vendor) { _, newValue in
                    guard !isEditing, newValue.count >= 4,
                          let guess = CategoryGuesser.guess(vendor: newValue) else { return }
                    category = guess
                }
            Picker("Paid with", selection: $paymentMethod) {
                ForEach(PaymentMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            if paymentMethod == .cash && receiptData == nil {
                Text("Cash leaves no bank trail. Attach the receipt and this deduction stops being contestable.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var categorySection: some View {
        Section {
            Picker("Category", selection: $category) {
                ForEach(ExpenseCategory.grouped) { group in
                    Section(group.line.label) {
                        ForEach(group.categories) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                }
            }
            TextField("Rename on reports (optional)", text: $customCategoryName)
        } header: {
            Text("Category")
        } footer: {
            Text("Reports as “\(category.scheduleELine.label)”.")
                .font(.caption2)
        }
    }

    private var allocationSection: some View {
        Section {
            Picker("Charge to", selection: $allocation) {
                ForEach(ExpenseAllocation.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            if allocation == .singleProperty {
                PropertyPickerField(selection: $property, properties: properties)
            } else {
                Text(allocation.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            PercentField(
                "Business use",
                value: $businessUsePercent,
                caption: businessUsePercent < 100
                    ? "Only \(settings.formatted(amount.applying(percent: businessUsePercent))) of this is claimed. Enter the full amount so the receipt still ties to your statement."
                    : "Set below 100% for anything you also use personally, such as a phone or internet line."
            )
        } header: {
            Text("Allocation")
        }
    }

    private var improvementSection: some View {
        Section {
            Toggle("Capitalise instead of deducting", isOn: $isCapitalImprovement)
            Button {
                showingImprovementAdvisor = true
            } label: {
                Label("Work out repair or improvement", systemImage: "arrow.triangle.branch")
            }
            if !isCapitalImprovement {
                Toggle("De minimis safe harbor elected", isOn: $deMinimisElected)
                if amount > RepairVsImprovementAdvisor.deMinimisLimitWithoutAFS && deMinimisElected {
                    Text("Over the \(settings.formatted(RepairVsImprovementAdvisor.deMinimisLimitWithoutAFS)) per-item limit, so this election will not hold on its own.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Repair or improvement")
        } footer: {
            Text("A repair comes off this year's income in full. An improvement is written off over 27.5 years. Getting it right is usually worth more than everything else on this screen.")
                .font(.caption2)
        }
    }

    private var receiptSection: some View {
        Section {
            ReceiptAttachmentView(
                data: $receiptData,
                fileName: $receiptFileName,
                onRecognized: { scanned in apply(scanned) },
                autoStartScanner: startWithScanner
            )
            if let scannerHint {
                Text(scannerHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Receipt")
        } footer: {
            Text("Substantiation is required at \(settings.formatted(AuditReadinessEngine.receiptThreshold)) and above. Text is read on device — the photo never leaves this phone.")
                .font(.caption2)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("What this was for", text: $notes, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete expense", systemImage: "trash")
            }
        }
    }

    // MARK: - Scanner result

    private func apply(_ scanned: ScannedReceipt) {
        var applied: [String] = []
        if let total = scanned.suggestedTotal, amount == 0 {
            amount = total
            applied.append("amount")
        }
        if let scannedDate = scanned.suggestedDate {
            date = scannedDate
            applied.append("date")
        }
        if let merchant = scanned.suggestedVendor, vendor.isEmpty {
            vendor = merchant
            applied.append("vendor")
        }
        if let guessed = scanned.suggestedCategory, !isEditing {
            category = guessed
            applied.append("category")
        }
        recognizedText = scanned.recognizedText
        source = .receiptScan

        scannerHint = applied.isEmpty
            ? "Receipt saved and made searchable, but nothing could be filled in automatically."
            : "Filled in the \(applied.joined(separator: ", ")) from the receipt. Check them before saving."
    }

    // MARK: - Load & save

    private func load() {
        guard let expense else {
            property = prefilledProperty
                ?? properties.first { $0.id == settings.defaultPropertyID }
                ?? properties.first
            paymentMethod = settings.defaultPaymentMethod
            return
        }
        date = expense.date
        vendor = expense.vendor
        amount = expense.amount
        category = expense.category
        customCategoryName = expense.customCategoryName
        property = expense.property
        allocation = expense.allocation
        businessUsePercent = expense.businessUsePercent
        paymentMethod = expense.paymentMethod
        isCapitalImprovement = expense.isCapitalImprovement
        deMinimisElected = expense.deMinimisElected
        notes = expense.notes
        receiptData = expense.receiptData
        receiptFileName = expense.receiptFileName
        recognizedText = expense.receiptRecognizedText
        source = expense.source
    }

    private func save() {
        let target = expense ?? Expense()
        if expense == nil { context.insert(target) }

        target.date = date
        target.vendor = vendor
        target.amount = amount
        target.category = category
        target.customCategoryName = customCategoryName
        target.property = allocation == .singleProperty ? property : nil
        target.allocation = allocation
        target.businessUsePercent = businessUsePercent.clampedPercent
        target.paymentMethod = paymentMethod
        target.isCapitalImprovement = isCapitalImprovement
        target.deMinimisElected = deMinimisElected
        target.notes = notes
        target.receiptData = receiptData
        target.receiptFileName = receiptFileName
        target.receiptContentType = receiptData == nil ? "" : "image/jpeg"
        target.receiptRecognizedText = recognizedText
        target.source = source
        target.touch()

        try? context.save()
        Haptics.play(.success)
        dismiss()
    }

    private func deleteExpense() {
        guard let expense else { return }
        context.delete(expense)
        try? context.save()
        Haptics.play(.warning)
        dismiss()
    }
}
