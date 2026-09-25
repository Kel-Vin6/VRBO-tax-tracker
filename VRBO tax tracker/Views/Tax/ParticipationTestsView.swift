//
//  ParticipationTestsView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct ParticipationTestsView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query private var entries: [ParticipationEntry]

    private var year: Int { appState.taxYear }

    private var analysis: MaterialParticipationAnalysis {
        Workspace.participation(year: year, properties: properties, entries: entries, settings: settings)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                verdictCard
                averageStayCard
                testsCard
                if let next = MaterialParticipationEngine.hoursToNearestTest(analysis) {
                    nextStepCard(next)
                }
                explainerCard
                TaxDisclaimer().padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Material participation")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .primaryAction) { YearMenu() } }
    }

    private var verdictCard: some View {
        SectionCard(
            analysis.statusTitle,
            subtitle: "\(year) · \(Fmt.hours(analysis.qualifyingHours)) qualifying",
            symbol: analysis.lossIsNonPassive ? "checkmark.seal.fill" : "hourglass"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ProgressRing(
                        progress: min(1, analysis.qualifyingHours / MaterialParticipationEngine.materialParticipationHours),
                        tint: analysis.meetsMaterialParticipation ? .green : .orange,
                        label: Fmt.number(analysis.qualifyingHours, fractionDigits: 0),
                        caption: "hours"
                    )
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 8) {
                        statusRow(
                            "Seven-day exception",
                            met: analysis.isShortTermRentalException,
                            detail: "Average stay \(Fmt.number(analysis.averageStayNights)) nights"
                        )
                        statusRow(
                            "Material participation",
                            met: analysis.meetsMaterialParticipation,
                            detail: analysis.meetsMaterialParticipation ? "At least one test met" : "No test met yet"
                        )
                        statusRow(
                            "Loss is non-passive",
                            met: analysis.lossIsNonPassive,
                            detail: analysis.lossIsNonPassive ? "Can offset other income" : "Suspended if there is a loss"
                        )
                    }
                    Spacer(minLength: 0)
                }

                Text(analysis.statusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusRow(_ title: String, met: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(met ? .green : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption.weight(.medium))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var averageStayCard: some View {
        SectionCard(
            "Average period of customer use",
            subtitle: "The test that comes before every other test",
            symbol: "moon.stars"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Fmt.number(analysis.averageStayNights))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(analysis.isShortTermRentalException ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("nights per stay").font(.subheadline)
                        Text("\(analysis.totalRentedNights) nights over \(analysis.completedStays) stay\(analysis.completedStays == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                thresholdBar

                Text("An activity is not a “rental activity” under §469 if the average period of customer use is seven days or fewer. That single sentence is why short-term rentals can produce a non-passive loss when a long-term rental cannot — but only if you also materially participate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if analysis.completedStays > 0 && analysis.averageStayNights > 7 && analysis.averageStayNights <= 30 {
                    InfoCallout(
                        level: .caution,
                        message: "Between 7 and 30 nights, the exception depends on providing significant personal services. That is a judgement call your accountant should make, not the app."
                    )
                }
            }
        }
    }

    private var thresholdBar: some View {
        GeometryReader { proxy in
            let maximum = max(14.0, analysis.averageStayNights * 1.2)
            let position = min(1, analysis.averageStayNights / maximum)
            let threshold = min(1, 7.0 / maximum)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.nestedFill)
                Capsule()
                    .fill(analysis.isShortTermRentalException ? Color.green : Color.orange)
                    .frame(width: max(4, proxy.size.width * position))
                Rectangle()
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 2)
                    .offset(x: proxy.size.width * threshold)
            }
        }
        .frame(height: 10)
    }

    private var testsCard: some View {
        SectionCard("The tests", subtitle: "Meeting any one of them is enough", symbol: "checklist") {
            VStack(spacing: 14) {
                ForEach(analysis.tests) { test in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: test.isMet ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(test.isMet ? .green : .secondary)
                            Text(test.title)
                                .font(.subheadline.weight(.semibold))
                            if test.isSelfAssessed {
                                TagChip("Judgement", tint: .orange)
                            }
                            Spacer(minLength: 0)
                        }
                        Text(test.requirement)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ProgressView(value: test.progress)
                            .tint(test.isMet ? .green : .accentColor)
                        Text(test.detail)
                            .font(.caption2)
                            .foregroundStyle(test.isMet ? .green : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func nextStepCard(_ next: (hours: Double, testTitle: String)) -> some View {
        SectionCard("What is left", symbol: "figure.walk") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Fmt.hours(next.hours)) more to meet the \(next.testTitle).")
                    .font(.headline)
                Text("That is roughly \(Fmt.hours(next.hours / 52)) a week for the rest of the year. Guest messages, pricing reviews, supply runs and turnovers all count — they just have to be written down.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    ParticipationView()
                } label: {
                    Label("Open the hours log", systemImage: "clock")
                        .font(.subheadline)
                }
            }
        }
    }

    private var explainerCard: some View {
        SectionCard("Why this is the biggest number on the return", symbol: "lightbulb") {
            VStack(alignment: .leading, spacing: 12) {
                FeatureLine(
                    symbol: "lock.open",
                    title: "Non-passive losses offset everything",
                    detail: "Salary, consulting income, dividends. A passive loss can only offset passive income and otherwise waits, sometimes for years."
                )
                FeatureLine(
                    symbol: "calendar",
                    title: "It is decided year by year",
                    detail: "Meeting the tests one year says nothing about the next. The log has to be kept every year you want the treatment."
                )
                FeatureLine(
                    symbol: "pencil.and.list.clipboard",
                    title: "The log is the evidence",
                    detail: "There is no form to file and nothing to elect. If it is questioned, what you have is your contemporaneous record — which is why this app timestamps every entry."
                )
                InfoCallout(
                    level: .caution,
                    message: "This is one of the most heavily examined positions in the code. Treat the tests as something to discuss with your accountant, with the log as your evidence — not as a box the app ticks for you."
                )
            }
        }
    }
}
