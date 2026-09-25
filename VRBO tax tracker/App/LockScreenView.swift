//
//  LockScreenView.swift
//  VRBO tax tracker
//

import SwiftUI

struct LockScreenView: View {

    @Environment(AppLockService.self) private var lock
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: lock.biometry.symbol)
                    .font(.system(size: 56))
                    .foregroundStyle(settings.accentColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: lock.isAuthenticating)

                VStack(spacing: 6) {
                    Text("Your records are locked")
                        .font(.title3.weight(.semibold))
                    Text("Unlock with \(lock.biometry.title) to see your bookings, receipts and tax figures.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                if let error = lock.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                Button {
                    Task { await lock.authenticate() }
                } label: {
                    Label("Unlock", systemImage: "lock.open")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(lock.isAuthenticating)
            }
            .padding(32)
        }
        .task {
            if lock.lastError == nil {
                await lock.authenticate()
            }
        }
    }
}
