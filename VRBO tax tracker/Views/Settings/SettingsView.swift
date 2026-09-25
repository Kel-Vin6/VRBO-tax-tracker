//
//  SettingsView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(AppLockService.self) private var lock

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("You") {
                TextField("Your name", text: $settings.ownerName)
                TextField("Business name", text: $settings.businessName)
            }

            Section {
                NavigationLink {
                    SettingsTaxProfileView()
                } label: {
                    settingsRow("Tax profile", "person.text.rectangle", .blue, detail: "\(settings.filingStatus.shortTitle)\(settings.stateCode.isEmpty ? "" : " · \(settings.stateCode)")")
                }
                NavigationLink {
                    SettingsElectionsView()
                } label: {
                    settingsRow("Methods and elections", "checkmark.seal", .teal, detail: settings.useBoltonAllocation ? "Tax Court method on" : "IRS method")
                }
                NavigationLink {
                    SettingsMileageRatesView()
                } label: {
                    settingsRow("Mileage rates", "car", .indigo, detail: Fmt.number(settings.mileageRates.rate(forYear: appState.taxYear), fractionDigits: 3))
                }
            } header: {
                Text("Tax")
            }

            Section {
                NavigationLink {
                    SettingsAppearanceView()
                } label: {
                    settingsRow("Appearance", settings.theme.symbol, .purple, detail: settings.theme.title)
                }
                NavigationLink {
                    SettingsCaptureDefaultsView()
                } label: {
                    settingsRow("Entry defaults", "square.and.pencil", .orange, detail: settings.defaultPaymentMethod.title)
                }
                NavigationLink {
                    SettingsNotificationsView()
                } label: {
                    settingsRow("Notifications", "bell", .red, detail: settings.notifyQuarterlyTaxes ? "On" : "Off")
                }
            } header: {
                Text("App")
            }

            Section {
                NavigationLink {
                    SettingsSecurityView()
                } label: {
                    settingsRow(
                        "Privacy & security",
                        settings.appLockEnabled ? "lock.fill" : "lock.open",
                        .green,
                        detail: settings.appLockEnabled ? lock.biometry.title : "Off"
                    )
                }
                NavigationLink {
                    SettingsDataView()
                } label: {
                    settingsRow("Data & sync", "icloud", .cyan, detail: settings.iCloudSyncEnabled ? "iCloud on" : "This device")
                }
            } header: {
                Text("Your records")
            }

            Section("Your accountant") {
                TextField("Name", text: $settings.accountantName)
                TextField("Email", text: $settings.accountantEmail)
                    .emailKeyboard()
                Text("Used to address the export package. The app never sends anything on its own.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink {
                    HelpView()
                } label: {
                    settingsRow("How this app works", "questionmark.circle", .gray, detail: nil)
                }
                NavigationLink {
                    AboutView()
                } label: {
                    settingsRow("About", "info.circle", .gray, detail: nil)
                }
            }

            Section {
                TaxDisclaimer(compact: true)
            }
        }
        .platformFormStyle()
        .navigationTitle("Settings")
    }

    private func settingsRow(_ title: String, _ symbol: String, _ tint: Color, detail: String?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            Text(title)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Tax profile

struct SettingsTaxProfileView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState

    private var table: FederalRateTable {
        FederalRates.table(for: appState.taxYear)
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Filing status", selection: $settings.filingStatus) {
                    ForEach(FilingStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                CurrencyField(
                    "Other income",
                    amount: $settings.otherOrdinaryIncome,
                    caption: "Wages, self-employment and everything outside the rentals. The estimator needs this to know your bracket."
                )
                CurrencyField("Federal tax withheld", amount: $settings.federalWithholding)
                Toggle("Itemise deductions", isOn: $settings.useItemizedDeductions)
                if settings.useItemizedDeductions {
                    CurrencyField("Itemised deductions", amount: $settings.itemizedDeductions)
                } else {
                    DetailRow(
                        "Standard deduction",
                        value: settings.formatted(table.standardDeduction(for: settings.filingStatus)),
                        caption: "For \(appState.taxYear), \(settings.filingStatus.title.lowercased())."
                    )
                }
            } header: {
                Text("Income and deductions")
            }

            Section {
                Toggle("Set my marginal rate myself", isOn: $settings.useMarginalRateOverride)
                if settings.useMarginalRateOverride {
                    PercentField("Marginal federal rate", value: $settings.marginalRateOverride, range: 0...50)
                } else {
                    Text("Worked out from the bracket table below and your projected taxable income.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                TextField("State", text: $settings.stateCode)
                PercentField("State income tax rate", value: $settings.stateRatePercent, range: 0...15)
            } header: {
                Text("Rates")
            }

            Section {
                CurrencyField(
                    "Last year's total tax",
                    amount: $settings.priorYearTotalTax,
                    caption: "Line 24 of last year's Form 1040. Unlocks the prior-year safe harbor, which is usually the cheaper of the two."
                )
                CurrencyField(
                    "Last year's AGI",
                    amount: $settings.priorYearAGI,
                    caption: "Above $150,000 the safe harbor rises from 100% to 110%."
                )
                CurrencyField(
                    "Modified AGI",
                    amount: $settings.modifiedAGI,
                    caption: "Used for the $25,000 special allowance, which phases out between $100,000 and $150,000. Leave at zero to use your other income."
                )
            } header: {
                Text("Safe harbor")
            }

            Section {
                Toggle("Subject to net investment income tax", isOn: $settings.subjectToNIIT)
                Toggle("Claim the §199A deduction", isOn: $settings.claimQBIDeduction)
                Toggle("I am a real estate professional", isOn: $settings.isRealEstateProfessional)
                Toggle("I provide hotel-like services", isOn: $settings.providesHotelLikeServices)
                Text("Daily housekeeping during a stay, meals, tours or concierge work can move the whole activity to Schedule C, where it also attracts self-employment tax.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Stepper(
                    "Prior years of material participation: \(settings.priorYearsMateriallyParticipated)",
                    value: $settings.priorYearsMateriallyParticipated,
                    in: 0...10
                )
                Text("Five of the last ten years is itself a material participation test.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Status")
            }

            Section {
                if table.isCarriedForward {
                    InfoCallout(
                        level: .caution,
                        title: "Carried forward from \(FederalRates.latestPublishedYear)",
                        message: "This build has no published table for \(appState.taxYear). Check the figures against the current IRS revenue procedure before relying on the estimate."
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                ForEach(bracketRows, id: \.self) { row in
                    Text(row).font(.caption).monospacedDigit()
                }
            } header: {
                Text("\(appState.taxYear) brackets · \(settings.filingStatus.shortTitle)")
            } footer: {
                Text("Ordinary income brackets used by the estimator.")
                    .font(.caption2)
            }
        }
        .platformFormStyle()
        .navigationTitle("Tax profile")
        .inlineNavigationTitle()
    }

    private var bracketRows: [String] {
        var lower = Decimal.zero
        return table.brackets(for: settings.filingStatus).map { bracket in
            let lowerText = Fmt.currency(lower, code: settings.currencyCode, hideCents: true)
            if let upper = bracket.upperBound {
                let upperText = Fmt.currency(upper, code: settings.currencyCode, hideCents: true)
                lower = upper
                return "\(Fmt.percent(bracket.ratePercent, fractionDigits: 0))   \(lowerText) – \(upperText)"
            }
            return "\(Fmt.percent(bracket.ratePercent, fractionDigits: 0))   \(lowerText) and above"
        }
    }
}

// MARK: - Elections

struct SettingsElectionsView: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Use the Tax Court allocation", isOn: $settings.useBoltonAllocation)
                Text("When a property has personal use, the IRS allocates every expense by rental days ÷ total days used. Courts have allowed mortgage interest and property taxes to be allocated by rental days ÷ days in the year instead, which leaves more of your other expenses available to offset rent. It is a position, not a certainty — agree it with your accountant before you rely on it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("§280A allocation")
            }

            Section {
                Toggle("De minimis safe harbor elected", isOn: $settings.deMinimisElectionInPlace)
                Toggle("I have audited financial statements", isOn: $settings.hasAuditedFinancialStatements)
                Text(settings.hasAuditedFinancialStatements
                     ? "The per-item limit is $5,000."
                     : "The per-item limit is $2,500. The election is made annually with your return and costs nothing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Tangible property")
            }

            Section {
                Toggle(
                    "Prompt me about repairs over $2,500",
                    isOn: $settings.promptImprovementReview
                )
                Text("Asks whether a large repair is really an improvement before it is deducted. It is the most expensive question in the return to get wrong.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Prompts")
            }

            Section {
                Picker("Bonus depreciation default", selection: Binding(
                    get: { settings.defaultBonusPercentOverride },
                    set: { settings.defaultBonusPercentOverride = $0 }
                )) {
                    Text("Statutory for the year").tag(-1.0)
                    Text("100%").tag(100.0)
                    Text("80%").tag(80.0)
                    Text("60%").tag(60.0)
                    Text("40%").tag(40.0)
                    Text("None").tag(0.0)
                }
                Text(DepreciationEngine.bonusExplanation(acquiredOn: Date()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Depreciation")
            }
        }
        .platformFormStyle()
        .navigationTitle("Methods and elections")
        .inlineNavigationTitle()
    }
}

// MARK: - Mileage rates

struct SettingsMileageRatesView: View {

    @Environment(AppSettings.self) private var settings
    @State private var editingYear: Int?
    @State private var draftRate: Double = 0

    private var years: [Int] { DateMath.selectableYears() }

    var body: some View {
        Form {
            Section {
                Text("The IRS publishes a standard business mileage rate each December. The app ships with the published figures; any year it has no figure for carries the last known rate forward and is flagged so you can correct it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Rates") {
                ForEach(years, id: \.self) { year in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: "\(year)").font(.subheadline)
                            Text(settings.mileageRates.sourceNote(forYear: year))
                                .font(.caption2)
                                .foregroundStyle(settings.mileageRates.isUnconfirmed(forYear: year) ? .orange : .secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Text(Fmt.number(settings.mileageRates.rate(forYear: year), fractionDigits: 3))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                        Button {
                            draftRate = settings.mileageRates.rate(forYear: year)
                            editingYear = year
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }
            }

            if !settings.mileageRateOverrides.isEmpty {
                Section("Your overrides") {
                    ForEach(settings.mileageRateOverrides.keys.sorted(by: >), id: \.self) { year in
                        HStack {
                            Text(verbatim: "\(year)")
                            Spacer()
                            Text(Fmt.number(settings.mileageRateOverrides[year] ?? 0, fractionDigits: 3))
                                .monospacedDigit()
                            Button("Reset") {
                                settings.setMileageRate(0, forYear: year)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .platformFormStyle()
        .navigationTitle("Mileage rates")
        .inlineNavigationTitle()
        .sheet(item: Binding(
            get: { editingYear.map { YearBox(year: $0) } },
            set: { if $0 == nil { editingYear = nil } }
        )) { box in
            NavigationStack {
                Form {
                    Section("Rate for \(box.year)") {
                        NumberField("Dollars per mile", value: $draftRate, fractionDigits: 3)
                    }
                }
                .platformFormStyle()
                .navigationTitle("Edit rate")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingYear = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            settings.setMileageRate(draftRate, forYear: box.year)
                            editingYear = nil
                        }
                    }
                }
            }
        }
    }

    private struct YearBox: Identifiable {
        let year: Int
        var id: Int { year }
    }
}
