import Foundation
import Testing
@testable import FarFocus

private func run(_ engine: inout FarFocusEngine, _ seconds: Int, hold: HoldReason? = nil) {
    for _ in 0..<seconds { engine.advance(by: 1, idle: 0, hold: hold) }
}

@Suite("Menu-bar text")
struct LabelTests {

    @Test func minutesRoundUpThenSeconds() {
        var e = FarFocusEngine()
        #expect(StatusText.label(for: e) == "20m")
        run(&e, 1)
        #expect(StatusText.label(for: e) == "20m", "19:59 left still reads 20m")
        run(&e, 59)
        #expect(StatusText.label(for: e) == "19m")
        run(&e, 1200 - 60 - 61)
        #expect(StatusText.label(for: e) == "2m")   // 61 s
        run(&e, 1)
        #expect(StatusText.label(for: e) == "60s")
        run(&e, 15)
        #expect(StatusText.label(for: e) == "45s")
    }

    @Test func secondsDuringWarningNothingDuringBreak() {
        var e = FarFocusEngine()
        run(&e, 1176)
        #expect(StatusText.label(for: e) == "24s")
        run(&e, 25)
        #expect(e.phase == .breaking)
        #expect(StatusText.label(for: e) == "")
    }

    @Test func dueWhileHeldEmptyWhenOff() {
        var e = FarFocusEngine()
        run(&e, 1171, hold: .screenShared)
        #expect(StatusText.label(for: e) == "due")
        #expect(StatusText.statusLine(for: e) == "Holding: your screen is being shared or recorded")
        e.setEnabled(false)
        #expect(StatusText.label(for: e) == "")
        #expect(StatusText.statusLine(for: e) == "Eye breaks are off")
    }

    @Test func labelChangesOnlyOncePerMinuteFarAway() {
        var e = FarFocusEngine()
        var changes = 0
        var last = StatusText.label(for: e)
        for _ in 0..<600 {
            e.advance(by: 1, idle: 0, hold: nil)
            let now = StatusText.label(for: e)
            if now != last { changes += 1; last = now }
        }
        #expect(changes == 10)
    }

    @Test func statusLines() {
        var e = FarFocusEngine()
        #expect(StatusText.statusLine(for: e) == "Next break in 20 min")
        e.advance(by: 5, idle: 600, hold: nil)
        #expect(StatusText.statusLine(for: e) == "Paused while you're away")
        #expect(StatusText.accessibilityLabel(for: e) == "FarFocus, paused while you're away")
    }

    @Test func clockFormat() {
        #expect(StatusText.clock(24) == "0:24")
        #expect(StatusText.clock(65) == "1:05")
        #expect(StatusText.clock(720) == "12:00")
        #expect(StatusText.clock(-3) == "0:00")
        #expect(StatusText.clock(24, padded: true) == "00:24")
        #expect(StatusText.clock(605, padded: true) == "10:05")
        #expect(StatusText.duration(45) == "45 s")
        #expect(StatusText.duration(61) == "2 min")
        #expect(StatusText.duration(7200) == "120 min")
    }
}
