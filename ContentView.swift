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
    private let lastResetKey = "lastResetAt"
    private let blockedTokensKey = "blockedTokens"
    private let orderedTokensKey = "orderedTokens"
    private let debugLogsKey = "debugLogs"

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

    func loadUsageUpdatedAt() -> Date? {
        return defaults.object(forKey: usageUpdatedAtKey) as? Date
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
}

final class ScreenTimeManager {
    private let center = DeviceActivityCenter()
    private let store = ManagedSettingsStore(named: managedStoreName)
    private let fallbackStore = ManagedSettingsStore()

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
        for (idx, token) in tokens.enumerated() {
            let tokenKey = TokenKey.sortKey(token)
            let perLimit = appLimits[tokenKey] ?? defaultLimit
            let perEventName = DeviceActivityEvent.Name("limit_idx_\(idx)")
            let perEvent: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                perEvent = DeviceActivityEvent(
                    applications: Set([token]),
                    threshold: DateComponents(minute: perLimit),
                    includesPastActivity: false
                )
            } else {
                perEvent = DeviceActivityEvent(
                    applications: Set([token]),
                    threshold: DateComponents(minute: perLimit)
                )
            }
            events[perEventName] = perEvent
        }
        AppStore().saveOrderedTokens(tokens)

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
    @Published var authorized = false
    @Published var selection = FamilyActivitySelection()
    let defaultLimitMinutes = 30
    @Published var appLimits: [String: Int] = [:]
    @Published var resetHour = 0
    @Published var resetMinute = 0
    @Published var isMonitoring = false
    @Published var setupCompleted = false
    @Published var errorMessage: String? = nil
    @Published var syncErrorMessage: String? = nil
    @Published var usageMinutes: [String: Int] = [:]
    @Published var blockedTokenKeys: Set<String> = []
    @Published var reportRefresh = Date()
    @Published var debugLogs: [String] = []

    private let store = AppStore()
    private let screenTimeManager = ScreenTimeManager()
    private let syncManager = UsageSyncManager()
    private let syncStaleThresholdSeconds: TimeInterval = 180
    private var syncWarmupUntil: Date?
    private var wasSyncDelayed = false

    init() {
        syncManager.onTick = { [weak self] in
            self?.syncUsage()
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
        blockedTokenKeys = Set(store.loadBlockedTokens().map { TokenKey.sortKey($0) })
        debugLogs = store.loadDebugLogs()
        if store.loadLastResetAt() == nil {
            store.saveLastResetAt(currentResetAnchor(now: Date()))
        }
        updateAuthorizationStatus()
        if isMonitoring {
            syncWarmupUntil = Date().addingTimeInterval(syncStaleThresholdSeconds)
            syncManager.start()
        }
    }

    func startMonitoring() {
        Task {
            errorMessage = nil
            let ok = await ensureScreenTimeAuthorization()
            if !ok { return }
            if selection.applicationTokens.isEmpty {
                errorMessage = "監視するアプリを選択してください"
                return
            }
            ensureAppLimitsForSelection()
            store.saveSelection(selection)
            store.saveAppLimits(appLimits)
            store.saveResetTime(hour: resetHour, minute: resetMinute)
            store.saveLastResetAt(currentResetAnchor(now: Date()))

            do {
                appendDebugLog("監視開始を要求")
                screenTimeManager.clearBlocks()
                store.clearBlockedTokens()
                store.saveLastResetAt(currentResetAnchor(now: Date()))
                try screenTimeManager.startMonitoring(
                    selection: selection,
                    appLimits: appLimits,
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
                syncManager.start()
            } catch {
                appendDebugLog("監視開始に失敗")
                errorMessage = "監視を開始できませんでした。再度お試しください"
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
        appendDebugLog("監視を停止")
        syncManager.stop()
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
        store.saveAppLimits(appLimits)
    }

    func updateResetTime(hour: Int, minute: Int) {
        guard !isMonitoring else { return }
        resetHour = hour
        resetMinute = minute
        store.saveResetTime(hour: hour, minute: minute)
        resetIfNeeded(now: Date())
    }

    func remainingMinutes(for tokenKey: String) -> Int {
        let used = usageMinutes[tokenKey] ?? 0
        let limit = appLimits[tokenKey] ?? defaultLimitMinutes
        return max(limit - used, 0)
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

    private func syncUsage() {
        resetIfNeeded(now: Date())
        var blockedTokens = store.loadBlockedTokens()
        let latestUsage = store.loadUsageMinutes()
        let usageUpdatedAt = store.loadUsageUpdatedAt()
        let now = Date()
        let isUsageFresh = usageUpdatedAt.map { now.timeIntervalSince($0) <= syncStaleThresholdSeconds } ?? false

        if isUsageFresh {
            usageMinutes = latestUsage
            syncWarmupUntil = nil
            syncErrorMessage = nil
            if wasSyncDelayed {
                appendDebugLog("同期遅延から復帰")
                wasSyncDelayed = false
            }
        } else if let warmupUntil = syncWarmupUntil, now < warmupUntil {
            syncErrorMessage = nil
        } else {
            syncErrorMessage = "使用時間の同期が遅れています"
            if !wasSyncDelayed {
                appendDebugLog("同期遅延を検知")
                wasSyncDelayed = true
            }
        }

        // Rebuild block state from persisted usage so restart/extension timing cannot miss limits.
        let selectedTokens = Array(selection.applicationTokens)
            .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
        var blockedKeys = Set(blockedTokens.map { TokenKey.sortKey($0) })
        for token in selectedTokens {
            let key = TokenKey.sortKey(token)
            let used = usageMinutes[key] ?? 0
            let limit = appLimits[key] ?? defaultLimitMinutes
            if used >= limit && !blockedKeys.contains(key) {
                blockedTokens.append(token)
                blockedKeys.insert(key)
            }
        }

        store.saveBlockedTokens(blockedTokens)
        blockedTokenKeys = blockedKeys
        screenTimeManager.applyBlocks(blockedTokens)
        debugLogs = store.loadDebugLogs()
        reportRefresh = Date()
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
        let startOfDay = Calendar.current.startOfDay(for: anchor)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: startOfDay) ?? now
        return DateInterval(start: startOfDay, end: end)
    }

    private func resetIfNeeded(now: Date) {
        let anchor = currentResetAnchor(now: now)
        if let last = store.loadLastResetAt(), last >= anchor {
            return
        }
        usageMinutes = [:]
        store.saveUsageMinutes([:])
        store.clearBlockedTokens()
        blockedTokenKeys = []
        screenTimeManager.clearBlocks()
        store.saveLastResetAt(anchor)
        appendDebugLog("日次リセットを実行")
    }


    private func ensureAppLimitsForSelection() {
        var updated = appLimits
        let tokens = Array(selection.applicationTokens)
            .sorted(by: { TokenKey.sortKey($0) < TokenKey.sortKey($1) })
        for token in tokens {
            let key = TokenKey.sortKey(token)
            if updated[key] == nil {
                updated[key] = defaultLimitMinutes
            }
        }
        if updated != appLimits {
            appLimits = updated
            store.saveAppLimits(updated)
        }
    }

    private func ensureScreenTimeAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            errorMessage = "Screen Timeの許可に失敗しました"
        }
        updateAuthorizationStatus()
        return authorized
    }

    private func updateAuthorizationStatus() {
        let status = AuthorizationCenter.shared.authorizationStatus
        authorized = (status == .approved)
    }

    private func appendDebugLog(_ message: String) {
        store.appendDebugLog(message)
        debugLogs = store.loadDebugLogs()
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var showPicker = false
    @State private var showEdit = false
    @State private var editingTokenKey: String? = nil
    @State private var draftLimitMinutes: Int = 0

    var body: some View {
        NavigationStack {
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
            .navigationTitle("SNSアラート")
            .background(
                DeviceActivityReport(
                    .daily,
                    filter: DeviceActivityFilter(
                        segment: .daily(during: viewModel.currentReportInterval()),
                        users: .all,
                        devices: .init([.iPhone, .iPad])
                    )
                )
                .id(viewModel.reportRefresh)
                .frame(height: 0)
                .opacity(0.001)
            )
        }
        .onAppear {
            viewModel.load()
        }
        .onChange(of: viewModel.isMonitoring) { isMonitoring in
            if isMonitoring {
                showEdit = false
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
                        let currentLimit = viewModel.appLimits[tokenKey] ?? viewModel.defaultLimitMinutes
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

            if let message = viewModel.errorMessage {
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
            Section("監視中") {
                ForEach(tokenEntries, id: \.tokenKey) { entry in
                    NavigationLink {
                        AppDetailView(
                            title: "アプリ \(entry.index + 1)",
                            limitMinutes: viewModel.appLimits[entry.tokenKey] ?? viewModel.defaultLimitMinutes,
                            remainingMinutes: viewModel.remainingMinutes(for: entry.tokenKey),
                            isBlocked: viewModel.isBlocked(tokenKey: entry.tokenKey)
                        )
                    } label: {
                        HStack {
                            Image(systemName: viewModel.isBlocked(tokenKey: entry.tokenKey) ? "lock.fill" : "checkmark.circle")
                                .foregroundColor(viewModel.isBlocked(tokenKey: entry.tokenKey) ? .red : .green)
                            VStack(alignment: .leading) {
                                Text("アプリ \(entry.index + 1)")
                                Text("上限: \(viewModel.appLimits[entry.tokenKey] ?? viewModel.defaultLimitMinutes)分")
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

            if let message = viewModel.syncErrorMessage {
                Section("同期") {
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
    let limitMinutes: Int
    let remainingMinutes: Int
    let isBlocked: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title2)
            Text("上限: \(limitMinutes)分")
            Text("残り: \(formatRemaining(remainingMinutes))")
                .font(.headline)
            Text(isBlocked ? "制限中" : "使用可能")
                .foregroundColor(isBlocked ? .red : .green)
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
