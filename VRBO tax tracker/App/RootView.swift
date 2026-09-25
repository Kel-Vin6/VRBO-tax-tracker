//
//  RootView.swift
//  VRBO tax tracker
//

import SwiftData
import SwiftUI

struct RootView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(AppLockService.self) private var lock

    var body: some View {
        @Bindable var state = appState

        ZStack {
            TabView(selection: $state.selectedTab) {
                Tab(AppTab.dashboard.title, systemImage: AppTab.dashboard.symbol, value: AppTab.dashboard) {
                    DashboardView()
                }
                Tab(AppTab.bookings.title, systemImage: AppTab.bookings.symbol, value: AppTab.bookings) {
                    BookingsView()
                }
                Tab(AppTab.expenses.title, systemImage: AppTab.expenses.symbol, value: AppTab.expenses) {
                    ExpensesView()
                }
                Tab(AppTab.taxes.title, systemImage: AppTab.taxes.symbol, value: AppTab.taxes) {
                    TaxCentreView()
                }
                Tab(AppTab.more.title, systemImage: AppTab.more.symbol, value: AppTab.more) {
                    MoreView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tint(settings.accentColor)

            if lock.isLocked {
                LockScreenView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.smooth(duration: 0.25), value: lock.isLocked)
        .sheet(item: $state.quickAction) { action in
            QuickActionSheet(action: action)
        }
        .alert(
            "Storage problem",
            isPresented: Binding(
                get: { appState.storageWarning != nil },
                set: { if !$0 { state.storageWarning = nil } }
            )
        ) {
            Button("OK", role: .cancel) { state.storageWarning = nil }
        } message: {
            Text(appState.storageWarning ?? "")
        }
    }
}

/// Routes the quick-add menu to the right editor.
struct QuickActionSheet: View {
    let action: QuickAction

    var body: some View {
        switch action {
        case .booking: BookingEditorView(booking: nil)
        case .expense: ExpenseEditorView(expense: nil)
        case .scanReceipt: ExpenseEditorView(expense: nil, startWithScanner: true)
        case .mileage: MileageEditorView(trip: nil)
        case .personalUse: PersonalUseEditorView(entry: nil)
        case .participation: ParticipationEditorView(entry: nil)
        case .property: PropertyEditorView(property: nil)
        }
    }
}
