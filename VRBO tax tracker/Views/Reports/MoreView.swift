//
//  MoreView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct MoreView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @Query private var properties: [Property]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]
    @Query private var participation: [ParticipationEntry]
    @Query private var documents: [StoredDocument]

    private var year: Int { appState.taxYear }

    private var auditScore: Int {
        AuditReadinessEngine.evaluate(
            year: year,
            properties: properties,
            expenses: expenses,
            trips: trips,
            participation: participation,
            documents: documents
        ).score
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Logs") {
                    row("Properties", "house", .teal) { PropertiesView() }
                    row("Mileage", "car", .blue, badge: "\(trips.filter { DateMath.contains($0.date, inYear: year) }.count)") { MileageView() }
                    row("Personal use", "figure.and.child.holdinghands", .orange) { PersonalUseView() }
                    row("Hours worked", "clock", .purple) { ParticipationView() }
                    row("Documents", "folder", .indigo, badge: "\(documents.count)") { DocumentsView() }
                    row("Recurring bills", "repeat", .green) { RecurringExpensesView() }
                }

                Section("Tools") {
                    row("Reports & analytics", "chart.xyaxis.line", .pink) { ReportsView() }
                    row("Export for your accountant", "square.and.arrow.up", .blue) { ExportView() }
                    row("Import a CSV", "square.and.arrow.down", .teal) { ImportView(kind: .bookings) }
                    row("Audit readiness", "checkmark.shield", auditScore >= 85 ? .green : .orange, badge: "\(auditScore)") { AuditReadinessView() }
                }

                Section("App") {
                    row("Settings", "gearshape", .gray) { SettingsView() }
                    row("How this app works", "questionmark.circle", .gray) { HelpView() }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not tax advice")
                            .font(.caption.weight(.semibold))
                        TaxDisclaimer(compact: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            .platformListStyle()
            .navigationTitle("More")
            .toolbar { ToolbarItem(placement: .principal) { YearMenu() } }
        }
    }

    private func row<Destination: View>(
        _ title: String,
        _ symbol: String,
        _ tint: Color,
        badge: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
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
                if let badge {
                    Text(badge)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
