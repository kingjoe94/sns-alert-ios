import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI
import ExtensionKit

private let appGroupID = "group.com.xa504.snsalert"
private let usageKey = "usageMinutes"
private let usageUpdatedAtKey = "usageUpdatedAt"
private let resetHourKey = "resetHour"
private let resetMinuteKey = "resetMinute"
private let debugLogsKey = "debugLogs"

extension DeviceActivityReport.Context {
    static let daily = Self("daily")
}

@MainActor
@main
struct UsageReportExtension: DeviceActivityReportExtension {
    typealias Configuration = ExtensionKit.AppExtensionSceneConfiguration

    @MainActor init() {}

    @MainActor var configuration: Configuration {
        Configuration(UsageReportConfiguration())
    }

    var body: some DeviceActivityReportScene {
        UsageReportConfiguration()
    }
}

struct UsageReportConfiguration: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .daily
    typealias Configuration = String
    typealias Content = UsageReportView

    var body: some ExtensionKit.AppExtensionScene {
        self
    }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        var usageSeconds: [String: TimeInterval] = [:]
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
                        let key = tokenKeyForApplication(app.application)
                        usageSeconds[key, default: 0] += app.totalActivityDuration * ratio
                    }
                }
            }
        }
        var usageMinutes: [String: Int] = [:]
        usageMinutes.reserveCapacity(usageSeconds.count)
        for (key, seconds) in usageSeconds {
            usageMinutes[key] = Int(seconds / 60)
        }
        let defaults = UserDefaults(suiteName: appGroupID)
        if let encoded = try? JSONEncoder().encode(usageMinutes) {
            defaults?.set(encoded, forKey: usageKey)
        }
        defaults?.set(Date(), forKey: usageUpdatedAtKey)
        appendDebugLog("使用時間を同期: \(usageMinutes.count) apps")
        return ""
    }

    let content: (String) -> UsageReportView = { (_: String) in UsageReportView() }

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

    private func overlapDuration(lhs: DateInterval, rhs: DateInterval) -> TimeInterval? {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        guard end > start else { return nil }
        return end.timeIntervalSince(start)
    }

    private func appendDebugLog(_ message: String, now: Date = Date()) {
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
}

struct UsageReportView: View {
    var body: some View {
        EmptyView()
    }
}
