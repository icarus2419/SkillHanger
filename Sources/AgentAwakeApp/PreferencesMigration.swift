import Foundation

enum PreferencesMigration {
    static let usageKeys = [
        "showClaude", "showOpenAI", "metric", "placement", "size", "layout", "theme",
        "opacity", "colorful", "showNames", "locked", "snapToEdges", "widgetVisible",
        "alerts", "refreshMinutes", "usageCache.v1", "widget.frame"
    ]

    static func importUsageBar(from legacy: [String: Any], into defaults: UserDefaults) {
        guard !defaults.bool(forKey: "skillhanger.usageMigration.v1") else { return }
        for key in usageKeys where defaults.object(forKey: key) == nil {
            if let value = legacy[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "skillhanger.usageMigration.v1")
    }
}
