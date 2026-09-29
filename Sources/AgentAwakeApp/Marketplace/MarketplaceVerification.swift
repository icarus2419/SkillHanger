import Foundation

/// Explicit development smoke check. All installs use a temporary home and are
/// removed before writing evidence; no user agent settings are changed.
enum MarketplaceVerification {
    static func run(output: URL) async {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("skillhanger-verify-\(UUID().uuidString)")
        var report: [String: Any] = ["isolated": true, "startedAt": ISO8601DateFormatter().string(from: Date())]
        do {
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            try fm.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
            try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
            let github = GitHubCatalog()
            var live: [CatalogItem] = []
            for agent in MarketplaceAgent.allCases { live += try await github.plugins(agent: agent) }
            for source in try CatalogLoader.skillSources() {
                live += try await github.skills(source: source)
            }
            report["liveCatalogCount"] = live.count
            report["liveSources"] = Array(Set(live.map(\.repository))).sorted()
            guard let skill = live.first(where: { $0.repository == "anthropics/skills" && $0.name == "pdf" }) else { throw MarketplaceError.invalid("The live PDF skill was not found.") }
            let files = try await github.skillFiles(skill)
            let installer = MarketplaceInstaller(home: home)
            var skillChecks: [[String: Any]] = []
            for agent in MarketplaceAgent.allCases {
                let destination = try await installer.installSkill(skill, for: agent, files: files)
                guard try installer.skillState(skill, for: agent) == .managed else { throw MarketplaceError.invalid("Managed install was not detected.") }
                for file in files {
                    guard try Data(contentsOf: destination.appendingPathComponent(file.path)) == file.data else { throw MarketplaceError.invalid("The installed file differs from GitHub.") }
                }
                try installer.removeSkill(skill, for: agent)
                guard try installer.skillState(skill, for: agent) == .absent else { throw MarketplaceError.invalid("Skill removal was incomplete.") }
                skillChecks.append(["agent": agent.rawValue, "fileCount": files.count, "repository": skill.repository, "revision": skill.revision, "installedAndRemoved": true])
            }
            report["skills"] = skillChecks
            var communityChecks: [[String: Any]] = []
            for (repository, name) in [("JuliusBrussee/caveman", "caveman"), ("DietrichGebert/ponytail", "ponytail"), ("multica-ai/andrej-karpathy-skills", "karpathy-guidelines")] {
                guard let item = live.first(where: { $0.repository == repository && $0.name == name }) else { throw MarketplaceError.invalid("A community skill is missing.") }
                let files = try await github.skillFiles(item)
                for agent in MarketplaceAgent.allCases {
                    let destination = try await installer.installSkill(item, for: agent, files: files)
                    for file in files {
                        guard try Data(contentsOf: destination.appendingPathComponent(file.path)) == file.data else { throw MarketplaceError.invalid("Community skill files differ from GitHub.") }
                    }
                    guard try installer.skillState(item, for: agent) == .managed else { throw MarketplaceError.invalid("Community install was not detected.") }
                    try installer.removeSkill(item, for: agent)
                    guard try installer.skillState(item, for: agent) == .absent else { throw MarketplaceError.invalid("Community removal was incomplete.") }
                    communityChecks.append(["name": name, "repository": repository, "revision": item.revision, "agent": agent.rawValue, "fileCount": files.count, "installedAndRemoved": true])
                }
            }
            report["communitySkills"] = communityChecks
            var pluginChecks: [[String: Any]] = []
            for agent in MarketplaceAgent.allCases {
                let root = home.appendingPathComponent("catalog-\(agent.rawValue)")
                let package = root.appendingPathComponent("plugin")
                let marker = agent == .codex ? ".codex-plugin" : ".claude-plugin"
                try fm.createDirectory(at: package.appendingPathComponent(marker), withIntermediateDirectories: true)
                let manifest: [String: Any] = ["name": "skillhanger-smoke", "version": "1.0.0", "description": "Isolated SkillHanger installer check", "skills": "./skills"]
                try JSONSerialization.data(withJSONObject: manifest).write(to: package.appendingPathComponent(marker + "/plugin.json"))
                try fm.createDirectory(at: package.appendingPathComponent("skills/check"), withIntermediateDirectories: true)
                try Data("---\nname: check\ndescription: An isolated install check\n---\nReturn ready.\n".utf8).write(to: package.appendingPathComponent("skills/check/SKILL.md"))
                let marketplace = "skillhanger-smoke-\(agent.rawValue)"
                let catalog: [String: Any]
                let catalogPath: String
                if agent == .codex {
                    catalogPath = ".agents/plugins"
                    catalog = ["name": marketplace, "plugins": [["name": "skillhanger-smoke", "source": ["source": "local", "path": "./plugin"], "policy": ["installation": "AVAILABLE", "authentication": "ON_INSTALL"]]]]
                } else {
                    catalogPath = ".claude-plugin"
                    catalog = ["name": marketplace, "owner": ["name": "SkillHanger verification"], "plugins": [["name": "skillhanger-smoke", "source": "./plugin", "description": "Isolated check"]]]
                }
                try fm.createDirectory(at: root.appendingPathComponent(catalogPath), withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: catalog).write(to: root.appendingPathComponent(catalogPath + "/marketplace.json"))
                var env = ProcessInfo.processInfo.environment
                env["CODEX_HOME"] = home.appendingPathComponent(".codex").path
                env["CLAUDE_CONFIG_DIR"] = home.appendingPathComponent(".claude").path
                let cli = NativeAgentCLI(home: home, environment: env)
                _ = try await cli.run(agent, arguments: ["plugin", "marketplace", "add", root.path])
                var plugin = skill
                plugin.kind = .plugin; plugin.name = "skillhanger-smoke"; plugin.marketplace = marketplace
                _ = try await cli.run(agent, arguments: PluginCommand.install(plugin, agent: agent))
                let inventory = try await cli.run(agent, arguments: ["plugin", "list", "--json"])
                guard try NativePluginInventory.identifiers(inventory, agent: agent).contains("skillhanger-smoke@" + marketplace) else { throw MarketplaceError.invalid("The native installer did not report the installed plugin.") }
                _ = try await cli.run(agent, arguments: PluginCommand.remove(plugin, agent: agent))
                let removed = try await cli.run(agent, arguments: ["plugin", "list", "--json"])
                guard try !NativePluginInventory.identifiers(removed, agent: agent).contains("skillhanger-smoke@" + marketplace) else { throw MarketplaceError.invalid("The native installer did not remove the plugin.") }
                let publisherRepo = agent == .codex ? "openai/plugins" : "anthropics/claude-plugins-official"
                let packageName = agent == .codex ? "build-macos-apps" : "frontend-design"
                guard let realPlugin = live.first(where: { $0.kind == .plugin && $0.agents == [agent] && $0.name == packageName }) else { throw MarketplaceError.invalid("The real GitHub plugin is missing from the catalog.") }
                var nativePlugin = realPlugin
                if agent == .codex {
                    let (translated, root) = try GitHubPluginMarketplace.prepare(realPlugin, home: home)
                    nativePlugin = translated
                    _ = try await cli.run(agent, arguments: ["plugin", "marketplace", "add", root.path])
                } else { _ = try await cli.run(agent, arguments: ["plugin", "marketplace", "add", publisherRepo]) }
                _ = try await cli.run(agent, arguments: PluginCommand.install(nativePlugin, agent: agent))
                let realInventory = try await cli.run(agent, arguments: ["plugin", "list", "--json"])
                guard try NativePluginInventory.identifiers(realInventory, agent: agent).contains(packageName + "@" + (nativePlugin.marketplace ?? "")) else { throw MarketplaceError.invalid("The real GitHub plugin install was not detected.") }
                _ = try await cli.run(agent, arguments: PluginCommand.remove(nativePlugin, agent: agent))
                pluginChecks.append(["agent": agent.rawValue, "nativeInstallAndRemove": true, "githubPlugin": packageName, "publisherRepository": publisherRepo, "githubInstallAndRemove": true])
            }
            report["plugins"] = pluginChecks
            report["success"] = true
        } catch { report["success"] = false; report["error"] = error.localizedDescription }
        do { try fm.removeItem(at: home); report["temporaryHomeRemoved"] = true }
        catch { report["temporaryHomeRemoved"] = false }
        report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic) }
        catch { fputs("Marketplace verification: \(error.localizedDescription)\n", stderr) }
    }
}
