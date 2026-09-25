//
//  AppLockService.swift
//  VRBO tax tracker
//
//  A tax file is a complete picture of someone's finances. Locking it behind
//  the device's own biometrics costs the user nothing and is the first thing
//  they ask for.
//

import Foundation
import LocalAuthentication
import Observation

public enum BiometryKind: String, Sendable {
    case none, touchID, faceID, opticID, passcode

    public var title: String {
        switch self {
        case .none: "Device passcode"
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        case .opticID: "Optic ID"
        case .passcode: "Device passcode"
        }
    }

    public var symbol: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .none, .passcode: "lock"
        }
    }
}

@Observable
public final class AppLockService {

    public static let shared = AppLockService()

    public private(set) var isLocked: Bool = false
    public private(set) var isAuthenticating: Bool = false
    public private(set) var lastError: String?
    public private(set) var biometry: BiometryKind = .none

    /// When the app last went to the background, used with the grace period.
    private var backgroundedAt: Date?

    public init() {
        refreshBiometry()
    }

    public func refreshBiometry() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            biometry = .none
            return
        }
        switch context.biometryType {
        case .faceID: biometry = .faceID
        case .touchID: biometry = .touchID
        case .opticID: biometry = .opticID
        default: biometry = .passcode
        }
    }

    public var isBiometryAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public func lockNow() {
        isLocked = true
        lastError = nil
    }

    public func unlockWithoutAuthenticating() {
        isLocked = false
    }

    public func applicationDidEnterBackground(enabled: Bool) {
        guard enabled else { return }
        backgroundedAt = Date()
    }

    /// Re-locks only once the configured grace period has elapsed, so switching
    /// apps to check a receipt does not demand a new scan every time.
    public func applicationWillEnterForeground(enabled: Bool, timeout: LockTimeout) {
        guard enabled else {
            isLocked = false
            return
        }
        guard let backgroundedAt else {
            isLocked = true
            return
        }
        let elapsedMinutes = Date().timeIntervalSince(backgroundedAt) / 60
        if elapsedMinutes >= Double(timeout.rawValue) {
            isLocked = true
        }
        self.backgroundedAt = nil
    }

    @discardableResult
    public func authenticate(reason: String = "Unlock your tax records") async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // With no passcode set there is nothing to authenticate against, so
            // refusing entry would lock the user out of their own data.
            lastError = "This device has no passcode or biometrics set up, so app lock cannot be used."
            isLocked = false
            return true
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                isLocked = false
                lastError = nil
            }
            return success
        } catch let authError as LAError {
            lastError = Self.message(for: authError)
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private static func message(for error: LAError) -> String? {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return nil
        case .userFallback:
            return "Enter your device passcode to continue."
        case .biometryNotEnrolled:
            return "No biometrics are enrolled on this device. Set them up in system settings, or turn app lock off."
        case .biometryLockout:
            return "Too many failed attempts. Unlock the device with its passcode first."
        default:
            return error.localizedDescription
        }
    }
}
