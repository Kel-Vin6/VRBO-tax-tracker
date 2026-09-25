//
//  AuditReadinessView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct AuditReadinessView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]
    @Query private var participation: [ParticipationEntry]
    @Query private var documents: [StoredDocument]

    private var year: Int { appState.taxYear }

    private var report: AuditReadinessReport {
        AuditReadinessEngine.evaluate(
            year: year,
            properties: properties,
            expenses: expenses,
            trips: trips,
            participation: participation,
            documents: documents
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scoreCard
                if report.findings.isEmpty {
                    SectionCard("Nothing outstanding", symbol: "checkmark.seal.fill") {
                        Text("Receipts are attached where they are needed, the mileage log carries a business purpose, the day counts reconcile and the paperwork is filed. This year is ready to hand over.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(report.findings) { finding in
                        findingCard(finding)
                    }
                }
                examinerCard
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Audit readiness")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .primaryAction) { YearMenu() } }
    }

    private var scoreTint: Color {
        report.score >= 85 ? .green : (report.score >= 65 ? .orange : .red)
    }

    private var scoreCard: some View {
        SectionCard(report.headline, subtitle: "\(year) documentation", symbol: "checkmark.shield") {
            HStack(spacing: 18) {
                ProgressRing(
                    progress: Double(report.score) / 100,
                    lineWidth: 14,
                    tint: scoreTint,
                    label: "\(report.score)",
                    caption: report.grade
                )
                .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: 8) {
                    Text(report.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if report.totalAtRisk > 0 {
                        DetailRow(
                            "Deductions at risk",
                            value: settings.formatted(report.totalAtRisk),
                            valueColor: .orange
                        )
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func findingCard(_ finding: AuditFinding) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: finding.severity.symbol)
                        .foregroundStyle(severityTint(finding.severity))
                    Text(finding.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    TagChip(finding.severity.title, tint: severityTint(finding.severity))
                }
                Text(finding.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if finding.amountAtRisk > 0 {
                    Text("\(settings.formatted(finding.amountAtRisk)) of deductions affected.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                destinationLink(finding)
            }
        }
    }

    private func severityTint(_ severity: AuditSeverity) -> Color {
        switch severity {
        case .critical: .red
        case .important: .orange
        case .advisory: .yellow
        case .informational: .blue
        }
    }

    @ViewBuilder
    private func destinationLink(_ finding: AuditFinding) -> some View {
        switch finding.destination {
        case .expenses:
            Button(finding.actionLabel) { appState.selectedTab = .expenses }
                .font(.subheadline)
        case .bookings:
            Button(finding.actionLabel) { appState.selectedTab = .bookings }
                .font(.subheadline)
        case .mileage:
            NavigationLink(finding.actionLabel) { MileageView() }
                .font(.subheadline)
        case .personalUse:
            NavigationLink(finding.actionLabel) { PersonalUseView() }
                .font(.subheadline)
        case .participation:
            NavigationLink(finding.actionLabel) { ParticipationView() }
                .font(.subheadline)
        case .properties:
            NavigationLink(finding.actionLabel) { PropertiesView() }
                .font(.subheadline)
        case .depreciation:
            NavigationLink(finding.actionLabel) { DepreciationView() }
                .font(.subheadline)
        case .documents:
            NavigationLink(finding.actionLabel) { DocumentsView() }
                .font(.subheadline)
        case .settings:
            NavigationLink(finding.actionLabel) { SettingsView() }
                .font(.subheadline)
        }
    }

    private var examinerCard: some View {
        SectionCard("What an examiner asks for first", symbol: "list.clipboard") {
            VStack(alignment: .leading, spacing: 12) {
                FeatureLine(
                    symbol: "calendar",
                    title: "The day counts",
                    detail: "Rental days and personal-use days, and whether they add up against the calendar. Everything else follows from these two numbers."
                )
                FeatureLine(
                    symbol: "car",
                    title: "The mileage log",
                    detail: "Date, miles, destination and business purpose for each trip. A log missing any of the four is routinely disallowed in full."
                )
                FeatureLine(
                    symbol: "paperclip",
                    title: "Receipts over $75",
                    detail: "Below that, a bank record is usually enough. Above it, the receipt is the substantiation."
                )
                FeatureLine(
                    symbol: "arrow.left.arrow.right",
                    title: "The 1099-K reconciliation",
                    detail: "Why the form says one number and the return says another. Have the answer written down before the question arrives."
                )
                FeatureLine(
                    symbol: "clock",
                    title: "The participation log",
                    detail: "If you claimed a non-passive loss, expect this to be the first thing examined — and expect a bare hours total not to be enough."
                )
            }
        }
    }
}
