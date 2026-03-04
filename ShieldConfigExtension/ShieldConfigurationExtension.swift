//
//  ShieldConfigurationExtension.swift
//  ShieldConfigExtension
//
//  Created by 金城静馬 on 2026/01/30.
//

import ManagedSettings
import ManagedSettingsUI
import FamilyControls
import UIKit

private let appGroupID = "group.com.xa504.snsalert"
private let managedStoreName = ManagedSettingsStore.Name("shared")
private let usageKey = "usageMinutes"
private let blockedTokensKey = "blockedTokens"
private let lastResetKey = "lastResetAt"
private let debugLogsKey = "debugLogs"
private let appNamesKey = "appNames"
private let orderedTokensKey = "orderedTokens"
private let continuousBlockAppliedAtKey = "continuousBlockAppliedAt"
private let continuousBlockDurationMinutesKey = "continuousBlockDurationMinutes"
private let continuousBlockDefaultMinutes = 5

// Override the functions below to customize the shields used in various situations.
// The system provides a default appearance for any methods that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let now = Date()
        performResetIfNeeded(now: now)
        cacheAppName(application)
        return shieldConfiguration(for: application, now: now)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        let now = Date()
        performResetIfNeeded(now: now)
        cacheAppName(application)
        return shieldConfiguration(for: application, now: now)
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        let now = Date()
        performResetIfNeeded(now: now)
        return ShieldConfiguration(
            title: ShieldConfiguration.Label(text: "本日の制限時間に到達しました", color: .white),
            subtitle: ShieldConfiguration.Label(text: unlockMessage(now: now), color: .white)
        )
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        let now = Date()
        performResetIfNeeded(now: now)
        return ShieldConfiguration(
            title: ShieldConfiguration.Label(text: "本日の制限時間に到達しました", color: .white),
            subtitle: ShieldConfiguration.Label(text: unlockMessage(now: now), color: .white)
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

    private func continuousBlockDuration(defaults: UserDefaults) -> TimeInterval {
        let saved = defaults.integer(forKey: continuousBlockDurationMinutesKey)
        let minutes = saved > 0 ? saved : continuousBlockDefaultMinutes
        return TimeInterval(minutes * 60)
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
            // Daily reset already done; check for expired continuous blocks
            checkExpiredContinuousBlocks(defaults: defaults, now: now)
            return
        }
        ManagedSettingsStore(named: managedStoreName).shield.applications = nil
        ManagedSettingsStore().shield.applications = nil
        defaults.removeObject(forKey: blockedTokensKey)
        defaults.removeObject(forKey: usageKey)
        defaults.removeObject(forKey: continuousBlockAppliedAtKey)
        defaults.set(anchor, forKey: lastResetKey)
        appendDebugLog("ShieldExtで日次リセットを実行: \(anchor)")
    }

    private func checkExpiredContinuousBlocks(defaults: UserDefaults, now: Date) {
        guard let data = defaults.data(forKey: continuousBlockAppliedAtKey),
              let appliedAt = try? JSONDecoder().decode([String: Double].self, from: data),
              !appliedAt.isEmpty else { return }

        var expiredKeys = Set<String>()
        var updatedAppliedAt = appliedAt
        let blockDuration = continuousBlockDuration(defaults: defaults)
        for (key, timestamp) in appliedAt {
            if now.timeIntervalSince1970 - timestamp >= blockDuration {
                expiredKeys.insert(key)
                updatedAppliedAt.removeValue(forKey: key)
            }
        }
        guard !expiredKeys.isEmpty else { return }

        // Update the applied-at record
        if updatedAppliedAt.isEmpty {
            defaults.removeObject(forKey: continuousBlockAppliedAtKey)
        } else if let encoded = try? JSONEncoder().encode(updatedAppliedAt) {
            defaults.set(encoded, forKey: continuousBlockAppliedAtKey)
        }

        // Remove expired tokens from blockedTokens and rebuild shield
        guard let blockedData = defaults.array(forKey: blockedTokensKey) as? [Data] else { return }
        var remainingData: [Data] = []
        var remainingTokens: [Token<Application>] = []
        for itemData in blockedData {
            guard let token = try? JSONDecoder().decode(Token<Application>.self, from: itemData) else {
                remainingData.append(itemData)
                continue
            }
            if expiredKeys.contains(tokenSortKey(token)) {
                // Expired continuous block — remove from list
            } else {
                remainingData.append(itemData)
                remainingTokens.append(token)
            }
        }
        defaults.set(remainingData, forKey: blockedTokensKey)
        let remainingSet: Set<Token<Application>>? = remainingTokens.isEmpty ? nil : Set(remainingTokens)
        ManagedSettingsStore(named: managedStoreName).shield.applications = remainingSet
        ManagedSettingsStore().shield.applications = remainingSet
        appendDebugLog("連続ブロック期限切れ: \(expiredKeys.count)件を解除")
    }

    private func shieldConfiguration(for application: Application, now: Date) -> ShieldConfiguration {
        // Check if this is a temporary continuous block still within expiry window
        if let token = application.token,
           let defaults = UserDefaults(suiteName: appGroupID),
           let data = defaults.data(forKey: continuousBlockAppliedAtKey),
           let appliedAt = try? JSONDecoder().decode([String: Double].self, from: data) {
            let key = tokenSortKey(token)
            if let timestamp = appliedAt[key] {
                let elapsed = now.timeIntervalSince1970 - timestamp
                let remaining = max(continuousBlockDuration(defaults: defaults) - elapsed, 0)
                let subtitle: String
                if remaining >= 60 {
                    subtitle = "あと\(Int(remaining / 60))分で解除されます"
                } else if remaining > 0 {
                    subtitle = "まもなく解除されます"
                } else {
                    subtitle = "画面を閉じて再度お試しください"
                }
                return ShieldConfiguration(
                    title: ShieldConfiguration.Label(text: "連続使用上限に達しました", color: .white),
                    subtitle: ShieldConfiguration.Label(text: subtitle, color: .white)
                )
            }
        }
        // Daily (permanent) block
        return ShieldConfiguration(
            title: ShieldConfiguration.Label(text: "本日の制限時間に到達しました", color: .white),
            subtitle: ShieldConfiguration.Label(text: unlockMessage(now: now), color: .white)
        )
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
