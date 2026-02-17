import SwiftUI
import FamilyControls
import DeviceActivity
import ManagedSettings
import Combine

private let appGroupID = "group.com.xa504.snsalert"
private let managedStoreName = ManagedSettingsStore.Name("shared")


extension DeviceActivityReport.Context {
    static let daily = Self("daily")
}

private enum TokenKey {
    static func sortKey<T: Encodable>(_ token: T) -> String {
        guard let data = try? JSONEncoder().encode(token) else {
            return String(describing: token)
        }
        return data.base64EncodedString()
    }
}

final class AppStore {
    private let defaults: UserDefaults
    private let selectionKey = "savedSelection"
    private let appLimitsKey = "appLimits"
    private let resetHourKey = "resetHour"
    private let resetMinuteKey = "resetMinute"
    private let monitoringKey = "monitoringEnabled"
    private let setupCompletedKey = "setupCompleted"
    private let usageKey = "usageMinutes"
    private let usageUpdatedAtKey = "usageUpdatedAt"
    private let usageEventAcceptedAtKey = "usageEventAcceptedAt"
    private let reportLastRunAtKey = "reportLastRunAt"
    private let lastResetKey = "lastResetAt"
    private let blockedTokensKey = "blockedTokens"
    private let orderedTokensKey = "orderedTokens"
    private let debugLogsKey = "debugLogs"
    private let debugForceSyncFailureKey = "debugForceSyncFailure"

    init() {
        defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    }

    func loadSelection() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: selectionKey) else {
            return FamilyActivitySelection()
        }
        return (try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)) ?? FamilyActivitySelection()
    }

    func saveSelection(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: selectionKey)
        }
    }

    func loadAppLimits() -> [String: Int] {
        guard let data = defaults.data(forKey: appLimitsKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    func saveAppLimits(_ limits: [String: Int]) {
        if let data = try? JSONEncoder().encode(limits) {
            defaults.set(data, forKey: appLimitsKey)
        }
    }

    func loadResetTime() -> (hour: Int, minute: Int) {
        let hour = defaults.integer(forKey: resetHourKey)
        let minute = defaults.integer(forKey: resetMinuteKey)
        return ((0...23).contains(hour) ? hour : 0, (0...59).contains(minute) ? minute : 0)
    }

    func saveResetTime(hour: Int, minute: Int) {
        defaults.set(hour, forKey: resetHourKey)
        defaults.set(minute, forKey: resetMinuteKey)
    }

    func loadMonitoringEnabled() -> Bool {
        defaults.bool(forKey: monitoringKey)
    }

    func saveMonitoringEnabled(_ value: Bool) {
        defaults.set(value, forKey: monitoringKey)
    }

    func loadSetupCompleted() -> Bool {
        defaults.bool(forKey: setupCompletedKey)
    }

    func saveSetupCompleted(_ value: Bool) {
        defaults.set(value, forKey: setupCompletedKey)
    }

    func loadUsageMinutes() -> [String: Int] {
        guard let data = defaults.data(forKey: usageKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    func saveUsageMinutes(_ usage: [String: Int]) {
        if let data = try? JSONEncoder().encode(usage) {
            defaults.set(data, forKey: usageKey)
        }
    }

    func clearUsageEventAcceptedAt() {
        defaults.removeObject(forKey: usageEventAcceptedAtKey)
    }

    func loadUsageUpdatedAt() -> Date? {
        return defaults.object(forKey: usageUpdatedAtKey) as? Date
    }

    func loadReportLastRunAt() -> Date? {
        return defaults.object(forKey: reportLastRunAtKey) as? Date
    }

    func loadLastResetAt() -> Date? {
        return defaults.object(forKey: lastResetKey) as? Date
    }

    func saveLastResetAt(_ date: Date) {
        defaults.set(date, forKey: lastResetKey)
    }


    func loadBlockedTokens() -> [Token<Application>] {
        guard let items = defaults.array(forKey: blockedTokensKey) as? [Data] else {
            return []
        }
        return items.compactMap { try? JSONDecoder().decode(Token<Application>.self, from: $0) }
    }

    func saveBlockedTokens(_ tokens: [Token<Application>]) {
        let items = tokens.compactMap { try? JSONEncoder().encode($0) }
        defaults.set(items, forKey: blockedTokensKey)
    }

    func clearBlockedTokens() {
        defaults.removeObject(forKey: blockedTokensKey)
    }

    func saveOrderedTokens(_ tokens: [Token<Application>]) {
        let items = tokens.compactMap { try? JSONEncoder().encode($0) }
        defaults.set(items, forKey: orderedTokensKey)
    }

    func loadDebugLogs() -> [String] {
        return defaults.stringArray(forKey: debugLogsKey) ?? []
    }

    func appendDebugLog(_ message: String, now: Date = Date()) {
        var logs = loadDebugLogs()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm:ss"
        logs.append("[\(formatter.string(from: now))] \(message)")
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
        defaults.set(logs, forKey: debugLogsKey)
    }

    func clearDebugLogs() {
        defaults.removeObject(forKey: debugLogsKey)
    }

    func loadDebugForceSyncFailure() -> Bool {
        defaults.bool(forKey: debugForceSyncFailureKey)
    }

    func saveDebugForceSyncFailure(_ value: Bool) {
        defaults.set(value, forKey: debugForceSyncFailureKey)
    }
}

final class ScreenTimeManager {
    private let center = DeviceActivityCenter()
    private let store = ManagedSettingsStore(named: managedStoreName)
    private let fallbackStore = ManagedSettingsStore()
    private let lastRearmAtKey = "lastRearmAt"

    func startMonitoring(selection: FamilyActivitySelection, appLimits: [String: Int], defaultLimit: Int, resetHour: Int, resetMinute: Int) throws {
        center.stopMonitoring([DeviceActivityName("daily-monitor")])
        let start = DateComponents(hour: resetHour, minute: resetMinute)
        let end = endComponentsForDailyReset(hour: resetHour, minute: resetMinute)
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true
        )

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let tokens = Array(selection.applicationTokens)
            .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
        let persistedUsage = AppStore().loadUsageMinutes()
        for (idx, token) in tokens.enumerated() {
            let tokenKey = TokenKey.sortKey(token)
            let perLimit = appLimits[tokenKey] ?? appLimits["idx_\(idx)"] ?? defaultLimit
            let perEventName = DeviceActivityEvent.Name("limit_idx_\(idx)")
            let perEvent: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                perEvent = DeviceActivityEvent(
                    applications: Set([token]),
                    threshold: DateComponents(minute: perLimit),
                    // Keep same-day usage when monitor is restarted.
                    includesPastActivity: true
                )
            } else {
                perEvent = DeviceActivityEvent(
                    applications: Set([token]),
                    threshold: DateComponents(minute: perLimit)
                )
            }
            events[perEventName] = perEvent

            // Fallback path when ReportExt is unavailable:
            // keep a per-minute threshold event so MonitorExt can persist usage minutes.
            let usedMinutes = persistedUsage["idx_\(idx)"] ?? persistedUsage[tokenKey] ?? 0
            if usedMinutes < perLimit {
                let usageEventName = DeviceActivityEvent.Name("usage_idx_\(idx)")
                let usageEvent: DeviceActivityEvent
                if #available(iOS 17.4, *) {
                    usageEvent = DeviceActivityEvent(
                        applications: Set([token]),
                        threshold: DateComponents(minute: 1),
                        // Count only newly-added usage after monitor registration.
                        includesPastActivity: false
                    )
                } else {
                    usageEvent = DeviceActivityEvent(
                        applications: Set([token]),
                        threshold: DateComponents(minute: 1)
                    )
                }
                events[usageEventName] = usageEvent
            }
        }
        AppStore().saveOrderedTokens(tokens)
        UserDefaults(suiteName: appGroupID)?.set(Date(), forKey: lastRearmAtKey)

        try center.startMonitoring(DeviceActivityName("daily-monitor"), during: schedule, events: events)
    }

    func stopMonitoring() {
        center.stopMonitoring([DeviceActivityName("daily-monitor")])
    }

    func clearBlocks() {
        store.shield.applications = nil
        fallbackStore.shield.applications = nil
    }

    func applyBlocks(_ tokens: [Token<Application>]) {
        let blocked = Set(tokens)
        if blocked.isEmpty {
            store.shield.applications = nil
            fallbackStore.shield.applications = nil
            return
        }
        store.shield.applications = blocked
        fallbackStore.shield.applications = blocked
    }

    private func endComponentsForDailyReset(hour: Int, minute: Int) -> DateComponents {
        let startTotal = hour * 60 + minute
        let endTotal = (startTotal + 24 * 60 - 1) % (24 * 60)
        return DateComponents(hour: endTotal / 60, minute: endTotal % 60)
    }
}

final class UsageSyncManager {
    private var timer: Timer?
    var onTick: (() -> Void)?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.onTick?()
        }
        onTick?()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

final class ContentViewModel: ObservableObject {
    private enum UIErrorKind {
        case permissionRequired
        case monitorStartFailed

        var message: String {
            switch self {
            case .permissionRequired:
                return "Screen Timeの許可が必要です"
            case .monitorStartFailed:
                return "監視開始に失敗しました"
            }
        }
    }

    private enum UIErrorText {
        static let syncFailed = "使用時間の同期に失敗しています"
    }

    @Published var authorized = false
    @Published var selection = FamilyActivitySelection()
    let defaultLimitMinutes = 30
    @Published var appLimits: [String: Int] = [:]
    @Published var resetHour = 0
    @Published var resetMinute = 0
    @Published var isMonitoring = false
    @Published var setupCompleted = false
    @Published private var uiError: UIErrorKind? = nil
    @Published var syncErrorMessage: String? = nil
    @Published var usageMinutes: [String: Int] = [:]
    @Published var lastUsageSyncAt: Date? = nil
    @Published var nextResetAt: Date = Date()
    @Published var blockedTokenKeys: Set<String> = []
    @Published var reportRefresh = Date()
    @Published var reportInterval = DateInterval(
        start: Date().addingTimeInterval(-60),
        end: Date()
    )
    @Published var debugLogs: [String] = []
    @Published var debugForceSyncFailure = false

    private let store = AppStore()
    private let screenTimeManager = ScreenTimeManager()
    private let syncManager = UsageSyncManager()
    private let syncStaleThresholdSeconds: TimeInterval = 180
    private let followupSyncDelaySeconds: TimeInterval = 2
    private var syncWarmupUntil: Date?
    private var wasSyncDelayed = false
    private var didLogMissingReportRun = false
    private var followupSyncWorkItem: DispatchWorkItem?

    init() {
        syncManager.onTick = { [weak self] in
            self?.syncUsage(reason: "syncTick")
        }
    }

    func load() {
        selection = store.loadSelection()
        appLimits = store.loadAppLimits()
        let reset = store.loadResetTime()
        resetHour = reset.hour
        resetMinute = reset.minute
        isMonitoring = store.loadMonitoringEnabled()
        setupCompleted = store.loadSetupCompleted()
        usageMinutes = store.loadUsageMinutes()
        lastUsageSyncAt = store.loadUsageUpdatedAt()
        blockedTokenKeys = Set(store.loadBlockedTokens().map { TokenKey.sortKey($0) })
        debugLogs = store.loadDebugLogs()
#if DEBUG
        debugForceSyncFailure = store.loadDebugForceSyncFailure()
#else
        debugForceSyncFailure = false
#endif
        ensureAppLimitsForSelection()
        if store.loadLastResetAt() == nil {
            store.saveLastResetAt(currentResetAnchor(now: Date()))
        }
        updateAuthorizationStatus()
        refreshPermissionErrorState()
        let now = Date()
        refreshNextResetAt(now: now)
        refreshReportInterval(now: now)
        if isMonitoring {
            syncWarmupUntil = Date().addingTimeInterval(syncStaleThresholdSeconds)
            syncManager.start()
        }
    }

    func startMonitoring() {
        Task {
            uiError = nil
            let ok = await ensureScreenTimeAuthorization()
            if !ok { return }
            if selection.applicationTokens.isEmpty {
                uiError = .monitorStartFailed
                return
            }
            ensureAppLimitsForSelection()
            let normalizedLimits = normalizedAppLimitsForSelection()
            appLimits = normalizedLimits
            let now = Date()
            let anchor = currentResetAnchor(now: now)
            if let lastReset = store.loadLastResetAt(),
               isResetTimeDrifted(lastReset: lastReset) {
                resetStateForResetTimeChange(now: now, lastReset: lastReset, newAnchor: anchor)
            }
            store.saveSelection(selection)
            store.saveAppLimits(normalizedLimits)
            store.saveResetTime(hour: resetHour, minute: resetMinute)
            if store.loadLastResetAt() == nil {
                store.saveLastResetAt(anchor)
            }
            resetIfNeeded(now: now)
            refreshNextResetAt(now: now)
            let lastResetAfterPrepare = store.loadLastResetAt()
            appendDebugLog("監視開始前リセット判定: anchor=\(anchor), lastReset=\(String(describing: lastResetAfterPrepare))")

            do {
                appendDebugLog("監視開始を要求")
                screenTimeManager.clearBlocks()
                store.clearBlockedTokens()
                try screenTimeManager.startMonitoring(
                    selection: selection,
                    appLimits: normalizedLimits,
                    defaultLimit: defaultLimitMinutes,
                    resetHour: resetHour,
                    resetMinute: resetMinute
                )
                isMonitoring = true
                setupCompleted = true
                store.saveMonitoringEnabled(true)
                store.saveSetupCompleted(true)
                syncWarmupUntil = Date().addingTimeInterval(syncStaleThresholdSeconds)
                wasSyncDelayed = false
                appendDebugLog("監視開始に成功")
                uiError = nil
                syncManager.start()
            } catch {
                appendDebugLog("監視開始に失敗")
                uiError = .monitorStartFailed
            }
        }
    }

    func stopMonitoring() {
        screenTimeManager.stopMonitoring()
        screenTimeManager.clearBlocks()
        store.clearBlockedTokens()
        isMonitoring = false
        store.saveMonitoringEnabled(false)
        syncWarmupUntil = nil
        wasSyncDelayed = false
        syncErrorMessage = nil
        uiError = nil
        appendDebugLog("監視を停止")
        syncManager.stop()
        followupSyncWorkItem?.cancel()
        followupSyncWorkItem = nil
        let now = Date()
        refreshNextResetAt(now: now)
        refreshReportInterval(now: now)
    }

    func updateSelection(_ selection: FamilyActivitySelection) {
        guard !isMonitoring else { return }
        self.selection = selection
        store.saveSelection(selection)
        ensureAppLimitsForSelection()
    }

    func updateAppLimit(tokenKey: String, value: Int) {
        guard !isMonitoring else { return }
        appLimits[tokenKey] = value
        if let index = indexForTokenKey(tokenKey) {
            appLimits[limitIndexKey(index)] = value
        }
        store.saveAppLimits(appLimits)
    }

    func updateResetTime(hour: Int, minute: Int) {
        guard !isMonitoring else { return }
        resetHour = hour
        resetMinute = minute
        store.saveResetTime(hour: hour, minute: minute)
        let now = Date()
        refreshNextResetAt(now: now)
        refreshReportInterval(now: now)
        resetIfNeeded(now: now)
    }

    func remainingMinutes(for tokenKey: String) -> Int {
        let used = usedMinutes(for: tokenKey)
        let limit = limitMinutes(for: tokenKey)
        return max(limit - used, 0)
    }

    func limitMinutes(for tokenKey: String) -> Int {
        if let value = appLimits[tokenKey] {
            return value
        }
        if let index = indexForTokenKey(tokenKey),
           let indexed = appLimits[limitIndexKey(index)] {
            return indexed
        }
        return defaultLimitMinutes
    }

    func usedMinutes(for tokenKey: String) -> Int {
        if let used = usageMinutes[tokenKey] {
            return used
        }
        if let index = indexForTokenKey(tokenKey),
           let indexed = usageMinutes[limitIndexKey(index)] {
            return indexed
        }
        return 0
    }

    func formatRemaining(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)時間\(mins)分"
    }

    func isBlocked(tokenKey: String) -> Bool {
        blockedTokenKeys.contains(tokenKey)
    }

    func debugResetUsage() {
        usageMinutes = [:]
        store.saveUsageMinutes([:])
    }

    func debugToggleBlock() {
        if blockedTokenKeys.isEmpty {
            let tokens = Array(selection.applicationTokens)
                .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
            guard let token = tokens.first else { return }
            let blocked = [token]
            blockedTokenKeys = [TokenKey.sortKey(token)]
            store.saveBlockedTokens(blocked)
            screenTimeManager.applyBlocks(blocked)
            appendDebugLog("DEBUG: 即ブロック ON")
        } else {
            blockedTokenKeys = []
            store.clearBlockedTokens()
            screenTimeManager.clearBlocks()
            appendDebugLog("DEBUG: 即ブロック OFF")
        }
    }

    func clearDebugLogs() {
        store.clearDebugLogs()
        debugLogs = []
    }

    func debugToggleSyncFailure() {
        debugForceSyncFailure.toggle()
        store.saveDebugForceSyncFailure(debugForceSyncFailure)
        appendDebugLog("DEBUG: 同期失敗トグル \(debugForceSyncFailure ? "ON" : "OFF")")
    }

    func handleAppBecameActive() {
        guard isMonitoring else { return }
        syncUsage(reason: "appActive")
    }

    private func syncUsage(reason: String, triggerReportRefresh: Bool = true) {
        resetIfNeeded(now: Date())
        var blockedTokens = store.loadBlockedTokens()
        let latestUsage = store.loadUsageMinutes()
        let usageUpdatedAt = store.loadUsageUpdatedAt()
        let reportLastRunAt = store.loadReportLastRunAt()
        let now = Date()
        lastUsageSyncAt = usageUpdatedAt
        refreshNextResetAt(now: now)
#if DEBUG
        let forceSyncFailure = debugForceSyncFailure
#else
        let forceSyncFailure = false
#endif
        let isUsageFresh = usageUpdatedAt.map { now.timeIntervalSince($0) <= syncStaleThresholdSeconds } ?? false
        let isReportRunFresh = reportLastRunAt.map { now.timeIntervalSince($0) <= syncStaleThresholdSeconds } ?? false
        if isReportRunFresh {
            didLogMissingReportRun = false
        }

        if forceSyncFailure {
            syncErrorMessage = UIErrorText.syncFailed
            if !wasSyncDelayed {
                appendDebugLog("同期遅延を検知")
                wasSyncDelayed = true
            }
        } else if isUsageFresh {
            usageMinutes = latestUsage
            syncWarmupUntil = nil
            syncErrorMessage = nil
            didLogMissingReportRun = false
            if wasSyncDelayed {
                appendDebugLog("同期遅延から復帰")
                wasSyncDelayed = false
            }
        } else if let warmupUntil = syncWarmupUntil, now < warmupUntil {
            syncErrorMessage = nil
            if !isReportRunFresh && !didLogMissingReportRun {
                appendDebugLog("ReportExt実行を未検知")
                didLogMissingReportRun = true
            }
        } else if !isReportRunFresh {
            // Keep previous usage and continue in monitor-based fallback mode
            // when report extension execution cannot be observed.
            syncErrorMessage = nil
            if !didLogMissingReportRun {
                appendDebugLog("ReportExt実行を未検知")
                didLogMissingReportRun = true
            }
            if wasSyncDelayed {
                appendDebugLog("同期遅延から復帰")
                wasSyncDelayed = false
            }
        } else {
            syncErrorMessage = UIErrorText.syncFailed
            if !isReportRunFresh && !didLogMissingReportRun {
                appendDebugLog("ReportExt実行を未検知")
                didLogMissingReportRun = true
            }
            if !wasSyncDelayed {
                appendDebugLog("同期遅延を検知")
                wasSyncDelayed = true
            }
        }

        // Sync error state: keep current block state as-is and skip usage-based reconciliation.
        if syncErrorMessage != nil {
            blockedTokenKeys = Set(blockedTokens.map { TokenKey.sortKey($0) })
            screenTimeManager.applyBlocks(blockedTokens)
            debugLogs = store.loadDebugLogs()
            if triggerReportRefresh {
                requestUsageReportRefresh(reason: "syncError")
                scheduleFollowupSync(baseReason: reason)
            }
            return
        }

        // Rebuild block state from persisted usage so restart/extension timing cannot miss limits.
        let selectedTokens = Array(selection.applicationTokens)
            .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
        var blockedKeys = Set(blockedTokens.map { TokenKey.sortKey($0) })
        for token in selectedTokens {
            let key = TokenKey.sortKey(token)
            let used = usedMinutes(for: key)
            let limit = limitMinutes(for: key)
            if used >= limit && !blockedKeys.contains(key) {
                blockedTokens.append(token)
                blockedKeys.insert(key)
            }
        }

        store.saveBlockedTokens(blockedTokens)
        blockedTokenKeys = blockedKeys
        screenTimeManager.applyBlocks(blockedTokens)
        debugLogs = store.loadDebugLogs()
        if triggerReportRefresh {
            requestUsageReportRefresh(reason: reason)
            scheduleFollowupSync(baseReason: reason)
        }
    }

    private func currentResetAnchor(now: Date) -> Date {
        let calendar = Calendar.current
        let todayReset = calendar.date(bySettingHour: resetHour, minute: resetMinute, second: 0, of: now) ?? now
        if now < todayReset {
            return calendar.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset
        }
        return todayReset
    }

    func currentReportInterval(now: Date = Date()) -> DateInterval {
        let anchor = currentResetAnchor(now: now)
        let minEnd = anchor.addingTimeInterval(60)
        let end = (now < minEnd) ? minEnd : now
        return DateInterval(start: anchor, end: end)
    }

    private func resetIfNeeded(now: Date) {
        let anchor = currentResetAnchor(now: now)
        if let last = store.loadLastResetAt(), last >= anchor {
            return
        }
        usageMinutes = [:]
        store.saveUsageMinutes([:])
        store.clearUsageEventAcceptedAt()
        store.clearBlockedTokens()
        blockedTokenKeys = []
        screenTimeManager.clearBlocks()
        store.saveLastResetAt(anchor)
        refreshNextResetAt(now: now)
        appendDebugLog("日次リセットを実行")
    }

    private func isResetTimeDrifted(lastReset: Date) -> Bool {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: lastReset)
        guard let hour = parts.hour, let minute = parts.minute else {
            return false
        }
        return hour != resetHour || minute != resetMinute
    }

    private func resetStateForResetTimeChange(now: Date, lastReset: Date, newAnchor: Date) {
        usageMinutes = [:]
        store.saveUsageMinutes([:])
        store.clearUsageEventAcceptedAt()
        store.clearBlockedTokens()
        blockedTokenKeys = []
        screenTimeManager.clearBlocks()
        store.saveLastResetAt(newAnchor)
        appendDebugLog(
            "リセット時刻変更を検知: 使用時間を初期化(anchor=\(newAnchor), lastReset=\(lastReset))"
        )
        refreshNextResetAt(now: now)
    }


    private func ensureAppLimitsForSelection() {
        let updated = normalizedAppLimitsForSelection()
        if updated != appLimits {
            appLimits = updated
            store.saveAppLimits(updated)
        }
    }

    private func normalizedAppLimitsForSelection() -> [String: Int] {
        var normalized = appLimits
        let tokens = Array(selection.applicationTokens)
            .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
        for (index, token) in tokens.enumerated() {
            let tokenKey = TokenKey.sortKey(token)
            let idxKey = limitIndexKey(index)
            let value = normalized[tokenKey] ?? normalized[idxKey] ?? defaultLimitMinutes
            normalized[tokenKey] = value
            normalized[idxKey] = value
        }
        return normalized
    }

    private func limitIndexKey(_ index: Int) -> String {
        "idx_\(index)"
    }

    private func indexForTokenKey(_ tokenKey: String) -> Int? {
        let tokens = Array(selection.applicationTokens)
            .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
        return tokens.firstIndex { TokenKey.sortKey($0) == tokenKey }
    }

    private func ensureScreenTimeAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            uiError = .permissionRequired
        }
        updateAuthorizationStatus()
        refreshPermissionErrorState()
        return authorized
    }

    private func updateAuthorizationStatus() {
        let status = AuthorizationCenter.shared.authorizationStatus
        authorized = (status == .approved)
    }

    private func refreshPermissionErrorState() {
        // Monitoring is already active; avoid false-positive permission error display.
        if isMonitoring {
            if uiError == .permissionRequired {
                uiError = nil
            }
            return
        }
        if !authorized {
            uiError = .permissionRequired
        } else if uiError == .permissionRequired {
            uiError = nil
        }
    }

    private func appendDebugLog(_ message: String) {
        store.appendDebugLog(message)
        debugLogs = store.loadDebugLogs()
    }

    func monitoringStatusText() -> String {
        isMonitoring ? "監視中" : "停止中"
    }

    func activeErrorMessage() -> String? {
        if let uiError {
            return uiError.message
        }
        return syncErrorMessage
    }

    func lastSyncDisplayText() -> String {
        guard let syncedAt = lastUsageSyncAt else {
            return "未同期"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter.string(from: syncedAt)
    }

    func nextResetDisplayText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: nextResetAt)
    }

    private func refreshNextResetAt(now: Date) {
        let calendar = Calendar.current
        let todayReset = calendar.date(
            bySettingHour: resetHour,
            minute: resetMinute,
            second: 0,
            of: now
        ) ?? now
        if now < todayReset {
            nextResetAt = todayReset
            return
        }
        nextResetAt = calendar.date(byAdding: .day, value: 1, to: todayReset) ?? todayReset
    }

    private func requestUsageReportRefresh(reason: String) {
        let now = Date()
        reportRefresh = now
        refreshReportInterval(now: now)
        appendDebugLog("使用時間同期を要求: \(reason)")
    }

    func markReportHostRendered(trigger: String) {
#if DEBUG
        appendDebugLog("ReportHost描画: \(trigger)")
#endif
    }

    private func scheduleFollowupSync(baseReason: String) {
        followupSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.syncUsage(reason: "\(baseReason)_followup", triggerReportRefresh: false)
        }
        followupSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + followupSyncDelaySeconds, execute: workItem)
    }

    private func refreshReportInterval(now: Date) {
        reportInterval = currentReportInterval(now: now)
    }
}

private struct UsageReportHostView: View {
    let refreshToken: Date
    let selection: FamilyActivitySelection
    let interval: DateInterval
    let onRender: ((String) -> Void)?

    var body: some View {
        DeviceActivityReport(.daily, filter: reportFilter)
        .id(reportIdentity)
        .frame(width: 8, height: 8)
        .opacity(0.01)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            onRender?("appear")
        }
        .onChange(of: refreshToken) { _ in
            onRender?("refresh")
        }
    }

    private var reportIdentity: String {
        let ts = Int(refreshToken.timeIntervalSince1970)
        let start = Int(interval.start.timeIntervalSince1970)
        let end = Int(interval.end.timeIntervalSince1970)
        return "\(ts)-\(start)-\(end)-\(selection.applicationTokens.count)"
    }

    private var reportFilter: DeviceActivityFilter {
        // Keep report execution stable by requesting the daily segment broadly,
        // then map selected tokens inside the report extension.
        return DeviceActivityFilter(
            segment: .daily(during: interval),
            devices: .all
        )
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPicker = false
    @State private var showEdit = false
    @State private var editingTokenKey: String? = nil
    @State private var draftLimitMinutes: Int = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Group {
                    if viewModel.setupCompleted && viewModel.isMonitoring && !showEdit {
                        SettingsSummaryView(
                            viewModel: viewModel,
                            onEdit: {
                                showEdit = true
                            }
                        )
                    } else {
                        setupView
                    }
                }
                UsageReportHostView(
                    refreshToken: viewModel.reportRefresh,
                    selection: viewModel.selection,
                    interval: viewModel.reportInterval,
                    onRender: { trigger in
                        viewModel.markReportHostRendered(trigger: trigger)
                    }
                )
                .padding(.top, 1)
                .padding(.leading, 1)
            }
            .navigationTitle("SNSアラート")
        }
        .onAppear {
            viewModel.load()
        }
        .onChange(of: viewModel.isMonitoring) { isMonitoring in
            if isMonitoring {
                showEdit = false
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                viewModel.handleAppBecameActive()
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: Binding(
            get: { viewModel.selection },
            set: { newValue in viewModel.updateSelection(newValue) }
        ))
    }

    private var setupView: some View {
        VStack(spacing: 16) {
            Text("Screen Time許可: \(viewModel.authorized ? "OK" : "未")")
            Text("選択アプリ数: \(viewModel.selection.applicationTokens.count)")
            statusBadge
            GroupBox("監視状態") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("状態")
                        Spacer()
                        Text(viewModel.monitoringStatusText())
                            .foregroundColor(viewModel.isMonitoring ? .green : .secondary)
                    }
                    HStack {
                        Text("最終同期")
                        Spacer()
                        Text(viewModel.lastSyncDisplayText())
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                    HStack {
                        Text("次回リセット")
                        Spacer()
                        Text(viewModel.nextResetDisplayText())
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                }
            }
            if !viewModel.selection.applicationTokens.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("選択アプリごとの上限")
                        .font(.headline)
                    let tokens = Array(viewModel.selection.applicationTokens)
                        .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
                    let tokenEntries = tokens.enumerated().map { index, token in
                        (index: index, tokenKey: TokenKey.sortKey(token))
                    }
                    ForEach(tokenEntries, id: \.tokenKey) { entry in
                        let index = entry.index
                        let tokenKey = entry.tokenKey
                        let currentLimit = viewModel.limitMinutes(for: tokenKey)
                        let isEditing = editingTokenKey == tokenKey
                        VStack(alignment: .leading, spacing: 8) {
                            Text("アプリ \(index + 1)")
                                .font(.subheadline)
                            if isEditing {
                                HStack(spacing: 8) {
                                    ForEach([15, 30, 60], id: \.self) { value in
                                        Button {
                                            draftLimitMinutes = value
                                            viewModel.updateAppLimit(tokenKey: tokenKey, value: value)
                                        } label: {
                                            Text("\(value)分")
                                                .frame(minWidth: 44, minHeight: 32)
                                        }
                                        .buttonStyle(.plain)
                                        .background(draftLimitMinutes == value ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                                        .foregroundColor(draftLimitMinutes == value ? .accentColor : .primary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(draftLimitMinutes == value ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                    Picker("上限", selection: $draftLimitMinutes) {
                                        ForEach(1...300, id: \.self) { minutes in
                                            Text("\(minutes)分").tag(minutes)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                                .onChange(of: draftLimitMinutes) { newValue in
                                    guard editingTokenKey == tokenKey else { return }
                                    viewModel.updateAppLimit(tokenKey: tokenKey, value: newValue)
                                }
                            } else {
                                Text("上限: \(currentLimit)分")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingTokenKey = tokenKey
                            draftLimitMinutes = currentLimit
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Text("リセット時刻")
                Picker("時", selection: Binding(
                    get: { viewModel.resetHour },
                    set: { viewModel.updateResetTime(hour: $0, minute: viewModel.resetMinute) }
                )) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)

                Picker("分", selection: Binding(
                    get: { viewModel.resetMinute },
                    set: { viewModel.updateResetTime(hour: viewModel.resetHour, minute: $0) }
                )) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .pickerStyle(.menu)
            }

            Button("監視するアプリを選ぶ") {
                showPicker = true
            }

            Button(viewModel.isMonitoring ? "監視中" : "監視開始") {
                viewModel.startMonitoring()
            }
            .disabled(viewModel.isMonitoring)

            Button("停止") {
                viewModel.stopMonitoring()
            }
            .disabled(!viewModel.isMonitoring)

            if let message = viewModel.activeErrorMessage() {
                Text(message)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
        }
        .padding()
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isMonitoring ? "checkmark.circle.fill" : "pause.circle")
            Text(viewModel.isMonitoring ? "監視中" : "停止中")
        }
        .foregroundColor(viewModel.isMonitoring ? .green : .gray)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(viewModel.isMonitoring ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SettingsSummaryView: View {
    @ObservedObject var viewModel: ContentViewModel
    let onEdit: () -> Void

    var body: some View {
        List {
            Section("状態") {
                HStack {
                    Text("監視")
                    Spacer()
                    Text(viewModel.monitoringStatusText())
                        .foregroundColor(viewModel.isMonitoring ? .green : .secondary)
                }
                HStack {
                    Text("最終同期")
                    Spacer()
                    Text(viewModel.lastSyncDisplayText())
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
                HStack {
                    Text("次回リセット")
                    Spacer()
                    Text(viewModel.nextResetDisplayText())
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
            }

            Section("監視中") {
                ForEach(tokenEntries, id: \.tokenKey) { entry in
                    NavigationLink {
                        AppDetailView(
                            title: "アプリ \(entry.index + 1)",
                            tokenKey: entry.tokenKey,
                            viewModel: viewModel
                        )
                    } label: {
                        HStack {
                            Image(systemName: viewModel.isBlocked(tokenKey: entry.tokenKey) ? "lock.fill" : "checkmark.circle")
                                .foregroundColor(viewModel.isBlocked(tokenKey: entry.tokenKey) ? .red : .green)
                            VStack(alignment: .leading) {
                                Text("アプリ \(entry.index + 1)")
                                Text("上限: \(viewModel.limitMinutes(for: entry.tokenKey))分")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }

            Section("リセット時刻") {
                Text(String(format: "%02d:%02d", viewModel.resetHour, viewModel.resetMinute))
            }

            if let message = viewModel.activeErrorMessage() {
                Section("注意") {
                    Text(message)
                        .foregroundColor(.red)
                }
            }

            if !viewModel.isMonitoring {
                Section {
                    Button("設定を編集") {
                        onEdit()
                    }
                }
            }

            Section {
                Button("停止") {
                    viewModel.stopMonitoring()
                }
                .disabled(!viewModel.isMonitoring)
            }

            #if DEBUG
            Section("DEBUG") {
                Button("使用時間を即リセット") {
                    viewModel.debugResetUsage()
                }
                Button("即ブロック/解除トグル") {
                    viewModel.debugToggleBlock()
                }
                Button(viewModel.debugForceSyncFailure ? "同期失敗シミュレーション: ON" : "同期失敗シミュレーション: OFF") {
                    viewModel.debugToggleSyncFailure()
                }
                Button("デバッグログをクリア") {
                    viewModel.clearDebugLogs()
                }
            }
            Section("DEBUGログ") {
                let logs = Array(viewModel.debugLogs.suffix(30))
                if logs.isEmpty {
                    Text("ログなし")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(.caption2)
                            .textSelection(.enabled)
                    }
                }
            }
            #endif
        }
    }

    private var tokenEntries: [(index: Int, tokenKey: String)] {
        let tokens = Array(viewModel.selection.applicationTokens)
            .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
        return tokens.enumerated().map { index, token in
            (index: index, tokenKey: TokenKey.sortKey(token))
        }
    }
}

struct AppDetailView: View {
    let title: String
    let tokenKey: String
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title2)
            Text("上限: \(viewModel.limitMinutes(for: tokenKey))分")
            Text("残り: \(formatRemaining(viewModel.remainingMinutes(for: tokenKey)))")
                .font(.headline)
            Text(viewModel.isBlocked(tokenKey: tokenKey) ? "制限中" : "使用可能")
                .foregroundColor(viewModel.isBlocked(tokenKey: tokenKey) ? .red : .green)
            Spacer()
        }
        .padding()
    }

    private func formatRemaining(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)時間\(mins)分"
    }
}
