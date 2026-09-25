//
//  BookingsView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct BookingsView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(sort: \Property.sortIndex) private var properties: [Property]
    @Query(sort: \Booking.checkIn, order: .reverse) private var allBookings: [Booking]

    @State private var searchText = ""
    @State private var platformFilter: RentalPlatform?
    @State private var propertyFilter: UUID?
    @State private var showCancelled = false
    @State private var editing: Booking?

    private var year: Int { appState.taxYear }

    private var yearBookings: [Booking] {
        allBookings.filter { booking in
            booking.nights(inYear: year) > 0 || DateMath.contains(booking.checkIn, inYear: year)
        }
    }

    private var filtered: [Booking] {
        yearBookings.filter { booking in
            if !showCancelled && booking.isCancelled { return false }
            if let platformFilter, booking.platform != platformFilter { return false }
            if let propertyFilter, booking.property?.id != propertyFilter { return false }
            if !searchText.isEmpty {
                let haystack = [
                    booking.guestName,
                    booking.confirmationCode,
                    booking.property?.displayName ?? "",
                    booking.notes
                ].joined(separator: " ").lowercased()
                if !haystack.contains(searchText.lowercased()) { return false }
            }
            return true
        }
    }

    private struct MonthGroup: Identifiable {
        let id: Date
        let bookings: [Booking]
        var month: Date { id }
    }

    private var grouped: [MonthGroup] {
        let groups = Dictionary(grouping: filtered) { booking -> Date in
            let components = DateMath.calendar.dateComponents([.year, .month], from: booking.checkIn)
            return DateMath.calendar.date(from: components) ?? booking.checkIn
        }
        return groups.keys.sorted(by: >).map { key in
            MonthGroup(id: key, bookings: groups[key]?.sorted { $0.checkIn > $1.checkIn } ?? [])
        }
    }

    private var totals: (gross: Decimal, fees: Decimal, nights: Int) {
        let active = filtered.filter { !$0.isCancelled }
        return (
            active.reduce(Decimal.zero) { $0 + $1.grossRents * $1.yearFraction(year) },
            active.reduce(Decimal.zero) { $0 + $1.totalPlatformFees * $1.yearFraction(year) },
            active.reduce(0) { $0 + $1.nights(inYear: year) }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if allBookings.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Bookings")
            .searchable(text: $searchText, prompt: "Guest, code or property")
            .toolbar { toolbar }
            .sheet(item: $editing) { booking in
                BookingEditorView(booking: booking)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    summaryPill("Gross rents", settings.formattedCompact(totals.gross), .green)
                    summaryPill("Platform fees", settings.formattedCompact(totals.fees), .orange)
                    summaryPill("Nights", "\(totals.nights)", .blue)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            }

            if filtered.isEmpty {
                Section {
                    Text("No bookings match the current filters for \(year).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(grouped) { group in
                Section {
                    ForEach(group.bookings) { booking in
                        Button {
                            editing = booking
                        } label: {
                            BookingRow(booking: booking, year: year, settings: settings)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(booking)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                booking.isCancelled.toggle()
                                try? context.save()
                                Haptics.play(.impact)
                            } label: {
                                Label(
                                    booking.isCancelled ? "Restore" : "Cancelled",
                                    systemImage: booking.isCancelled ? "arrow.uturn.backward" : "xmark.circle"
                                )
                            }
                            .tint(.orange)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        Text(settings.formattedCompact(
                            group.bookings
                                .filter { !$0.isCancelled }
                                .reduce(Decimal.zero) { $0 + $1.grossRents * $1.yearFraction(year) }
                        ))
                        .monospacedDigit()
                    }
                }
            }
        }
        .platformListStyle()
    }

    private func summaryPill(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardSurface(radius: 12)
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "calendar.badge.plus",
            title: "No bookings yet",
            message: "Add a stay by hand, or import your Airbnb or Vrbo payout CSV and the app will read the dates, fees and taxes out of it.",
            actionTitle: "Add a booking"
        ) {
            appState.open(.booking)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.open(.booking)
            } label: {
                Label("Add booking", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .principal) { YearMenu() }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker("Platform", selection: $platformFilter) {
                    Text("All platforms").tag(RentalPlatform?.none)
                    ForEach(RentalPlatform.allCases) { platform in
                        Text(platform.title).tag(RentalPlatform?.some(platform))
                    }
                }
                Picker("Property", selection: $propertyFilter) {
                    Text("All properties").tag(UUID?.none)
                    ForEach(properties) { property in
                        Text(property.displayName).tag(UUID?.some(property.id))
                    }
                }
                Toggle("Show cancelled", isOn: $showCancelled)
                Divider()
                NavigationLink {
                    ImportView(kind: .bookings)
                } label: {
                    Label("Import a CSV", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private func delete(_ booking: Booking) {
        context.delete(booking)
        try? context.save()
        Haptics.play(.warning)
    }
}

struct BookingRow: View {
    let booking: Booking
    let year: Int
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(booking.checkIn.formatted(.dateTime.day()))
                    .font(.headline)
                    .monospacedDigit()
                Text(booking.checkIn.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(booking.displayGuest)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .strikethrough(booking.isCancelled)
                    if booking.isInProgress {
                        TagChip("In house", symbol: "person.fill.checkmark", tint: .green)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: booking.platform.symbol)
                        .font(.caption2)
                        .foregroundStyle(PropertyPalette.color(for: booking.platform.tintHex))
                    Text("\(booking.nights) night\(booking.nights == 1 ? "" : "s")")
                    if let property = booking.property {
                        Text("· \(property.displayName)").lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if !booking.validationIssues.isEmpty {
                    Text(booking.validationIssues[0].message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if booking.hasPayoutVariance {
                    Text("Payout differs by \(settings.formatted(booking.payoutVariance))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(settings.formatted(booking.grossRents))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if booking.totalPlatformFees > 0 {
                    Text("−\(settings.formatted(booking.totalPlatformFees)) fees")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .opacity(booking.isCancelled ? 0.55 : 1)
    }
}
