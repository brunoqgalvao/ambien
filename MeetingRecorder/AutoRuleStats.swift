//
//  AutoRuleStats.swift
//  MeetingRecorder
//
//  Tracks auto-record rule statistics including discard counts.
//  Auto-disables rules that are frequently discarded by the user.
//

import Foundation

/// Statistics for a single auto-record rule
struct AutoRuleStat: Codable, Equatable {
    let ruleId: String  // e.g., "zoom", "googleMeet", "teams"
    var totalTriggers: Int = 0
    var consecutiveDiscards: Int = 0
    var totalDiscards: Int = 0
    var autoDisabledAt: Date? = nil
    var lastTriggeredAt: Date? = nil

    /// Whether this rule was auto-disabled due to repeated discards
    var isAutoDisabled: Bool {
        autoDisabledAt != nil
    }
}

/// Manages auto-rule statistics with persistence
@MainActor
class AutoRuleStatsManager: ObservableObject {
    static let shared = AutoRuleStatsManager()

    /// Threshold for consecutive discards before auto-disabling
    private let discardThreshold = 5

    /// Published stats for UI binding
    @Published private(set) var stats: [String: AutoRuleStat] = [:]

    /// UserDefaults key for persistence
    private let storageKey = "autoRuleStats"

    private init() {
        loadStats()
    }

    // MARK: - Public Methods

    /// Record that a rule triggered and started a recording
    func recordTrigger(for app: MeetingApp) {
        let ruleId = ruleId(for: app)
        var stat = stats[ruleId] ?? AutoRuleStat(ruleId: ruleId)
        stat.totalTriggers += 1
        stat.lastTriggeredAt = Date()
        stats[ruleId] = stat
        saveStats()
    }

    /// Record that the user kept a recording (resets consecutive discard count)
    func recordKept(for app: MeetingApp) {
        let ruleId = ruleId(for: app)
        guard var stat = stats[ruleId] else { return }
        stat.consecutiveDiscards = 0
        stats[ruleId] = stat
        saveStats()
    }

    /// Record that the user discarded a recording
    /// Returns true if the rule should be auto-disabled
    func recordDiscard(for app: MeetingApp) -> Bool {
        let ruleId = ruleId(for: app)
        var stat = stats[ruleId] ?? AutoRuleStat(ruleId: ruleId)
        stat.consecutiveDiscards += 1
        stat.totalDiscards += 1
        stats[ruleId] = stat
        saveStats()

        // Check if we should auto-disable
        if stat.consecutiveDiscards >= discardThreshold && !stat.isAutoDisabled {
            return true
        }
        return false
    }

    /// Mark a rule as auto-disabled
    func markAutoDisabled(for app: MeetingApp) {
        let ruleId = ruleId(for: app)
        guard var stat = stats[ruleId] else { return }
        stat.autoDisabledAt = Date()
        stats[ruleId] = stat
        saveStats()

        // Actually disable the rule in UserDefaults
        disableAutoRecord(for: app)
    }

    /// Re-enable a rule that was auto-disabled
    func reEnableRule(for app: MeetingApp) {
        let ruleId = ruleId(for: app)
        guard var stat = stats[ruleId] else { return }
        stat.autoDisabledAt = nil
        stat.consecutiveDiscards = 0
        stats[ruleId] = stat
        saveStats()

        // Re-enable the rule in UserDefaults
        enableAutoRecord(for: app)
    }

    /// Get stats for a specific app
    func getStat(for app: MeetingApp) -> AutoRuleStat? {
        return stats[ruleId(for: app)]
    }

    /// Get all auto-disabled rules
    func getAutoDisabledRules() -> [MeetingApp] {
        return MeetingApp.allCases.filter { app in
            stats[ruleId(for: app)]?.isAutoDisabled == true
        }
    }

    /// Clear all stats (for testing)
    func clearStats() {
        stats = [:]
        saveStats()
    }

    // MARK: - Private Methods

    private func ruleId(for app: MeetingApp) -> String {
        switch app {
        case .zoom: return "zoom"
        case .googleMeet: return "googleMeet"
        case .teams: return "teams"
        case .slack: return "slack"
        case .faceTime: return "faceTime"
        case .whatsApp: return "whatsApp"
        }
    }

    private func app(for ruleId: String) -> MeetingApp? {
        switch ruleId {
        case "zoom": return .zoom
        case "googleMeet": return .googleMeet
        case "teams": return .teams
        case "slack": return .slack
        case "faceTime": return .faceTime
        case "whatsApp": return .whatsApp
        default: return nil
        }
    }

    private func disableAutoRecord(for app: MeetingApp) {
        switch app {
        case .zoom:
            UserDefaults.standard.set(false, forKey: "autoRecordZoom")
        case .googleMeet:
            UserDefaults.standard.set(false, forKey: "autoRecordMeet")
        case .teams:
            UserDefaults.standard.set(false, forKey: "autoRecordTeams")
        case .slack:
            UserDefaults.standard.set(false, forKey: "autoRecordSlack")
        case .faceTime:
            UserDefaults.standard.set(false, forKey: "autoRecordFaceTime")
        case .whatsApp:
            UserDefaults.standard.set(false, forKey: "autoRecordWhatsApp")
        }
    }

    private func enableAutoRecord(for app: MeetingApp) {
        switch app {
        case .zoom:
            UserDefaults.standard.set(true, forKey: "autoRecordZoom")
        case .googleMeet:
            UserDefaults.standard.set(true, forKey: "autoRecordMeet")
        case .teams:
            UserDefaults.standard.set(true, forKey: "autoRecordTeams")
        case .slack:
            UserDefaults.standard.set(true, forKey: "autoRecordSlack")
        case .faceTime:
            UserDefaults.standard.set(true, forKey: "autoRecordFaceTime")
        case .whatsApp:
            UserDefaults.standard.set(true, forKey: "autoRecordWhatsApp")
        }
    }

    private func loadStats() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: AutoRuleStat].self, from: data) else {
            return
        }
        stats = decoded
    }

    private func saveStats() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
