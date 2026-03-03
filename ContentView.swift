import SwiftUI
import FamilyControls
import DeviceActivity
import ManagedSettings
import Combine
import UserNotifications

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

private func appColor(forIndex index: Int) -> Color {
    let hues: [Double] = [0.58, 0.95, 0.13, 0.35, 0.72, 0.02, 0.48, 0.85]
    return Color(hue: hues[index % hues.count], saturation: 0.6, brightness: 0.85)
}

final class AppStore {
    private let defaults: UserDefaults
    private let selectionKey = "savedSelection"
    private let appLimitsKey = "appLimits"
    private let continuousAlertLimitsKey = "continuousAlertLimits"
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
    private let continuousUsageKey = "continuousUsageMinutes"
    private let continuousLastEventAtKey = "continuousLastEventAt"
    private let continuousLastNotifiedAtKey = "continuousLastNotifiedAt"
    private let continuousActiveIndexKey = "continuousActiveIndex"
    private let onboardingCompletedKey = "onboardingCompleted"

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

    func loadContinuousAlertLimits() -> [String: Int] {
        guard let data = defaults.data(forKey: continuousAlertLimitsKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    func saveContinuousAlertLimits(_ limits: [String: Int]) {
        if let data = try? JSONEncoder().encode(limits) {
            defaults.set(data, forKey: continuousAlertLimitsKey)
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

    func loadOnboardingCompleted() -> Bool {
        defaults.bool(forKey: onboardingCompletedKey)
    }

    func saveOnboardingCompleted(_ value: Bool) {
        defaults.set(value, forKey: onboardingCompletedKey)
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

    func loadContinuousUsageMinutes() -> [String: Int] {
        guard let data = defaults.data(forKey: continuousUsageKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
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

    func clearContinuousUsageState() {
        defaults.removeObject(forKey: continuousUsageKey)
        defaults.removeObject(forKey: continuousLastEventAtKey)
        defaults.removeObject(forKey: continuousLastNotifiedAtKey)
        defaults.removeObject(forKey: continuousActiveIndexKey)
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
    @Published var notificationAuthorized = false
    @Published var selection = FamilyActivitySelection()
    let defaultLimitMinutes = 30
    @Published var appLimits: [String: Int] = [:]
    @Published var continuousAlertLimits: [String: Int] = [:]
    @Published var resetHour = 0
    @Published var resetMinute = 0
    @Published var isMonitoring = false
    @Published var setupCompleted = false
    @Published var onboardingCompleted = false
    @Published private var uiError: UIErrorKind? = nil
    @Published var syncErrorMessage: String? = nil
    @Published var usageMinutes: [String: Int] = [:]
    @Published var continuousUsageMinutes: [String: Int] = [:]
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
        continuousAlertLimits = store.loadContinuousAlertLimits()
        let reset = store.loadResetTime()
        resetHour = reset.hour
        resetMinute = reset.minute
        isMonitoring = store.loadMonitoringEnabled()
        setupCompleted = store.loadSetupCompleted()
        onboardingCompleted = store.loadOnboardingCompleted()
        usageMinutes = store.loadUsageMinutes()
        continuousUsageMinutes = store.loadContinuousUsageMinutes()
        lastUsageSyncAt = store.loadUsageUpdatedAt()
        blockedTokenKeys = Set(store.loadBlockedTokens().map { TokenKey.sortKey($0) })
        debugLogs = store.loadDebugLogs()
#if DEBUG
        debugForceSyncFailure = store.loadDebugForceSyncFailure()
#else
        debugForceSyncFailure = false
#endif
        ensureAppLimitsForSelection()
        ensureContinuousAlertLimitsForSelection()
        if store.loadLastResetAt() == nil {
            store.saveLastResetAt(currentResetAnchor(now: Date()))
        }
        updateAuthorizationStatus()
        refreshPermissionErrorState()
        Task {
            await refreshNotificationAuthorizationStatus()
        }
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
            ensureContinuousAlertLimitsForSelection()
            let normalizedLimits = normalizedAppLimitsForSelection()
            let normalizedContinuousLimits = normalizedContinuousAlertLimitsForSelection()
            appLimits = normalizedLimits
            continuousAlertLimits = normalizedContinuousLimits
            await ensureNotificationAuthorizationIfNeeded(
                hasEnabledContinuousAlert: normalizedContinuousLimits.values.contains(where: { $0 > 0 })
            )
            let now = Date()
            let anchor = currentResetAnchor(now: now)
            if let lastReset = store.loadLastResetAt(),
               isResetTimeDrifted(lastReset: lastReset) {
                resetStateForResetTimeChange(now: now, lastReset: lastReset, newAnchor: anchor)
            }
            store.saveSelection(selection)
            store.saveAppLimits(normalizedLimits)
            store.saveContinuousAlertLimits(normalizedContinuousLimits)
            store.saveResetTime(hour: resetHour, minute: resetMinute)
            if store.loadLastResetAt() == nil {
                store.saveLastResetAt(anchor)
            }
            resetIfNeeded(now: now)
            store.clearContinuousUsageState()
            continuousUsageMinutes = [:]
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
        store.clearContinuousUsageState()
        continuousUsageMinutes = [:]
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
        ensureContinuousAlertLimitsForSelection()
    }

    func updateAppLimit(tokenKey: String, value: Int) {
        guard !isMonitoring else { return }
        appLimits[tokenKey] = value
        if let index = indexForTokenKey(tokenKey) {
            appLimits[limitIndexKey(index)] = value
        }
        store.saveAppLimits(appLimits)
    }

    func updateContinuousAlertLimit(tokenKey: String, value: Int) {
        guard !isMonitoring else { return }
        let normalized = max(value, 0)
        continuousAlertLimits[tokenKey] = normalized
        if let index = indexForTokenKey(tokenKey) {
            continuousAlertLimits[limitIndexKey(index)] = normalized
        }
        store.saveContinuousAlertLimits(continuousAlertLimits)
        Task {
            await ensureNotificationAuthorizationIfNeeded(
                hasEnabledContinuousAlert: continuousAlertLimits.values.contains(where: { $0 > 0 })
            )
        }
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

    func continuousAlertLimitMinutes(for tokenKey: String) -> Int {
        if let value = continuousAlertLimits[tokenKey] {
            return value
        }
        if let index = indexForTokenKey(tokenKey),
           let indexed = continuousAlertLimits[limitIndexKey(index)] {
            return indexed
        }
        return 0
    }

    func continuousAlertDisplayText(for tokenKey: String) -> String {
        let value = continuousAlertLimitMinutes(for: tokenKey)
        return value > 0 ? "\(value)分" : "OFF"
    }

    func continuousUsageStreakMinutes(for tokenKey: String) -> Int {
        if let value = continuousUsageMinutes[tokenKey] {
            return value
        }
        if let index = indexForTokenKey(tokenKey),
           let indexed = continuousUsageMinutes[limitIndexKey(index)] {
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
        continuousUsageMinutes = [:]
        store.clearContinuousUsageState()
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
        let latestContinuousUsage = store.loadContinuousUsageMinutes()
        let usageUpdatedAt = store.loadUsageUpdatedAt()
        let reportLastRunAt = store.loadReportLastRunAt()
        let now = Date()
        continuousUsageMinutes = latestContinuousUsage
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
            continuousUsageMinutes = latestContinuousUsage
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
            continuousUsageMinutes = latestContinuousUsage
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
        continuousUsageMinutes = [:]
        store.clearContinuousUsageState()
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
        continuousUsageMinutes = [:]
        store.clearContinuousUsageState()
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

    private func ensureContinuousAlertLimitsForSelection() {
        let updated = normalizedContinuousAlertLimitsForSelection()
        if updated != continuousAlertLimits {
            continuousAlertLimits = updated
            store.saveContinuousAlertLimits(updated)
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

    private func normalizedContinuousAlertLimitsForSelection() -> [String: Int] {
        var normalized = continuousAlertLimits
        let tokens = Array(selection.applicationTokens)
            .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
        for (index, token) in tokens.enumerated() {
            let tokenKey = TokenKey.sortKey(token)
            let idxKey = limitIndexKey(index)
            let value = max(normalized[tokenKey] ?? normalized[idxKey] ?? 0, 0)
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

    private func ensureNotificationAuthorizationIfNeeded(hasEnabledContinuousAlert: Bool) async {
        guard hasEnabledContinuousAlert else {
            await refreshNotificationAuthorizationStatus()
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationAuthorized = true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            notificationAuthorized = granted
        case .denied:
            notificationAuthorized = false
        @unknown default:
            notificationAuthorized = false
        }
    }

    private func refreshNotificationAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationAuthorized = true
        case .notDetermined, .denied:
            notificationAuthorized = false
        @unknown default:
            notificationAuthorized = false
        }
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

    func completeOnboarding() {
        onboardingCompleted = true
        store.saveOnboardingCompleted(true)
    }

    func resetOnboarding() {
        onboardingCompleted = false
        store.saveOnboardingCompleted(false)
    }

    func refreshPermissions() async {
        updateAuthorizationStatus()
        await refreshNotificationAuthorizationStatus()
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
    @State private var draftContinuousAlertMinutes: Int = 0

    var body: some View {
        Group {
            if !viewModel.onboardingCompleted {
                OnboardingView(viewModel: viewModel)
                    .transition(.opacity)
            } else {
                NavigationStack {
                    ZStack(alignment: .topLeading) {
                        let isShowingSummary = viewModel.setupCompleted && viewModel.isMonitoring && !showEdit
                        Group {
                            if isShowingSummary {
                                SettingsSummaryView(
                                    viewModel: viewModel,
                                    onEdit: {
                                        showEdit = true
                                    }
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                            } else {
                                setupView
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .move(edge: .trailing).combined(with: .opacity)
                                    ))
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: isShowingSummary)
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
                .transition(.opacity)
            }
        }
        .onAppear {
            viewModel.load()
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.onboardingCompleted)
    }

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !viewModel.authorized || !viewModel.notificationAuthorized {
                    permissionStatusCard
                }
                appSelectionCard
                resetTimeCard
                Button {
                    viewModel.startMonitoring()
                } label: {
                    Label(
                        viewModel.isMonitoring ? "監視中" : "監視を開始",
                        systemImage: viewModel.isMonitoring ? "shield.fill" : "shield"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isMonitoring ? .green : .blue)
                .disabled(viewModel.isMonitoring)

                if viewModel.isMonitoring {
                    Button {
                        viewModel.stopMonitoring()
                    } label: {
                        Label("停止", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                setupErrorAndWarningSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var permissionStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("権限")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack {
                Label(
                    "Screen Time",
                    systemImage: viewModel.authorized ? "checkmark.shield.fill" : "exclamationmark.shield"
                )
                .foregroundStyle(viewModel.authorized ? .green : .orange)
                Spacer()
                Text(viewModel.authorized ? "許可済み" : "未許可")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Label(
                    "通知",
                    systemImage: viewModel.notificationAuthorized ? "bell.fill" : "bell.slash"
                )
                .foregroundStyle(viewModel.notificationAuthorized ? .green : .secondary)
                Spacer()
                Text(viewModel.notificationAuthorized ? "許可済み" : "未設定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var appSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("監視するアプリ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            let tokens = Array(viewModel.selection.applicationTokens)
                .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
            if tokens.isEmpty {
                Label("未選択", systemImage: "apps.iphone")
                    .foregroundStyle(.secondary)
            } else {
                let tokenEntries = tokens.enumerated().map { index, token in
                    (index: index, tokenKey: TokenKey.sortKey(token))
                }
                ForEach(Array(tokenEntries.enumerated()), id: \.offset) { listIndex, entry in
                    if listIndex > 0 {
                        Divider().padding(.leading, 46)
                    }
                    appSetupRow(index: entry.index, tokenKey: entry.tokenKey)
                }
            }
            Button {
                showPicker = true
            } label: {
                Label("アプリを選択", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isMonitoring)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func appSetupRow(index: Int, tokenKey: String) -> some View {
        let isEditing = editingTokenKey == tokenKey
        let currentLimit = viewModel.limitMinutes(for: tokenKey)
        let currentContinuousAlertLimit = viewModel.continuousAlertLimitMinutes(for: tokenKey)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(appColor(forIndex: index))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    )
                Text("アプリ \(index + 1)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if !viewModel.isMonitoring {
                    Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !viewModel.isMonitoring else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if editingTokenKey == tokenKey {
                        editingTokenKey = nil
                    } else {
                        editingTokenKey = tokenKey
                        draftLimitMinutes = currentLimit
                        draftContinuousAlertMinutes = currentContinuousAlertLimit
                    }
                }
            }
            if isEditing && !viewModel.isMonitoring {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("日次上限")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach([15, 30, 60], id: \.self) { value in
                            Button {
                                draftLimitMinutes = value
                                viewModel.updateAppLimit(tokenKey: tokenKey, value: value)
                            } label: {
                                Text("\(value)分")
                                    .frame(minWidth: 44, minHeight: 32)
                            }
                            .buttonStyle(.plain)
                            .background(
                                draftLimitMinutes == value
                                    ? appColor(forIndex: index).opacity(0.2)
                                    : Color(.systemFill)
                            )
                            .foregroundStyle(
                                draftLimitMinutes == value ? appColor(forIndex: index) : .primary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        draftLimitMinutes == value
                                            ? appColor(forIndex: index)
                                            : Color(.systemFill),
                                        lineWidth: 1
                                    )
                            )
                        }
                        Picker("上限", selection: $draftLimitMinutes) {
                            ForEach(1...300, id: \.self) { minutes in
                                Text("\(minutes)分").tag(minutes)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack(spacing: 8) {
                        Text("連続通知")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("連続通知", selection: $draftContinuousAlertMinutes) {
                            ForEach([0, 5, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                                if minutes == 0 {
                                    Text("OFF").tag(minutes)
                                } else {
                                    Text("\(minutes)分").tag(minutes)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .onChange(of: draftLimitMinutes) { newValue in
                    guard editingTokenKey == tokenKey else { return }
                    viewModel.updateAppLimit(tokenKey: tokenKey, value: newValue)
                }
                .onChange(of: draftContinuousAlertMinutes) { newValue in
                    guard editingTokenKey == tokenKey else { return }
                    viewModel.updateContinuousAlertLimit(tokenKey: tokenKey, value: newValue)
                }
            } else if !isEditing {
                HStack(spacing: 16) {
                    Label("\(currentLimit)分", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(
                        viewModel.continuousAlertDisplayText(for: tokenKey),
                        systemImage: "bell"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var resetTimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("リセット時刻")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise.circle")
                    .foregroundStyle(.blue)
                Picker("時", selection: Binding(
                    get: { viewModel.resetHour },
                    set: { viewModel.updateResetTime(hour: $0, minute: viewModel.resetMinute) }
                )) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60, height: 100)
                .clipped()
                Text(":")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                Picker("分", selection: Binding(
                    get: { viewModel.resetMinute },
                    set: { viewModel.updateResetTime(hour: viewModel.resetHour, minute: $0) }
                )) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60, height: 100)
                .clipped()
                Spacer()
                Text("次回 \(viewModel.nextResetDisplayText())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(viewModel.isMonitoring)
    }

    private var setupErrorAndWarningSection: some View {
        VStack(spacing: 8) {
            if let message = viewModel.activeErrorMessage() {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        Color.red.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            if !viewModel.notificationAuthorized &&
                viewModel.continuousAlertLimits.values.contains(where: { $0 > 0 }) {
                Label(
                    "連続使用通知を使うには通知の許可が必要です",
                    systemImage: "bell.slash"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    Color.orange.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
        }
    }
}

struct SettingsSummaryView: View {
    @ObservedObject var viewModel: ContentViewModel
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusCard
                if !tokenEntries.isEmpty {
                    appListSection
                }
                resetTimeRow
                if let message = viewModel.activeErrorMessage() {
                    summaryErrorBanner(message: message)
                }
                summaryActionButtons
                #if DEBUG
                debugSection
                #endif
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("監視中", systemImage: "shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Text(viewModel.lastSyncDisplayText())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Divider()
            HStack {
                Text("次回リセット")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text(viewModel.nextResetDisplayText())
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var appListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("監視中のアプリ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(Array(tokenEntries.enumerated()), id: \.offset) { listIndex, entry in
                if listIndex > 0 {
                    Divider().padding(.leading, 46)
                }
                NavigationLink {
                    AppDetailView(
                        title: "アプリ \(entry.index + 1)",
                        tokenKey: entry.tokenKey,
                        appIndex: entry.index,
                        viewModel: viewModel
                    )
                } label: {
                    appRowLabel(entry: entry)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func appRowLabel(entry: (index: Int, tokenKey: String)) -> some View {
        let isBlocked = viewModel.isBlocked(tokenKey: entry.tokenKey)
        let remaining = viewModel.remainingMinutes(for: entry.tokenKey)
        let limit = viewModel.limitMinutes(for: entry.tokenKey)
        let used = limit - remaining
        let progress = limit > 0 ? Double(max(used, 0)) / Double(limit) : 1.0
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(appColor(forIndex: entry.index))
                    .frame(width: 32, height: 32)
                if isBlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(entry.index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("アプリ \(entry.index + 1)")
                        .font(.subheadline.weight(.medium))
                    if isBlocked {
                        Text("制限中")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemFill))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isBlocked ? Color.red : appColor(forIndex: entry.index))
                            .frame(width: geo.size.width * min(progress, 1.0), height: 4)
                    }
                }
                .frame(height: 4)
                Text("\(limit)分制限")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var resetTimeRow: some View {
        HStack {
            Label("リセット時刻", systemImage: "arrow.clockwise.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%02d:%02d", viewModel.resetHour, viewModel.resetMinute))
                .font(.subheadline.monospacedDigit())
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func summaryErrorBanner(message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var summaryActionButtons: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.stopMonitoring()
            } label: {
                Label("監視を停止", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!viewModel.isMonitoring)

            if !viewModel.isMonitoring {
                Button {
                    onEdit()
                } label: {
                    Label("設定を編集", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEBUG")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Button("使用時間を即リセット") { viewModel.debugResetUsage() }
            Button("即ブロック/解除トグル") { viewModel.debugToggleBlock() }
            Button(
                viewModel.debugForceSyncFailure
                    ? "同期失敗シミュレーション: ON"
                    : "同期失敗シミュレーション: OFF"
            ) { viewModel.debugToggleSyncFailure() }
            Button("デバッグログをクリア") { viewModel.clearDebugLogs() }
            Button("オンボーディングをリセット") { viewModel.resetOnboarding() }
            Divider()
            Text("DEBUGログ")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            let logs = Array(viewModel.debugLogs.suffix(30))
            if logs.isEmpty {
                Text("ログなし")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            } else {
                ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                    Text(log)
                        .font(.caption2)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    #endif

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
    let appIndex: Int
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                remainingGauge
                metricsGrid
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var remainingGauge: some View {
        let remaining = viewModel.remainingMinutes(for: tokenKey)
        let limit = viewModel.limitMinutes(for: tokenKey)
        let progress = limit > 0 ? Double(remaining) / Double(limit) : 0.0
        let gaugeColor: Color = progress > 0.5 ? .green : progress > 0.2 ? .orange : .red
        let isBlocked = viewModel.isBlocked(tokenKey: tokenKey)
        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 14)
                    .frame(width: 160, height: 160)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        gaugeColor,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: progress)
                VStack(spacing: 4) {
                    Text(formatRemaining(remaining))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(gaugeColor)
                    Text("残り")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if isBlocked {
                Label("制限中", systemImage: "lock.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.12), in: Capsule())
            }
        }
        .padding(.top, 8)
    }

    private var metricsGrid: some View {
        let remaining = viewModel.remainingMinutes(for: tokenKey)
        let limit = viewModel.limitMinutes(for: tokenKey)
        let used = max(limit - remaining, 0)
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 14
        ) {
            metricCard(label: "日次上限", value: "\(limit)分", icon: "clock", color: .blue)
            metricCard(label: "使用済み", value: "\(used)分", icon: "chart.bar.fill", color: .indigo)
            metricCard(
                label: "連続通知",
                value: viewModel.continuousAlertDisplayText(for: tokenKey),
                icon: "bell",
                color: .orange
            )
            metricCard(
                label: "現在の連続",
                value: "\(viewModel.continuousUsageStreakMinutes(for: tokenKey))分",
                icon: "timer",
                color: .purple
            )
        }
    }

    private func metricCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Spacer()
            }
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func formatRemaining(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)時間\(mins)分"
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var step: Int = 0
    @State private var slideDirection: Int = 1

    private struct Page {
        let icon: String
        let iconColor: Color
        let title: String
        let description: String
    }

    private let pages: [Page] = [
        Page(
            icon: "timer",
            iconColor: .blue,
            title: "SNSアラートへようこそ",
            description: "SNSアプリの使用時間を記録し、設定した上限に達すると自動でブロックします。\nスマートフォンとの時間を見直しましょう。"
        ),
        Page(
            icon: "checkmark.shield",
            iconColor: .green,
            title: "Screen Time の許可",
            description: "アプリの使用時間を計測・制限するために Screen Time へのアクセスが必要です。\n次の画面で「続ける」を選択してください。"
        ),
        Page(
            icon: "bell",
            iconColor: .orange,
            title: "通知の許可",
            description: "連続使用アラートを受け取るために通知を許可します。\n使わない場合はスキップできます。"
        ),
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                stepDots
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                // ページコンテンツ
                ZStack {
                    ForEach(0..<pages.count, id: \.self) { index in
                        if index == step {
                            pageContent(for: index)
                                .transition(.asymmetric(
                                    insertion: .move(edge: slideDirection > 0 ? .trailing : .leading)
                                        .combined(with: .opacity),
                                    removal: .move(edge: slideDirection > 0 ? .leading : .trailing)
                                        .combined(with: .opacity)
                                ))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                actionArea
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
        }
    }

    // MARK: ステップドット

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Color.blue : Color(.systemFill))
                    .frame(width: index == step ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    // MARK: ページコンテンツ

    private func pageContent(for index: Int) -> some View {
        let page = pages[index]
        return VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(page.iconColor.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: page.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(page.iconColor)
            }
            VStack(spacing: 14) {
                Text(page.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: アクションエリア

    @ViewBuilder
    private var actionArea: some View {
        VStack(spacing: 12) {
            switch step {
            case 0:
                primaryButton("はじめる") { advance() }

            case 1:
                if viewModel.authorized {
                    primaryButton("次へ") { advance() }
                } else {
                    primaryButton("Screen Time を許可する") {
                        Task {
                            try? await AuthorizationCenter.shared
                                .requestAuthorization(for: .individual)
                            await viewModel.refreshPermissions()
                            advance()
                        }
                    }
                    skipButton("スキップ") { advance() }
                }

            case 2:
                if viewModel.notificationAuthorized {
                    primaryButton("完了") { viewModel.completeOnboarding() }
                } else {
                    primaryButton("通知を許可する") {
                        Task {
                            _ = try? await UNUserNotificationCenter.current()
                                .requestAuthorization(options: [.alert, .sound])
                            await viewModel.refreshPermissions()
                            viewModel.completeOnboarding()
                        }
                    }
                    skipButton("スキップ") { viewModel.completeOnboarding() }
                }

            default:
                EmptyView()
            }

            // 戻るボタン（Step 1 以降に表示）
            if step > 0 {
                Button {
                    slideDirection = -1
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = max(step - 1, 0)
                    }
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    private func skipButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func advance() {
        slideDirection = 1
        withAnimation(.easeInOut(duration: 0.3)) {
            step = min(step + 1, pages.count - 1)
        }
    }
}
