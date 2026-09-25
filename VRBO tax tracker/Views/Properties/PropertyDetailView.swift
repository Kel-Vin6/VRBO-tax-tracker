//
//  PropertyDetailView.swift
//  VRBO tax tracker
//

import Charts
import SwiftData
import SwiftUI

struct PropertyDetailView: View {

    let property: Property

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query private var allExpenses: [Expense]
    @Query private var allTrips: [MileageTrip]

    @State private var editingProperty = false
    @State private var editingAsset: DepreciableAsset?
    @State private var addingAsset = false
    @State private var editingLoan: LoanAccount?
    @State private var addingLoan = false
    @State private var showingRecapture = false

    private var year: Int { appState.taxYear }

    private var column: ScheduleEColumn? {
        Workspace.report(
            year: year,
            properties: [property],
            expenses: allExpenses,
            trips: allTrips,
            settings: settings
        ).columns.first
    }

    private var analysis: PersonalUseAnalysis {
        PersonalUseEngine.analyze(
            bookings: property.bookingList,
            personalUse: property.personalUseList,
            year: year,
            propertyID: property.id,
            daysAvailable: property.daysAvailablePerYear
        )
    }

    private var specs: [DepreciationSpec] { property.allDepreciationSpecs }

    private var accumulatedDepreciation: Decimal {
        specs.reduce(Decimal.zero) { running, spec in
            running + DepreciationEngine.schedule(for: spec).accumulated(throughYear: year)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if let column { performanceCard(column) }
                dayCountCard
                depreciationCard
                assetsCard
                loansCard
                complianceCard
                TaxDisclaimer()
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle(property.displayName)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editingProperty = true } label: {
                        Label("Edit property", systemImage: "pencil")
                    }
                    Button { addingAsset = true } label: {
                        Label("Add an asset", systemImage: "shippingbox")
                    }
                    Button { addingLoan = true } label: {
                        Label("Add a loan", systemImage: "banknote")
                    }
                    Button { showingRecapture = true } label: {
                        Label("Estimate a sale", systemImage: "house.badge.minus")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editingProperty) { PropertyEditorView(property: property) }
        .sheet(isPresented: $addingAsset) { AssetEditorView(asset: nil, property: property) }
        .sheet(item: $editingAsset) { asset in AssetEditorView(asset: asset, property: property) }
        .sheet(isPresented: $addingLoan) { LoanEditorView(loan: nil, property: property) }
        .sheet(item: $editingLoan) { loan in LoanEditorView(loan: loan, property: property) }
        .sheet(isPresented: $showingRecapture) {
            SaleEstimatorView(
                property: property,
                accumulatedDepreciation: accumulatedDepreciation
            )
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(property.color)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Text(property.monogram)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(property.displayName)
                            .font(.title3.weight(.semibold))
                        Text(property.shortAddress.isEmpty ? property.kind.title : property.shortAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    TagChip(property.kind.title, symbol: "house", tint: property.color)
                    if property.bedrooms > 0 {
                        TagChip("\(property.bedrooms) bed", tint: .secondary)
                    }
                    if property.maxGuests > 0 {
                        TagChip("Sleeps \(property.maxGuests)", tint: .secondary)
                    }
                    if property.ownershipPercent < 100 {
                        TagChip("\(Fmt.percent(property.ownershipPercent, fractionDigits: 0)) owned", tint: .blue)
                    }
                }
            }
        }
    }

    private func performanceCard(_ column: ScheduleEColumn) -> some View {
        SectionCard("\(year) performance", symbol: "chart.bar.xaxis") {
            VStack(spacing: 10) {
                DetailRow("Rents received", value: settings.formatted(column.rentsReceived), isEmphasised: true)
                DetailRow("Total deductions", value: settings.formatted(column.totalExpenses))
                DetailRow("Depreciation", value: settings.formatted(column.depreciationAmount), caption: "Non-cash — it reduces tax without reducing your bank balance.")
                Divider()
                DetailRow(
                    "Net for Schedule E",
                    value: settings.formatted(column.netIncomeOrLoss),
                    isEmphasised: true,
                    valueColor: Theme.resultColor(column.netIncomeOrLoss)
                )
                DetailRow(
                    "Cash kept",
                    value: settings.formatted(column.cashFlow),
                    caption: "Net plus depreciation added back.",
                    valueColor: Theme.resultColor(column.cashFlow)
                )

                if !column.notes.isEmpty {
                    ForEach(column.notes, id: \.self) { note in
                        InfoCallout(level: .caution, message: note)
                    }
                }

                NavigationLink {
                    ScheduleEView()
                } label: {
                    Label("See the full Schedule E", systemImage: "doc.text")
                        .font(.subheadline)
                }
            }
        }
    }

    private var dayCountCard: some View {
        SectionCard(
            "Day counts",
            subtitle: analysis.classification.title,
            symbol: analysis.classification.symbol
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    dayStat("Rental", analysis.fairRentalDays, .green)
                    dayStat("Personal", analysis.personalUseDays, analysis.classification.isFavourable ? .blue : .orange)
                    dayStat("Repair", analysis.repairDays, .teal)
                    dayStat("Vacant", analysis.vacantDays, .secondary)
                }

                if analysis.fairRentalDays > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Personal use against the limit")
                                .font(.caption)
                            Spacer()
                            Text("\(analysis.personalUseDays) of \(analysis.personalUseThreshold)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        ProgressView(value: analysis.thresholdProgress)
                            .tint(analysis.headroomDays >= 0 ? .green : .red)
                        Text(analysis.headroomDays >= 0
                             ? "\(analysis.headroomDays) personal day\(analysis.headroomDays == 1 ? "" : "s") left before this becomes a residence."
                             : "\(abs(analysis.headroomDays)) day\(abs(analysis.headroomDays) == 1 ? "" : "s") over the limit.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(analysis.classification.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink {
                    PersonalUseView(focusedProperty: property)
                } label: {
                    Label("Manage personal-use days", systemImage: "calendar")
                        .font(.subheadline)
                }
            }
        }
    }

    private func dayStat(_ label: String, _ value: Int, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.nestedFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var depreciationCard: some View {
        SectionCard("Depreciation", symbol: "chart.line.downtrend.xyaxis") {
            if specs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No depreciation is being claimed for this property.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if property.placedInServiceDate == nil || property.buildingBasis <= 0 {
                        InfoCallout(
                            level: .caution,
                            title: "Missing basis",
                            message: "Add the purchase price, the land value and the date it was placed in service, and the building starts depreciating automatically."
                        )
                    }
                    Button("Complete the basis") { editingProperty = true }
                        .font(.subheadline)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(specs) { spec in
                        let schedule = DepreciationEngine.schedule(for: spec)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Label(spec.name, systemImage: spec.assetClass.symbol)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(settings.formatted(schedule.deduction(inYear: year)))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            Text("\(Fmt.number(spec.recoveryYears))-year · basis \(settings.formatted(spec.basis)) · claimed \(settings.formatted(schedule.accumulated(throughYear: year)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    DetailRow(
                        "\(year) deduction",
                        value: settings.formatted(specs.reduce(Decimal.zero) {
                            $0 + DepreciationEngine.schedule(for: $1).deduction(inYear: year)
                        }),
                        isEmphasised: true
                    )
                    DetailRow(
                        "Claimed to date",
                        value: settings.formatted(accumulatedDepreciation),
                        caption: "This is the figure that will be recaptured when you sell."
                    )
                    NavigationLink {
                        DepreciationView(property: property)
                    } label: {
                        Label("Full schedule year by year", systemImage: "list.bullet.rectangle")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var assetsCard: some View {
        SectionCard("Assets", subtitle: "Furniture, appliances and improvements", symbol: "shippingbox") {
            VStack(spacing: 10) {
                if property.assetList.isEmpty {
                    Text("Nothing added yet. Beds, appliances, hot tubs and smart locks each depreciate on their own, much faster than the building.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(property.assetList.sorted { $0.placedInService > $1.placedInService }) { asset in
                        Button { editingAsset = asset } label: {
                            HStack {
                                Label(asset.displayName, systemImage: asset.assetClass.symbol)
                                    .font(.subheadline)
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(settings.formatted(asset.cost))
                                        .font(.subheadline)
                                        .monospacedDigit()
                                    Text(Fmt.shortDate(asset.placedInService))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { addingAsset = true } label: {
                    Label("Add an asset", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
        }
    }

    private var loansCard: some View {
        SectionCard("Loans", subtitle: "Mortgage interest, computed", symbol: "banknote") {
            VStack(spacing: 10) {
                if property.loanList.isEmpty {
                    Text("Add your mortgage and the app amortises it, so the deductible interest for any year is known without waiting for Form 1098.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(property.loanList) { loan in
                        Button { editingLoan = loan } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(loan.displayName).font(.subheadline.weight(.medium))
                                    Spacer(minLength: 8)
                                    Text(settings.formatted(LoanAmortizationEngine.interest(for: loan, inYear: year)))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                                Text("\(Fmt.percent(loan.annualRatePercent, fractionDigits: 3)) · balance \(settings.formatted(LoanAmortizationEngine.balance(for: loan))) · \(year) interest")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { addingLoan = true } label: {
                    Label("Add a loan", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
        }
    }

    private var complianceCard: some View {
        let flags = property.complianceFlags()
        return SectionCard("Compliance", symbol: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 10) {
                if flags.isEmpty {
                    Label("Permit and insurance are current.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else {
                    ForEach(flags) { flag in
                        InfoCallout(
                            level: flag.isCritical ? .critical : .caution,
                            message: flag.message
                        )
                    }
                }
                if !property.permitNumber.isEmpty {
                    DetailRow("Permit", value: property.permitNumber)
                }
                if property.lodgingTaxRatePercent > 0 {
                    DetailRow(
                        "Lodging tax",
                        value: Fmt.percent(property.lodgingTaxRatePercent, fractionDigits: 2),
                        caption: property.lodgingTaxRemittedByPlatform
                            ? "Collected and remitted by the platform."
                            : "You collect and remit this yourself."
                    )
                }
            }
        }
    }
}
