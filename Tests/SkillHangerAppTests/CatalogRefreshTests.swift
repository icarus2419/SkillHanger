import Foundation
import Testing
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct CatalogRefreshTests {
    @Test(arguments: [false, true]) func refreshingAndCancellingKeepTheSavedCatalogIntact(usingCancelControl: Bool) async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let originals = try MarketplaceAgent.allCases.map { agent in
            try #require(CatalogLoader.bundled().first { $0.kind == .plugin && $0.agents == [agent] })
        }
        let gate = CatalogRefreshGate()
        let store = MarketplaceStore(home: home, readPlugins: { _, _ in Data("[]".utf8) },
            refreshSources: MarketplaceAgent.allCases.map(CatalogRefreshSource.plugins), readSource: { source, _ in
                if case .plugins(.claude) = source { await gate.pause() }
                var item = originals.first(where: source.contains)!
                item.title = "Updated \(item.title)"
                return [item]
            })
        store.items = originals
        let pending = Task { await store.refresh() }
        await gate.waitUntilPaused()
        while store.refreshedSourceCount < 1 { await Task.yield() }
        #expect(store.refreshing)
        #expect(store.canCancelRefresh)
        #expect(store.items == originals)
        if usingCancelControl { store.cancelRefresh() }
        else { pending.cancel() }
        await gate.resume()
        await pending.value
        #expect(store.items == originals)
        #expect(!store.refreshing)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/SkillHanger/marketplace-catalog.json").path))
    }

    @Test func aPartialRefreshPreservesUnavailableSourcesAndBundledArtwork() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        var originals = try MarketplaceAgent.allCases.map { agent in
            try #require(CatalogLoader.bundled().first { $0.kind == .plugin && $0.agents == [agent] })
        }
        originals[0].logoName = "bundled-fixture-logo"
        let fixtures = originals
        let store = MarketplaceStore(home: home, readPlugins: { _, _ in Data("[]".utf8) },
            refreshSources: MarketplaceAgent.allCases.map(CatalogRefreshSource.plugins), readSource: { source, _ in
                if case .plugins(.claude) = source { throw MarketplaceError.transport("Fixture source is offline") }
                var item = fixtures[0]
                item.summary = "Updated summary"
                item.logoName = nil
                return [item]
            })
        store.items = originals
        await store.refresh()
        #expect(store.items.first { $0.id == originals[0].id }?.summary == "Updated summary")
        #expect(store.items.first { $0.id == originals[0].id }?.logoName == originals[0].logoName)
        #expect(store.items.first { $0.id == originals[1].id } == originals[1])
        #expect(store.catalogNotice?.contains("Fixture source is offline") == true)
        #expect(store.lastRefreshed != nil)
        let cache = home.appendingPathComponent("Library/Application Support/SkillHanger/marketplace-catalog.json")
        #expect(try JSONDecoder().decode([CatalogItem].self, from: Data(contentsOf: cache)) == store.items)
    }
}

private actor CatalogRefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0 } }
    func waitUntilPaused() async { while continuation == nil { await Task.yield() } }
    func resume() { continuation?.resume(); continuation = nil }
}
