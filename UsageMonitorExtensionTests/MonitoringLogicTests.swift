import Foundation
import XCTest
@testable import UsageMonitorLogic

final class MonitoringLogicTests: XCTestCase {
    func testResetAnchorUsesPreviousDayWhenNowIsBeforeResetTime() {
        let calendar = fixedCalendar()
        let now = makeDate(year: 2026, month: 2, day: 10, hour: 0, minute: 10, calendar: calendar)

        let anchor = MonitoringLogic.resetAnchor(
            now: now,
            resetHour: 1,
            resetMinute: 0,
            calendar: calendar
        )

        XCTAssertEqual(
            anchor,
            makeDate(year: 2026, month: 2, day: 9, hour: 1, minute: 0, calendar: calendar)
        )
    }

    func testResetAnchorUsesTodayWhenNowIsAtResetTime() {
        let calendar = fixedCalendar()
        let now = makeDate(year: 2026, month: 2, day: 10, hour: 1, minute: 0, calendar: calendar)

        let anchor = MonitoringLogic.resetAnchor(
            now: now,
            resetHour: 1,
            resetMinute: 0,
            calendar: calendar
        )

        XCTAssertEqual(
            anchor,
            makeDate(year: 2026, month: 2, day: 10, hour: 1, minute: 0, calendar: calendar)
        )
    }

    func testEndComponentsForDailyResetWrapsToPreviousMinute() {
        XCTAssertEqual(
            MonitoringLogic.endComponentsForDailyReset(hour: 0, minute: 0),
            DateComponents(hour: 23, minute: 59)
        )
        XCTAssertEqual(
            MonitoringLogic.endComponentsForDailyReset(hour: 1, minute: 0),
            DateComponents(hour: 0, minute: 59)
        )
    }

    func testIsWithinResetGraceUsesHalfOpenInterval() {
        let calendar = fixedCalendar()
        let reset = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)

        XCTAssertTrue(
            MonitoringLogic.isWithinResetGrace(
                now: reset.addingTimeInterval(29.9),
                lastReset: reset,
                graceSeconds: 30
            )
        )
        XCTAssertFalse(
            MonitoringLogic.isWithinResetGrace(
                now: reset.addingTimeInterval(30),
                lastReset: reset,
                graceSeconds: 30
            )
        )
    }

    func testUsageThresholdIgnoreReasonReturnsUnsyncedInsideWindow() {
        let calendar = fixedCalendar()
        let reset = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let now = reset.addingTimeInterval(120)

        let reason = MonitoringLogic.usageThresholdIgnoreReason(
            now: now,
            lastReset: reset,
            usageUpdatedAt: nil,
            usedMinutes: nil,
            limitMinutes: 1
        )

        XCTAssertEqual(reason, .usageNotSynced(elapsedSeconds: 120))
    }

    func testUsageThresholdIgnoreReasonStopsUnsyncedIgnoreAfterWindow() {
        let calendar = fixedCalendar()
        let reset = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let now = reset.addingTimeInterval(181)

        let reason = MonitoringLogic.usageThresholdIgnoreReason(
            now: now,
            lastReset: reset,
            usageUpdatedAt: nil,
            usedMinutes: nil,
            limitMinutes: 1
        )

        XCTAssertEqual(reason, .none)
    }

    func testUsageThresholdIgnoreReasonUsesRearmStartForUnsyncedWindow() {
        let calendar = fixedCalendar()
        let reset = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let rearm = reset.addingTimeInterval(7200)
        let now = rearm.addingTimeInterval(120)
        let syncedBeforeRearm = rearm.addingTimeInterval(-60)

        let reason = MonitoringLogic.usageThresholdIgnoreReason(
            now: now,
            lastReset: reset,
            thresholdEvaluationStart: rearm,
            usageUpdatedAt: syncedBeforeRearm,
            usedMinutes: nil,
            limitMinutes: 1
        )

        XCTAssertEqual(reason, .usageNotSynced(elapsedSeconds: 120))
    }

    func testUsageThresholdIgnoreReasonStopsRearmUnsyncedIgnoreAfterWindow() {
        let calendar = fixedCalendar()
        let reset = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let rearm = reset.addingTimeInterval(7200)
        let now = rearm.addingTimeInterval(181)
        let syncedBeforeRearm = rearm.addingTimeInterval(-60)

        let reason = MonitoringLogic.usageThresholdIgnoreReason(
            now: now,
            lastReset: reset,
            thresholdEvaluationStart: rearm,
            usageUpdatedAt: syncedBeforeRearm,
            usedMinutes: nil,
            limitMinutes: 1
        )

        XCTAssertEqual(reason, .none)
    }

    func testUsageThresholdIgnoreReasonIgnoresWhenUsageIsBelowLimitAfterSync() {
        let calendar = fixedCalendar()
        let reset = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let now = reset.addingTimeInterval(120)
        let syncedAt = reset.addingTimeInterval(31)

        let reason = MonitoringLogic.usageThresholdIgnoreReason(
            now: now,
            lastReset: reset,
            usageUpdatedAt: syncedAt,
            usedMinutes: 1,
            limitMinutes: 2
        )

        XCTAssertEqual(reason, .usageBelowLimit(usedMinutes: 1, limitMinutes: 2))
    }

    func testUsageThresholdIgnoreReasonDoesNotIgnoreWhenUsageReachedLimit() {
        let calendar = fixedCalendar()
        let reset = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let now = reset.addingTimeInterval(120)
        let syncedAt = reset.addingTimeInterval(31)

        let reason = MonitoringLogic.usageThresholdIgnoreReason(
            now: now,
            lastReset: reset,
            usageUpdatedAt: syncedAt,
            usedMinutes: 2,
            limitMinutes: 2
        )

        XCTAssertEqual(reason, .none)
    }

    func testUsageThresholdIgnoreReasonDoesNotIgnoreWithoutUsageSnapshotAfterSync() {
        let calendar = fixedCalendar()
        let reset = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let now = reset.addingTimeInterval(120)
        let syncedAt = reset.addingTimeInterval(31)

        let reason = MonitoringLogic.usageThresholdIgnoreReason(
            now: now,
            lastReset: reset,
            usageUpdatedAt: syncedAt,
            usedMinutes: nil,
            limitMinutes: 2
        )

        XCTAssertEqual(reason, .none)
    }

    func testShouldAcceptUsageMinuteEventReturnsTrueWhenNoLastAcceptedAt() {
        let calendar = fixedCalendar()
        let now = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)

        XCTAssertTrue(
            MonitoringLogic.shouldAcceptUsageMinuteEvent(
                now: now,
                lastAcceptedAt: nil
            )
        )
    }

    func testShouldAcceptUsageMinuteEventReturnsFalseInsideMinInterval() {
        let calendar = fixedCalendar()
        let last = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let now = last.addingTimeInterval(20)

        XCTAssertFalse(
            MonitoringLogic.shouldAcceptUsageMinuteEvent(
                now: now,
                lastAcceptedAt: last,
                minIntervalSeconds: 50
            )
        )
    }

    func testShouldAcceptUsageMinuteEventReturnsTrueAtMinInterval() {
        let calendar = fixedCalendar()
        let last = makeDate(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let now = last.addingTimeInterval(50)

        XCTAssertTrue(
            MonitoringLogic.shouldAcceptUsageMinuteEvent(
                now: now,
                lastAcceptedAt: last,
                minIntervalSeconds: 50
            )
        )
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }
}
