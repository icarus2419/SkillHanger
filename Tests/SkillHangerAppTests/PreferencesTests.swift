import Foundation
import Testing
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct UnifiedPreferencesTests {
    @Test func migrationPreservesDestinationAndImportsOnlyKnownSettings() {
        let name = "SkillHanger.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "showClaude")
        PreferencesMigration.importUsageBar(from: ["showClaude": true, "showOpenAI": false,
                                                  "opacity": 0.8, "accessToken": "never-import"], into: defaults)
        #expect(defaults.bool(forKey: "showClaude") == false)
        #expect(defaults.bool(forKey: "showOpenAI") == false)
        #expect(defaults.double(forKey: "opacity") == 0.8)
        #expect(defaults.object(forKey: "accessToken") == nil)
        PreferencesMigration.importUsageBar(from: ["showOpenAI": true], into: defaults)
        #expect(defaults.bool(forKey: "showOpenAI") == false)
    }

    @Test func usageSettingsPersistAcrossAppModels() {
        let name = "SkillHanger.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Prefs(defaults: defaults)
        prefs.showClaude = false
        prefs.widgetVisible = false
        prefs.metric = .weekly
        prefs.refreshMinutes = 5
        let restored = Prefs(defaults: defaults)
        #expect(!restored.showClaude)
        #expect(!restored.widgetVisible)
        #expect(restored.metric == .weekly)
        #expect(restored.refreshMinutes == 5)
    }
}
