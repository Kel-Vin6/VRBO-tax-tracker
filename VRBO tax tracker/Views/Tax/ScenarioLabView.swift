//
//  ScenarioLabView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct ScenarioLabView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]
    @Query private var participationEntries: [ParticipationEntry]
    @Query private var payments: [EstimatedTaxPayment]

    @State private var kind: ScenarioKind = .deductibleExpense
    @State private var amount: Decimal = 2_500
    @State private var assetClass: AssetClass = .applianceAndFurniture
    @State private var purchaseDate = Date()
    @State private var extraNights: Int = 10
    @State private var personalDays: Int = 7
    @State private var rateIncreasePercent: Double = 10
    @State private var selectedProperty: Property?

    private var year: Int { appState.taxYear }

    private var report: ScheduleEReport {
        Workspace.report(year: year, properties: properties, expenses: expenses, trips: trips, settings: settings)
    }

    private var metrics: PortfolioMetrics {
        AnalyticsEngine.metrics(
            year: year,
            properties: properties,
            expenses: expenses,
            trips: trips,
            mileageRates: settings.mileageRates,
            report: report
        )
    }

    private var participation: MaterialParticipationAnalysis {
        Workspace.participation(year: year, properties: properties, entries: participationEntries, settings: settings)
    }

    private var estimate: TaxEstimateResult {
        Workspace.estimate(year: year, report: report, participation: participation, payments: payments, settings: settings)
    }

    private var marginalRate: Double {
        settings.useMarginalRateOverride && settings.marginalRateOverride > 0
            ? settings.marginalRateOverride
            : estimate.marginalRatePercent
    }

    private var variableCostPerNight: Decimal {
        let variable = report.totalExpenses - report.totalDepreciation
            - report.amount(for: .mortgageInterest)
            - report.amount(for: .taxes)
            - report.amount(for: .insurance)
        guard metrics.nightsBooked > 0, variable > 0 else { return 0 }
        return (variable / Decimal(metrics.nightsBooked)).rounded(2)
    }

    private var result: ScenarioResult? {
        switch kind {
        case .deductibleExpense:
            return ScenarioEngine.deductibleExpense(
                amount: amount,
                marginalRatePercent: marginalRate,
                stateRatePercent: settings.stateRatePercent
            )
        case .capitalPurchase:
            return ScenarioEngine.capitalPurchase(
                amount: amount,
                assetClass: assetClass,
                purchaseDate: purchaseDate,
                marginalRatePercent: marginalRate,
                stateRatePercent: settings.stateRatePercent
            )
        case .extraBookings:
            return ScenarioEngine.extraBookings(
                nights: extraNights,
                averageDailyRate: metrics.averageDailyRate,
                variableCostPerNight: variableCostPerNight,
                platformFeePercent: metrics.feeDragPercent,
                marginalRatePercent: marginalRate,
                stateRatePercent: settings.stateRatePercent
            )
        case .rateIncrease:
            return ScenarioEngine.rateIncrease(
                percent: rateIncreasePercent,
                currentGrossRents: report.totalRents,
                platformFeePercent: metrics.feeDragPercent,
                marginalRatePercent: marginalRate,
                stateRatePercent: settings.stateRatePercent
            )
        case .personalUseDays:
            guard let property = selectedProperty ?? properties.first else { return nil }
            let analysis = PersonalUseEngine.analyze(
                bookings: property.bookingList,
                personalUse: property.personalUseList,
                year: year,
                propertyID: property.id,
                daysAvailable: property.daysAvailablePerYear
            )
            let column = report.columns.first { $0.id == property.id }
            return ScenarioEngine.personalUse(
                days: personalDays,
                current: analysis,
                averageDailyRate: metrics.averageDailyRate,
                totalAllocableExpenses: column?.totalExpenses ?? 0,
                marginalRatePercent: marginalRate
            )
        case .sellProperty:
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                pickerCard
                inputCard
                if let result {
                    resultCard(result)
                } else if kind == .sellProperty {
                    sellCard
                }
                assumptionsCard
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Scenario lab")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .primaryAction) { YearMenu() } }
        .onAppear {
            if selectedProperty == nil { selectedProperty = properties.first }
        }
    }

    private var pickerCard: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            ForEach(ScenarioKind.allCases) { option in
                Button {
                    kind = option
                    Haptics.play(.selection)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: option.symbol)
                            .font(.subheadline)
                            .foregroundStyle(kind == option ? .white : .tint)
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(kind == option ? .white : .primary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        kind == option ? Color.accentColor : Theme.cardFill,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var inputCard: some View {
        SectionCard(kind.title, subtitle: kind.detail, symbol: kind.symbol) {
            VStack(spacing: 12) {
                switch kind {
                case .deductibleExpense:
                    CurrencyField("Amount you would spend", amount: $amount, isProminent: true)
                case .capitalPurchase:
                    CurrencyField("Purchase price", amount: $amount, isProminent: true)
                    Picker("What is it?", selection: $assetClass) {
                        ForEach(AssetClass.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    DatePicker("Placed in service", selection: $purchaseDate, displayedComponents: .date)
                case .extraBookings:
                    Stepper("\(extraNights) extra night\(extraNights == 1 ? "" : "s")", value: $extraNights, in: 1...200)
                    DetailRow("Your average nightly rate", value: settings.formatted(metrics.averageDailyRate))
                    DetailRow("Variable cost per night", value: settings.formatted(variableCostPerNight), caption: "Cleaning, supplies and commissions, averaged over the nights you sold.")
                case .rateIncrease:
                    PercentField("Rate increase", value: $rateIncreasePercent, range: 0...50)
                    DetailRow("Current gross rents", value: settings.formatted(report.totalRents))
                case .personalUseDays:
                    PropertyPickerField(selection: $selectedProperty, properties: properties)
                    Stepper("\(personalDays) personal day\(personalDays == 1 ? "" : "s")", value: $personalDays, in: 1...60)
                case .sellProperty:
                    PropertyPickerField(selection: $selectedProperty, properties: properties)
                    Text("Open a property and choose “Estimate a sale” to model depreciation recapture, the gain and what actually reaches your account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resultCard(_ result: ScenarioResult) -> some View {
        SectionCard(symbol: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                Text(result.headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(result.breakdown) { line in
                        DetailRow(
                            line.label,
                            value: settings.formatted(line.amount),
                            caption: line.detail,
                            isEmphasised: line.isSubtotal
                        )
                    }
                }

                Text(result.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(result.warnings, id: \.self) { warning in
                    InfoCallout(level: .caution, message: warning)
                }
            }
        }
    }

    @ViewBuilder
    private var sellCard: some View {
        if let property = selectedProperty {
            let accumulated = property.allDepreciationSpecs.reduce(Decimal.zero) {
                $0 + DepreciationEngine.schedule(for: $1).accumulated(throughYear: year)
            }
            NavigationLink {
                SaleEstimatorView(property: property, accumulatedDepreciation: accumulated)
            } label: {
                SectionCard("Model a sale of \(property.displayName)", symbol: "house.badge.minus") {
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow("Depreciation taken so far", value: settings.formatted(accumulated))
                        DetailRow("Original basis", value: settings.formatted(property.totalBasis))
                        Text("Open the sale estimator to see the recapture, the capital gain and the cash that reaches you.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var assumptionsCard: some View {
        SectionCard("Assumptions", symbol: "gearshape") {
            VStack(spacing: 8) {
                DetailRow(
                    "Marginal federal rate",
                    value: Fmt.percent(marginalRate),
                    caption: settings.useMarginalRateOverride
                        ? "Your override from Settings."
                        : "From your projected taxable income of \(settings.formatted(estimate.taxableIncome))."
                )
                DetailRow("State rate", value: Fmt.percent(settings.stateRatePercent))
                DetailRow("Platform fee drag", value: Fmt.percent(metrics.feeDragPercent))
                Text("Every figure here is modelled against this year's actual records, not a template. Change your tax profile in Settings and these move with it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
