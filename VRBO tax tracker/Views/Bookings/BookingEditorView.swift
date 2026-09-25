//
//  BookingEditorView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct BookingEditorView: View {

    let booking: Booking?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState

    @Query(sort: \Property.sortIndex) private var properties: [Property]

    @State private var property: Property?
    @State private var platform: RentalPlatform = .airbnb
    @State private var checkIn = Date()
    @State private var checkOut = DateMath.adding(days: 2, to: Date())
    @State private var bookedOn = Date()
    @State private var hasBookedOn = false
    @State private var guestName = ""
    @State private var guestCount = 2
    @State private var confirmationCode = ""

    @State private var accommodation: Decimal = 0
    @State private var cleaningFee: Decimal = 0
    @State private var otherFees: Decimal = 0
    @State private var lodgingTax: Decimal = 0
    @State private var hostFee: Decimal = 0
    @State private var processingFee: Decimal = 0
    @State private var reportedPayout: Decimal = 0
    @State private var securityDeposit: Decimal = 0

    @State private var isCancelled = false
    @State private var cancellationRetained: Decimal = 0
    @State private var notes = ""
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool { booking != nil }

    private var nights: Int { DateMath.nights(from: checkIn, to: checkOut) }
    private var grossRents: Decimal {
        isCancelled ? cancellationRetained : accommodation + cleaningFee + otherFees
    }
    private var totalFees: Decimal { hostFee + processingFee }
    private var computedPayout: Decimal { grossRents - totalFees }
    private var variance: Decimal {
        reportedPayout == 0 ? 0 : (reportedPayout - computedPayout).rounded(2)
    }
    private var nightlyRate: Decimal {
        nights > 0 ? (accommodation / Decimal(nights)).rounded(2) : 0
    }

    /// Days already claimed by another stay or by personal use.
    private var conflicts: [String] {
        guard let property else { return [] }
        var messages: [String] = []

        for other in property.bookingList where other.id != booking?.id && !other.isCancelled {
            if DateMath.rangesOverlap(
                checkIn, DateMath.adding(days: -1, to: checkOut),
                other.checkIn, DateMath.adding(days: -1, to: other.checkOut)
            ) {
                messages.append("Overlaps \(other.displayGuest)'s stay (\(other.dateRangeLabel)).")
            }
        }
        for entry in property.personalUseList where entry.countsAsPersonalUse {
            if DateMath.rangesOverlap(checkIn, DateMath.adding(days: -1, to: checkOut), entry.startDate, entry.endDate) {
                messages.append("Overlaps a personal-use block (\(entry.dateRangeLabel)). A day cannot be both rented and personal.")
            }
        }
        return messages
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                detailsSection
                revenueSection
                feesSection
                reconciliationSection
                statusSection
                if !conflicts.isEmpty { conflictSection }
                if isEditing { deleteSection }
            }
            .platformFormStyle()
            .navigationTitle(isEditing ? "Edit booking" : "New booking")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(property == nil)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete this booking?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete booking", role: .destructive) { deleteBooking() }
            } message: {
                Text("The stay and its revenue will be removed from \(DateMath.year(of: checkIn))'s Schedule E.")
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            LiveSummaryStrip(items: [
                .init(label: "Nights", value: "\(nights)"),
                .init(label: "Gross rent", value: settings.formatted(grossRents), tint: .green),
                .init(label: "Per night", value: settings.formatted(nightlyRate)),
                .init(label: "Payout", value: settings.formatted(computedPayout), tint: .blue)
            ])
        }
    }

    private var detailsSection: some View {
        Section("Stay") {
            PropertyPickerField(selection: $property, properties: properties)
            Picker("Platform", selection: $platform) {
                ForEach(RentalPlatform.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            DatePicker("Check-in", selection: $checkIn, displayedComponents: .date)
                .onChange(of: checkIn) { _, newValue in
                    if checkOut <= newValue {
                        checkOut = DateMath.adding(days: 1, to: newValue)
                    }
                }
            DatePicker("Check-out", selection: $checkOut, in: checkIn..., displayedComponents: .date)
            Text(nights == 0
                 ? "Check-out must be at least one day after check-in."
                 : "\(nights) night\(nights == 1 ? "" : "s"). A stay is counted by nights, which is what the platform bills.")
                .font(.caption2)
                .foregroundStyle(nights == 0 ? Color.orange : Color.secondary)

            Toggle("Record when it was booked", isOn: $hasBookedOn)
            if hasBookedOn {
                DatePicker("Booked on", selection: $bookedOn, in: ...checkIn, displayedComponents: .date)
            }

            TextField("Guest name", text: $guestName)
            IntegerField("Guests", value: $guestCount)
            TextField("Confirmation code", text: $confirmationCode)
                .autocorrectionDisabled()
        }
    }

    private var revenueSection: some View {
        Section {
            CurrencyField("Accommodation", amount: $accommodation, caption: "The nightly charge before any fees.")
            CurrencyField("Cleaning fee", amount: $cleaningFee)
            CurrencyField("Other guest fees", amount: $otherFees, caption: "Pet fees, extra guests, early check-in.")
            CurrencyField("Lodging tax collected", amount: $lodgingTax)
        } header: {
            Text("What the guest paid")
        } footer: {
            Text("Cleaning and other fees you charge are rental income, not a reimbursement. The cleaner you pay is deducted separately, which is how it should look on Schedule E.")
                .font(.caption2)
        }
    }

    private var feesSection: some View {
        Section {
            CurrencyField("Host service fee", amount: $hostFee)
            CurrencyField("Payment processing fee", amount: $processingFee)
        } header: {
            Text("What the platform kept")
        } footer: {
            Text("These never reach your bank account, but they are reported in your 1099-K gross and they are deductible on line 8. Leaving them out is the most common way hosts overpay.")
                .font(.caption2)
        }
    }

    private var reconciliationSection: some View {
        Section {
            CurrencyField("Payout received", amount: $reportedPayout, caption: "Leave at zero to use the computed figure.")
            if reportedPayout != 0 {
                DetailRow(
                    "Computed payout",
                    value: settings.formatted(computedPayout)
                )
                DetailRow(
                    "Difference",
                    value: settings.formatted(variance),
                    caption: abs(variance) < 1
                        ? "Matches your records."
                        : "Check for a fee, a refund or a tax the platform handled differently.",
                    valueColor: abs(variance) < 1 ? .green : .orange
                )
            }
            CurrencyField("Security deposit held", amount: $securityDeposit, caption: "Refundable deposits are not income while you hold them.")
        } header: {
            Text("Reconciliation")
        }
    }

    private var statusSection: some View {
        Section {
            Toggle("Cancelled", isOn: $isCancelled)
            if isCancelled {
                CurrencyField(
                    "Amount retained",
                    amount: $cancellationRetained,
                    caption: "Money kept under the cancellation policy is still taxable income."
                )
            }
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("Status")
        }
    }

    private var conflictSection: some View {
        Section {
            ForEach(conflicts, id: \.self) { message in
                InfoCallout(level: .caution, message: message)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        } header: {
            Text("Calendar conflicts")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete booking", systemImage: "trash")
            }
        }
    }

    // MARK: - Load & save

    private func load() {
        guard let booking else {
            property = properties.first { $0.id == settings.defaultPropertyID } ?? properties.first
            return
        }
        property = booking.property
        platform = booking.platform
        checkIn = booking.checkIn
        checkOut = booking.checkOut
        if let date = booking.bookedOn {
            bookedOn = date
            hasBookedOn = true
        }
        guestName = booking.guestName
        guestCount = booking.guestCount
        confirmationCode = booking.confirmationCode
        accommodation = booking.accommodationRevenue
        cleaningFee = booking.cleaningFeeRevenue
        otherFees = booking.otherFeeRevenue
        lodgingTax = booking.lodgingTaxCollected
        hostFee = booking.platformHostFee
        processingFee = booking.paymentProcessingFee
        reportedPayout = booking.reportedPayout
        securityDeposit = booking.securityDepositHeld
        isCancelled = booking.isCancelled
        cancellationRetained = booking.cancellationRetainedAmount
        notes = booking.notes
    }

    private func save() {
        let target = booking ?? Booking()
        if booking == nil { context.insert(target) }

        target.property = property
        target.platform = platform
        target.checkIn = checkIn
        target.checkOut = checkOut
        target.bookedOn = hasBookedOn ? bookedOn : nil
        target.guestName = guestName
        target.guestCount = guestCount
        target.confirmationCode = confirmationCode
        target.accommodationRevenue = accommodation
        target.cleaningFeeRevenue = cleaningFee
        target.otherFeeRevenue = otherFees
        target.lodgingTaxCollected = lodgingTax
        target.platformHostFee = hostFee
        target.paymentProcessingFee = processingFee
        target.reportedPayout = reportedPayout
        target.securityDepositHeld = securityDeposit
        target.isCancelled = isCancelled
        target.cancellationRetainedAmount = cancellationRetained
        target.notes = notes

        try? context.save()
        Haptics.play(.success)
        dismiss()
    }

    private func deleteBooking() {
        guard let booking else { return }
        context.delete(booking)
        try? context.save()
        Haptics.play(.warning)
        dismiss()
    }
}
