//
//  ParticipationTimer.swift
//  VRBO tax tracker
//
//  A running clock for hours worked on the rental. The start time is written to
//  disk immediately, so quitting the app, a crash or a restart cannot lose an
//  afternoon's work — which for a material participation log is real money.
//

import Foundation
import Observation

@Observable
public final class ParticipationTimer {

    public static let shared = ParticipationTimer()

    private static let startKey = "com.kelvin.vrbotaxtracker.timer.start"
    private static let activityKey = "com.kelvin.vrbotaxtracker.timer.activity"
    private static let propertyKey = "com.kelvin.vrbotaxtracker.timer.property"
    private static let noteKey = "com.kelvin.vrbotaxtracker.timer.note"

    public private(set) var startedAt: Date?
    public var activity: ParticipationActivity = .guestCommunication
    public var propertyID: UUID?
    public var note: String = ""
    /// Ticks so the view re-renders every second while running.
    public private(set) var tick: Date = Date()

    private var timerTask: Task<Void, Never>?
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    public var isRunning: Bool { startedAt != nil }

    public var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, tick.timeIntervalSince(startedAt))
    }

    public var elapsedHours: Double {
        (elapsed / 3600 * 100).rounded() / 100
    }

    public var elapsedLabel: String {
        let total = Int(elapsed)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    public func start(activity: ParticipationActivity, propertyID: UUID?, note: String = "") {
        self.activity = activity
        self.propertyID = propertyID
        self.note = note
        startedAt = Date()
        tick = Date()
        persist()
        beginTicking()
    }

    /// Stops the clock and returns the elapsed hours, or nil if it was not running.
    @discardableResult
    public func stop() -> Double? {
        guard startedAt != nil else { return nil }
        let hours = elapsedHours
        startedAt = nil
        timerTask?.cancel()
        timerTask = nil
        clear()
        return hours
    }

    public func cancel() {
        startedAt = nil
        timerTask?.cancel()
        timerTask = nil
        clear()
    }

    private func beginTicking() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.startedAt != nil else { return }
                self.tick = Date()
            }
        }
    }

    private func persist() {
        defaults.set(startedAt, forKey: Self.startKey)
        defaults.set(activity.rawValue, forKey: Self.activityKey)
        defaults.set(propertyID?.uuidString ?? "", forKey: Self.propertyKey)
        defaults.set(note, forKey: Self.noteKey)
    }

    private func clear() {
        defaults.removeObject(forKey: Self.startKey)
        defaults.removeObject(forKey: Self.activityKey)
        defaults.removeObject(forKey: Self.propertyKey)
        defaults.removeObject(forKey: Self.noteKey)
    }

    private func restore() {
        guard let saved = defaults.object(forKey: Self.startKey) as? Date else { return }
        // A timer left running for days was forgotten, not worked.
        guard Date().timeIntervalSince(saved) < 60 * 60 * 18 else {
            clear()
            return
        }
        startedAt = saved
        tick = Date()
        if let raw = defaults.string(forKey: Self.activityKey),
           let restored = ParticipationActivity(rawValue: raw) {
            activity = restored
        }
        if let raw = defaults.string(forKey: Self.propertyKey), !raw.isEmpty {
            propertyID = UUID(uuidString: raw)
        }
        note = defaults.string(forKey: Self.noteKey) ?? ""
        beginTicking()
    }
}
