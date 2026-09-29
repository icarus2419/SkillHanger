import Foundation

enum PackageWorkspaceVerification {
    @MainActor static func run(output: URL) async {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("skillhanger-workspaces-\(UUID().uuidString)")
        let suite = "SkillHanger.WorkspaceVerification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        var report: [String: Any] = ["isolated": true, "startedAt": ISO8601DateFormatter().string(from: Date())]
        var checks: [[String: Any]] = []
        do {
            let store = MarketplaceStore(home: home, defaults: defaults)
            let names = ["caveman", "humanizer", "ui-ux-pro-max", "agent-browser", "obsidian-markdown", "context-compression"]
            for name in names {
                guard let item = store.items.first(where: { $0.kind == .skill && $0.name == name }) else { throw MarketplaceError.invalid("Missing \(name) from the catalog.") }
                fputs("Checking \(name)\n", stderr)
                let files = try await store.github.skillFiles(item)
                for agent in MarketplaceAgent.allCases {
                    try await store.installSkill(item, for: agent, files: files)
                    let selection = PackageSelection(itemID: item.id, agent: agent)
                    guard store.workspaceSelection == selection, store.selectedWorkspace?.item.id == item.id else { throw MarketplaceError.invalid("Installation did not select its workspace.") }
                    let destination = try store.installer.existingSkillURL(item, for: agent)
                    for file in files {
                        guard try Data(contentsOf: destination.appendingPathComponent(file.path)) == file.data else { throw MarketplaceError.invalid("The installed \(name) file differs from GitHub.") }
                    }
                    store.packagePreferences.setMode("ultra", for: selection)
                    store.setSkillEnabled(item, agent: agent, enabled: false)
                    let restarted = MarketplaceStore(home: home, defaults: defaults)
                    guard restarted.workspaces.contains(where: { $0.selection == selection }),
                          restarted.packagePreferences.mode(for: selection) == "ultra",
                          restarted.disabledSkills[agent]?.contains(item.id) == true,
                          !fm.fileExists(atPath: destination.path) else { throw MarketplaceError.invalid("Disabled workspace settings did not survive restart.") }
                    restarted.setSkillEnabled(item, agent: agent, enabled: true)
                    for file in files {
                        guard try Data(contentsOf: destination.appendingPathComponent(file.path)) == file.data else { throw MarketplaceError.invalid("Re-enabled skill files changed.") }
                    }
                    try store.installer.removeSkill(item, for: agent)
                    store.reconcileSkills()
                    guard !store.workspaces.contains(where: { $0.selection == selection }) else { throw MarketplaceError.invalid("The removed workspace is still installed.") }
                    checks.append(["name": name, "repository": item.repository, "revision": item.revision, "agent": agent.rawValue,
                                   "fileCount": files.count, "filesMatch": true, "workspaceOpened": true,
                                   "settingsSurviveRestart": true, "disabledAndReEnabled": true, "removed": true])
                }
            }
            report["success"] = true
        } catch { report["success"] = false; report["error"] = error.localizedDescription }
        report["checks"] = checks
        defaults.removePersistentDomain(forName: suite)
        do { if fm.fileExists(atPath: home.path) { try fm.removeItem(at: home) }; report["temporaryHomeRemoved"] = true }
        catch { report["temporaryHomeRemoved"] = false }
        report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic) }
        catch { fputs("Workspace verification: \(error.localizedDescription)\n", stderr) }
    }
}
