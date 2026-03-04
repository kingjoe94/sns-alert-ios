//
//  ShieldConfigurationExtension.swift
//  ShieldConfigExtension
//
//  Created by 金城静馬 on 2026/01/30.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

private let appGroupID = "group.com.xa504.snsalert"
private let managedStoreName = ManagedSettingsStore.Name("shared")
private let usageKey = "usageMinutes"
private let blockedTokensKey = "blockedTokens"
private let lastResetKey = "lastResetAt"
private let debugLogsKey = "debugLogs"
private let appNamesKey = "appNames"
private let orderedTokensKey = "orderedTokens"

// Override the functions below to customize the shields used in various situations.
// The system provides a default appearance for any methods that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        performResetIfNeeded()
        cacheAppName(application)
        return ShieldConfiguration(
            title: ShieldConfiguration.Label(text: "制限時間に到達しました", color: .white),
            subtitle: ShieldConfiguration.Label(text: unlockMessage(), color: .white)
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        performResetIfNeeded()
        cacheAppName(application)
        return ShieldConfiguration(
            title: ShieldConfiguration.Label(text: "制限時間に到達しました", color: .white),
            subtitle: ShieldConfiguration.Label(text: unlockMessage(), color: .white)
        )
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        performResetIfNeeded()
        // Customize the shield as needed for web domains.
        return ShieldConfiguration(
            title: ShieldConfiguration.Label(text: "制限時間に到達しました", color: .white),
            subtitle: ShieldConfiguration.Label(text: unlockMessage(), color: .white)
        )
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        performResetIfNeeded()
        // Customize the shield as needed for web domains shielded because of their category.
        return ShieldConfiguration(
            title: ShieldConfiguration.Label(text: "制限時間に到達しました", color: .white),
            subtitle: ShieldConfiguration.Label(text: unlockMessage(), color: .white)
        )
    }

    private func cacheAppName(_ application: Application) {
        guard let name = application.localizedDisplayName, !name.isEmpty,
              let token = application.token,
              let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let tokenKey = tokenSortKey(token)
        var existing: [String: String] = [:]
        if let data = defaults.data(forKey: appNamesKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            existing = decoded
        }
        existing[tokenKey] = name
        // Also store by index if we can resolve it
        if let items = defaults.array(forKey: orderedTokensKey) as? [Data] {
            for (index, itemData) in items.enumerated() {
                if let t = try? JSONDecoder().decode(Token<Application>.self, from: itemData),
                   tokenSortKey(t) == tokenKey {
                    existing["idx_\(index)"] = name
                    break
                }
            }
        }
        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: appNamesKey)
        }
    }

    private func tokenSortKey<T: Encodable>(_ token: T) -> String {
        guard let data = try? JSONEncoder().encode(token) else {
            return String(describing: token)
        }
        return data.base64EncodedString()
    }

    private func performResetIfNeeded(now: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let hour = defaults.integer(forKey: "resetHour")
        let minute = defaults.integer(forKey: "resetMinute")
        let calendar = Calendar.current
        let anchor = currentResetAnchor(
            now: now,
            resetHour: hour,
            resetMinute: minute,
            calendar: calendar
        )
        if let last = defaults.object(forKey: lastResetKey) as? Date, last >= anchor {
            return
        }
        ManagedSettingsStore(named: managedStoreName).shield.applications = nil
        ManagedSettingsStore().shield.applications = nil
        defaults.removeObject(forKey: blockedTokensKey)
        defaults.removeObject(forKey: usageKey)
        defaults.set(anchor, forKey: lastResetKey)
        appendDebugLog("ShieldExtで日次リセットを実行: \(anchor)")
    }

    private func unlockMessage(now: Date = Date()) -> String {
        let defaults = UserDefaults(suiteName: appGroupID)
        let hour = defaults?.integer(forKey: "resetHour") ?? 0
        let minute = defaults?.integer(forKey: "resetMinute") ?? 0

        let calendar = Calendar.current
        let todayReset = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        let isToday = now <= todayReset
        let targetDate = isToday ? todayReset : (calendar.date(byAdding: .day, value: 1, to: todayReset) ?? todayReset)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"

        let label = isToday ? "今日" : "明日"
        return "\(label) \(formatter.string(from: targetDate)) に解除されます"
    }

    private func appendDebugLog(_ message: String, now: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        var logs = defaults.stringArray(forKey: debugLogsKey) ?? []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm:ss"
        logs.append("[\(formatter.string(from: now))] [ShieldExt] \(message)")
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
        defaults.set(logs, forKey: debugLogsKey)
    }

    private func currentResetAnchor(
        now: Date,
        resetHour: Int,
        resetMinute: Int,
        calendar: Calendar
    ) -> Date {
        let todayReset = calendar.date(
            bySettingHour: resetHour,
            minute: resetMinute,
            second: 0,
            of: now
        ) ?? now
        if now < todayReset {
            return calendar.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset
        }
        return todayReset
    }
}
