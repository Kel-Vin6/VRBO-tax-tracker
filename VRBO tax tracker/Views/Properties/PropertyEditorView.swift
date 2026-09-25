//
//  PropertyEditorView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct PropertyEditorView: View {

    let property: Property?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var name = ""
    @State private var street = ""
    @State private var city = ""
    @State private var state = ""
    @State private var postalCode = ""
    @State private var country = "United States"
    @State private var kind: PropertyKind = .vacationOrShortTerm
    @State private var colorHex = PropertyPalette.hexes[0]
    @State private var isActive = true

    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var hasPlacedInService = false
    @State private var placedInService = Date()
    @State private var purchasePrice: Decimal = 0
    @State private var landValue: Decimal = 0
    @State private var closingCosts: Decimal = 0
    @State private var ownershipPercent: Double = 100
    @State private var rentedSpacePercent: Double = 100

    @State private var bedrooms = 0
    @State private var bathrooms: Double = 0
    @State private var maxGuests = 0
    @State private var squareFeet = 0
    @State private var daysAvailable = 365
    @State private var targetRate: Decimal = 0

    @State private var permitNumber = ""
    @State private var hasPermitExpiry = false
    @State private var permitExpiry = Date()
    @State private var insurancePolicy = ""
    @State private var hasInsuranceExpiry = false
    @State private var insuranceExpiry = Date()
    @State private var lodgingJurisdiction = ""
    @State private var lodgingRate: Double = 0
    @State private var platformRemitsTax = true

    @State private var notes = ""
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool { property != nil }

    private var buildingBasis: Decimal {
        let raw = purchasePrice + closingCosts - landValue
        guard raw > 0 else { return 0 }
        return raw.applying(percent: ownershipPercent).applying(percent: rentedSpacePercent)
    }

    private var landPercent: Double {
        let total = purchasePrice + closingCosts
        guard total > 0 else { return 0 }
        return (landValue / total).doubleValue * 100
    }

    private var firstYearDepreciation: Decimal {
        guard hasPlacedInService, buildingBasis > 0 else { return 0 }
        let spec = DepreciationSpec(
            name: name,
            assetClass: kind == .commercial || kind == .selfRental ? .nonresidentialBuilding : .residentialBuilding,
            basis: buildingBasis,
            placedInService: placedInService,
            recoveryYears: kind.realPropertyRecoveryYears
        )
        return DepreciationEngine.schedule(for: spec)
            .deduction(inYear: DateMath.year(of: placedInService))
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                addressSection
                basisSection
                listingSection
                complianceSection
                Section("Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                if isEditing { deleteSection }
            }
            .platformFormStyle()
            .navigationTitle(isEditing ? "Edit property" : "New property")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && street.isEmpty)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete this property?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete property and its records", role: .destructive) { deleteProperty() }
            } message: {
                Text("Its bookings, personal-use days, assets and loans are deleted too. Expenses stay but become unassigned.")
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Property") {
            TextField("Name", text: $name)
            Picker("Type", selection: $kind) {
                ForEach(PropertyKind.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Text("Reported as type \(kind.scheduleECode) on Schedule E line 1b.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            colorPicker
            Toggle("Currently rented out", isOn: $isActive)
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour").font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PropertyPalette.hexes, id: \.self) { hex in
                        Button {
                            colorHex = hex
                            Haptics.play(.selection)
                        } label: {
                            Circle()
                                .fill(PropertyPalette.color(for: hex))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var addressSection: some View {
        Section("Address") {
            TextField("Street", text: $street)
            TextField("City", text: $city)
            TextField("State or region", text: $state)
            TextField("Postal code", text: $postalCode)
            TextField("Country", text: $country)
        }
    }

    private var basisSection: some View {
        Section {
            Toggle("Record the purchase date", isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date)
            }
            Toggle("Record when it was placed in service", isOn: $hasPlacedInService)
            if hasPlacedInService {
                DatePicker("Placed in service", selection: $placedInService, displayedComponents: .date)
                Text("Depreciation starts the month the property was first available to rent, not the month you bought it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            CurrencyField("Purchase price", amount: $purchasePrice)
            CurrencyField(
                "Land value",
                amount: $landValue,
                caption: landPercent > 0
                    ? "\(Fmt.percent(landPercent)) of the total. Land is never depreciated — the tax assessor's split is the usual source for this."
                    : "Land is never depreciated. Use the land-to-improvement split on your property tax assessment."
            )
            CurrencyField("Capitalised closing costs", amount: $closingCosts, caption: "Title fees, transfer taxes and legal costs added to basis.")
            PercentField("Your ownership share", value: $ownershipPercent)
            PercentField(
                "Share of the home rented",
                value: $rentedSpacePercent,
                caption: "Renting two bedrooms of four? Set 50 and the depreciable basis halves."
            )

            if buildingBasis > 0 {
                DetailRow(
                    "Depreciable basis",
                    value: settings.formatted(buildingBasis),
                    caption: "Over \(Fmt.number(kind.realPropertyRecoveryYears)) years, straight line, mid-month convention.",
                    isEmphasised: true
                )
                if firstYearDepreciation > 0 {
                    DetailRow(
                        "First-year deduction",
                        value: settings.formatted(firstYearDepreciation),
                        caption: "For \(DateMath.year(of: placedInService)), prorated from the month placed in service.",
                        valueColor: .green
                    )
                }
            } else if purchasePrice > 0 && landValue <= 0 {
                InfoCallout(
                    level: .caution,
                    message: "Enter a land value. Without it the app will not guess a split, and no depreciation can be computed."
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        } header: {
            Text("Cost basis and depreciation")
        } footer: {
            Text("Depreciation is not optional. When you sell, the IRS reduces your basis by the depreciation you were allowed to take — whether or not you actually took it.")
                .font(.caption2)
        }
    }

    private var listingSection: some View {
        Section("Listing") {
            IntegerField("Bedrooms", value: $bedrooms)
            NumberField("Bathrooms", value: $bathrooms)
            IntegerField("Sleeps", value: $maxGuests)
            IntegerField("Square feet", value: $squareFeet)
            IntegerField("Days available a year", value: $daysAvailable, unit: "days")
            Text("Occupancy is measured against days available, not 365, so a seasonal rental is not unfairly penalised.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            CurrencyField("Target nightly rate", amount: $targetRate)
        }
    }

    private var complianceSection: some View {
        Section {
            TextField("Permit or licence number", text: $permitNumber)
            Toggle("Track permit expiry", isOn: $hasPermitExpiry)
            if hasPermitExpiry {
                DatePicker("Permit expires", selection: $permitExpiry, displayedComponents: .date)
            }
            TextField("Insurance policy number", text: $insurancePolicy)
            Toggle("Track insurance renewal", isOn: $hasInsuranceExpiry)
            if hasInsuranceExpiry {
                DatePicker("Insurance renews", selection: $insuranceExpiry, displayedComponents: .date)
            }
            TextField("Lodging tax jurisdiction", text: $lodgingJurisdiction)
            PercentField("Lodging tax rate", value: $lodgingRate)
            Toggle("Platform collects and remits it", isOn: $platformRemitsTax)
            Text(platformRemitsTax
                 ? "Tax the platform remits never becomes your income, so it is excluded from gross rents."
                 : "Because you remit it yourself, the tax you collect is rental income and the payment you make is deducted on line 16.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } header: {
            Text("Compliance")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete property", systemImage: "trash")
            }
        }
    }

    // MARK: - Load & save

    private func load() {
        guard let property else {
            colorHex = PropertyPalette.hex(forIndex: properties.count)
            return
        }
        name = property.name
        street = property.street
        city = property.city
        state = property.state
        postalCode = property.postalCode
        country = property.country
        kind = property.kind
        colorHex = property.colorHex
        isActive = property.isActive

        if let date = property.purchaseDate {
            purchaseDate = date
            hasPurchaseDate = true
        }
        if let date = property.placedInServiceDate {
            placedInService = date
            hasPlacedInService = true
        }
        purchasePrice = property.purchasePrice
        landValue = property.landValue
        closingCosts = property.capitalizedClosingCosts
        ownershipPercent = property.ownershipPercent
        rentedSpacePercent = property.rentedSpacePercent

        bedrooms = property.bedrooms
        bathrooms = property.bathrooms
        maxGuests = property.maxGuests
        squareFeet = property.squareFeet
        daysAvailable = property.daysAvailablePerYear
        targetRate = property.targetNightlyRate

        permitNumber = property.permitNumber
        if let date = property.permitExpiration {
            permitExpiry = date
            hasPermitExpiry = true
        }
        insurancePolicy = property.insurancePolicyNumber
        if let date = property.insuranceExpiration {
            insuranceExpiry = date
            hasInsuranceExpiry = true
        }
        lodgingJurisdiction = property.lodgingTaxJurisdiction
        lodgingRate = property.lodgingTaxRatePercent
        platformRemitsTax = property.lodgingTaxRemittedByPlatform
        notes = property.notes
    }

    private func save() {
        let target = property ?? Property()
        if property == nil {
            context.insert(target)
            target.sortIndex = properties.count
        }

        target.name = name
        target.street = street
        target.city = city
        target.state = state
        target.postalCode = postalCode
        target.country = country
        target.kind = kind
        target.colorHex = colorHex
        target.isActive = isActive

        target.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        target.placedInServiceDate = hasPlacedInService ? placedInService : nil
        target.purchasePrice = purchasePrice
        target.landValue = landValue
        target.capitalizedClosingCosts = closingCosts
        target.ownershipPercent = ownershipPercent.clampedPercent
        target.rentedSpacePercent = rentedSpacePercent.clampedPercent

        target.bedrooms = bedrooms
        target.bathrooms = bathrooms
        target.maxGuests = maxGuests
        target.squareFeet = squareFeet
        target.daysAvailablePerYear = max(1, min(366, daysAvailable))
        target.targetNightlyRate = targetRate

        target.permitNumber = permitNumber
        target.permitExpiration = hasPermitExpiry ? permitExpiry : nil
        target.insurancePolicyNumber = insurancePolicy
        target.insuranceExpiration = hasInsuranceExpiry ? insuranceExpiry : nil
        target.lodgingTaxJurisdiction = lodgingJurisdiction
        target.lodgingTaxRatePercent = lodgingRate
        target.lodgingTaxRemittedByPlatform = platformRemitsTax
        target.notes = notes

        try? context.save()
        Haptics.play(.success)
        dismiss()
    }

    private func deleteProperty() {
        guard let property else { return }
        context.delete(property)
        try? context.save()
        dismiss()
    }
}
