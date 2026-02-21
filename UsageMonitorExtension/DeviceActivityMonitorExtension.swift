import Foundation
import DeviceActivity
import UserNotifications
import ManagedSettings
import FamilyControls
private let appGroupID = "group.com.xa504.snsalert"
private let managedStoreName = ManagedSettingsStore.Name("shared")
private let selectionKey = "savedSelection"
private let blockedTokensKey = "blockedTokens"
private let orderedTokensKey = "orderedTokens"
private let usageKey = "usageMinutes"
private let usageUpdatedAtKey = "usageUpdatedAt"
private let appLimitsKey = "appLimits"
private let continuousAlertLimitsKey = "continuousAlertLimits"
private let continuousUsageKey = "continuousUsageMinutes"
private let continuousLastEventAtKey = "continuousLastEventAt"
private let continuousLastNotifiedAtKey = "continuousLastNotifiedAt"
private let continuousActiveIndexKey = "continuousActiveIndex"
private let lastResetKey = "lastResetAt"
private let usageEventAcceptedAtKey = "usageEventAcceptedAt"
private let resetGraceSeconds: TimeInterval = 30
private let debugLogsKey = "debugLogs"
private let defaultLimitMinutes = 30
private let unsyncedThresholdIgnoreWindowSeconds: TimeInterval = 180
private let usageEventMinIntervalSeconds: TimeInterval = 50
private let continuousSessionMaxGapSeconds: TimeInterval = 120
private let lastRearmAtKey = "lastRearmAt"
private let monitorName = DeviceActivityName("daily-monitor")

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let center = DeviceActivityCenter()
    private let store = ManagedSettingsStore(named: managedStoreName)
    private let fallbackStore = ManagedSettingsStore()

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        let now = Date()
        if isWithinResetGrace(now: now) {
            appendDebugLog("eventDidReachThresholdをgraceで無視: \(event.rawValue)")
            rearmMonitoringIfNeeded(reason: "grace_\(event.rawValue)", now: now)
            return
        }
        let usagePrefix = "usage_idx_"
        let limitPrefix = "limit_idx_"

        if event.rawValue.hasPrefix(usagePrefix) {
            handleUsageMinuteEvent(event: event, now: now)
            return
        }

        guard event.rawValue.hasPrefix(limitPrefix) else { return }
        let indexString = String(event.rawValue.dropFirst(limitPrefix.count))
        guard let index = Int(indexString) else { return }
        guard let tokens = loadTokensForMonitoring(), tokens.indices.contains(index) else {
            appendDebugLog("token解決に失敗: event=\(event.rawValue)")
            return
        }
        let token = tokens[index]
        if shouldIgnoreByUsageSnapshot(token: token, index: index) {
            rearmMonitoringIfNeeded(reason: event.rawValue, now: now)
            return
        }
        applyBlock(for: token, eventName: event.rawValue, now: now)

        // Keep usage snapshot consistent when only limit threshold arrives.
        if let defaults = UserDefaults(suiteName: appGroupID) {
            let limits = loadAppLimits(defaults: defaults)
            let tokenKey = tokenSortKey(token)
            let limit = limitMinutesForToken(tokenKey: tokenKey, index: index, limits: limits)
            var usage = loadUsageMinutes(defaults: defaults)
            let idxKey = "idx_\(index)"
            let current = max(usage[idxKey] ?? 0, usage[tokenKey] ?? 0)
            if current < limit {
                usage[idxKey] = limit
                usage[tokenKey] = limit
                saveUsageMinutes(usage, defaults: defaults)
                defaults.set(now, forKey: usageUpdatedAtKey)
                appendDebugLog("limit到達で使用時間を補正: idx=\(index), used=\(limit)", now: now)
            }
        }
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let hour = defaults.integer(forKey: "resetHour")
        let minute = defaults.integer(forKey: "resetMinute")
        let now = Date()
        let anchor = MonitoringLogic.resetAnchor(
            now: now,
            resetHour: hour,
            resetMinute: minute,
            calendar: Calendar.current
        )
        let lastReset = defaults.object(forKey: lastResetKey) as? Date
        let shouldReset = (lastReset == nil) || (lastReset! < anchor)
        guard shouldReset else {
            appendDebugLog("intervalDidStart: resetスキップ(resetAnchor=\(anchor), lastReset=\(String(describing: lastReset)))")
            return
        }

        store.shield.applications = nil
        fallbackStore.shield.applications = nil
        saveBlockedTokens([])
        defaults.set(nil, forKey: usageKey)
        defaults.removeObject(forKey: usageUpdatedAtKey)
        defaults.removeObject(forKey: usageEventAcceptedAtKey)
        clearContinuousUsageState(defaults: defaults)
        defaults.set(anchor, forKey: lastResetKey)
        appendDebugLog("intervalDidStart: reset実行(resetAnchor=\(anchor), lastResetBefore=\(String(describing: lastReset)))")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        appendDebugLog("intervalDidEnd")
    }

    private func handleUsageMinuteEvent(event: DeviceActivityEvent.Name, now: Date) {
        let prefix = "usage_idx_"
        let indexString = String(event.rawValue.dropFirst(prefix.count))
        guard let index = Int(indexString) else { return }
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        guard shouldAcceptUsageMinuteEvent(index: index, now: now, defaults: defaults) else {
            return
        }
        guard let tokens = loadTokensForMonitoring(), tokens.indices.contains(index) else {
            appendDebugLog("usage eventのtoken解決に失敗: event=\(event.rawValue)", now: now)
            return
        }

        let token = tokens[index]
        let tokenKey = tokenSortKey(token)
        let limits = loadAppLimits(defaults: defaults)
        let limit = limitMinutesForToken(tokenKey: tokenKey, index: index, limits: limits)
        let idxKey = "idx_\(index)"

        var usage = loadUsageMinutes(defaults: defaults)
        let current = max(usage[idxKey] ?? 0, usage[tokenKey] ?? 0)
        let updated = min(max(current + 1, 1), limit)
        usage[idxKey] = updated
        usage[tokenKey] = updated
        saveUsageMinutes(usage, defaults: defaults)
        defaults.set(now, forKey: usageUpdatedAtKey)
        appendDebugLog("使用時間を同期: idx=\(index), used=\(updated), limit=\(limit)", now: now)
        updateContinuousUsageAndNotify(token: token, index: index, now: now, defaults: defaults)

        if updated >= limit {
            applyBlock(for: token, eventName: event.rawValue, now: now)
            return
        }

        rearmMonitoringIfNeeded(reason: event.rawValue, now: now, cooldownSeconds: 0)
    }

    private func applyBlock(for token: Token<Application>, eventName: String, now: Date = Date()) {
        var blockedTokens = loadBlockedTokens()
        if !blockedTokens.contains(where: { tokenSortKey($0) == tokenSortKey(token) }) {
            blockedTokens.append(token)
            saveBlockedTokens(blockedTokens)
        }
        let blockedSet = Set(blockedTokens)
        store.shield.applications = blockedSet
        fallbackStore.shield.applications = blockedSet
        appendDebugLog("しきい値到達: \(eventName), blocked=\(blockedSet.count)", now: now)
    }

    private func loadBlockedTokens() -> [Token<Application>] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let items = defaults.array(forKey: blockedTokensKey) as? [Data] else {
            return []
        }
        return items.compactMap { try? JSONDecoder().decode(Token<Application>.self, from: $0) }
    }

    private func saveBlockedTokens(_ tokens: [Token<Application>]) {
        let items = tokens.compactMap { try? JSONEncoder().encode($0) }
        UserDefaults(suiteName: appGroupID)?.set(items, forKey: blockedTokensKey)
    }

    private func loadOrderedTokens() -> [Token<Application>]? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let items = defaults.array(forKey: orderedTokensKey) as? [Data] else {
            return nil
        }
        return items.compactMap { try? JSONDecoder().decode(Token<Application>.self, from: $0) }
    }

    private func tokenSortKey<T: Encodable>(_ token: T) -> String {
        guard let data = try? JSONEncoder().encode(token) else {
            return String(describing: token)
        }
        return data.base64EncodedString()
    }

    private func loadSelection() -> FamilyActivitySelection? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: selectionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private func loadTokensForMonitoring() -> [Token<Application>]? {
        if let ordered = loadOrderedTokens(), !ordered.isEmpty {
            return ordered
        }
        guard let selection = loadSelection() else {
            return nil
        }
        let tokens = Array(selection.applicationTokens)
            .sorted(by: { tokenSortKey($0) < tokenSortKey($1) })
        return tokens.isEmpty ? nil : tokens
    }

    private func isWithinResetGrace(now: Date = Date()) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let lastReset = defaults.object(forKey: lastResetKey) as? Date else {
            return false
        }
        return MonitoringLogic.isWithinResetGrace(
            now: now,
            lastReset: lastReset,
            graceSeconds: resetGraceSeconds
        )
    }

    private func shouldIgnoreByUsageSnapshot(token: Token<Application>, index: Int, now: Date = Date()) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return false
        }
        guard let lastReset = defaults.object(forKey: lastResetKey) as? Date else {
            return false
        }

        let usageUpdatedAt = defaults.object(forKey: usageUpdatedAtKey) as? Date
        let thresholdEvaluationStart = defaults.object(forKey: lastRearmAtKey) as? Date
        let usageEventAcceptedAt = loadUsageEventAcceptedAt(defaults: defaults)["idx_\(index)"]
        let hasUsageSignal = (usageEventAcceptedAt != nil)

        let tokenKey = tokenSortKey(token)
        var usedMinutes: Int?
        if let usageData = defaults.data(forKey: usageKey),
           let usage = try? JSONDecoder().decode([String: Int].self, from: usageData) {
            usedMinutes = usage["idx_\(index)"] ?? usage[tokenKey] ?? 0
        }

        var limitMinutes = defaultLimitMinutes
        if let limitsData = defaults.data(forKey: appLimitsKey),
           let limits = try? JSONDecoder().decode([String: Int].self, from: limitsData) {
            limitMinutes = limitMinutesForToken(tokenKey: tokenKey, index: index, limits: limits)
        }

        let ignoreReason = MonitoringLogic.usageThresholdIgnoreReason(
            now: now,
            lastReset: lastReset,
            thresholdEvaluationStart: thresholdEvaluationStart,
            usageUpdatedAt: usageUpdatedAt,
            hasUsageSignal: hasUsageSignal,
            usedMinutes: usedMinutes,
            limitMinutes: limitMinutes,
            unsyncedThresholdIgnoreWindowSeconds: unsyncedThresholdIgnoreWindowSeconds
        )

        switch ignoreReason {
        case .usageNotSynced(let elapsedSeconds):
            appendDebugLog(
                "しきい値を使用量未同期で無視: elapsed=\(elapsedSeconds)s",
                now: now
            )
            return true
        case .usageBelowLimit(let used, let limit):
            appendDebugLog(
                "しきい値を使用量突合で無視: used=\(used), limit=\(limit), token=\(tokenKey)",
                now: now
            )
            return true
        case .none:
            return false
        }
    }

    private func rearmMonitoringIfNeeded(
        reason: String,
        now: Date = Date(),
        cooldownSeconds: TimeInterval = 30
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if cooldownSeconds > 0,
           let lastRearmAt = defaults.object(forKey: lastRearmAtKey) as? Date,
           now.timeIntervalSince(lastRearmAt) < cooldownSeconds {
            appendDebugLog("monitor再登録をスキップ(クールダウン): reason=\(reason)", now: now)
            return
        }
        guard let tokens = loadTokensForMonitoring(), !tokens.isEmpty else {
            appendDebugLog("monitor再登録を中止(トークンなし): reason=\(reason)", now: now)
            return
        }

        let limits = loadAppLimits(defaults: defaults)
        let usage = loadUsageMinutes(defaults: defaults)
        let resetHour = defaults.integer(forKey: "resetHour")
        let resetMinute = defaults.integer(forKey: "resetMinute")

        let start = DateComponents(hour: resetHour, minute: resetMinute)
        let end = endComponentsForDailyReset(hour: resetHour, minute: resetMinute)
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true
        )

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for (index, token) in tokens.enumerated() {
            let tokenKey = tokenSortKey(token)
            let perLimit = limitMinutesForToken(tokenKey: tokenKey, index: index, limits: limits)
            let limitName = DeviceActivityEvent.Name("limit_idx_\(index)")
            let limitEvent: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                limitEvent = DeviceActivityEvent(
                    applications: Set([token]),
                    threshold: DateComponents(minute: perLimit),
                    // Rearm should continue counting current-day usage.
                    includesPastActivity: true
                )
            } else {
                limitEvent = DeviceActivityEvent(
                    applications: Set([token]),
                    threshold: DateComponents(minute: perLimit)
                )
            }
            events[limitName] = limitEvent

            let used = usage["idx_\(index)"] ?? usage[tokenKey] ?? 0
            if used < perLimit {
                let usageName = DeviceActivityEvent.Name("usage_idx_\(index)")
                let usageEvent: DeviceActivityEvent
                if #available(iOS 17.4, *) {
                    usageEvent = DeviceActivityEvent(
                        applications: Set([token]),
                        threshold: DateComponents(minute: 1),
                        // Track one newly-consumed minute after each rearm.
                        includesPastActivity: false
                    )
                } else {
                    usageEvent = DeviceActivityEvent(
                        applications: Set([token]),
                        threshold: DateComponents(minute: 1)
                    )
                }
                events[usageName] = usageEvent
            }
        }

        saveOrderedTokens(tokens, defaults: defaults)
        do {
            center.stopMonitoring([monitorName])
            try center.startMonitoring(monitorName, during: schedule, events: events)
            defaults.set(now, forKey: lastRearmAtKey)
            appendDebugLog("monitorを再登録: reason=\(reason)", now: now)
        } catch {
            appendDebugLog("monitor再登録失敗: reason=\(reason), error=\(error)", now: now)
        }
    }

    private func loadAppLimits(defaults: UserDefaults) -> [String: Int] {
        guard let data = defaults.data(forKey: appLimitsKey),
              let limits = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return limits
    }

    private func loadContinuousAlertLimits(defaults: UserDefaults) -> [String: Int] {
        guard let data = defaults.data(forKey: continuousAlertLimitsKey),
              let limits = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return limits
    }

    private func loadUsageMinutes(defaults: UserDefaults) -> [String: Int] {
        guard let data = defaults.data(forKey: usageKey),
              let usage = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return usage
    }

    private func loadUsageEventAcceptedAt(defaults: UserDefaults) -> [String: Date] {
        guard let data = defaults.data(forKey: usageEventAcceptedAtKey),
              let acceptedAt = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return acceptedAt
    }

    private func saveUsageEventAcceptedAt(_ acceptedAt: [String: Date], defaults: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(acceptedAt) {
            defaults.set(encoded, forKey: usageEventAcceptedAtKey)
        }
    }

    private func shouldAcceptUsageMinuteEvent(index: Int, now: Date, defaults: UserDefaults) -> Bool {
        let key = "idx_\(index)"
        var acceptedAt = loadUsageEventAcceptedAt(defaults: defaults)
        let shouldAccept = MonitoringLogic.shouldAcceptUsageMinuteEvent(
            now: now,
            lastAcceptedAt: acceptedAt[key],
            minIntervalSeconds: usageEventMinIntervalSeconds
        )
        if !shouldAccept {
            if let last = acceptedAt[key] {
                let delta = Int(now.timeIntervalSince(last))
                appendDebugLog("usage event重複をスキップ: idx=\(index), delta=\(delta)s", now: now)
            } else {
                appendDebugLog("usage event重複をスキップ: idx=\(index)", now: now)
            }
            return false
        }
        acceptedAt[key] = now
        saveUsageEventAcceptedAt(acceptedAt, defaults: defaults)
        return true
    }

    private func saveUsageMinutes(_ usage: [String: Int], defaults: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(usage) {
            defaults.set(encoded, forKey: usageKey)
        }
    }

    private func loadContinuousUsageMinutes(defaults: UserDefaults) -> [String: Int] {
        guard let data = defaults.data(forKey: continuousUsageKey),
              let usage = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return usage
    }

    private func saveContinuousUsageMinutes(_ usage: [String: Int], defaults: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(usage) {
            defaults.set(encoded, forKey: continuousUsageKey)
        }
    }

    private func loadContinuousLastNotifiedAt(defaults: UserDefaults) -> [String: Date] {
        guard let data = defaults.data(forKey: continuousLastNotifiedAtKey),
              let notified = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return notified
    }

    private func saveContinuousLastNotifiedAt(_ notified: [String: Date], defaults: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(notified) {
            defaults.set(encoded, forKey: continuousLastNotifiedAtKey)
        }
    }

    private func clearContinuousUsageState(defaults: UserDefaults) {
        defaults.removeObject(forKey: continuousUsageKey)
        defaults.removeObject(forKey: continuousLastEventAtKey)
        defaults.removeObject(forKey: continuousLastNotifiedAtKey)
        defaults.removeObject(forKey: continuousActiveIndexKey)
    }

    private func limitMinutesForToken(tokenKey: String, index: Int, limits: [String: Int]) -> Int {
        let idxKey = "idx_\(index)"
        return limits[idxKey] ?? limits[tokenKey] ?? defaultLimitMinutes
    }

    private func saveOrderedTokens(_ tokens: [Token<Application>], defaults: UserDefaults) {
        let items = tokens.compactMap { try? JSONEncoder().encode($0) }
        defaults.set(items, forKey: orderedTokensKey)
    }

    private func updateContinuousUsageAndNotify(
        token: Token<Application>,
        index: Int,
        now: Date,
        defaults: UserDefaults
    ) {
        let idxKey = "idx_\(index)"
        let tokenKey = tokenSortKey(token)
        var usage = loadContinuousUsageMinutes(defaults: defaults)
        var notifiedAt = loadContinuousLastNotifiedAt(defaults: defaults)
        let activeIndex = defaults.object(forKey: continuousActiveIndexKey) as? Int
        let lastEventAt = defaults.object(forKey: continuousLastEventAtKey) as? Date

        let shouldReset = MonitoringLogic.shouldResetContinuousSession(
            eventIndex: index,
            activeIndex: activeIndex,
            lastEventAt: lastEventAt,
            now: now,
            maxGapSeconds: continuousSessionMaxGapSeconds
        )
        if shouldReset {
            if let activeIndex, activeIndex != index {
                let previousIdxKey = "idx_\(activeIndex)"
                usage[previousIdxKey] = 0
                notifiedAt.removeValue(forKey: previousIdxKey)
                if let tokens = loadTokensForMonitoring(), tokens.indices.contains(activeIndex) {
                    let previousTokenKey = tokenSortKey(tokens[activeIndex])
                    usage[previousTokenKey] = 0
                    notifiedAt.removeValue(forKey: previousTokenKey)
                }
            }
            usage[idxKey] = 0
            usage[tokenKey] = 0
            notifiedAt.removeValue(forKey: idxKey)
            notifiedAt.removeValue(forKey: tokenKey)
            if let activeIndex, activeIndex != index {
                appendDebugLog("連続使用セッション切替: from=\(activeIndex), to=\(index)", now: now)
            } else {
                appendDebugLog("連続使用セッションをリセット: idx=\(index)", now: now)
            }
        }

        let previous = max(usage[idxKey] ?? 0, usage[tokenKey] ?? 0)
        let streak = previous + 1
        usage[idxKey] = streak
        usage[tokenKey] = streak
        saveContinuousUsageMinutes(usage, defaults: defaults)
        defaults.set(now, forKey: continuousLastEventAtKey)
        defaults.set(index, forKey: continuousActiveIndexKey)

        let limits = loadContinuousAlertLimits(defaults: defaults)
        let threshold = max(limits[idxKey] ?? limits[tokenKey] ?? 0, 0)
        let lastNotified = notifiedAt[idxKey] ?? notifiedAt[tokenKey]
        let shouldNotify = MonitoringLogic.shouldNotifyForContinuousUsage(
            streakMinutes: streak,
            thresholdMinutes: threshold,
            lastNotifiedAt: lastNotified,
            now: now
        )

        if shouldNotify {
            postContinuousUsageNotification(index: index, streakMinutes: streak, thresholdMinutes: threshold)
            notifiedAt[idxKey] = now
            notifiedAt[tokenKey] = now
            appendDebugLog("連続使用通知を送信: idx=\(index), streak=\(streak), threshold=\(threshold)", now: now)
        }

        saveContinuousLastNotifiedAt(notifiedAt, defaults: defaults)
    }

    private func postContinuousUsageNotification(index: Int, streakMinutes: Int, thresholdMinutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "SNSアラート"
        content.body = "アプリ\(index + 1)を\(streakMinutes)分連続で使用しています（通知閾値: \(thresholdMinutes)分）"
        content.sound = .default
        let identifier = "continuous_idx_\(index)_\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.appendDebugLog("連続使用通知の送信に失敗: idx=\(index), error=\(error)")
            }
        }
    }

    private func endComponentsForDailyReset(hour: Int, minute: Int) -> DateComponents {
        MonitoringLogic.endComponentsForDailyReset(hour: hour, minute: minute)
    }

    private func appendDebugLog(_ message: String, now: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        var logs = defaults.stringArray(forKey: debugLogsKey) ?? []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm:ss"
        logs.append("[\(formatter.string(from: now))] [MonitorExt] \(message)")
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
        defaults.set(logs, forKey: debugLogsKey)
    }
}
