//
//  ParticipationView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct ParticipationView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query(sort: \ParticipationEntry.date, order: .reverse) private var allEntries: [ParticipationEntry]

    @State private var timer = ParticipationTimer.shared
    @State private var editing: ParticipationEntry?
    @State private var showingNew = false
    @State private var timerProperty: Property?
    @State private var timerActivity: ParticipationActivity = .guestCommunication

    private var year: Int { appState.taxYear }

    private var entries: [ParticipationEntry] {
        allEntries.filter { DateMath.contains($0.date, inYear: year) }
    }

    private var analysis: MaterialParticipationAnalysis {
        Workspace.participation(
            year: year,
            properties: properties,
            entries: allEntries,
            settings: settings
        )
    }

    private struct ActivityTotal: Identifiable {
        let activity: ParticipationActivity
        let hours: Double
        var id: String { activity.rawValue }
    }

    private var byActivity: [ActivityTotal] {
        Dictionary(grouping: entries, by: \.activity)
            .map { ActivityTotal(activity: $0.key, hours: $0.value.map(\.hours).reduce(0, +)) }
            .sorted { $0.hours > $1.hours }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                timerCard
                totalsCard
                if !byActivity.isEmpty { breakdownCard }
                logCard
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Hours worked")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("Log hours", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) { YearMenu() }
        }
        .onAppear {
            if timerProperty == nil, let id = timer.propertyID {
                timerProperty = properties.first { $0.id == id }
            }
            if timer.isRunning { timerActivity = timer.activity }
        }
        .sheet(isPresented: $showingNew) { ParticipationEditorView(entry: nil) }
        .sheet(item: $editing) { entry in ParticipationEditorView(entry: entry) }
    }

    // MARK: - Timer

    private var timerCard: some View {
        SectionCard(
            timer.isRunning ? "Working now" : "Start a timer",
            subtitle: timer.isRunning
                ? "Running since \(timer.startedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")"
                : "The most reliable log is the one you did not have to remember",
            symbol: "clock"
        ) {
            VStack(spacing: 14) {
                if timer.isRunning {
                    Text(timer.elapsedLabel)
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(timer.activity.title)\(timerProperty.map { " · \($0.displayName)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            timer.cancel()
                            Haptics.play(.warning)
                        } label: {
                            Label("Discard", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            stopAndSave()
                        } label: {
                            Label("Stop and log", systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Picker("Activity", selection: $timerActivity) {
                        ForEach(ParticipationActivity.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    PropertyPickerField(
                        selection: $timerProperty,
                        properties: properties,
                        allowsNone: true,
                        noneLabel: "Whole portfolio"
                    )
                    Button {
                        timer.start(
                            activity: timerActivity,
                            propertyID: timerProperty?.id
                        )
                        Haptics.play(.success)
                    } label: {
                        Label("Start", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if timerActivity.isInvestorActivity {
                        InfoCallout(
                            level: .caution,
                            message: "Investor-type work does not count toward material participation. It is still logged, just excluded from the tests."
                        )
                    }
                }
            }
        }
    }

    private func stopAndSave() {
        guard let hours = timer.stop(), hours > 0 else { return }
        let entry = ParticipationEntry(
            date: Date(),
            hours: hours,
            activity: timer.activity,
            property: timerProperty
        )
        entry.wasTimed = true
        entry.loggedSameDay = true
        entry.descriptionText = timer.note
        context.insert(entry)
        try? context.save()
        Haptics.play(.success)
        editing = entry
    }

    // MARK: - Totals

    private var totalsCard: some View {
        SectionCard(
            "\(year) participation",
            subtitle: analysis.statusTitle,
            symbol: analysis.lossIsNonPassive ? "checkmark.seal.fill" : "hourglass"
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatTile(
                        label: "Qualifying hours",
                        value: Fmt.number(analysis.qualifyingHours),
                        caption: "of 500 for the main test",
                        symbol: "clock.fill",
                        tint: .blue
                    )
                    StatTile(
                        label: "Average stay",
                        value: "\(Fmt.number(analysis.averageStayNights)) nights",
                        caption: analysis.isShortTermRentalException ? "Under the 7-night threshold" : "Over the 7-night threshold",
                        symbol: "moon.stars",
                        tint: analysis.isShortTermRentalException ? .green : .orange
                    )
                    StatTile(
                        label: "Written same day",
                        value: Fmt.percent(analysis.contemporaneousPercent),
                        caption: "Contemporaneous records",
                        symbol: "pencil.and.list.clipboard",
                        tint: analysis.contemporaneousPercent >= 70 ? .green : .orange
                    )
                }

                Text(analysis.statusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink {
                    ParticipationTestsView()
                } label: {
                    Label("See all five tests", systemImage: "checklist")
                        .font(.subheadline)
                }
            }
        }
    }

    private var breakdownCard: some View {
        SectionCard("Where the hours went", symbol: "chart.pie") {
            VStack(spacing: 10) {
                ForEach(byActivity) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.activity.symbol)
                            .font(.caption)
                            .foregroundStyle(item.activity.isInvestorActivity ? .secondary : .tint)
                            .frame(width: 22)
                        Text(item.activity.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        if item.activity.isInvestorActivity {
                            TagChip("Excluded", tint: .secondary)
                        }
                        Spacer(minLength: 8)
                        Text(Fmt.hours(item.hours))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var logCard: some View {
        SectionCard("Log", subtitle: "\(entries.count) entries", symbol: "list.bullet") {
            VStack(spacing: 10) {
                if entries.isEmpty {
                    Text("Nothing logged for \(year) yet. Every message to a guest, every turnover, every supply run counts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries.prefix(25)) { entry in
                        Button { editing = entry } label: {
                            HStack(spacing: 10) {
                                Image(systemName: entry.activity.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.descriptionText.isEmpty ? entry.activity.title : entry.descriptionText)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(Fmt.shortDate(entry.date))
                                        if entry.wasTimed {
                                            Image(systemName: "stopwatch")
                                        }
                                        if entry.descriptionText.isEmpty {
                                            Text("· no description")
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(Fmt.hours(entry.hours))
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if entries.count > 25 {
                        Text("Showing the 25 most recent of \(entries.count).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Button { showingNew = true } label: {
                    Label("Log hours", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
        }
    }
}
