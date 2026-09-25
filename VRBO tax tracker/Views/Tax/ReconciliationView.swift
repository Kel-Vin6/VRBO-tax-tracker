//
//  ReconciliationView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct ReconciliationView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var forms: [PlatformTaxForm]

    @State private var editingForm: PlatformTaxForm?
    @State private var addingPlatform: RentalPlatform?

    private var year: Int { appState.taxYear }

    private var reconciliations: [PlatformReconciliation] {
        ReconciliationEngine.reconcile(
            year: year,
            bookings: properties.flatMap(\.bookingList),
            forms: forms
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                explainerCard
                if reconciliations.isEmpty {
                    EmptyStateView(
                        symbol: "arrow.left.arrow.right",
                        title: "No bookings for \(year)",
                        message: "Once there are bookings, the app rebuilds what each platform should have reported and compares it to the 1099-K you enter."
                    )
                    .frame(minHeight: 240)
                } else {
                    ForEach(reconciliations) { item in
                        reconciliationCard(item)
                    }
                }
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("1099-K reconciliation")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .primaryAction) { YearMenu() } }
        .sheet(item: $editingForm) { form in
            FormEditorSheet(form: form, year: year)
        }
        .sheet(item: $addingPlatform) { platform in
            FormEditorSheet(form: nil, year: year, platform: platform)
        }
    }

    private var explainerCard: some View {
        SectionCard("Why the numbers never match", symbol: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 10) {
                Text("A 1099-K reports what guests were charged, not what you were paid. It usually includes the occupancy tax the platform remitted for you and is always before the platform's own fee. Your Schedule E shows something smaller, and the matching program notices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Reconciling the two takes five minutes and turns a letter into a non-event. It also catches the fees hosts forget to deduct — which is money, not paperwork.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reconciliationCard(_ item: PlatformReconciliation) -> some View {
        SectionCard(
            item.platform.title,
            subtitle: item.status,
            symbol: item.platform.symbol
        ) {
            VStack(spacing: 10) {
                ForEach(item.lines) { line in
                    DetailRow(
                        line.label,
                        value: settings.formatted(line.amount),
                        caption: line.detail,
                        isEmphasised: line.isSubtotal
                    )
                }

                if item.hasForm {
                    Divider()
                    DetailRow(
                        "Variance",
                        value: settings.formatted(item.variance),
                        isEmphasised: true,
                        valueColor: item.isReconciled ? .green : .orange
                    )
                }

                InfoCallout(
                    level: item.hasForm ? (item.isReconciled ? .success : .caution) : .info,
                    message: item.guidance
                )

                Button {
                    if let form = forms.first(where: { $0.taxYear == year && $0.platform == item.platform }) {
                        editingForm = form
                    } else {
                        addingPlatform = item.platform
                    }
                } label: {
                    Label(
                        item.hasForm ? "Edit the 1099-K figures" : "Enter the 1099-K",
                        systemImage: item.hasForm ? "pencil" : "plus.circle"
                    )
                    .font(.subheadline)
                }
            }
        }
    }
}

private struct FormEditorSheet: View {

    let form: PlatformTaxForm?
    let year: Int
    var platform: RentalPlatform = .airbnb

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var grossAmount: Decimal = 0
    @State private var includesLodgingTax = true
    @State private var includesFees = true
    @State private var payerName = ""
    @State private var payerTIN = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Box 1a") {
                    CurrencyField("Gross amount reported", amount: $grossAmount, isProminent: true)
                    Text("The single largest figure on the form — gross amount of payment transactions.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("How the platform reports") {
                    Toggle("Includes occupancy tax", isOn: $includesLodgingTax)
                    Toggle("Reported before platform fees", isOn: $includesFees)
                }
                Section("Payer") {
                    TextField("Payer name", text: $payerName)
                    TextField("Payer TIN", text: $payerTIN)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                if form != nil {
                    Section {
                        Button(role: .destructive) {
                            if let form { context.delete(form) }
                            try? context.save()
                            dismiss()
                        } label: {
                            Label("Remove this form", systemImage: "trash")
                        }
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle("\(form?.platform.title ?? platform.title) 1099-K")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(grossAmount <= 0)
                }
            }
            .onAppear {
                guard let form else { return }
                grossAmount = form.grossAmountReported
                includesLodgingTax = form.includesLodgingTax
                includesFees = form.includesPlatformFees
                payerName = form.payerName
                payerTIN = form.payerTIN
                notes = form.notes
            }
        }
    }

    private func save() {
        let target = form ?? PlatformTaxForm(taxYear: year, platform: platform)
        if form == nil { context.insert(target) }
        target.grossAmountReported = grossAmount
        target.includesLodgingTax = includesLodgingTax
        target.includesPlatformFees = includesFees
        target.payerName = payerName
        target.payerTIN = payerTIN
        target.notes = notes
        try? context.save()
        Haptics.play(.success)
        dismiss()
    }
}
