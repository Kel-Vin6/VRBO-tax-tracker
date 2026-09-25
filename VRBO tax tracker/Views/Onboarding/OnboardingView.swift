//
//  OnboardingView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct OnboardingView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var page = 0
    @State private var ownerName = ""
    @State private var filingStatus: FilingStatus = .single
    @State private var stateCode = ""
    @State private var otherIncome: Decimal = 0

    @State private var propertyName = ""
    @State private var propertyStreet = ""
    @State private var propertyCity = ""
    @State private var propertyKind: PropertyKind = .vacationOrShortTerm
    @State private var purchasePrice: Decimal = 0
    @State private var landValue: Decimal = 0
    @State private var hasPlacedInService = false
    @State private var placedInService = Date()

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            pages
            footer
        }
    }

    @ViewBuilder
    private var pages: some View {
        #if os(iOS)
        TabView(selection: $page) {
            welcomePage.tag(0)
            featuresPage.tag(1)
            profilePage.tag(2)
            propertyPage.tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        switch page {
        case 0: welcomePage
        case 1: featuresPage
        case 2: profilePage
        default: propertyPage
        }
        #endif
    }

    // MARK: - Pages

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 40)
                ZStack {
                    Circle()
                        .fill(settings.accentColor.opacity(0.14))
                        .frame(width: 128, height: 128)
                    Image(systemName: "house.and.flag.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(settings.accentColor)
                }
                VStack(spacing: 10) {
                    Text("Your rental, ready for tax season")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Track what you earn and spend on your short-term rental, and the app builds Schedule E as you go — with the rules that decide what you can actually claim checked all year, not in April.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                Spacer(minLength: 20)
            }
        }
    }

    private var featuresPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What it does that a spreadsheet cannot")
                    .font(.title2.weight(.bold))
                    .padding(.top, 36)

                FeatureLine(
                    symbol: "doc.text",
                    title: "Builds the actual form",
                    detail: "Every expense lands on a numbered line of Schedule E, per property, with the detail behind each figure one tap away."
                )
                FeatureLine(
                    symbol: "calendar.badge.exclamationmark",
                    title: "Watches the 14-day rule",
                    detail: "Tells you how many personal nights are left before the property becomes a residence and the loss disappears."
                )
                FeatureLine(
                    symbol: "clock.badge.checkmark",
                    title: "Tracks material participation",
                    detail: "The average length of stay and the hours you work, which together decide whether a loss can offset your salary."
                )
                FeatureLine(
                    symbol: "chart.line.downtrend.xyaxis",
                    title: "Runs real MACRS depreciation",
                    detail: "Mid-month on the building, declining balance on the contents, with bonus and §179 where they apply."
                )
                FeatureLine(
                    symbol: "doc.viewfinder",
                    title: "Reads your receipts",
                    detail: "Scan a receipt and the amount, date and merchant are filled in — on device, with nothing uploaded."
                )
                FeatureLine(
                    symbol: "arrow.left.arrow.right",
                    title: "Reconciles your 1099-K",
                    detail: "Rebuilds what each platform should have reported and shows you exactly why it differs from your return."
                )
                FeatureLine(
                    symbol: "checkmark.shield",
                    title: "Scores your paperwork",
                    detail: "Shows what an examiner would ask for first, and what is still missing, while there is time to fix it."
                )
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    private var profilePage: some View {
        Form {
            Section {
                Text("A few details make the tax estimates real rather than generic. You can change all of this later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("You") {
                TextField("Your name", text: $ownerName)
                Picker("Filing status", selection: $filingStatus) {
                    ForEach(FilingStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                TextField("State", text: $stateCode)
                CurrencyField(
                    "Income outside the rental",
                    amount: $otherIncome,
                    caption: "Wages and everything else. It is what tells the app your tax bracket."
                )
            }
            Section {
                Text("Nothing here leaves your device. The app has no account and no server.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .platformFormStyle()
    }

    private var propertyPage: some View {
        Form {
            Section {
                Text("Add your rental. The cost basis is optional now, but entering it is what unlocks depreciation — usually the largest deduction on the return.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Property") {
                TextField("Name", text: $propertyName)
                TextField("Street", text: $propertyStreet)
                TextField("City", text: $propertyCity)
                Picker("Type", selection: $propertyKind) {
                    ForEach(PropertyKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }
            Section {
                CurrencyField("Purchase price", amount: $purchasePrice)
                CurrencyField(
                    "Land value",
                    amount: $landValue,
                    caption: "From your property tax assessment. Land is never depreciated, so this split matters."
                )
                Toggle("I know when it was placed in service", isOn: $hasPlacedInService)
                if hasPlacedInService {
                    DatePicker("Placed in service", selection: $placedInService, displayedComponents: .date)
                }
                if purchasePrice > landValue && landValue > 0 && hasPlacedInService {
                    let basis = purchasePrice - landValue
                    let spec = DepreciationSpec(
                        name: propertyName,
                        assetClass: propertyKind == .commercial ? .nonresidentialBuilding : .residentialBuilding,
                        basis: basis,
                        placedInService: placedInService,
                        recoveryYears: propertyKind.realPropertyRecoveryYears
                    )
                    let firstYear = DepreciationEngine.schedule(for: spec)
                        .deduction(inYear: DateMath.year(of: placedInService))
                    InfoCallout(
                        level: .success,
                        title: "That is \(settings.formatted(firstYear)) of depreciation",
                        message: "In \(DateMath.year(of: placedInService)) alone, and roughly \(settings.formatted((basis / Decimal(propertyKind.realPropertyRecoveryYears)).rounded(0))) every year after that."
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            } header: {
                Text("Cost basis")
            }
        }
        .platformFormStyle()
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? settings.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == page ? 20 : 7, height: 7)
                        .animation(.smooth, value: page)
                }
            }

            HStack(spacing: 12) {
                if page > 0 {
                    Button("Back") {
                        withAnimation { page -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Button(page == pageCount - 1 ? "Start tracking" : "Continue") {
                    if page == pageCount - 1 {
                        finish()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            if page == pageCount - 1 {
                Button("Skip for now") { finish(skipProperty: true) }
                    .font(.footnote)
            }

            TaxDisclaimer(compact: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .controlSize(.large)
    }

    private func finish(skipProperty: Bool = false) {
        settings.ownerName = ownerName
        settings.filingStatus = filingStatus
        settings.stateCode = stateCode.uppercased()
        settings.otherOrdinaryIncome = otherIncome

        if !skipProperty, !propertyName.trimmingCharacters(in: .whitespaces).isEmpty || !propertyStreet.isEmpty {
            let property = Property(
                name: propertyName,
                kind: propertyKind,
                colorHex: PropertyPalette.hexes[0]
            )
            property.street = propertyStreet
            property.city = propertyCity
            property.purchasePrice = purchasePrice
            property.landValue = landValue
            property.placedInServiceDate = hasPlacedInService ? placedInService : nil
            context.insert(property)
            try? context.save()
            settings.defaultPropertyID = property.id
        }

        settings.hasAcceptedDisclaimer = true
        settings.hasCompletedOnboarding = true
        Haptics.play(.success)
    }
}
