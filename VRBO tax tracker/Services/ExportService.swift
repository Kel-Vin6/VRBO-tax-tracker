//
//  ExportService.swift
//  VRBO tax tracker
//
//  Everything the app knows, in formats an accountant can open. CSV for the
//  ledgers, a PDF for the return summary, and a bundle that puts the whole year
//  in one folder.
//

import Foundation

public struct ExportFile: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var fileName: String
    public var url: URL
    public var byteCount: Int

    public var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

public enum ExportError: LocalizedError {
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .writeFailed(let name): "Could not write \(name)."
        }
    }
}

public enum ExportService {

    // MARK: - Directory

    public static func makeExportDirectory(named name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @discardableResult
    public static func write(_ contents: String, to directory: URL, fileName: String) throws -> ExportFile {
        let url = directory.appendingPathComponent(fileName)
        guard let data = contents.data(using: .utf8) else {
            throw ExportError.writeFailed(fileName)
        }
        try data.write(to: url, options: .atomic)
        return ExportFile(fileName: fileName, url: url, byteCount: data.count)
    }

    @discardableResult
    public static func write(_ data: Data, to directory: URL, fileName: String) throws -> ExportFile {
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return ExportFile(fileName: fileName, url: url, byteCount: data.count)
    }

    // MARK: - CSV builders

    public static func bookingsCSV(_ properties: [Property], year: Int) -> String {
        var lines = [CSVParser.line([
            "Property", "Platform", "Confirmation", "Guest", "Check-in", "Check-out",
            "Nights", "Nights in year", "Accommodation", "Cleaning fee", "Other fees",
            "Gross rents", "Lodging tax collected", "Host service fee", "Processing fee",
            "Computed payout", "Reported payout", "Variance", "Cancelled", "Notes"
        ])]

        for property in properties {
            let bookings = property.bookingList
                .filter { $0.nights(inYear: year) > 0 || DateMath.contains($0.checkIn, inYear: year) }
                .sorted { $0.checkIn < $1.checkIn }

            for booking in bookings {
                lines.append(CSVParser.line([
                    property.displayName,
                    booking.platform.title,
                    booking.confirmationCode,
                    booking.guestName,
                    Fmt.isoDate(booking.checkIn),
                    Fmt.isoDate(booking.checkOut),
                    "\(booking.nights)",
                    "\(booking.nights(inYear: year))",
                    string(booking.accommodationRevenue),
                    string(booking.cleaningFeeRevenue),
                    string(booking.otherFeeRevenue),
                    string(booking.grossRents),
                    string(booking.lodgingTaxCollected),
                    string(booking.platformHostFee),
                    string(booking.paymentProcessingFee),
                    string(booking.computedPayout),
                    string(booking.reportedPayout),
                    string(booking.payoutVariance),
                    booking.isCancelled ? "Yes" : "No",
                    booking.notes
                ]))
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func expensesCSV(_ expenses: [Expense], year: Int) -> String {
        var lines = [CSVParser.line([
            "Date", "Property", "Vendor", "Category", "Schedule E line", "Line description",
            "Amount", "Business use %", "Deductible", "Payment method", "Allocation",
            "Capitalised", "Receipt", "Source", "Notes"
        ])]

        for expense in expenses.filter({ DateMath.contains($0.date, inYear: year) }).sorted(by: { $0.date < $1.date }) {
            lines.append(CSVParser.line([
                Fmt.isoDate(expense.date),
                expense.property?.displayName ?? (expense.isSplitAcrossPortfolio ? "Portfolio" : "Unassigned"),
                expense.vendor,
                expense.displayCategory,
                "\(expense.scheduleELine.rawValue)",
                expense.scheduleELine.title,
                string(expense.amount),
                Fmt.number(expense.businessUsePercent, fractionDigits: 0),
                string(expense.deductibleAmount),
                expense.paymentMethod.title,
                expense.allocation.title,
                expense.isCapitalImprovement ? "Yes" : "No",
                expense.hasReceipt ? "Attached" : "Missing",
                expense.source.title,
                expense.notes
            ]))
        }
        return lines.joined(separator: "\n")
    }

    public static func mileageCSV(_ trips: [MileageTrip], year: Int, rates: MileageRateTable) -> String {
        var lines = [CSVParser.line([
            "Date", "Property", "Purpose", "From", "To", "Miles", "Round trip",
            "Rate", "Mileage deduction", "Tolls & parking", "Total", "Logged same day", "Notes"
        ])]

        for trip in trips.filter({ DateMath.contains($0.date, inYear: year) }).sorted(by: { $0.date < $1.date }) {
            lines.append(CSVParser.line([
                Fmt.isoDate(trip.date),
                trip.property?.displayName ?? "Unassigned",
                trip.purpose.title,
                trip.fromLabel,
                trip.toLabel,
                Fmt.number(trip.effectiveMiles),
                trip.isRoundTrip ? "Yes" : "No",
                Fmt.number(trip.rate(using: rates), fractionDigits: 3),
                string(Decimal.fromDouble(trip.effectiveMiles * trip.rate(using: rates))),
                string(trip.tollsAndParking),
                string(trip.deduction(using: rates)),
                trip.loggedSameDay ? "Yes" : "No",
                trip.notes
            ]))
        }
        return lines.joined(separator: "\n")
    }

    public static func personalUseCSV(_ properties: [Property], year: Int) -> String {
        var lines = [CSVParser.line([
            "Property", "Start", "End", "Days in year", "Kind",
            "Counts as personal use", "Occupant", "Rent collected", "Notes"
        ])]

        for property in properties {
            for entry in property.personalUseList
                .filter({ $0.dayCount(inYear: year) > 0 })
                .sorted(by: { $0.startDate < $1.startDate }) {
                lines.append(CSVParser.line([
                    property.displayName,
                    Fmt.isoDate(entry.startDate),
                    Fmt.isoDate(entry.endDate),
                    "\(entry.dayCount(inYear: year))",
                    entry.kind.title,
                    entry.countsAsPersonalUse ? "Yes" : "No",
                    entry.occupantName,
                    string(entry.rentCollected),
                    entry.notes
                ]))
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func participationCSV(_ entries: [ParticipationEntry], year: Int) -> String {
        var lines = [CSVParser.line([
            "Date", "Property", "Activity", "Hours", "Counts toward participation",
            "By spouse", "Other individuals' hours", "Logged same day", "Description"
        ])]

        for entry in entries.filter({ DateMath.contains($0.date, inYear: year) }).sorted(by: { $0.date < $1.date }) {
            lines.append(CSVParser.line([
                Fmt.isoDate(entry.date),
                entry.property?.displayName ?? "Portfolio",
                entry.activity.title,
                Fmt.number(entry.hours),
                entry.countsForMaterialParticipation ? "Yes" : "No",
                entry.performedBySpouse ? "Yes" : "No",
                Fmt.number(entry.contractorHoursSameDay),
                entry.loggedSameDay ? "Yes" : "No",
                entry.descriptionText
            ]))
        }
        return lines.joined(separator: "\n")
    }

    public static func depreciationCSV(_ properties: [Property], year: Int) -> String {
        var lines = [CSVParser.line([
            "Property", "Asset", "Class", "Placed in service", "Recovery years",
            "Basis", "Method", "Section 179", "Bonus", "MACRS",
            "Total this year", "Accumulated", "Remaining basis"
        ])]

        for property in properties {
            for spec in property.allDepreciationSpecs {
                let schedule = DepreciationEngine.schedule(for: spec)
                guard let row = schedule.rows.first(where: { $0.year == year }) else { continue }
                lines.append(CSVParser.line([
                    property.displayName,
                    spec.name,
                    spec.assetClass.title,
                    Fmt.isoDate(spec.placedInService),
                    Fmt.number(spec.recoveryYears),
                    string(spec.basis),
                    row.methodLabel,
                    string(row.section179),
                    string(row.bonus),
                    string(row.macrs),
                    string(row.total),
                    string(row.accumulated),
                    string(row.closingBasis)
                ]))
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func scheduleECSV(_ report: ScheduleEReport) -> String {
        var lines: [String] = []
        let header = ["Line", "Description"] + report.columns.map(\.propertyName) + ["Total"]
        lines.append(CSVParser.line(header))

        lines.append(CSVParser.line(
            ["1b", "Type of property"]
            + report.columns.map(\.propertyKindCode)
            + [""]
        ))
        lines.append(CSVParser.line(
            ["2", "Fair rental days"]
            + report.columns.map { "\($0.fairRentalDays)" }
            + ["\(report.columns.map(\.fairRentalDays).reduce(0, +))"]
        ))
        lines.append(CSVParser.line(
            ["2", "Personal use days"]
            + report.columns.map { "\($0.personalUseDays)" }
            + ["\(report.columns.map(\.personalUseDays).reduce(0, +))"]
        ))
        lines.append(CSVParser.line(
            ["3", "Rents received"]
            + report.columns.map { string($0.rentsReceived) }
            + [string(report.totalRents)]
        ))

        for line in ScheduleELine.allCases {
            let amounts = report.columns.map { column in
                column.lines.first(where: { $0.line == line })?.reportedAmount ?? 0
            }
            guard amounts.contains(where: { $0 != 0 }) else { continue }
            lines.append(CSVParser.line(
                ["\(line.rawValue)", line.title]
                + amounts.map(string)
                + [string(amounts.total)]
            ))
        }

        lines.append(CSVParser.line(
            ["20", "Total expenses"]
            + report.columns.map { string($0.totalExpenses) }
            + [string(report.totalExpenses)]
        ))
        lines.append(CSVParser.line(
            ["21", "Income or loss"]
            + report.columns.map { string($0.netIncomeOrLoss) }
            + [string(report.totalNet)]
        ))
        return lines.joined(separator: "\n")
    }

    /// One row per underlying record, so the accountant can trace any figure on
    /// the summary back to the transaction behind it.
    public static func generalLedgerCSV(
        properties: [Property],
        expenses: [Expense],
        trips: [MileageTrip],
        year: Int,
        rates: MileageRateTable
    ) -> String {
        var lines = [CSVParser.line([
            "Date", "Type", "Property", "Description", "Schedule E line",
            "Debit (expense)", "Credit (income)", "Source", "Receipt"
        ])]

        var rows: [(Date, [String])] = []

        for property in properties {
            for booking in property.bookingList where booking.nights(inYear: year) > 0 {
                let amount = booking.grossRents * booking.yearFraction(year)
                rows.append((booking.checkIn, [
                    Fmt.isoDate(booking.checkIn),
                    "Rental income",
                    property.displayName,
                    "\(booking.platform.title) — \(booking.displayGuest) (\(booking.nights) nights)",
                    "3",
                    "",
                    string(amount),
                    booking.source.title,
                    ""
                ]))
            }
        }

        for expense in expenses where DateMath.contains(expense.date, inYear: year) {
            rows.append((expense.date, [
                Fmt.isoDate(expense.date),
                "Expense",
                expense.property?.displayName ?? "Portfolio",
                "\(expense.displayVendor) — \(expense.displayCategory)",
                "\(expense.scheduleELine.rawValue)",
                string(expense.deductibleAmount),
                "",
                expense.source.title,
                expense.hasReceipt ? "Yes" : "No"
            ]))
        }

        for trip in trips where DateMath.contains(trip.date, inYear: year) {
            rows.append((trip.date, [
                Fmt.isoDate(trip.date),
                "Mileage",
                trip.property?.displayName ?? "Portfolio",
                "\(trip.routeLabel) — \(Fmt.miles(trip.effectiveMiles))",
                "6",
                string(trip.deduction(using: rates)),
                "",
                "Mileage log",
                ""
            ]))
        }

        for row in rows.sorted(by: { $0.0 < $1.0 }) {
            lines.append(CSVParser.line(row.1))
        }
        return lines.joined(separator: "\n")
    }

    public static func reconciliationCSV(_ reconciliations: [PlatformReconciliation]) -> String {
        var lines = [CSVParser.line([
            "Platform", "Year", "Bookings", "Gross rents recorded",
            "Lodging tax collected", "Expected on 1099-K", "Reported on 1099-K",
            "Variance", "Host fees deductible", "Status"
        ])]

        for item in reconciliations {
            lines.append(CSVParser.line([
                item.platform.title,
                "\(item.year)",
                "\(item.bookingCount)",
                string(item.recordedGrossRents),
                string(item.lodgingTaxCollected),
                string(item.recordedGuestCharges),
                string(item.reportedOnForm),
                string(item.variance),
                string(item.platformFees),
                item.status
            ]))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Plain, unlocalised decimal strings — a spreadsheet should never have to
    /// guess whether "1.234" is a thousand or one and a bit.
    private static func string(_ value: Decimal) -> String {
        "\(value.rounded(2))"
    }
}
