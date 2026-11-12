import Foundation
import Observation

/// Every setting, saved in UserDefaults (a throwaway store in demo mode, a dictionary in tests).
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings(store: Demo.isOn ? Demo.defaults : UserDefaults.standard)

    var enabled: Bool { didSet { save(enabled, Keys.enabled) } }
    var workMinutes: Int { didSet { save(workMinutes, Keys.workMinutes) } }
    var breakSeconds: Int { didSet { save(breakSeconds, Keys.breakSeconds) } }
    var warningLeadSeconds: Int { didSet { save(warningLeadSeconds, Keys.warningLead) } }
    var postponeLimit: Int { didSet { save(postponeLimit, Keys.postponeLimit) } }
    var idleThresholdSeconds: Int { didSet { save(idleThresholdSeconds, Keys.idleThreshold) } }
    var holdDuringFocus: Bool { didSet { save(holdDuringFocus, Keys.holdDuringFocus) } }

    /// Called after any change that affects the cycle.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let store: SettingsStore

    enum Keys {
        static let enabled = "enabled"
        static let workMinutes = "workMinutes"
        static let breakSeconds = "breakSeconds"
        static let warningLead = "warningLeadSeconds"
        static let postponeLimit = "postponeLimit"
        static let idleThreshold = "idleThresholdSeconds"
        static let holdDuringFocus = "holdDuringFocus"
    }

    init(store: SettingsStore) {
        self.store = store
        let d = BreakSettings()
        enabled = store.object(forKey: Keys.enabled) as? Bool ?? true
        workMinutes = Self.clamp(store.object(forKey: Keys.workMinutes) as? Int ?? Int(d.workInterval / 60),
                                 BreakSettings.workMinutesRange)
        breakSeconds = Self.clamp(store.object(forKey: Keys.breakSeconds) as? Int ?? Int(d.breakLength),
                                  BreakSettings.breakSecondsRange)
        warningLeadSeconds = Self.pick(store.object(forKey: Keys.warningLead) as? Int ?? Int(d.warningLead),
                                       BreakSettings.warningLeadChoices, fallback: Int(d.warningLead))
        postponeLimit = Self.clamp(store.object(forKey: Keys.postponeLimit) as? Int ?? d.postponeLimit,
                                   BreakSettings.postponeLimitRange)
        idleThresholdSeconds = Self.pick(store.object(forKey: Keys.idleThreshold) as? Int ?? Int(d.idleThreshold),
                                         BreakSettings.idleThresholdChoices, fallback: Int(d.idleThreshold))
        holdDuringFocus = store.object(forKey: Keys.holdDuringFocus) as? Bool ?? true
    }

    /// The cycle's numbers. Demo mode can shrink them to seconds to watch a whole cycle quickly.
    var breakSettings: BreakSettings {
        var s = BreakSettings()
        s.workInterval = Demo.workSeconds ?? TimeInterval(workMinutes * 60)
        s.breakLength = Demo.breakSeconds ?? TimeInterval(breakSeconds)
        s.warningLead = Demo.leadSeconds ?? TimeInterval(warningLeadSeconds)
        s.postponeLimit = postponeLimit
        s.idleThreshold = Demo.idleSeconds ?? TimeInterval(idleThresholdSeconds)
        return s
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        onChange?()
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func pick(_ value: Int, _ choices: [Int], fallback: Int) -> Int {
        choices.contains(value) ? value : fallback
    }
}

/// Where settings live: UserDefaults in the app, a plain dictionary in tests (nothing on disk).
protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}
