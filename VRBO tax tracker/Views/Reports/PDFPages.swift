//
//  PDFPages.swift
//  VRBO tax tracker
//
//  The printable pages. These are ordinary SwiftUI views rendered into a PDF,
//  so what the accountant receives is the same layout the user reviewed.
//

import SwiftUI

private enum Page {
    static let margin: CGFloat = 40
    static let titleFont = Font.system(size: 20, weight: .semibold)
    static let headingFont = Font.system(size: 12, weight: .semibold)
    static let bodyFont = Font.system(size: 9.5)
    static let smallFont = Font.system(size: 8)
}

struct PDFPageChrome<Content: View>: View {
    let title: String
    let subtitle: String
    let footer: String
    let content: Content

    init(title: String, subtitle: String, footer: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Page.titleFont)
                Text(subtitle).font(Page.smallFont).foregroundStyle(.secondary)
            }
            Rectangle()
                .fill(Color.black.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 10)

            content

            Spacer(minLength: 0)

            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(height: 1)
                .padding(.top, 10)
            Text(footer)
                .font(Page.smallFont)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(Page.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

/// Page one: the Schedule E figures, one column per property.
struct ScheduleEPDFPage: View {

    let report: ScheduleEReport
    let ownerName: String
    let businessName: String
    let currencyCode: String

    private func money(_ value: Decimal) -> String {
        Fmt.currency(value, code: currencyCode, hideCents: true)
    }

    var body: some View {
        PDFPageChrome(
            title: "Schedule E (Form 1040), Part I — \(report.year)",
            subtitle: [businessName, ownerName].filter { !$0.isEmpty }.joined(separator: " · "),
            footer: "Prepared \(Fmt.mediumDate(report.generatedAt)). An estimate prepared from the owner's own records to support preparation of a return. Not tax advice and not a filed return."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                headerGrid
                Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1)
                lineRows
                Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1)
                totals
                if !allNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes").font(Page.headingFont)
                        ForEach(allNotes, id: \.self) { note in
                            Text("• \(note)")
                                .font(Page.smallFont)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private var allNotes: [String] {
        report.columns.flatMap { column in
            column.notes.map { "\(column.propertyName): \($0)" }
        }
    }

    private var headerGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("", report.columns.map(\.propertyName), isHeader: true)
            row("1a  Address", report.columns.map { $0.address.isEmpty ? "—" : $0.address })
            row("1b  Type", report.columns.map(\.propertyKindCode))
            row("2    Fair rental days", report.columns.map { "\($0.fairRentalDays)" })
            row("2    Personal use days", report.columns.map { "\($0.personalUseDays)" })
        }
    }

    private var lineRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("3    Rents received", report.columns.map { money($0.rentsReceived) }, isBold: true)
            ForEach(ScheduleELine.allCases) { line in
                let values = report.columns.map { column in
                    column.lines.first(where: { $0.line == line })?.reportedAmount ?? 0
                }
                if values.contains(where: { $0 != 0 }) {
                    row(
                        "\(paddedNumber(line.rawValue))  \(line.title)",
                        values.map(money)
                    )
                }
            }
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("20  Total expenses", report.columns.map { money($0.totalExpenses) }, isBold: true)
            row("21  Income or loss", report.columns.map { money($0.netIncomeOrLoss) }, isBold: true)
            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1).padding(.vertical, 4)
            HStack {
                Text("Total rents received").font(Page.headingFont)
                Spacer()
                Text(money(report.totalRents)).font(Page.headingFont)
            }
            HStack {
                Text("Total expenses").font(Page.headingFont)
                Spacer()
                Text(money(report.totalExpenses)).font(Page.headingFont)
            }
            HStack {
                Text("Total income or loss").font(Page.headingFont)
                Spacer()
                Text(money(report.totalNet)).font(Page.headingFont)
            }
        }
    }

    private func paddedNumber(_ value: Int) -> String {
        value < 10 ? " \(value)" : "\(value)"
    }

    private func row(_ label: String, _ values: [String], isHeader: Bool = false, isBold: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(isHeader ? Page.headingFont : (isBold ? Page.headingFont : Page.bodyFont))
                .frame(width: 210, alignment: .leading)
                .lineLimit(2)
            ForEach(values.indices, id: \.self) { index in
                Text(values[index])
                    .font(isHeader ? Page.headingFont : (isBold ? Page.headingFont : Page.bodyFont))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(2)
            }
        }
    }
}

/// Page two: the supporting figures an accountant asks for next.
struct SupportingSchedulePDFPage: View {

    let report: ScheduleEReport
    let metrics: PortfolioMetrics
    let participation: MaterialParticipationAnalysis
    let reconciliations: [PlatformReconciliation]
    let currencyCode: String

    private func money(_ value: Decimal) -> String {
        Fmt.currency(value, code: currencyCode, hideCents: true)
    }

    var body: some View {
        PDFPageChrome(
            title: "Supporting schedules — \(report.year)",
            subtitle: "Day counts, participation, platform reconciliation and depreciation",
            footer: "Prepared from the owner's records. Figures are estimates for preparation purposes."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                section("Day counts and §280A") {
                    ForEach(report.columns) { column in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(column.propertyName).font(Page.headingFont)
                            keyValue("Classification", column.analysis.classification.title)
                            keyValue("Fair rental days", "\(column.fairRentalDays)")
                            keyValue("Personal use days", "\(column.personalUseDays)")
                            keyValue("Personal use limit", "\(column.analysis.personalUseThreshold)")
                            keyValue("Expense allocation applied", Fmt.percent(column.allocationPercentApplied))
                            if column.interestAllocationPercentApplied != column.allocationPercentApplied {
                                keyValue("Interest and taxes allocation", Fmt.percent(column.interestAllocationPercentApplied))
                            }
                            if column.section280ACarryforward > 0 {
                                keyValue("Disallowed, carried forward", money(column.section280ACarryforward))
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }

                section("Material participation (§469)") {
                    keyValue("Average period of customer use", "\(Fmt.number(participation.averageStayNights)) nights over \(participation.completedStays) stays")
                    keyValue("Seven-day exception", participation.isShortTermRentalException ? "Met" : "Not met")
                    keyValue("Qualifying hours logged", Fmt.hours(participation.qualifyingHours))
                    keyValue("Hours by others recorded", Fmt.hours(participation.otherIndividualHours))
                    keyValue("Tests met", participation.tests.filter(\.isMet).map(\.title).joined(separator: ", ").isEmpty
                             ? "None"
                             : participation.tests.filter(\.isMet).map(\.title).joined(separator: ", "))
                    keyValue("Treatment", participation.lossIsNonPassive ? "Non-passive" : "Passive")
                }

                if !reconciliations.isEmpty {
                    section("Form 1099-K reconciliation") {
                        ForEach(reconciliations) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.platform.title).font(Page.headingFont)
                                keyValue("Gross rents recorded", money(item.recordedGrossRents))
                                keyValue("Lodging tax collected", money(item.lodgingTaxCollected))
                                keyValue("Expected on Form 1099-K", money(item.recordedGuestCharges))
                                if item.hasForm {
                                    keyValue("Reported on Form 1099-K", money(item.reportedOnForm))
                                    keyValue("Variance", money(item.variance))
                                }
                                keyValue("Host fees deducted", money(item.platformFees))
                            }
                            .padding(.bottom, 4)
                        }
                    }
                }

                section("Operating metrics") {
                    keyValue("Nights booked", "\(metrics.nightsBooked) of \(metrics.nightsAvailable) available")
                    keyValue("Occupancy", Fmt.percent(metrics.occupancyPercent))
                    keyValue("Average daily rate", money(metrics.averageDailyRate))
                    keyValue("RevPAR", money(metrics.revPAR))
                    keyValue("Platform fee drag", Fmt.percent(metrics.feeDragPercent))
                    keyValue("Depreciation claimed", money(report.totalDepreciation))
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Page.headingFont)
            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5)
            content()
        }
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).font(Page.bodyFont)
            Spacer(minLength: 12)
            Text(value).font(Page.bodyFont).multilineTextAlignment(.trailing)
        }
    }
}

/// Page three: the depreciation schedule for the year.
/// One line of the printed depreciation schedule.
struct DepreciationPDFRow: Identifiable {
    let id: UUID
    let propertyName: String
    let spec: DepreciationSpec
    let row: DepreciationYearRow
}

struct DepreciationPDFPage: View {

    let year: Int
    let rows: [DepreciationPDFRow]
    let currencyCode: String

    private func money(_ value: Decimal) -> String {
        Fmt.currency(value, code: currencyCode, hideCents: true)
    }

    var body: some View {
        PDFPageChrome(
            title: "Depreciation schedule — \(year)",
            subtitle: "MACRS, computed per asset",
            footer: "Mid-month straight line for real property; declining balance with a straight-line switch and the half-year convention for personal property."
        ) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Rectangle().fill(Color.black.opacity(0.15)).frame(height: 0.5)
                ForEach(rows) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.spec.name).font(Page.bodyFont).frame(width: 150, alignment: .leading).lineLimit(2)
                        Text(item.propertyName).font(Page.bodyFont).frame(width: 90, alignment: .leading).lineLimit(1)
                        Text(Fmt.isoDate(item.spec.placedInService)).font(Page.bodyFont).frame(width: 66, alignment: .leading)
                        Text(Fmt.number(item.spec.recoveryYears)).font(Page.bodyFont).frame(width: 30, alignment: .trailing)
                        Text(money(item.spec.basis)).font(Page.bodyFont).frame(width: 70, alignment: .trailing)
                        Text(money(item.row.total)).font(Page.bodyFont).frame(width: 66, alignment: .trailing)
                        Text(money(item.row.accumulated)).font(Page.bodyFont).frame(width: 66, alignment: .trailing)
                    }
                    .padding(.vertical, 1)
                }
                Rectangle().fill(Color.black.opacity(0.15)).frame(height: 0.5).padding(.top, 4)
                HStack {
                    Text("Total depreciation for \(year)").font(Page.headingFont)
                    Spacer()
                    Text(money(rows.map { $0.row.total }.total)).font(Page.headingFont)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Asset").frame(width: 150, alignment: .leading)
            Text("Property").frame(width: 90, alignment: .leading)
            Text("In service").frame(width: 66, alignment: .leading)
            Text("Life").frame(width: 30, alignment: .trailing)
            Text("Basis").frame(width: 70, alignment: .trailing)
            Text("This year").frame(width: 66, alignment: .trailing)
            Text("Accumulated").frame(width: 66, alignment: .trailing)
        }
        .font(Page.headingFont)
    }
}
