//
//  AssetEditorView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct AssetEditorView: View {

    let asset: DepreciableAsset?
    let property: Property

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var name = ""
    @State private var assetClass: AssetClass = .applianceAndFurniture
    @State private var cost: Decimal = 0
    @State private var placedInService = Date()
    @State private var businessUsePercent: Double = 100
    @State private var useCustomRecovery = false
    @State private var recoveryYears: Double = 7
    @State private var bonusPercent: Double = 0
    @State private var useBonus = true
    @State private var section179: Decimal = 0
    @State private var isDisposed = false
    @State private var disposedDate = Date()
    @State private var dispositionProceeds: Decimal = 0
    @State private var notes = ""
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool { asset != nil }

    private var spec: DepreciationSpec {
        DepreciationSpec(
            name: name.isEmpty ? assetClass.title : name,
            assetClass: assetClass,
            basis: cost.applying(percent: businessUsePercent.clampedPercent),
            placedInService: placedInService,
            recoveryYears: useCustomRecovery ? recoveryYears : assetClass.recoveryYears,
            bonusPercent: useBonus ? bonusPercent : 0,
            section179: section179,
            disposedDate: isDisposed ? disposedDate : nil,
            dispositionProceeds: dispositionProceeds,
            propertyID: property.id
        )
    }

    private var schedule: DepreciationSchedule { DepreciationEngine.schedule(for: spec) }

    private var statutoryBonus: Double {
        DepreciationEngine.defaultBonusPercent(acquiredOn: placedInService)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LiveSummaryStrip(items: [
                        .init(
                            label: "Year one",
                            value: settings.formatted(schedule.deduction(inYear: DateMath.year(of: placedInService))),
                            tint: .green
                        ),
                        .init(label: "Basis", value: settings.formatted(spec.basis)),
                        .init(label: "Life", value: "\(Fmt.number(spec.recoveryYears)) yr")
                    ])
                }

                Section("What it is") {
                    TextField("Name", text: $name)
                    Picker("Class", selection: $assetClass) {
                        ForEach(AssetClass.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    .onChange(of: assetClass) { _, newValue in
                        recoveryYears = newValue.recoveryYears
                        if !newValue.isBonusEligible { useBonus = false }
                    }
                    Text(assetClass.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    CurrencyField("Cost", amount: $cost)
                    DatePicker("Placed in service", selection: $placedInService, displayedComponents: .date)
                    PercentField(
                        "Business use",
                        value: $businessUsePercent,
                        caption: "A television used by guests all year is 100%. One you also use yourself is not."
                    )
                }

                Section("Recovery period") {
                    Toggle("Set the recovery period myself", isOn: $useCustomRecovery)
                    if useCustomRecovery {
                        NumberField("Recovery years", value: $recoveryYears, unit: "years")
                    } else {
                        DetailRow(
                            "Recovery period",
                            value: "\(Fmt.number(assetClass.recoveryYears)) years",
                            caption: assetClass.isRealProperty
                                ? "Straight line, mid-month convention."
                                : "\(Int(assetClass.decliningBalanceFactor * 100))% declining balance switching to straight line, half-year convention."
                        )
                    }
                }

                if assetClass.isBonusEligible {
                    Section {
                        Toggle("Claim bonus depreciation", isOn: $useBonus)
                        if useBonus {
                            PercentField("Bonus percentage", value: $bonusPercent)
                            Button("Use the statutory \(Fmt.percent(statutoryBonus, fractionDigits: 0))") {
                                bonusPercent = statutoryBonus
                            }
                            .font(.caption)
                        }
                        CurrencyField(
                            "Section 179 expensing",
                            amount: $section179,
                            caption: "Section 179 is only available if the rental rises to the level of a trade or business. Check this with your accountant."
                        )
                    } header: {
                        Text("First-year deductions")
                    } footer: {
                        Text(DepreciationEngine.bonusExplanation(acquiredOn: placedInService))
                            .font(.caption2)
                    }
                }

                Section("Disposal") {
                    Toggle("Sold, scrapped or replaced", isOn: $isDisposed)
                    if isDisposed {
                        DatePicker("Disposed", selection: $disposedDate, in: placedInService..., displayedComponents: .date)
                        CurrencyField("Proceeds", amount: $dispositionProceeds)
                        Text("Depreciation stops in the year of disposal, with a half year claimed in that final year.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !schedule.rows.isEmpty {
                    Section("Schedule") {
                        ForEach(schedule.rows.prefix(12)) { row in
                            HStack {
                                Text(verbatim: "\(row.year)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .frame(width: 52, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(settings.formatted(row.total))
                                        .font(.subheadline)
                                        .monospacedDigit()
                                    Text(row.methodLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(settings.formatted(row.closingBasis))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if schedule.rows.count > 12 {
                            Text("…and \(schedule.rows.count - 12) more years, through \(schedule.finalYear).")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Model, serial number, where it went", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete asset", systemImage: "trash")
                        }
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle(isEditing ? "Edit asset" : "New asset")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(cost <= 0)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete this asset?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete asset", role: .destructive) { deleteAsset() }
            }
        }
    }

    private func load() {
        guard let asset else {
            bonusPercent = statutoryBonus
            recoveryYears = assetClass.recoveryYears
            return
        }
        name = asset.name
        assetClass = asset.assetClass
        cost = asset.cost
        placedInService = asset.placedInService
        businessUsePercent = asset.businessUsePercent
        useCustomRecovery = asset.recoveryYearsOverride > 0
        recoveryYears = asset.recoveryYears
        bonusPercent = asset.bonusPercent
        useBonus = asset.bonusPercent > 0
        section179 = asset.section179Amount
        if let date = asset.disposedDate {
            disposedDate = date
            isDisposed = true
        }
        dispositionProceeds = asset.dispositionProceeds
        notes = asset.notes
    }

    private func save() {
        let target = asset ?? DepreciableAsset()
        if asset == nil { context.insert(target) }

        target.name = name
        target.assetClass = assetClass
        target.cost = cost
        target.placedInService = placedInService
        target.businessUsePercent = businessUsePercent.clampedPercent
        target.recoveryYearsOverride = useCustomRecovery ? recoveryYears : 0
        target.bonusPercent = useBonus ? bonusPercent.clampedPercent : 0
        target.section179Amount = section179
        target.disposedDate = isDisposed ? disposedDate : nil
        target.dispositionProceeds = dispositionProceeds
        target.notes = notes
        target.property = property

        try? context.save()
        Haptics.play(.success)
        dismiss()
    }

    private func deleteAsset() {
        guard let asset else { return }
        context.delete(asset)
        try? context.save()
        dismiss()
    }
}
