//
//  VRBO_tax_trackerApp.swift
//  VRBO tax tracker
//
//  Created by Kelvin Wallace on 24/09/2026.
//

import SwiftData
import SwiftUI

@main
struct VRBO_tax_trackerApp: App {

    @State private var settings: AppSettings
    @State private var appState: AppState
    @State private var lock = AppLockService.shared
    @State private var notifications = NotificationService.shared

    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    init() {
        let settings = AppSettings.shared
        let outcome = PersistenceController.makeContainer(cloudSyncEnabled: settings.iCloudSyncEnabled)
        let state = AppState(taxYear: settings.activeTaxYear)
        state.storageWarning = outcome.degradationMessage

        self.container = outcome.container
        _settings = State(initialValue: settings)
        _appState = State(initialValue: state)

        if settings.appLockEnabled {
            AppLockService.shared.lockNow()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if settings.hasCompletedOnboarding {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .environment(settings)
            .environment(appState)
            .environment(lock)
            .environment(notifications)
            .preferredColorScheme(settings.theme.colorScheme)
            .tint(settings.accentColor)
            .task {
                await notifications.refreshStatus()
                lock.refreshBiometry()
                RecurringExpenseRunner.runIfNeeded(
                    context: container.mainContext,
                    settings: settings
                )
            }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.applicationDidEnterBackground(enabled: settings.appLockEnabled)
            case .active:
                lock.applicationWillEnterForeground(
                    enabled: settings.appLockEnabled,
                    timeout: settings.lockTimeout
                )
            default:
                break
            }
        }

        #if os(macOS)
        Settings {
            NavigationStack { SettingsView() }
                .environment(settings)
                .environment(appState)
                .environment(lock)
                .environment(notifications)
                .modelContainer(container)
                .frame(minWidth: 560, minHeight: 520)
        }
        #endif
    }
}
