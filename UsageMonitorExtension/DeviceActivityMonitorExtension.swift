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
private let lastResetKey = "lastResetAt"
private let resetGraceSeconds: TimeInterval = 30
private let debugLogsKey = "debugLogs"
private let defaultLimitMinutes = 30
private let unsyncedThresholdIgnoreWindowSeconds: TimeInterval = 180
private let lastRearmAtKey = "lastRearmAt"
private let monitorName = DeviceActivityName("daily-monitor")

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let center = DeviceActivityCenter()
    private let store = ManagedSettingsStore(named: managedStoreName)
    private let fallbackStore = ManagedSettingsStore()

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        if isWithinResetGrace() {
            appendDebugLog("eventDidReachThresholdをgraceで無視: \(event.rawValue)")
            return
        }
        let prefix = "limit_idx_"
        guard event.rawValue.hasPrefix(prefix) else { return }
        let indexString = String(event.rawValue.dropFirst(prefix.count))
        guard let index = Int(indexString) else { return }
        guard let tokens = loadTokensForMonitoring(), tokens.indices.contains(index) else {
            appendDebugLog("token解決に失敗: event=\(event.rawValue)")
            return
        }
        let token = tokens[index]
        if shouldIgnoreByUsageSnapshot(token: token) {
            rearmMonitoringIfNeeded(reason: event.rawValue)
            return
        }

        var blockedTokens = loadBlockedTokens()
        if !blockedTokens.contains(where: { tokenSortKey($0) == tokenSortKey(token) }) {
            blockedTokens.append(token)
            saveBlockedTokens(blockedTokens)
        }
        let blockedSet = Set(blockedTokens)
        store.shield.applications = blockedSet
        fallbackStore.shield.applications = blockedSet
        appendDebugLog("しきい値到達: \(event.rawValue), blocked=\(blockedSet.count)")
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        store.shield.applications = nil
        fallbackStore.shield.applications = nil
        saveBlockedTokens([])
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(nil, forKey: usageKey)
        defaults.removeObject(forKey: usageUpdatedAtKey)
        let hour = defaults.integer(forKey: "resetHour")
        let minute = defaults.integer(forKey: "resetMinute")
        let now = Date()
        let anchor = MonitoringLogic.resetAnchor(
            now: now,
            resetHour: hour,
            resetMinute: minute,
            calendar: Calendar.current
        )
        defaults.set(anchor, forKey: lastResetKey)
        appendDebugLog("intervalDidStart: resetAnchor=\(anchor)")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        appendDebugLog("intervalDidEnd")
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

    private func shouldIgnoreByUsageSnapshot(token: Token<Application>, now: Date = Date()) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return false
        }
        guard let lastReset = defaults.object(forKey: lastResetKey) as? Date else {
            return false
        }

        let usageUpdatedAt = defaults.object(forKey: usageUpdatedAtKey) as? Date

        let tokenKey = tokenSortKey(token)
        var usedMinutes: Int?
        if let usageData = defaults.data(forKey: usageKey),
           let usage = try? JSONDecoder().decode([String: Int].self, from: usageData) {
            usedMinutes = usage[tokenKey] ?? 0
        }

        var limitMinutes = defaultLimitMinutes
        if let limitsData = defaults.data(forKey: appLimitsKey),
           let limits = try? JSONDecoder().decode([String: Int].self, from: limitsData),
           let value = limits[tokenKey] {
            limitMinutes = value
        }

        let ignoreReason = MonitoringLogic.usageThresholdIgnoreReason(
            now: now,
            lastReset: lastReset,
            usageUpdatedAt: usageUpdatedAt,
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

    private func rearmMonitoringIfNeeded(reason: String, now: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if let lastRearmAt = defaults.object(forKey: lastRearmAtKey) as? Date,
           now.timeIntervalSince(lastRearmAt) < 30 {
            appendDebugLog("monitor再登録をスキップ(クールダウン): reason=\(reason)", now: now)
            return
        }
        guard let tokens = loadTokensForMonitoring(), !tokens.isEmpty else {
            appendDebugLog("monitor再登録を中止(トークンなし): reason=\(reason)", now: now)
            return
        }

        let limits = loadAppLimits(defaults: defaults)
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
            let perLimit = limits[tokenKey] ?? defaultLimitMinutes
            let name = DeviceActivityEvent.Name("limit_idx_\(index)")
            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                event = DeviceActivityEvent(
                    applications: Set([token]),
                    threshold: DateComponents(minute: perLimit),
                    includesPastActivity: false
                )
            } else {
                event = DeviceActivityEvent(
                    applications: Set([token]),
                    threshold: DateComponents(minute: perLimit)
                )
            }
            events[name] = event
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

    private func saveOrderedTokens(_ tokens: [Token<Application>], defaults: UserDefaults) {
        let items = tokens.compactMap { try? JSONEncoder().encode($0) }
        defaults.set(items, forKey: orderedTokensKey)
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
