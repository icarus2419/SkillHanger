import Foundation
import Testing
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct MarketplaceInventoryTests {
    @Test func aSlowInventoryCannotEraseASkillInstalledWhileItWasReading() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let gate = InventoryGate()
        let store = MarketplaceStore(preview: true, home: home, readSkills: { items, installer in
            let result = await MarketplaceSkillInventory.read(items: items, installer: installer)
            await gate.pauseFirstRead()
            return result
        })
        let item = try #require(store.items.first { $0.name == "caveman" })
        let pending = Task { await store.reconcileSkills() }
        await gate.waitUntilPaused()
        try await store.installSkill(item, for: .codex, files: [
            SkillFile(path: "SKILL.md", data: Data("---\nname: caveman\ndescription: Inventory race fixture\n---".utf8))
        ])
        await gate.resume()
        await pending.value
        #expect(store.installed[.codex]?.contains(item.id) == true)
        #expect(store.managedSkills[.codex]?.contains(item.id) == true)
        #expect(store.selectedWorkspace?.item.id == item.id)
        #expect(await gate.reads >= 2)
    }

    @Test func navigationChecksReuseInventoryButAnExplicitCheckRefreshesIt() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let requests = InventoryRequests()
        let store = MarketplaceStore(home: home, readPlugins: { agent, _ in
            await requests.increment(agent)
            return Data("[]".utf8)
        })
        await store.start()
        for _ in 0..<4 {
            store.query.agent = .claude
            await store.reconcile(force: false)
            store.query.agent = .codex
            await store.reconcile(force: false)
        }
        #expect(await requests.counts == [.codex: 1, .claude: 1])
        await store.reconcile()
        #expect(await requests.counts == [.codex: 2, .claude: 2])
        #expect(!store.checking)
    }

    @Test func aFailedPluginCheckPreservesKnownInstallationAndEnableState() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let requests = InventoryRequests()
        let item = try #require(CatalogLoader.bundled().first { $0.kind == .plugin && $0.agents == [.claude] })
        let selector = try #require(GitHubPluginMarketplace.selectors(item).first)
        let store = MarketplaceStore(home: home, readPlugins: { agent, _ in
            let attempt = await requests.increment(agent)
            if attempt > 1 { throw MarketplaceError.command("Offline inventory") }
            if agent == .codex { return Data("[]".utf8) }
            return try JSONSerialization.data(withJSONObject: [["id": selector, "enabled": false, "scope": "user"]])
        })
        await store.reconcile()
        #expect(store.installed[.claude]?.contains(item.id) == true)
        #expect(store.pluginEnabled[.claude]?[item.id] == false)
        await store.reconcile()
        #expect(store.installed[.claude]?.contains(item.id) == true)
        #expect(store.pluginEnabled[.claude]?[item.id] == false)
        #expect(store.cliErrors[.claude]?.contains("Offline inventory") == true)
    }
}

private actor InventoryGate {
    private(set) var reads = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func pauseFirstRead() async {
        reads += 1
        if reads == 1 { await withCheckedContinuation { continuation = $0 } }
    }
    func waitUntilPaused() async {
        while continuation == nil { await Task.yield() }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

private actor InventoryRequests {
    private(set) var counts: [MarketplaceAgent: Int] = [:]
    @discardableResult func increment(_ agent: MarketplaceAgent) -> Int {
        counts[agent, default: 0] += 1
        return counts[agent]!
    }
}
