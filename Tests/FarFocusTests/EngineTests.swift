import Foundation
import Testing
@testable import FarFocus

/// Runs the engine for `seconds` in 1-second ticks with someone at the keyboard.
private func run(_ engine: inout FarFocusEngine, _ seconds: Int, idle: TimeInterval = 0, hold: HoldReason? = nil) {
    for _ in 0..<seconds { engine.advance(by: 1, idle: idle, hold: hold) }
}

private let defaults = BreakSettings()

@Suite("Cycle")
struct CycleTests {

    @Test func defaultsAreTheTwentyTwentyRule() {
        #expect(defaults.workInterval == 1200)
        #expect(defaults.breakLength == 20)
        #expect(defaults.warningLead == 30)
        #expect(defaults.postponeLimit == 4)
        #expect(defaults.idleThreshold == 60)
        #expect(BreakSettings.countdownLength == 5)
        #expect(BreakSettings.postponeChoices == [1, 5, 15])
    }

    @Test func fullCycleWalksEveryPhaseInOrder() {
        var e = FarFocusEngine()
        #expect(e.phase == .working && e.remaining == 1200 && e.surface == .none)

        run(&e, 1169)
        #expect(e.phase == .working && e.remaining == 31)
        run(&e, 1)
        #expect(e.phase == .warning && e.remaining == 30)
        #expect(e.surface == .card)

        // The card stays 10 s (0:30 → 0:20, the user's choice), then leaves; the warning goes on.
        run(&e, 9)
        #expect(e.surface == .card)
        run(&e, 1)
        #expect(e.phase == .warning && e.surface == .none)

        run(&e, 15)
        #expect(e.phase == .starting && e.remaining == 5 && e.surface == .countdown)
        #expect(e.secondsLeft == 5)

        run(&e, 4)
        #expect(e.phase == .starting && e.secondsLeft == 1)
        run(&e, 1)
        #expect(e.phase == .breaking && e.remaining == 20 && e.surface == .breakScreen)
        #expect(e.breakProgress == 0)

        run(&e, 10)
        #expect(e.breakProgress == 0.5)
        run(&e, 10)
        #expect(e.phase == .working && e.remaining == 1200 && e.surface == .none)
    }

    @Test func coarseTicksKeepExactTime() {
        var a = FarFocusEngine(), b = FarFocusEngine()
        for _ in 0..<200 { a.advance(by: 5, idle: 0, hold: nil) }
        run(&b, 1000)
        #expect(a.remaining == b.remaining)
    }

    @Test func overshootingTickStillShowsTheWholeWarning() {
        var e = FarFocusEngine()
        e.advance(by: 1175, idle: 0, hold: nil)   // jumps 5 s past the warning point
        #expect(e.phase == .warning && e.remaining == 30)
    }

    @Test func leadLongerThanWorkStartsWithTheWarning() {
        var s = BreakSettings()
        s.workInterval = 20
        s.warningLead = 30
        #expect(s.effectiveLead == 20)
        var e = FarFocusEngine(settings: s)
        run(&e, 1)
        #expect(e.phase == .warning && e.remaining == 20)
        #expect(e.secondsLeft >= 0)
    }

    @Test func leadNeverShorterThanTheCountdown() {
        var s = BreakSettings()
        s.warningLead = 2
        #expect(s.effectiveLead == 5)
        #expect(s.cardVisibleFor == 0)
    }

    @Test func cardVisibleTimeFollowsTheLead() {
        var s = BreakSettings()
        for (lead, visible) in [(10.0, 5.0), (15, 10), (30, 10), (90, 10), (8, 3)] {
            s.warningLead = lead
            #expect(s.cardVisibleFor == visible)
        }
    }

    @Test func tickIsCoarseFarAwayAndFineNearTheBreak() {
        var e = FarFocusEngine()
        #expect(e.tickInterval == 5)
        #expect(!e.needsPreciseTiming)
        run(&e, 1200 - 30 - 70)
        #expect(e.tickInterval == 1)
        #expect(e.needsPreciseTiming)
    }
}

@Suite("Postpone, start now, skip")
struct ChoiceTests {

    private func atWarning() -> FarFocusEngine {
        var e = FarFocusEngine()
        run(&e, 1170)
        return e
    }

    @Test func postponeSetsTheNewTimeAndUsesOneUp() {
        var e = atWarning()
        e.postpone(minutes: 5)
        #expect(e.phase == .working && e.remaining == 300 && e.postponesLeft == 3)
        #expect(e.surface == .none)
    }

    @Test func postponesRunOutAndRefillAfterTheBreak() {
        var e = atWarning()
        for minutes in [1, 1, 1, 1] {
            e.postpone(minutes: minutes)
            run(&e, 30)
            #expect(e.phase == .warning)
        }
        #expect(e.postponesLeft == 0)
        e.postpone(minutes: 15)
        #expect(e.phase == .warning, "no postpones left: nothing happens")
        e.skip()
        #expect(e.postponesLeft == 4 && e.remaining == 1200)
    }

    @Test func postponeOnlyWhileTheBreakIsComing() {
        var e = FarFocusEngine()
        e.postpone(minutes: 5)
        #expect(e.remaining == 1200 && e.postponesLeft == 4)
    }

    @Test func zeroPostponesAllowed() {
        var s = BreakSettings()
        s.postponeLimit = 0
        var e = FarFocusEngine(settings: s)
        run(&e, 1170)
        e.postpone(minutes: 1)
        #expect(e.phase == .warning)
    }

    @Test func startNowGoesStraightToTheCountdown() {
        var e = FarFocusEngine()
        run(&e, 100)
        e.startNow()
        #expect(e.phase == .starting && e.remaining == 5 && e.surface == .countdown)
        run(&e, 5)
        #expect(e.phase == .breaking)
    }

    @Test func startNowIgnoresHolds() {
        var e = FarFocusEngine()
        e.startNow()
        run(&e, 5, hold: .screenShared)
        #expect(e.phase == .breaking)
    }

    @Test func startNowDoesNothingDuringABreak() {
        var e = FarFocusEngine()
        e.startNow()
        run(&e, 7)
        e.startNow()
        #expect(e.phase == .breaking && e.remaining == 18)
    }

    @Test func skipFromEveryPhaseGivesAFreshCycle() {
        for steps in [1170, 1195, 1210] {
            var e = FarFocusEngine()
            run(&e, steps)
            #expect(e.phase != .working)
            e.skip()
            #expect(e.phase == .working && e.remaining == 1200 && e.postponesLeft == 4)
        }
    }
}

@Suite("Idle pause")
struct IdleTests {

    @Test func awayFromTheDeskStopsTheTimer() {
        var e = FarFocusEngine()
        run(&e, 100, idle: 120)
        #expect(e.remaining == 1200)
        #expect(e.isIdle)
    }

    @Test func idleBelowTheThresholdStillCounts() {
        var e = FarFocusEngine()
        run(&e, 100, idle: 59)
        #expect(e.remaining == 1100)
        #expect(!e.isIdle)
    }

    @Test func coarseTickCountsOnlyUpToTheThreshold() {
        var e = FarFocusEngine()
        // Last input 62 s ago, tick of 5 s: 3 s of it were still within the 60 s threshold.
        e.advance(by: 5, idle: 62, hold: nil)
        #expect(e.remaining == 1197)
    }

    @Test func idleDoesNotPauseTheBreakOrTheWarning() {
        var e = FarFocusEngine()
        run(&e, 1170)
        run(&e, 10, idle: 300)
        #expect(e.remaining == 20)
    }

    @Test func customThreshold() {
        var s = BreakSettings()
        s.idleThreshold = 300
        var e = FarFocusEngine(settings: s)
        run(&e, 10, idle: 120)
        #expect(e.remaining == 1190)
    }
}

@Suite("Esc twice and the safety net")
struct EscapeTests {

    private func inBreak() -> FarFocusEngine {
        var e = FarFocusEngine()
        e.startNow()
        run(&e, 5)
        return e
    }

    @Test func onePressDoesNotEndTheBreak() {
        var e = inBreak()
        do { let ended = e.escape(at: 100); #expect(!ended) }
        #expect(e.phase == .breaking)
        #expect(e.escapeHintActive(at: 100.5))
    }

    @Test func twoQuickPressesEndIt() {
        var e = inBreak()
        e.escape(at: 100)
        do { let ended = e.escape(at: 101.2); #expect(ended) }
        #expect(e.phase == .working && e.remaining == 1200)
    }

    @Test func twoSlowPressesDoNot() {
        var e = inBreak()
        e.escape(at: 100)
        do { let ended = e.escape(at: 102); #expect(!ended) }
        #expect(!e.escapeHintActive(at: 103.6))
        #expect(e.phase == .breaking)
        do { let ended = e.escape(at: 102.9); #expect(ended, "the slow second press started a new pair") }
    }

    @Test func escSpamEndsOnTheSecondPressOnly() {
        var e = inBreak()
        var ended = 0
        for i in 0..<10 where e.escape(at: 100 + Double(i) * 0.05) { ended += 1 }
        #expect(ended == 1)
        #expect(e.phase == .working)
    }

    @Test func escOutsideABreakDoesNothing() {
        var e = FarFocusEngine()
        run(&e, 1196)
        #expect(e.phase == .starting)
        do { let ended = e.escape(at: 1); #expect(!ended) }
        do { let ended = e.escape(at: 1.1); #expect(!ended) }
        #expect(e.phase == .starting)
    }

    @Test func aClockGoingBackwardsIsNotASecondPress() {
        var e = inBreak()
        e.escape(at: 100)
        do { let ended = e.escape(at: 99.5); #expect(!ended) }
    }

    @Test func safetyNetEndsAnyBreak() {
        var e = inBreak()
        e.forceEndBreak()
        #expect(e.phase == .working && e.remaining == 1200)
        e.forceEndBreak()   // no-op outside a break
        #expect(e.phase == .working)
    }

    @Test func safetyNetDeadline() {
        #expect(!SafetyNet.isOverdue(shownAt: 1000, now: 1029.9, breakLength: 20))
        #expect(SafetyNet.isOverdue(shownAt: 1000, now: 1030, breakLength: 20))
    }
}

@Suite("Holds")
struct HoldTests {

    @Test func dueBreakWaitsWhileTheScreenIsShared() {
        var e = FarFocusEngine()
        run(&e, 1170, hold: .screenShared)
        #expect(e.phase == .working && e.hold == .screenShared)
        #expect(e.surface == .none)
        run(&e, 600, hold: .screenShared)
        #expect(e.phase == .working && e.remaining == 30)
        #expect(e.postponesLeft == 4, "a hold is not a postpone")
        run(&e, 1)
        #expect(e.phase == .warning && e.remaining == 30 && e.hold == nil)
        #expect(e.surface == .card, "after a hold the full warning still comes first")
    }

    @Test func holdsDoNotMatterFarFromTheBreak() {
        var e = FarFocusEngine()
        run(&e, 100, hold: .focus)
        #expect(e.hold == nil && e.remaining == 1100)
    }

    @Test func sharingThatStartsDuringTheWarningPutsItAway() {
        var e = FarFocusEngine()
        run(&e, 1180)
        #expect(e.phase == .warning)
        run(&e, 1, hold: .fullScreenMedia)
        #expect(e.phase == .working && e.hold == .fullScreenMedia && e.surface == .none)
    }

    @Test func sharingThatStartsDuringTheCountdownPutsItAway() {
        var e = FarFocusEngine()
        run(&e, 1197)
        #expect(e.phase == .starting)
        run(&e, 1, hold: .mirroredDisplay)
        #expect(e.phase == .working && e.surface == .none)
    }

    @Test func holdsNeverInterruptABreak() {
        var e = FarFocusEngine()
        run(&e, 1201)
        #expect(e.phase == .breaking)
        run(&e, 5, hold: .screenShared)
        #expect(e.phase == .breaking && e.remaining == 14)
    }

    @Test func holdCheckOnlyNearTheBreak() {
        var e = FarFocusEngine()
        #expect(!e.wantsHoldCheck)
        run(&e, 1164)
        #expect(e.wantsHoldCheck)
    }
}

@Suite("Sleep, wake and the clock")
struct SleepTests {

    @Test func nothingCountsOrShowsWhileAsleep() {
        var e = FarFocusEngine()
        run(&e, 1201)
        e.willSleep()
        #expect(e.surface == .none)
        run(&e, 100)
        #expect(e.phase == .breaking && e.remaining == 19)
    }

    @Test func aLongSleepCountsAsTheBreak() {
        var e = FarFocusEngine()
        run(&e, 1201)
        e.willSleep()
        e.didWake(sleptFor: 3600)
        #expect(e.phase == .working && e.remaining == 1200 && e.surface == .none)
    }

    @Test func aShortSleepResumes() {
        var e = FarFocusEngine()
        run(&e, 1205)
        e.willSleep()
        e.didWake(sleptFor: 8)
        #expect(e.phase == .breaking && e.remaining == 15 && e.surface == .breakScreen)
    }

    @Test func aLongSleepWhileWorkingStartsAFreshCycle() {
        var e = FarFocusEngine()
        run(&e, 600)
        e.willSleep()
        e.didWake(sleptFor: 25)
        #expect(e.remaining == 1200)
    }

    @Test func wakeWithoutSleepIsIgnored() {
        var e = FarFocusEngine()
        run(&e, 600)
        e.didWake(sleptFor: 9999)
        #expect(e.remaining == 600)
    }

    @Test func ticksMeasureElapsedTimeNotTheWallClock() {
        // The engine never sees the wall clock: only the elapsed seconds handed to it. A clock set an hour
        // back or forward changes nothing; zero or negative steps are ignored.
        var e = FarFocusEngine()
        e.advance(by: 0, idle: 0, hold: nil)
        e.advance(by: -3600, idle: 0, hold: nil)
        #expect(e.remaining == 1200)
    }
}

@Suite("Settings and on/off")
struct SettingsTests {

    @Test func newWorkIntervalWhileWorkingRestartsTheCycle() {
        var e = FarFocusEngine()
        run(&e, 300)
        var s = defaults
        s.workInterval = 45 * 60
        e.apply(s)
        #expect(e.remaining == 2700)
    }

    @Test func otherChangesWaitForTheNextCycle() {
        var e = FarFocusEngine()
        run(&e, 1205)
        var s = defaults
        s.breakLength = 60
        e.apply(s)
        #expect(e.phase == .breaking && e.breakTotal == 20)
        run(&e, 15)
        e.startNow()
        run(&e, 5)
        #expect(e.breakTotal == 60)
    }

    @Test func lowerPostponeLimitClampsWhatIsLeft() {
        var e = FarFocusEngine()
        var s = defaults
        s.postponeLimit = 1
        e.apply(s)
        #expect(e.postponesLeft == 1)
    }

    @Test func offHidesEverythingAndStopsCounting() {
        var e = FarFocusEngine()
        run(&e, 1201)
        e.setEnabled(false)
        #expect(e.surface == .none && e.phase == .working)
        run(&e, 50)
        #expect(e.remaining == 1200)
        e.startNow()
        #expect(e.phase == .working)
        e.setEnabled(true)
        #expect(e.remaining == 1200)
    }
}

/// The user's decisions on the source's quirks (2026-11-12).
@Suite("Decisions")
struct DecisionTests {

    private func atWarningWithNoPostpones() -> FarFocusEngine {
        var s = BreakSettings()
        s.postponeLimit = 0
        var e = FarFocusEngine(settings: s)
        run(&e, 1170)
        return e
    }

    @Test func startNowStillWorksWithNoPostponesLeft() {
        var e = atWarningWithNoPostpones()
        e.postpone(minutes: 5)
        #expect(e.phase == .warning, "postponing is blocked")
        e.startNow()
        #expect(e.phase == .starting, "starting early is always possible")
    }

    @Test func skipStillWorksWithNoPostponesLeft() {
        var e = atWarningWithNoPostpones()
        e.skip()
        #expect(e.phase == .working && e.remaining == 1200)
    }

    @Test func takeABreakNowNeverRestartsACountdownOrABreak() {
        var e = FarFocusEngine()
        e.startNow()
        run(&e, 2)
        e.startNow()
        #expect(e.phase == .starting && e.secondsLeft == 3, "countdown keeps going, not back to 5")
        run(&e, 3)
        #expect(e.phase == .breaking)
        run(&e, 4)
        e.startNow()
        #expect(e.phase == .breaking && e.remaining == 16, "break keeps going")
    }

    @Test func escNeedsTwoPresses() {
        var e = FarFocusEngine()
        e.startNow()
        run(&e, 5)
        do { let ended = e.escape(at: 10); #expect(!ended) }
        do { let ended = e.escape(at: 11); #expect(ended) }
    }
}

@Suite("Badge ring")
struct RingTests {

    @Test func fullWhenTheCardAppears() {
        #expect(Ring.now(remaining: 30, total: 30) == 1)
        // A custom 10 s lead: also full.
        #expect(Ring.now(remaining: 10, total: 10) == 1)
    }

    @Test func fullWhenTheCountdownAppears() {
        #expect(Ring.now(remaining: BreakSettings.countdownLength, total: BreakSettings.countdownLength) == 1)
    }

    @Test func itOnlyEverDrains() {
        // Each tick's target is below the value it starts from: the ring never fills up on screen.
        var remaining = 30.0
        var shown = Ring.now(remaining: remaining, total: 30)
        while remaining > 0 {
            let target = Ring.inOneSecond(remaining: remaining, total: 30)
            #expect(target < shown)
            shown = target
            remaining -= 1
        }
        #expect(shown == 0)
    }

    @Test func clamped() {
        #expect(Ring.now(remaining: 45, total: 30) == 1)
        #expect(Ring.now(remaining: -2, total: 30) == 0)
        #expect(Ring.now(remaining: 5, total: 0) == 0)
    }
}
