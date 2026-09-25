//
//  SettingsDetailViews.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

// MARK: - Appearance

struct SettingsAppearanceView: View {

    @Environment(AppSettings.self) private var settings

    private let currencies = ["USD", "CAD", "EUR", "GBP", "AUD", "NZD", "CHF", "MXN", "JPY"]

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.title, systemImage: theme.symbol).tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Accent colour") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(PropertyPalette.hexes, id: \.self) { hex in
                            Button {
                                settings.accentHex = hex
                                Haptics.play(.selection)
                            } label: {
                                Circle()
                                    .fill(PropertyPalette.color(for: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if settings.accentHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Numbers") {
                Picker("Currency", selection: $settings.currencyCode) {
                    ForEach(currencies, id: \.self) { code in
                        Text("\(code) · \(Fmt.currencySymbol(for: code))").tag(code)
                    }
                }
                Toggle("Hide cents", isOn: $settings.hideCents)
                DetailRow("Preview", value: settings.formatted(12_345.67))
            }

            Section {
                Toggle("Always use the current year", isOn: $settings.followsCurrentYear)
                if !settings.followsCurrentYear {
                    Picker("Default tax year", selection: $settings.pinnedTaxYear) {
                        ForEach(DateMath.selectableYears(), id: \.self) { year in
                            Text(verbatim: "\(year)").tag(year)
                        }
                    }
                }
            } header: {
                Text("Default year")
            } footer: {
                Text("Useful in the spring, when you are still working on last year's return.")
                    .font(.caption2)
            }
        }
        .platformFormStyle()
        .navigationTitle("Appearance")
        .inlineNavigationTitle()
    }
}

// MARK: - Capture defaults

struct SettingsCaptureDefaultsView: View {

    @Environment(AppSettings.self) private var settings
    @Query(sort: \Property.sortIndex) private var properties: [Property]

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("New entries") {
                Picker("Default property", selection: Binding(
                    get: { settings.defaultPropertyID },
                    set: { settings.defaultPropertyID = $0 }
                )) {
                    Text("First in the list").tag(UUID?.none)
                    ForEach(properties) { property in
                        Text(property.displayName).tag(UUID?.some(property.id))
                    }
                }
                Picker("Default payment method", selection: $settings.defaultPaymentMethod) {
                    ForEach(PaymentMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
            }

            Section {
                Toggle("Post recurring bills automatically", isOn: $settings.autoRunRecurringRules)
                Text("Rules marked auto-post are created when their date arrives. Rules that are not stay in a list for you to confirm — the app will not invent a transaction on your behalf.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Recurring bills")
            }
        }
        .platformFormStyle()
        .navigationTitle("Entry defaults")
        .inlineNavigationTitle()
    }
}

// MARK: - Notifications

struct SettingsNotificationsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(NotificationService.self) private var notifications
    @Environment(AppState.self) private var appState
    @Query(sort: \Property.sortIndex) private var properties: [Property]

    private var weekdays: [String] { DateMath.calendar.weekdaySymbols }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                switch notifications.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    Label("Notifications are allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    DetailRow("Scheduled", value: "\(notifications.pendingCount)")
                case .denied:
                    InfoCallout(
                        level: .caution,
                        message: "Notifications are turned off for this app in system settings. Reminders cannot be delivered until they are allowed there."
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                default:
                    Button("Allow notifications") {
                        Task { await notifications.requestAuthorization() }
                    }
                }
            } header: {
                Text("Permission")
            }

            Section("Reminders") {
                Toggle("Estimated tax due dates", isOn: $settings.notifyQuarterlyTaxes)
                Toggle("Permit and insurance renewals", isOn: $settings.notifyPermitExpiry)
                Toggle("Personal-use limit warnings", isOn: $settings.notifyPersonalUseThreshold)
                Toggle("Receipts still missing", isOn: $settings.notifyMissingReceipts)
            }

            Section {
                Toggle("Weekly log reminder", isOn: $settings.notifyWeeklyLogReminder)
                if settings.notifyWeeklyLogReminder {
                    Picker("Day", selection: $settings.weeklyReminderWeekday) {
                        ForEach(1...7, id: \.self) { index in
                            Text(weekdays.indices.contains(index - 1) ? weekdays[index - 1] : "\(index)")
                                .tag(index)
                        }
                    }
                    Picker("Time", selection: $settings.weeklyReminderHour) {
                        ForEach(6...22, id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                }
            } header: {
                Text("Keeping the log current")
            } footer: {
                Text("A mileage or participation entry written the same day carries far more weight than one reconstructed in April.")
                    .font(.caption2)
            }

            Section {
                Button("Reschedule everything now") {
                    Task { await reschedule() }
                }
                Button("Cancel all reminders", role: .destructive) {
                    notifications.cancelAll()
                }
            }

            if let error = notifications.lastError {
                Section {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .platformFormStyle()
        .navigationTitle("Notifications")
        .inlineNavigationTitle()
        .task { await notifications.refreshStatus() }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = DateMath.calendar.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    private func reschedule() async {
        guard await notifications.requestAuthorization() else { return }
        if settings.notifyPermitExpiry {
            await notifications.schedulePermitReminders(for: properties)
        }
        if settings.notifyWeeklyLogReminder {
            await notifications.scheduleWeeklyLogReminder(
                weekday: settings.weeklyReminderWeekday,
                hour: settings.weeklyReminderHour
            )
        }
        Haptics.play(.success)
    }
}

// MARK: - Security

struct SettingsSecurityView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppLockService.self) private var lock

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Require \(lock.biometry.title)", isOn: $settings.appLockEnabled)
                    .disabled(!lock.isBiometryAvailable)
                if !lock.isBiometryAvailable {
                    Text("This device has no passcode or biometrics set up, so app lock is unavailable.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if settings.appLockEnabled {
                    Picker("Lock after", selection: $settings.lockTimeout) {
                        ForEach(LockTimeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout)
                        }
                    }
                    Button("Lock now") { lock.lockNow() }
                }
            } header: {
                Text("App lock")
            } footer: {
                Text("A tax file is a complete picture of your finances. Locking it costs nothing and takes a glance to undo.")
                    .font(.caption2)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    privacyLine("Your records stay on your device", "Bookings, receipts and figures are stored locally, and in your own iCloud account if you turn sync on.")
                    privacyLine("Receipt text is read on device", "Optical character recognition runs locally with Apple's Vision framework. Photographs are never uploaded.")
                    privacyLine("No analytics, no accounts, no advertising", "The app has no server of its own, so there is nowhere for your data to go.")
                    privacyLine("You control every export", "Nothing is shared until you build a package and choose where to send it.")
                }
                .padding(.vertical, 4)
            } header: {
                Text("What leaves this device")
            }
        }
        .platformFormStyle()
        .navigationTitle("Privacy & security")
        .inlineNavigationTitle()
    }

    private func privacyLine(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Data

struct SettingsDataView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query private var properties: [Property]
    @Query private var bookings: [Booking]
    @Query private var expenses: [Expense]
    @Query private var trips: [MileageTrip]
    @Query private var participation: [ParticipationEntry]
    @Query private var documents: [StoredDocument]

    @State private var showingEraseConfirmation = false
    @State private var eraseConfirmationText = ""

    private var receiptCount: Int { expenses.filter(\.hasReceipt).count }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Sync with iCloud", isOn: $settings.iCloudSyncEnabled)
                Text(settings.iCloudSyncEnabled
                     ? "Your records sync through your private iCloud database. Quit and reopen the app for a change to take effect."
                     : "Records are kept on this device only. Turning sync on keeps every device you own up to date, in your own iCloud account.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Sync")
            }

            Section("What you have") {
                DetailRow("Properties", value: "\(properties.count)")
                DetailRow("Bookings", value: "\(bookings.count)")
                DetailRow("Expenses", value: "\(expenses.count)", caption: "\(receiptCount) with a receipt attached")
                DetailRow("Mileage entries", value: "\(trips.count)")
                DetailRow("Participation entries", value: "\(participation.count)")
                DetailRow("Documents", value: "\(documents.count)")
            }

            Section {
                NavigationLink {
                    ExportView()
                } label: {
                    Label("Export everything", systemImage: "square.and.arrow.up")
                }
                NavigationLink {
                    ImportView(kind: .bookings)
                } label: {
                    Label("Import a CSV", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Moving your data")
            } footer: {
                Text("Export before you change devices, and keep a copy with your return. Tax records should be kept for at least three years, and seven is safer.")
                    .font(.caption2)
            }

            Section {
                Button("Reset settings to defaults") {
                    settings.resetToDefaults()
                    Haptics.play(.warning)
                }
                Button("Erase all records", role: .destructive) {
                    showingEraseConfirmation = true
                }
            } header: {
                Text("Danger")
            }
        }
        .platformFormStyle()
        .navigationTitle("Data & sync")
        .inlineNavigationTitle()
        .alert("Erase everything?", isPresented: $showingEraseConfirmation) {
            TextField("Type ERASE to confirm", text: $eraseConfirmationText)
            Button("Cancel", role: .cancel) { eraseConfirmationText = "" }
            Button("Erase", role: .destructive) {
                if eraseConfirmationText.uppercased() == "ERASE" { eraseEverything() }
                eraseConfirmationText = ""
            }
        } message: {
            Text("Every property, booking, receipt, mileage entry and document is deleted permanently. This cannot be undone, and it is not covered by an iCloud backup once it syncs.")
        }
    }

    private func eraseEverything() {
        for property in properties { context.delete(property) }
        for booking in bookings { context.delete(booking) }
        for expense in expenses { context.delete(expense) }
        for trip in trips { context.delete(trip) }
        for entry in participation { context.delete(entry) }
        for document in documents { context.delete(document) }
        try? context.save()
        Haptics.play(.warning)
    }
}

// MARK: - About

struct AboutView: View {

    private var version: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A tax tracker for short-term rental hosts")
                        .font(.headline)
                    Text("Built around Schedule E rather than bolted onto a general ledger, so every figure you record has a line on the form it belongs to — and the rules that decide whether you can claim it are checked as you go.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Version") {
                DetailRow("App version", value: version)
                DetailRow("Rate tables", value: "Published through \(FederalRates.latestPublishedYear)")
                DetailRow("Mileage rates", value: "Published through \(MileageRateTable.latestPublishedYear)")
            }

            Section {
                Text("This app produces estimates to help you plan and to give your accountant a complete, documented file. It is not tax advice, it does not file anything, and it cannot replace professional judgement on the positions it helps you measure.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Important")
            }
        }
        .platformFormStyle()
        .navigationTitle("About")
        .inlineNavigationTitle()
    }
}
