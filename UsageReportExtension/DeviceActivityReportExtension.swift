import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
@preconcurrency import SwiftUI
import ExtensionKit

private let appGroupID = "group.com.xa504.snsalert"
private let usageKey = "usageMinutes"
private let usageUpdatedAtKey = "usageUpdatedAt"
private let reportLastRunAtKey = "reportLastRunAt"
private let orderedTokensKey = "orderedTokens"
private let resetHourKey = "resetHour"
private let resetMinuteKey = "resetMinute"
private let debugLogsKey = "debugLogs"
private let debugForceSyncFailureKey = "debugForceSyncFailure"

extension DeviceActivityReport.Context {
    static let daily = Self("daily")
}

private func appendReportDebugLog(_ message: String, now: Date = Date()) {
    guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
    var logs = defaults.stringArray(forKey: debugLogsKey) ?? []
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "HH:mm:ss"
    logs.append("[\(formatter.string(from: now))] [ReportExt] \(message)")
    if logs.count > 200 {
        logs.removeFirst(logs.count - 200)
    }
    defaults.set(logs, forKey: debugLogsKey)
}

@main
struct UsageReportExtension: DeviceActivityReportExtension {
    init() {
        appendReportDebugLog("extension初期化")
    }

    @MainActor
    var body: some DeviceActivityReportScene {
        UsageReportConfiguration { marker in
            UsageReportView(marker: marker)
        }
    }
}

struct UsageReportConfiguration: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .daily
    let content: @Sendable (String) -> UsageReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        appendReportDebugLog("makeConfiguration開始")
        var usageSeconds: [String: TimeInterval] = [:]
        let defaults = UserDefaults(suiteName: appGroupID)
        if defaults == nil {
            NSLog("[ReportExt] UserDefaults suite unavailable: %@", appGroupID)
        }
        defaults?.set(Date(), forKey: reportLastRunAtKey)
        let tokenIndexMaps = loadTokenIndexMaps(defaults: defaults)
        var indexedMatches = 0
        let resetInterval = currentResetInterval()
        for await day in data {
            for await segment in day.activitySegments {
                guard let overlapDuration = overlapDuration(
                    lhs: resetInterval,
                    rhs: segment.dateInterval
                ),
                segment.dateInterval.duration > 0 else {
                    continue
                }
                let ratio = overlapDuration / segment.dateInterval.duration
                for await category in segment.categories {
                    for await app in category.applications {
                        guard let appToken = app.application.token else {
                            continue
                        }
                        let key = tokenKeyForApplication(app.application)
                        let seconds = app.totalActivityDuration * ratio
                        usageSeconds[key, default: 0] += seconds
                        if let index = tokenIndexMaps.byToken[appToken] ?? tokenIndexMaps.bySortKey[key] {
                            usageSeconds["idx_\(index)", default: 0] += seconds
                            indexedMatches += 1
                        }
                    }
                }
            }
        }
        var usageMinutes: [String: Int] = [:]
        usageMinutes.reserveCapacity(usageSeconds.count)
        for (key, seconds) in usageSeconds {
            usageMinutes[key] = Int(seconds / 60)
        }
#if DEBUG
        if defaults?.bool(forKey: debugForceSyncFailureKey) == true {
            defaults?.removeObject(forKey: usageUpdatedAtKey)
            appendReportDebugLog("DEBUG: 使用時間同期を失敗シミュレーション")
            return ""
        }
#endif
        if let encoded = try? JSONEncoder().encode(usageMinutes) {
            defaults?.set(encoded, forKey: usageKey)
        }
        defaults?.set(Date(), forKey: usageUpdatedAtKey)
        appendReportDebugLog(
            "使用時間を同期: keys=\(usageMinutes.count), idxMatch=\(indexedMatches), ordered=\(tokenIndexMaps.orderedCount)"
        )
        return "sync_\(Int(Date().timeIntervalSince1970))"
    }

    private func tokenKeyForApplication(_ application: Application) -> String {
        guard let data = try? JSONEncoder().encode(application.token) else {
            return String(describing: application.token)
        }
        return data.base64EncodedString()
    }

    private func currentResetInterval(now: Date = Date()) -> DateInterval {
        let defaults = UserDefaults(suiteName: appGroupID)
        let hour = defaults?.integer(forKey: resetHourKey) ?? 0
        let minute = defaults?.integer(forKey: resetMinuteKey) ?? 0
        let calendar = Calendar.current
        let todayReset = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        let anchor = (now < todayReset) ? (calendar.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset) : todayReset
        let end = calendar.date(byAdding: .day, value: 1, to: anchor) ?? now
        return DateInterval(start: anchor, end: end)
    }

    private struct TokenIndexMaps {
        var byToken: [Token<Application>: Int]
        var bySortKey: [String: Int]
        var orderedCount: Int
    }

    private func loadTokenIndexMaps(defaults: UserDefaults?) -> TokenIndexMaps {
        guard let defaults,
              let items = defaults.array(forKey: orderedTokensKey) as? [Data] else {
            return TokenIndexMaps(byToken: [:], bySortKey: [:], orderedCount: 0)
        }
        let tokens = items.compactMap { try? JSONDecoder().decode(Token<Application>.self, from: $0) }
        var byToken: [Token<Application>: Int] = [:]
        var bySortKey: [String: Int] = [:]
        byToken.reserveCapacity(tokens.count)
        bySortKey.reserveCapacity(tokens.count)
        for (index, token) in tokens.enumerated() {
            byToken[token] = index
            bySortKey[tokenSortKey(token)] = index
        }
        return TokenIndexMaps(byToken: byToken, bySortKey: bySortKey, orderedCount: tokens.count)
    }

    private func tokenSortKey<T: Encodable>(_ token: T) -> String {
        guard let data = try? JSONEncoder().encode(token) else {
            return String(describing: token)
        }
        return data.base64EncodedString()
    }

    private func overlapDuration(lhs: DateInterval, rhs: DateInterval) -> TimeInterval? {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        guard end > start else { return nil }
        return end.timeIntervalSince(start)
    }

}

struct UsageReportView: View {
    let marker: String

    var body: some View {
        Text(marker.isEmpty ? "." : marker)
            .font(.system(size: 1))
            .opacity(0.01)
    }
}
