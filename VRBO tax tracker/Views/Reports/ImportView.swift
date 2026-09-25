//
//  ImportView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {

    var kind: ImportKind = .bookings

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var existingBookings: [Booking]

    @State private var importKind: ImportKind = .bookings
    @State private var table: CSVTable?
    @State private var mapping = ColumnMapping()
    @State private var detectedPlatform: RentalPlatform?
    @State private var targetProperty: Property?
    @State private var assignedPlatform: RentalPlatform = .airbnb
    @State private var showingFileImporter = false
    @State private var errorMessage: String?
    @State private var outcome: ImportOutcome?
    @State private var fileName = ""

    private var fields: [ImportField] { ImportService.fields(for: importKind) }

    private var previewRows: [ImportPreviewRow] {
        guard let table else { return [] }
        return table.rows.prefix(8).map { row in
            switch importKind {
            case .bookings:
                let parsed = ImportService.parseBooking(row: row, table: table, mapping: mapping)
                guard let booking = parsed.booking else {
                    return ImportPreviewRow(
                        summary: "Could not read this row",
                        detail: parsed.problems.joined(separator: " "),
                        amount: 0,
                        date: nil,
                        isValid: false,
                        problems: parsed.problems
                    )
                }
                return ImportPreviewRow(
                    summary: booking.guestName.isEmpty ? "Guest" : booking.guestName,
                    detail: "\(Fmt.shortDate(booking.checkIn)) – \(Fmt.shortDate(booking.checkOut)) · \(DateMath.nights(from: booking.checkIn, to: booking.checkOut)) nights",
                    amount: booking.accommodationRevenue + booking.cleaningFee,
                    date: booking.checkIn,
                    isValid: parsed.problems.isEmpty,
                    problems: parsed.problems
                )
            case .expenses:
                let parsed = ImportService.parseExpense(row: row, table: table, mapping: mapping)
                guard let expense = parsed.expense else {
                    return ImportPreviewRow(
                        summary: "Could not read this row",
                        detail: parsed.problems.joined(separator: " "),
                        amount: 0,
                        date: nil,
                        isValid: false,
                        problems: parsed.problems
                    )
                }
                return ImportPreviewRow(
                    summary: expense.vendor.isEmpty ? "Expense" : expense.vendor,
                    detail: "\(Fmt.shortDate(expense.date)) · \(expense.category.title)\(expense.categoryWasGuessed ? " (guessed)" : "")",
                    amount: expense.amount,
                    date: expense.date,
                    isValid: parsed.problems.isEmpty,
                    problems: parsed.problems
                )
            }
        }
    }

    private var canImport: Bool {
        guard table != nil, mapping.isComplete(for: fields) else { return false }
        if importKind == .bookings && targetProperty == nil { return false }
        return true
    }

    var body: some View {
        Form {
            if table == nil {
                introSection
            } else {
                fileSection
                mappingSection
                destinationSection
                previewSection
                importSection
            }
            if let outcome {
                Section("Result") {
                    Label(outcome.summary, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    ForEach(outcome.problems.prefix(6), id: \.self) { problem in
                        Text(problem)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            if let errorMessage {
                Section {
                    InfoCallout(level: .critical, message: errorMessage)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
        }
        .platformFormStyle()
        .navigationTitle("Import")
        .inlineNavigationTitle()
        .onAppear {
            importKind = kind
            targetProperty = properties.first { $0.id == settings.defaultPropertyID } ?? properties.first
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFile(result)
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Picker("What are you importing?", selection: $importKind) {
                    ForEach(ImportKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(importKind.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showingFileImporter = true
                } label: {
                    Label("Choose a CSV file", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Where to get the file")
                        .font(.subheadline.weight(.semibold))
                    Text("Airbnb: Account ▸ Transaction history ▸ Completed payouts ▸ Export CSV.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Vrbo: Reservation manager ▸ Payments ▸ download the payout report.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Bank or card: most institutions export a CSV with a date, a description and an amount, which is all the app needs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Theme.nestedFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                InfoCallout(
                    level: .info,
                    message: "Nothing is imported until you have seen the preview and pressed Import. Rows the app cannot read are skipped and listed, never guessed at."
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var fileSection: some View {
        Section("File") {
            DetailRow(fileName, value: "\(table?.rows.count ?? 0) rows")
            if let detectedPlatform {
                DetailRow("Recognised as", value: "\(detectedPlatform.title) export", valueColor: .green)
            }
            Button("Choose a different file") { showingFileImporter = true }
                .font(.subheadline)
        }
    }

    private var mappingSection: some View {
        Section {
            ForEach(fields) { field in
                Picker(selection: Binding(
                    get: { mapping.assignments[field.id] },
                    set: { newValue in
                        if let newValue {
                            mapping.assignments[field.id] = newValue
                        } else {
                            mapping.assignments.removeValue(forKey: field.id)
                        }
                    }
                )) {
                    Text("Not in this file").tag(Int?.none)
                    if let table {
                        ForEach(table.headers.indices, id: \.self) { index in
                            Text(table.headers[index].isEmpty ? "Column \(index + 1)" : table.headers[index])
                                .tag(Int?.some(index))
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(field.title)
                            if field.isRequired {
                                Text("required")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        if !field.hint.isEmpty {
                            Text(field.hint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Columns")
        } footer: {
            Text(mapping.isComplete(for: fields)
                 ? "Every required column is mapped."
                 : "Map the required columns to continue.")
                .font(.caption2)
                .foregroundStyle(mapping.isComplete(for: fields) ? .secondary : .orange)
        }
    }

    private var destinationSection: some View {
        Section("Destination") {
            if importKind == .bookings {
                PropertyPickerField(selection: $targetProperty, properties: properties)
                Picker("Platform", selection: $assignedPlatform) {
                    ForEach(RentalPlatform.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } else {
                PropertyPickerField(
                    selection: $targetProperty,
                    properties: properties,
                    allowsNone: true,
                    noneLabel: "Leave unassigned"
                )
                Text("Categories are guessed from the description where the app is confident, and left as “Other” where it is not.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            ForEach(previewRows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(row.isValid ? .green : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.summary).font(.subheadline).lineLimit(1)
                        Text(row.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text(settings.formatted(row.amount))
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }
            if let table, table.rows.count > previewRows.count {
                Text("Showing the first \(previewRows.count) of \(table.rows.count) rows.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var importSection: some View {
        Section {
            Button {
                runImport()
            } label: {
                Label("Import \(table?.rows.count ?? 0) rows", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canImport)
        }
    }

    // MARK: - Actions

    private func handleFile(_ result: Result<[URL], Error>) {
        errorMessage = nil
        outcome = nil
        do {
            guard let url = try result.get().first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            guard !text.isEmpty else {
                errorMessage = "That file appears to be empty, or is not plain text."
                return
            }
            let parsed = CSVParser.parse(text)
            guard !parsed.headers.isEmpty else {
                errorMessage = "No column headers were found. The first row of the file should name the columns."
                return
            }
            fileName = url.lastPathComponent
            table = parsed
            detectedPlatform = ImportService.detectPlatform(table: parsed)
            if let detectedPlatform { assignedPlatform = detectedPlatform }
            mapping = ImportService.autoMap(table: parsed, kind: importKind)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runImport() {
        guard let table else { return }
        var imported = 0
        var skipped = 0
        var duplicates = 0
        var problems: [String] = []

        let existingCodes = Set(
            existingBookings
                .map(\.confirmationCode)
                .filter { !$0.isEmpty }
        )

        for row in table.rows {
            switch importKind {
            case .bookings:
                let parsed = ImportService.parseBooking(row: row, table: table, mapping: mapping)
                guard let booking = parsed.booking else {
                    skipped += 1
                    problems.append(contentsOf: parsed.problems)
                    continue
                }
                if !booking.confirmationCode.isEmpty && existingCodes.contains(booking.confirmationCode) {
                    duplicates += 1
                    continue
                }
                let model = Booking(
                    platform: assignedPlatform,
                    checkIn: booking.checkIn,
                    checkOut: booking.checkOut,
                    property: targetProperty
                )
                model.guestName = booking.guestName
                model.confirmationCode = booking.confirmationCode
                model.accommodationRevenue = booking.accommodationRevenue
                model.cleaningFeeRevenue = booking.cleaningFee
                model.lodgingTaxCollected = booking.lodgingTax
                model.platformHostFee = booking.serviceFee
                model.reportedPayout = booking.payout
                model.source = .csvImport
                model.externalReference = booking.listingName
                context.insert(model)
                imported += 1

            case .expenses:
                let parsed = ImportService.parseExpense(row: row, table: table, mapping: mapping)
                guard let expense = parsed.expense else {
                    skipped += 1
                    problems.append(contentsOf: parsed.problems)
                    continue
                }
                let model = Expense(
                    date: expense.date,
                    vendor: expense.vendor,
                    amount: expense.amount,
                    category: expense.category,
                    property: targetProperty
                )
                model.source = .csvImport
                model.paymentMethod = settings.defaultPaymentMethod
                context.insert(model)
                imported += 1
            }
        }

        try? context.save()
        outcome = ImportOutcome(
            imported: imported,
            skipped: skipped,
            duplicates: duplicates,
            problems: Array(Set(problems))
        )
        self.table = nil
        Haptics.play(.success)
    }
}
