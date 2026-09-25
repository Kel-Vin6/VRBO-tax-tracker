//
//  HelpView.swift
//  VRBO tax tracker
//

import SwiftUI

struct HelpView: View {

    private struct Topic: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let body: String
    }

    private let topics: [Topic] = [
        Topic(
            title: "Cleaning fees are income",
            symbol: "sparkles",
            body: "The cleaning fee you charge a guest is rental income, reported on line 3 with the rest of the rent. The cleaner you pay is a separate deduction on line 7. Netting the two is the most common bookkeeping error on a host return, and it is the one that makes the 1099-K stop reconciling."
        ),
        Topic(
            title: "The platform's fee is deductible",
            symbol: "percent",
            body: "The host service fee never reaches your bank account, so it is easy to forget — but it is included in the gross the platform reports to the IRS, and it is deductible on line 8. Recording it both raises your deduction and explains the gap between the 1099-K and your return."
        ),
        Topic(
            title: "The 14-day rule cuts both ways",
            symbol: "calendar.badge.exclamationmark",
            body: "Rent the place out for fewer than 15 days in a year while using it as a residence and the income is not reported at all. Use it personally for more than the greater of 14 days or 10% of the days rented, and the property becomes a residence: expenses are allocated and no rental loss can be claimed. The app tracks how close you are to that line, all year."
        ),
        Topic(
            title: "Days spent on repairs are not personal days",
            symbol: "hammer",
            body: "A day you spend substantially full time repairing and maintaining the property does not count as personal use, even if your family is there. Record those days as repair days and they stay out of the §280A numerator."
        ),
        Topic(
            title: "Seven nights is the number that matters",
            symbol: "moon.stars",
            body: "If the average period of customer use is seven days or fewer, the activity is not a rental activity under §469 at all. Materially participate in it and a loss becomes non-passive, able to offset salary and other income. This is the single largest tax difference between a short-term rental and a long-term one."
        ),
        Topic(
            title: "Depreciation is not optional",
            symbol: "chart.line.downtrend.xyaxis",
            body: "When you sell, your basis is reduced by the depreciation you were allowed to take — whether or not you actually took it. Skipping it does not save the deduction for later; it simply loses it while still creating the recapture. Entering a purchase price and a land value is the most valuable five minutes you will spend in this app."
        ),
        Topic(
            title: "Land never depreciates",
            symbol: "leaf",
            body: "Only the building does. The split between land and improvements on your property tax assessment is the usual source for the allocation, and keeping a copy of that assessment with your records is what makes it defensible."
        ),
        Topic(
            title: "A repair is not an improvement",
            symbol: "arrow.triangle.branch",
            body: "A repair comes off this year's income in full; an improvement is written off over 27.5 years. Three safe harbors can rescue an item that would otherwise be capitalised — de minimis, routine maintenance and the small taxpayer safe harbor — and the app walks all three before falling back to the betterment, adaptation and restoration test."
        ),
        Topic(
            title: "Mileage needs four things",
            symbol: "car",
            body: "Date, miles, destination and business purpose. A log missing any one of them is routinely disallowed in full, however honest it is. Logging a drive on the day you make it is worth more than any amount of reconstruction in April."
        ),
        Topic(
            title: "Estimated tax has a safe harbor",
            symbol: "shield.lefthalf.filled",
            body: "Rental income is lumpy, so predicting the year is hard. You do not have to: pay 100% of last year's tax — 110% if your prior-year AGI was above $150,000 — or 90% of this year's, and the underpayment penalty cannot apply however well the season goes."
        ),
        Topic(
            title: "Substantial services move you to Schedule C",
            symbol: "exclamationmark.triangle",
            body: "Ordinary rental income belongs on Schedule E and is not subject to self-employment tax. Provide services beyond those customary for occupancy — daily housekeeping during a stay, meals, tours — and the activity can land on Schedule C, where the profit also carries 15.3% self-employment tax."
        ),
        Topic(
            title: "Keep the records for seven years",
            symbol: "archivebox",
            body: "Three years is the ordinary assessment period, six if income is substantially understated, and there is no limit where no return was filed. Records that support basis — the closing statement, improvements, the depreciation schedule — should be kept for as long as you own the property and then some."
        )
    ]

    var body: some View {
        List {
            Section {
                Text("The rules that decide most of a short-term rental return, in the order they tend to cost people money.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(topics) { topic in
                DisclosureGroup {
                    Text(topic.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                } label: {
                    Label(topic.title, systemImage: topic.symbol)
                        .font(.subheadline)
                }
            }
            Section {
                TaxDisclaimer(compact: true)
            }
        }
        .platformListStyle()
        .navigationTitle("How this works")
        .inlineNavigationTitle()
    }
}
