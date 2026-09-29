import Foundation
import Combine

@MainActor
final class MarketplaceStore: ObservableObject {
    @Published var items: [CatalogItem] = []
    @Published var query = CatalogQuery()
    @Published private(set) var refreshing = false
    @Published private(set) var checking = false
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var installed: [MarketplaceAgent: Set<String>] = [:]
    @Published private(set) var managedSkills: [MarketplaceAgent: Set<String>] = [:]
    @Published private(set) var externalSkills: [MarketplaceAgent: Set<String>] = [:]
    @Published private(set) var disabledSkills: [MarketplaceAgent: Set<String>] = [:]
    @Published var message: String?
    @Published private(set) var removalFailure: String?
    @Published private(set) var catalogNotice: String?
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var cliErrors: [MarketplaceAgent: String] = [:]
    @Published private(set) var pluginEnabled: [MarketplaceAgent: [String: Bool]] = [:]
    @Published var workspaceSelection: PackageSelection?
    let packagePreferences: PackagePreferences
    private var pluginSelectors: [MarketplaceAgent: [String: String]] = [:]
    let preview: Bool
    let installer: MarketplaceInstaller
    let github = GitHubCatalog()
    let cli: NativeAgentCLI
    private var operations: [String: Task<Void, Never>] = [:]
    private var started = false
    private let cacheURL: URL

    init(preview: Bool = false, home: URL = FileManager.default.homeDirectoryForCurrentUser, defaults: UserDefaults? = nil) {
        self.preview = preview; installer = MarketplaceInstaller(home: home); cli = NativeAgentCLI(home: home)
        let isolated = preview || home != FileManager.default.homeDirectoryForCurrentUser
        packagePreferences = PackagePreferences(defaults: defaults ?? (isolated ? UserDefaults(suiteName: "SkillHanger.Packages.\(UUID().uuidString)")! : .standard))
        cacheURL = home.appendingPathComponent("Library/Application Support/SkillHanger/marketplace-catalog.json")
        items = (try? CatalogLoader.bundled()) ?? []
        if !preview, let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode([CatalogItem].self, from: data), !cached.isEmpty {
            // New bundled sources must remain discoverable after an app update.
            let cachedIDs = Set(cached.map(\.id))
            let bundledByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            items = cached.map { item in
                var result = item
                if result.logoName == nil, let bundled = bundledByID[item.id], bundled.repository == item.repository { result.logoName = bundled.logoName }
                return result
            } + items.filter { !cachedIDs.contains($0.id) }
            if let sources = try? CatalogLoader.skillSources() {
                items = items.map { item in sources.first(where: { $0.repository == item.repository && item.kind == .skill })?.curate(item) ?? item }
            }
            lastRefreshed = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        if preview {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--marketplace-claude-preview") { query.agent = .claude }
            if args.contains("--marketplace-community-preview") { query.scope = .community }
            if args.contains("--marketplace-empty-preview") { query.search = "nothing matches this query" }
            if args.contains("--marketplace-error-preview") { catalogNotice = "GitHub is unavailable. Browse the saved catalog and retry when connected." }
            if args.contains("--installed-library-preview") {
                let names: Set<String> = ["caveman", "ponytail", "humanizer", "ui-ux-pro-max", "agent-browser", "obsidian-cli", "context-compression", "karpathy-guidelines"]
                for agent in MarketplaceAgent.allCases {
                    let samples = items.filter { $0.agents.contains(agent) && ($0.kind == .skill && names.contains($0.name) || $0.kind == .plugin && ["frontend-design", "build-macos-apps", "figma"].contains($0.name)) }
                    installed[agent] = Set(samples.map(\.id))
                    managedSkills[agent] = Set(samples.filter { $0.kind == .skill }.map(\.id))
                    disabledSkills[agent] = Set(samples.filter { $0.name == "humanizer" }.map(\.id))
                }
            }
            if args.contains("--library-installed-preview") { query.scope = .installed }
            let packageName = args.firstIndex(of: "--package-preview-name").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
            if args.contains("--package-workspace-preview"), let item = items.first(where: { $0.name == (packageName ?? "caveman") && $0.kind == .skill }) {
                installed[query.agent, default: []].insert(item.id)
                managedSkills[query.agent, default: []].insert(item.id)
                workspaceSelection = PackageSelection(itemID: item.id, agent: query.agent)
                if args.contains("--package-design-system-preview"), let selection = workspaceSelection {
                    packagePreferences.setOption("design-system", key: "intent", for: selection)
                    packagePreferences.setOption("swiftui", key: "stack", for: selection)
                    packagePreferences.setOption("8", key: "density", for: selection)
                }
            }
            if args.contains("--plugin-workspace-preview"), let item = items.first(where: { $0.kind == .plugin && $0.agents.contains(query.agent) && $0.name == (query.agent == .claude ? "frontend-design" : "build-macos-apps") }) {
                installed[query.agent, default: []].insert(item.id)
                workspaceSelection = PackageSelection(itemID: item.id, agent: query.agent)
                pluginEnabled[query.agent] = [item.id: true]
            }
        } else {
            reconcileSkills()
        }
    }
    func reconcileSkills() {
        for agent in MarketplaceAgent.allCases {
            var found = Set((installed[agent] ?? []).filter { id in items.contains { $0.id == id && $0.kind == .plugin } })
            let skills = skillInventory(agent)
            found.formUnion(skills.found)
            installed[agent] = found; managedSkills[agent] = skills.owned; disabledSkills[agent] = skills.disabled; externalSkills[agent] = skills.external
        }
    }
    private func skillInventory(_ agent: MarketplaceAgent) -> (found: Set<String>, owned: Set<String>, disabled: Set<String>, external: Set<String>) {
        var found: Set<String> = [], owned: Set<String> = [], disabled: Set<String> = [], external: Set<String> = []
        for item in items where item.kind == .skill && item.agents.contains(agent) {
            if let state = try? installer.skillState(item, for: agent), state != .absent {
                found.insert(item.id)
                if state == .managed || state == .disabled { owned.insert(item.id) }
                if state == .disabled { disabled.insert(item.id) }
                if state == .external, (try? installer.canTrashExternalSkill(item, for: agent)) == true { external.insert(item.id) }
            }
        }
        return (found, owned, disabled, external)
    }
    func setSkillEnabled(_ item: CatalogItem, agent: MarketplaceAgent, enabled: Bool) {
        guard !preview, !busy.contains(key(item, agent: agent)) else { return }
        do {
            try installer.setSkillEnabled(item, for: agent, enabled: enabled)
            reconcileSkills()
            message = "\(item.title) \(enabled ? "enabled" : "disabled") for \(agent.title). Start a new session to apply the change."
        } catch { message = "Could not change \(item.title). \(error.localizedDescription)" }
    }
    var workspaces: [InstalledPackage] {
        var result: [InstalledPackage] = []
        for agent in MarketplaceAgent.allCases {
            for item in items where installed[agent]?.contains(item.id) == true {
                result.append(InstalledPackage(item: item, agent: agent))
            }
        }
        return result.sorted { a, b in
            if a.item.title == b.item.title { return a.id < b.id }
            return a.item.title.localizedStandardCompare(b.item.title) == .orderedAscending
        }
    }
    var selectedWorkspace: InstalledPackage? { workspaces.first { $0.selection == workspaceSelection } }
    func openWorkspace(_ item: CatalogItem, agent: MarketplaceAgent? = nil) {
        let target = agent ?? query.agent
        guard installed[target]?.contains(item.id) == true else { return }
        workspaceSelection = PackageSelection(itemID: item.id, agent: target)
    }
    func browse() { query.scope = .all; query.category = nil; query.search = ""; query.sort = .recommended }
    func installSkill(_ item: CatalogItem, for agent: MarketplaceAgent, files: [SkillFile]) async throws {
        _ = try await installer.installSkill(item, for: agent, files: files)
        managedSkills[agent, default: []].insert(item.id)
        installed[agent, default: []].insert(item.id)
        openWorkspace(item, agent: agent)
    }
    var snapshot: CatalogSnapshot { query.snapshot(in: items, installed: installed[query.agent] ?? []) }
    var results: [CatalogItem] { snapshot.results }
    var categories: [CatalogCategory] { CatalogCategory.allCases.filter { category in items.contains { $0.category == category && $0.agents.contains(query.agent) } } }
    func count(_ category: CatalogCategory?) -> Int {
        let current = snapshot
        return category.map { current.counts[$0, default: 0] } ?? current.total
    }
    func isInstalled(_ item: CatalogItem) -> Bool { installed[query.agent]?.contains(item.id) == true }
    func canRemove(_ item: CatalogItem, agent target: MarketplaceAgent? = nil) -> Bool {
        let agent = target ?? query.agent
        return installed[agent]?.contains(item.id) == true &&
            (item.kind == .plugin || managedSkills[agent]?.contains(item.id) == true || externalSkills[agent]?.contains(item.id) == true)
    }
    func isBusy(_ item: CatalogItem, agent: MarketplaceAgent? = nil) -> Bool { busy.contains(key(item, agent: agent ?? query.agent)) }
    private func key(_ item: CatalogItem, agent: MarketplaceAgent) -> String { agent.rawValue + ":" + item.id }
    func start() async {
        guard !started else { return }; started = true
        if !preview { await reconcile() }
    }
    func refresh() async {
        guard !preview, !refreshing else { return }
        refreshing = true; catalogNotice = nil
        defer { refreshing = false }
        var failures: [String] = []
        var refreshedSources = 0
        // Each source is replaced only after it loads completely.
        for agent in MarketplaceAgent.allCases {
            do {
                let loaded = try await github.plugins(agent: agent)
                items.removeAll { $0.kind == .plugin && $0.agents == [agent] }; items += loaded
                refreshedSources += 1
            } catch { failures.append("\(agent.title) plugins: \(error.localizedDescription)") }
        }
        for source in (try? CatalogLoader.skillSources()) ?? [] {
            do {
                let loaded = try await github.skills(source: source)
                items.removeAll { $0.kind == .skill && $0.repository == source.repository }; items += loaded
                refreshedSources += 1
            } catch { failures.append("\(source.repository): \(error.localizedDescription)") }
        }
        if refreshedSources > 0 {
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(items).write(to: cacheURL, options: .atomic)
                lastRefreshed = Date()
            } catch { failures.append("Could not save the catalog: \(error.localizedDescription)") }
        }
        catalogNotice = failures.isEmpty ? nil : "Some sources could not refresh. Their saved entries are still available.\n" + failures.joined(separator: "\n")
        await reconcile()
    }
    func reconcile() async {
        guard !preview, !checking else { return }
        checking = true
        defer { checking = false }
        for agent in MarketplaceAgent.allCases {
            var found: Set<String> = []
            do {
                let args = ["plugin", "list", "--json"]
                let data = try await cli.run(agent, arguments: args, timeout: 30)
                let identifiers = try NativePluginInventory.identifiers(data, agent: agent)
                let states = try NativePluginInventory.enabledStates(data, agent: agent)
                pluginSelectors[agent] = [:]
                pluginEnabled[agent] = [:]
                for item in items where item.kind == .plugin && item.agents.contains(agent) {
                    if let selector = GitHubPluginMarketplace.selectors(item).first(where: identifiers.contains) {
                        found.insert(item.id); pluginSelectors[agent]?[item.id] = selector
                        pluginEnabled[agent]?[item.id] = states[selector]
                    }
                }
                cliErrors[agent] = nil
            } catch {
                cliErrors[agent] = error.localizedDescription
                // Keep known plugin state if the CLI temporarily cannot respond.
                found.formUnion((installed[agent] ?? []).filter { id in items.contains { $0.id == id && $0.kind == .plugin } })
            }
            // Skill installs can complete while native plugin inventory awaits.
            // Re-read the filesystem at publication so those workspaces survive.
            let skills = skillInventory(agent)
            found.formUnion(skills.found)
            installed[agent] = found; managedSkills[agent] = skills.owned; disabledSkills[agent] = skills.disabled; externalSkills[agent] = skills.external
        }
        if let selection = workspaceSelection, installed[selection.agent]?.contains(selection.itemID) != true { workspaceSelection = nil }
    }
    func install(_ item: CatalogItem) {
        guard !preview, !isBusy(item), !isInstalled(item) else { return }
        let agent = query.agent, operationKey = key(item, agent: query.agent)
        busy.insert(operationKey); message = nil
        operations[operationKey] = Task {
            defer { busy.remove(operationKey); operations[operationKey] = nil }
            do {
                if item.kind == .skill {
                    let files = try await github.skillFiles(item)
                    try await installSkill(item, for: agent, files: files)
                } else {
                    var installItem = item
                    if agent == .codex {
                        let (translated, root) = try GitHubPluginMarketplace.prepare(item, home: installer.home)
                        installItem = translated
                        _ = try await cli.run(agent, arguments: ["plugin", "marketplace", "add", root.path])
                    } else {
                        let listed = try await cli.run(agent, arguments: ["plugin", "marketplace", "list", "--json"], timeout: 30)
                        if !String(decoding: listed, as: UTF8.self).contains(item.marketplace ?? "") {
                            _ = try await cli.run(agent, arguments: ["plugin", "marketplace", "add", "anthropics/claude-plugins-official"])
                        }
                    }
                    _ = try await cli.run(agent, arguments: PluginCommand.install(installItem, agent: agent))
                }
                installed[agent, default: []].insert(item.id)
                openWorkspace(item, agent: agent)
                message = "\(item.title) installed for \(agent.title). Start a new agent session to load it. Plugins with connected services may need account setup in the agent."
                await reconcile()
            } catch { message = "Could not install \(item.title). \(error.localizedDescription)" }
        }
    }
    func cancel(_ item: CatalogItem) { operations[key(item, agent: query.agent)]?.cancel() }
    func setPluginEnabled(_ item: CatalogItem, agent: MarketplaceAgent, enabled: Bool) {
        let operationKey = key(item, agent: agent)
        guard !preview, item.kind == .plugin, agent == .claude, installed[agent]?.contains(item.id) == true,
              !busy.contains(operationKey), !checking else { return }
        busy.insert(operationKey); message = nil
        operations[operationKey] = Task {
            defer { busy.remove(operationKey); operations[operationKey] = nil }
            do {
                var target = item
                if let selector = pluginSelectors[agent]?[item.id], let marketplace = selector.split(separator: "@").last { target.marketplace = String(marketplace) }
                _ = try await cli.run(agent, arguments: PluginCommand.setEnabled(target, enabled: enabled, agent: agent))
                pluginEnabled[agent, default: [:]][item.id] = enabled
                message = "\(item.title) \(enabled ? "enabled" : "disabled") for \(agent.title). Start a new session to apply the change."
                await reconcile()
            } catch { message = "Could not change \(item.title). \(error.localizedDescription)" }
        }
    }
    func remove(_ item: CatalogItem, agent target: MarketplaceAgent? = nil) {
        let agent = target ?? query.agent, operationKey = key(item, agent: target ?? query.agent)
        guard !preview, !busy.contains(operationKey), canRemove(item, agent: agent) else { return }
        busy.insert(operationKey); removalFailure = nil
        operations[operationKey] = Task {
            defer { busy.remove(operationKey); operations[operationKey] = nil }
            do {
                if item.kind == .skill {
                    if try installer.skillState(item, for: agent) == .external { try installer.trashExternalSkill(item, for: agent) }
                    else { try installer.removeSkill(item, for: agent) }
                }
                else {
                    var installedItem = item
                    if let selector = pluginSelectors[agent]?[item.id], let marketplace = selector.split(separator: "@").last { installedItem.marketplace = String(marketplace) }
                    _ = try await cli.run(agent, arguments: PluginCommand.remove(installedItem, agent: agent))
                }
                installed[agent]?.remove(item.id); managedSkills[agent]?.remove(item.id); disabledSkills[agent]?.remove(item.id); externalSkills[agent]?.remove(item.id)
                if workspaceSelection == PackageSelection(itemID: item.id, agent: agent) { workspaceSelection = nil }
                message = "\(item.title) removed from \(agent.title). Start a new session to apply this change."
                await reconcile()
            } catch {
                let failure = "Could not uninstall \(item.title) from \(agent.title). \(error.localizedDescription)"
                message = failure; removalFailure = failure
            }
        }
    }
}

enum NativePluginInventory {
    private static func entries(_ data: Data, agent: MarketplaceAgent) throws -> [[String: Any]] {
        let json = try JSONSerialization.jsonObject(with: data)
        let entries: [[String: Any]]
        if let array = json as? [[String: Any]] { entries = array }
        else if let object = json as? [String: Any], let installed = object["installed"] as? [[String: Any]] { entries = installed }
        else { throw MarketplaceError.invalid("The agent returned an unsupported plugin inventory. Update the CLI and retry.") }
        return entries.filter { entry in agent != .claude || entry["scope"] == nil || entry["scope"] as? String == "user" }
    }
    private static func identifier(_ entry: [String: Any]) -> String? {
            if let id = entry["pluginId"] as? String { return id }
            if let id = entry["id"] as? String { return id }
            if let name = entry["name"] as? String, let marketplace = entry["marketplaceName"] as? String ?? entry["marketplace"] as? String { return name + "@" + marketplace }
            return nil
    }
    static func identifiers(_ data: Data, agent: MarketplaceAgent) throws -> Set<String> {
        Set(try entries(data, agent: agent).compactMap(identifier))
    }
    static func enabledStates(_ data: Data, agent: MarketplaceAgent) throws -> [String: Bool] {
        var result: [String: Bool] = [:]
        for entry in try entries(data, agent: agent) {
            if let id = identifier(entry), let enabled = entry["enabled"] as? Bool { result[id] = enabled }
        }
        return result
    }
}
