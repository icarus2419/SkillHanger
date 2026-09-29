import Foundation
import Testing
@testable import AgentAwakeApp

struct PackageCustomizationTests {
    private func item(_ name: String) throws -> CatalogItem {
        try #require(CatalogLoader.bundled().first { $0.name == name && $0.kind == .skill })
    }

    @Test func uiDesignDefaultsDetectTheStackAndExplicitControlsUseSupportedFlags() throws {
        let ui = try item("ui-ux-pro-max")
        let automatic = PackageCustomization.invocation(ui, agent: .codex, mode: "full")
        #expect(automatic.contains("Detect the implementation stack"))
        #expect(!automatic.contains("--stack swiftui"))
        let options = ["stack": "nextjs", "intent": "design-system", "variance": "8", "motion": "2", "density": "9"]
        let explicit = PackageCustomization.invocation(ui, agent: .claude, mode: "full", options: options)
        #expect(explicit.hasPrefix("/ui-ux-pro-max"))
        for flag in ["--stack nextjs", "--design-system", "--variance 8", "--motion 2", "--density 9"] { #expect(explicit.contains(flag)) }
        #expect(!explicit.contains("--force"))
        let invalid = PackageCustomization.invocation(ui, agent: .codex, mode: "full", options: ["stack": "imaginary", "intent": "focused", "domain": "ux", "density": "11"])
        #expect(invalid.contains("--domain ux"))
        #expect(!invalid.contains("imaginary"))
        #expect(!invalid.contains("--density"))
        let fields = PackageCustomization.fields(ui, options: ["intent": "focused"])
        #expect(fields.contains { $0.id == "domain" })
        #expect(!fields.contains { $0.id == "density" })
        #expect(PackageCustomization.fields(ui, options: options).contains { $0.id == "density" })
    }

    @Test func browserWorkflowAndSessionPreferencesLoadVersionMatchedInstructions() throws {
        let browser = try item("agent-browser")
        let command = PackageCustomization.invocation(browser, agent: .codex, mode: "full", options: ["workflow": "dogfood", "visibility": "headed", "session": "qa-local"])
        #expect(command.contains("agent-browser skills get dogfood"))
        #expect(command.contains("--headed true"))
        #expect(command.contains("--session qa-local"))
        #expect(!command.contains("--restore"))
        #expect(!command.contains("--profile"))
        let invalid = PackageCustomization.invocation(browser, agent: .codex, mode: "full", options: ["workflow": "$(bad)", "visibility": "wrong", "session": "qa; touch /tmp/unsafe"])
        #expect(invalid.contains("agent-browser skills get core"))
        #expect(!invalid.contains("$(bad)"))
        #expect(!invalid.contains("--session"))
        var unrelated = browser; unrelated.repository = "someone/agent-browser"
        #expect(PackageCustomization.fields(unrelated).isEmpty)
    }

    @Test @MainActor func savedOptionsSurviveRestartStayAgentScopedAndResetOnlyOnePackage() throws {
        let suite = "SkillHanger.OptionsTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ui = try item("ui-ux-pro-max")
        let codex = PackageSelection(itemID: ui.id, agent: .codex)
        let claude = PackageSelection(itemID: ui.id, agent: .claude)
        let other = PackageSelection(itemID: "other", agent: .codex)
        let preferences = PackagePreferences(defaults: defaults)
        preferences.setOption("swiftui", key: "stack", for: codex)
        preferences.setOption("react", key: "stack", for: claude)
        preferences.setOption("kept", key: "value", for: other)
        preferences.setTask("Example task", for: codex)
        preferences.setMode("ultra", for: codex)
        let restarted = PackagePreferences(defaults: defaults)
        #expect(restarted.options(for: codex)["stack"] == "swiftui")
        #expect(restarted.options(for: claude)["stack"] == "react")
        restarted.reset(for: codex)
        #expect(restarted.options(for: codex).isEmpty)
        #expect(restarted.task(for: codex).isEmpty)
        #expect(restarted.mode(for: codex) == "full")
        #expect(restarted.options(for: claude)["stack"] == "react")
        #expect(restarted.options(for: other)["value"] == "kept")
    }

    @Test func obsidianVaultIsLiteralDataAndEmptyUsesTheFocusedVault() throws {
        let obsidian = try item("obsidian-cli")
        let vaultField = try #require(PackageCustomization.fields(obsidian).first)
        #expect(vaultField.value(in: ["vault": "Research "]) == "Research ")
        let automatic = PackageCustomization.invocation(obsidian, agent: .codex, mode: "full")
        #expect(automatic.contains("most recently focused vault"))
        let named = PackageCustomization.invocation(obsidian, agent: .claude, mode: "full", options: ["vault": "Research \"Notes\"\nteam"])
        #expect(named.contains("literal vault name"))
        #expect(named.contains("Research \\\"Notes\\\" team"))
        #expect(named.contains("first parameter"))
        #expect(named.contains("Obsidian to be open"))
    }
}
