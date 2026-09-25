//
//  SaleEstimatorView.swift
//  VRBO tax tracker
//
//  Depreciation recapture is the bill nobody sees coming. Modelling it years
//  before a sale is the difference between a planned exit and a surprise.
//

import SwiftUI

struct SaleEstimatorView: View {

    let property: Property
    let accumulatedDepreciation: Decimal

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var salePrice: Decimal = 0
    @State private var sellingCostPercent: Double = 7
    @State private var recaptureRate: Double = 25
    @State private var capitalGainsRate: Double = 15
    @State private var mortgagePayoff: Decimal = 0

    private var sellingCosts: Decimal {
        salePrice.applying(percent: sellingCostPercent.clampedPercent)
    }

    private var estimate: DepreciationEngine.RecaptureEstimate {
        DepreciationEngine.estimateRecapture(
            accumulatedDepreciation: accumulatedDepreciation,
            originalBasis: property.totalBasis,
            salePrice: salePrice,
            sellingCosts: sellingCosts,
            recaptureRate: recaptureRate,
            capitalGainsRate: capitalGainsRate
        )
    }

    private var netToOwner: Decimal {
        salePrice - sellingCosts - mortgagePayoff - estimate.estimatedTotalTax
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LiveSummaryStrip(items: [
                        .init(label: "Tax on sale", value: settings.formattedCompact(estimate.estimatedTotalTax), tint: .orange),
                        .init(label: "Gain", value: settings.formattedCompact(estimate.totalGain)),
                        .init(label: "Net to you", value: settings.formattedCompact(netToOwner), tint: Theme.resultColor(netToOwner))
                    ])
                }

                Section("The sale") {
                    CurrencyField("Sale price", amount: $salePrice, isProminent: true)
                    PercentField("Selling costs", value: $sellingCostPercent, caption: "Agent commission, transfer tax and closing costs. \(settings.formatted(sellingCosts)).", range: 0...15)
                    CurrencyField("Mortgage payoff", amount: $mortgagePayoff, caption: "Not a tax item, but it decides what reaches your account.")
                }

                Section {
                    DetailRow("Original basis", value: settings.formatted(property.totalBasis))
                    DetailRow(
                        "Depreciation taken",
                        value: settings.formatted(accumulatedDepreciation),
                        caption: "Reduces your basis whether or not you claimed it."
                    )
                    DetailRow("Adjusted basis", value: settings.formatted(estimate.adjustedBasis), isEmphasised: true)
                } header: {
                    Text("Basis")
                }

                Section {
                    DetailRow("Total gain", value: settings.formatted(estimate.totalGain), isEmphasised: true)
                    DetailRow(
                        "Unrecaptured §1250 gain",
                        value: settings.formatted(estimate.section1250Gain),
                        caption: "The depreciation you took, taxed at up to 25% rather than the long-term capital gains rate."
                    )
                    DetailRow("Long-term capital gain", value: settings.formatted(estimate.capitalGain))
                    PercentField("Recapture rate", value: $recaptureRate, range: 0...37)
                    PercentField("Capital gains rate", value: $capitalGainsRate, range: 0...37)
                } header: {
                    Text("Gain")
                }

                Section {
                    DetailRow("Recapture tax", value: settings.formatted(estimate.estimatedRecaptureTax), valueColor: .orange)
                    DetailRow("Capital gains tax", value: settings.formatted(estimate.estimatedCapitalGainsTax), valueColor: .orange)
                    DetailRow(
                        "Total tax on the sale",
                        value: settings.formatted(estimate.estimatedTotalTax),
                        isEmphasised: true,
                        valueColor: .red
                    )
                    DetailRow(
                        "Cash to you after payoff",
                        value: settings.formatted(netToOwner),
                        isEmphasised: true,
                        valueColor: Theme.resultColor(netToOwner)
                    )
                } header: {
                    Text("The bill")
                } footer: {
                    Text("State tax, the 3.8% net investment income tax and any suspended passive losses released on sale are not included here. A 1031 exchange can defer all of this — worth discussing with your accountant well before you list.")
                        .font(.caption2)
                }
            }
            .platformFormStyle()
            .navigationTitle("If you sold")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if salePrice == 0 { salePrice = property.totalBasis }
                if mortgagePayoff == 0 {
                    mortgagePayoff = property.loanList
                        .map { LoanAmortizationEngine.balance(for: $0) }
                        .total
                }
            }
        }
    }
}
