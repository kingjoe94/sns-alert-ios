import Foundation

enum UsageThresholdIgnoreReason: Equatable {
    case none
    case usageNotSynced(elapsedSeconds: Int)
    case usageBelowLimit(usedMinutes: Int, limitMinutes: Int)
}

enum MonitoringLogic {
    static func resetAnchor(
        now: Date,
        resetHour: Int,
        resetMinute: Int,
        calendar: Calendar = .current
    ) -> Date {
        let todayReset = calendar.date(
            bySettingHour: resetHour,
            minute: resetMinute,
            second: 0,
            of: now
        ) ?? now

        return now < todayReset
            ? (calendar.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset)
            : todayReset
    }

    static func endComponentsForDailyReset(hour: Int, minute: Int) -> DateComponents {
        let startTotal = hour * 60 + minute
        let endTotal = (startTotal + 24 * 60 - 1) % (24 * 60)
        return DateComponents(hour: endTotal / 60, minute: endTotal % 60)
    }

    static func isWithinResetGrace(
        now: Date,
        lastReset: Date?,
        graceSeconds: TimeInterval
    ) -> Bool {
        guard let lastReset else { return false }
        let delta = now.timeIntervalSince(lastReset)
        return delta >= 0 && delta < graceSeconds
    }

    static func usageThresholdIgnoreReason(
        now: Date,
        lastReset: Date?,
        usageUpdatedAt: Date?,
        usedMinutes: Int?,
        limitMinutes: Int,
        unsyncedThresholdIgnoreWindowSeconds: TimeInterval = 180,
        minSyncedUsageDelaySeconds: TimeInterval = 30
    ) -> UsageThresholdIgnoreReason {
        guard let lastReset else { return .none }

        let elapsedFromReset = now.timeIntervalSince(lastReset)
        let syncedDelay = usageUpdatedAt?.timeIntervalSince(lastReset)

        // Ignore brief post-reset races, then fall back to threshold-only behavior.
        if syncedDelay == nil || syncedDelay! < minSyncedUsageDelaySeconds {
            if elapsedFromReset >= 0 && elapsedFromReset < unsyncedThresholdIgnoreWindowSeconds {
                return .usageNotSynced(elapsedSeconds: Int(elapsedFromReset))
            }
            return .none
        }

        guard let usedMinutes else { return .none }

        if usedMinutes < limitMinutes {
            return .usageBelowLimit(usedMinutes: usedMinutes, limitMinutes: limitMinutes)
        }

        return .none
    }
}
