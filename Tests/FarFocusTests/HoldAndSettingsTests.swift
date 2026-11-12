import CoreGraphics
import Foundation
import IOKit.pwr_mgt
import Testing
@testable import FarFocus

@Suite("Hold rules")
struct HoldRuleTests {

    @Test func aWindowCoversADisplayOnlyWhenItFillsIt() {
        let display = CGRect(x: -114, y: -1050, width: 1680, height: 1050)
        #expect(HoldDetector.covers(display, display))
        #expect(HoldDetector.covers(CGRect(x: -114, y: -1050, width: 1680, height: 1050.5), display))
        #expect(!HoldDetector.covers(CGRect(x: -114, y: -1025, width: 1680, height: 1025), display), "a maximised window under the menu bar is not full screen")
        #expect(!HoldDetector.covers(CGRect(x: 0, y: 0, width: 1440, height: 900), display))
    }

    private func assertion(_ type: String, _ name: String) -> [String: Any] {
        [kIOPMAssertionTypeKey as String: type, kIOPMAssertionNameKey as String: name]
    }

    @Test func displaySleepAssertionsFromTheFrontmostAppCount() {
        #expect(HoldDetector.isMediaAssertion(assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep, "Playing"),
                                              ownedByFrontmost: true))
        #expect(HoldDetector.isMediaAssertion(assertion(kIOPMAssertionTypeNoDisplaySleep, "Keynote"),
                                              ownedByFrontmost: true))
    }

    @Test func mediaHelpersOfBrowsersCount() {
        #expect(HoldDetector.isMediaAssertion(assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep, "WebKit Media Playback"),
                                              ownedByFrontmost: false))
        #expect(HoldDetector.isMediaAssertion(assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep, "Video Wake Lock"),
                                              ownedByFrontmost: false))
    }

    @Test func keepAwakeToolsAndSystemSleepAssertionsDoNot() {
        #expect(!HoldDetector.isMediaAssertion(assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep, "caffeinate command-line tool"),
                                               ownedByFrontmost: false))
        #expect(!HoldDetector.isMediaAssertion(assertion(kIOPMAssertionTypePreventUserIdleSystemSleep, "Video export"),
                                               ownedByFrontmost: true))
    }

    @Test func holdReasonsExplainThemselves() {
        for reason in [HoldReason.screenShared, .mirroredDisplay, .fullScreenMedia, .focus] {
            #expect(!reason.explanation.isEmpty)
        }
    }
}

/// Settings in a dictionary: nothing touches UserDefaults on disk.
private final class MemoryStore: SettingsStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@Suite("Saved settings")
struct SavedSettingsTests {

    @Test func defaultsMatchTheEngine() {
        let s = AppSettings(store: MemoryStore())
        #expect(s.enabled && s.holdDuringFocus)
        #expect(s.breakSettings == BreakSettings())
    }

    @Test func changesAreSavedAndReported() {
        let store = MemoryStore()
        let s = AppSettings(store: store)
        var calls = 0
        s.onChange = { calls += 1 }
        s.workMinutes = 45
        s.postponeLimit = 0
        #expect(store.values[AppSettings.Keys.workMinutes] as? Int == 45)
        #expect(calls == 2)
        #expect(AppSettings(store: store).breakSettings.workInterval == 2700)
        #expect(AppSettings(store: store).breakSettings.postponeLimit == 0)
    }

    @Test func outOfRangeValuesAreRepaired() {
        let store = MemoryStore()
        store.values = [AppSettings.Keys.workMinutes: 999, AppSettings.Keys.breakSeconds: 1,
                        AppSettings.Keys.warningLead: 37, AppSettings.Keys.postponeLimit: -4,
                        AppSettings.Keys.idleThreshold: 7]
        let s = AppSettings(store: store)
        #expect(s.workMinutes == 120)
        #expect(s.breakSeconds == 10)
        #expect(s.warningLeadSeconds == 30)
        #expect(s.postponeLimit == 0)
        #expect(s.idleThresholdSeconds == 60)
    }
}
