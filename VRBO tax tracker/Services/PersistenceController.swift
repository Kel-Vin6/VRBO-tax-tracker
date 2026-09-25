//
//  PersistenceController.swift
//  VRBO tax tracker
//

import Foundation
import SwiftData

public enum PersistenceController {

    public static let schema = Schema([
        Property.self,
        Booking.self,
        Expense.self,
        MileageTrip.self,
        PersonalUseEntry.self,
        ParticipationEntry.self,
        DepreciableAsset.self,
        LoanAccount.self,
        EstimatedTaxPayment.self,
        StoredDocument.self,
        RecurringExpenseRule.self,
        PlatformTaxForm.self
    ])

    public struct Outcome {
        public var container: ModelContainer
        /// Set when the app had to fall back, so the UI can tell the truth
        /// instead of silently losing the user's data.
        public var degradationMessage: String?
    }

    public static func makeContainer(cloudSyncEnabled: Bool) -> Outcome {
        if cloudSyncEnabled {
            let cloudConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
                return Outcome(container: container, degradationMessage: nil)
            }
        }

        let localConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
            return Outcome(
                container: container,
                degradationMessage: cloudSyncEnabled
                    ? "iCloud sync could not be started, so your records are being saved on this device only. Check that you are signed in to iCloud, then turn sync off and on again in Settings."
                    : nil
            )
        }

        let memoryConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [memoryConfiguration])
            return Outcome(
                container: container,
                degradationMessage: "The saved database could not be opened, so this session is running in memory and nothing will be kept when you quit. Export your data before closing the app."
            )
        } catch {
            fatalError("Unable to create a model container of any kind: \(error)")
        }
    }
}
