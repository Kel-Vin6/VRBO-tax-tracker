//
//  ExportView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct ExportView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]
    @Query private var participationEntries: [ParticipationEntry]
    @Query private var documents: [StoredDocument]
    @Query private var forms: [PlatformTaxForm]

    @State private var includeScheduleE = true
    @State private var includeLedger = true
    @State private var includeBookings = true
    @State private var includeExpenses = true
    @State private var includeMileage = true
    @State private var includePersonalUse = true
    @State private var includeParticipation = true
    @State private var includeDepreciation = true
    @State private var includeReconciliation = true
    @State private var includePDF = true
    @State private var includeReceipts = false

    @State private var files: [ExportFile] = []
    @State private var isBuilding = false
    @State private var errorMessage: String?

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

    private var reconciliations: [PlatformReconciliation] {
        ReconciliationEngine.reconcile(year: year, bookings: properties.flatMap(\.bookingList), forms: forms)
    }

    private var receiptCount: Int {
        expenses.filter { DateMath.contains($0.date, inYear: year) && $0.hasReceipt }.count
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Everything your accountant needs for \(year)")
                        .font(.headline)
                    Text("CSV ledgers they can open in anything, a printable summary of the return, and the receipts behind it. Nothing leaves your device until you choose where to send it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Summary") {
                Toggle("Schedule E summary (PDF)", isOn: $includePDF)
                Toggle("Schedule E figures (CSV)", isOn: $includeScheduleE)
                Toggle("General ledger", isOn: $includeLedger)
            }

            Section("Ledgers") {
                Toggle("Bookings", isOn: $includeBookings)
                Toggle("Expenses", isOn: $includeExpenses)
                Toggle("Mileage log", isOn: $includeMileage)
                Toggle("Personal-use days", isOn: $includePersonalUse)
                Toggle("Participation hours", isOn: $includeParticipation)
                Toggle("Depreciation schedule", isOn: $includeDepreciation)
                Toggle("1099-K reconciliation", isOn: $includeReconciliation)
            }

            Section {
                Toggle("Receipt images", isOn: $includeReceipts)
                if includeReceipts {
                    Text("\(receiptCount) receipt\(receiptCount == 1 ? "" : "s") will be written as individual image files, named by date and vendor.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Attachments")
            }

            Section {
                Button {
                    build()
                } label: {
                    HStack {
                        if isBuilding {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "shippingbox")
                        }
                        Text(isBuilding ? "Building…" : "Build the package")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBuilding)
            }

            if !files.isEmpty {
                Section("Ready") {
                    ForEach(files) { file in
                        HStack {
                            Image(systemName: file.fileName.hasSuffix(".pdf") ? "doc.richtext" : "tablecells")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.fileName).font(.subheadline).lineLimit(1)
                                Text(file.displaySize).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    ShareLink(items: files.map(\.url)) {
                        Label("Share \(files.count) file\(files.count == 1 ? "" : "s")", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if !settings.accountantEmail.isEmpty {
                        Text("Your accountant is \(settings.accountantName.isEmpty ? settings.accountantEmail : "\(settings.accountantName) (\(settings.accountantEmail))"). Choose Mail from the share sheet to send it straight on.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section {
                    InfoCallout(level: .critical, message: errorMessage)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }

            Section {
                TaxDisclaimer(compact: true)
            }
        }
        .platformFormStyle()
        .navigationTitle("Export")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .primaryAction) { YearMenu() } }
    }

    // MARK: - Build

    private func build() {
        isBuilding = true
        errorMessage = nil
        files = []

        do {
            let folderName = "\(settings.businessName.isEmpty ? "Rental" : settings.businessName)-\(year)-\(Fmt.fileStamp())"
                .replacingOccurrences(of: " ", with: "-")
            let directory = try ExportService.makeExportDirectory(named: folderName)
            var produced: [ExportFile] = []

            let currentReport = report

            if includeScheduleE {
                produced.append(try ExportService.write(
                    ExportService.scheduleECSV(currentReport),
                    to: directory,
                    fileName: "schedule-e-\(year).csv"
                ))
            }
            if includeLedger {
                produced.append(try ExportService.write(
                    ExportService.generalLedgerCSV(
                        properties: properties,
                        expenses: expenses,
                        trips: trips,
                        year: year,
                        rates: settings.mileageRates
                    ),
                    to: directory,
                    fileName: "general-ledger-\(year).csv"
                ))
            }
            if includeBookings {
                produced.append(try ExportService.write(
                    ExportService.bookingsCSV(properties, year: year),
                    to: directory,
                    fileName: "bookings-\(year).csv"
                ))
            }
            if includeExpenses {
                produced.append(try ExportService.write(
                    ExportService.expensesCSV(expenses, year: year),
                    to: directory,
                    fileName: "expenses-\(year).csv"
                ))
            }
            if includeMileage {
                produced.append(try ExportService.write(
                    ExportService.mileageCSV(trips, year: year, rates: settings.mileageRates),
                    to: directory,
                    fileName: "mileage-\(year).csv"
                ))
            }
            if includePersonalUse {
                produced.append(try ExportService.write(
                    ExportService.personalUseCSV(properties, year: year),
                    to: directory,
                    fileName: "personal-use-\(year).csv"
                ))
            }
            if includeParticipation {
                produced.append(try ExportService.write(
                    ExportService.participationCSV(participationEntries, year: year),
                    to: directory,
                    fileName: "participation-hours-\(year).csv"
                ))
            }
            if includeDepreciation {
                produced.append(try ExportService.write(
                    ExportService.depreciationCSV(properties, year: year),
                    to: directory,
                    fileName: "depreciation-\(year).csv"
                ))
            }
            if includeReconciliation {
                produced.append(try ExportService.write(
                    ExportService.reconciliationCSV(reconciliations),
                    to: directory,
                    fileName: "1099k-reconciliation-\(year).csv"
                ))
            }

            if includePDF, let data = makePDF(report: currentReport) {
                produced.append(try ExportService.write(
                    data,
                    to: directory,
                    fileName: "schedule-e-summary-\(year).pdf"
                ))
            }

            if includeReceipts {
                let receiptsFolder = directory.appendingPathComponent("receipts", isDirectory: true)
                try FileManager.default.createDirectory(at: receiptsFolder, withIntermediateDirectories: true)
                for expense in expenses where DateMath.contains(expense.date, inYear: year) {
                    guard let data = expense.receiptData else { continue }
                    let safeVendor = expense.displayVendor
                        .replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: ":", with: "-")
                        .prefix(40)
                    let name = "\(Fmt.isoDate(expense.date))-\(safeVendor).jpg"
                    produced.append(try ExportService.write(data, to: receiptsFolder, fileName: name))
                }
            }

            files = produced
            Haptics.play(.success)
        } catch {
            errorMessage = error.localizedDescription
            Haptics.play(.error)
        }

        isBuilding = false
    }

    private func makePDF(report: ScheduleEReport) -> Data? {
        var pages: [AnyView] = []

        pages.append(AnyView(
            ScheduleEPDFPage(
                report: report,
                ownerName: settings.ownerName,
                businessName: settings.businessName,
                currencyCode: settings.currencyCode
            )
        ))

        pages.append(AnyView(
            SupportingSchedulePDFPage(
                report: report,
                metrics: metrics,
                participation: participation,
                reconciliations: reconciliations,
                currencyCode: settings.currencyCode
            )
        ))

        let depreciationRows: [DepreciationPDFRow] = properties.flatMap { property in
            property.allDepreciationSpecs.compactMap { spec in
                let schedule = DepreciationEngine.schedule(for: spec)
                guard let row = schedule.rows.first(where: { $0.year == year }) else { return nil }
                return DepreciationPDFRow(
                    id: spec.id,
                    propertyName: property.displayName,
                    spec: spec,
                    row: row
                )
            }
        }
        if !depreciationRows.isEmpty {
            pages.append(AnyView(
                DepreciationPDFPage(
                    year: year,
                    rows: depreciationRows,
                    currencyCode: settings.currencyCode
                )
            ))
        }

        return PDFReportBuilder.makePDF(pages: pages)
    }
}
