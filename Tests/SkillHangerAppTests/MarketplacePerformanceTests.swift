import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct MarketplacePerformanceTests {
    @Test(arguments: MarketplaceResultTransition.allCases)
    func changingLibraryResultsStartsAtTheTopInACompactWindow(_ transition: MarketplaceResultTransition) async throws {
        let catalog = try expandedCatalog(copies: 4)
        let (window, hosting, runtime, home) = try await compactDashboard(items: catalog)
        defer { window.close(); try? FileManager.default.removeItem(at: home) }
        let before = try #require(resultScroll(in: hosting))
        scroll(before, to: 300)
        #expect(before.contentView.bounds.origin.y >= 299)

        switch transition {
        case .community: runtime.marketplace.query.scope = .community
        case .search: runtime.marketplace.query.search = "focused-fixture"
        case .category: runtime.marketplace.query.category = .development
        case .sort: runtime.marketplace.query.sort = .publisher
        case .agent: runtime.marketplace.query.agent = .codex
        }
        await settle(hosting)

        let after = try #require(resultScroll(in: hosting))
        #expect(runtime.marketplace.results.count > 20)
        #expect(after.contentView.bounds.origin.y <= 1,
                "A new result set must start at its first row, rather than inherit the previous list's scroll offset.")
    }

    @Test func clearingAnEmptySearchRestoresTheFirstResultsInACompactWindow() async throws {
        let (window, hosting, runtime, home) = try await compactDashboard(items: expandedCatalog(copies: 4))
        defer { window.close(); try? FileManager.default.removeItem(at: home) }
        scroll(try #require(resultScroll(in: hosting)), to: 600)
        runtime.marketplace.query.search = "a-query-that-cannot-match-any-package"
        await settle(hosting)
        #expect(runtime.marketplace.results.isEmpty)

        runtime.marketplace.query.clearFilters()
        await settle(hosting)

        let results = try #require(resultScroll(in: hosting))
        #expect(!runtime.marketplace.results.isEmpty)
        #expect(results.contentView.bounds.origin.y <= 1)
        #expect(results.visibleRect.height >= 200,
                "The result list needs a usable viewport at the app's compact window size.")
    }

    @Test func noticesAndMonitoringUpdatesPreserveTheCurrentLibraryPosition() async throws {
        let (window, hosting, runtime, home) = try await compactDashboard(items: expandedCatalog(copies: 4))
        defer { window.close(); try? FileManager.default.removeItem(at: home) }
        runtime.marketplace.query.scope = .community
        await settle(hosting)
        let ids = runtime.marketplace.results.map(\.id)
        scroll(try #require(resultScroll(in: hosting)), to: 300)

        runtime.marketplace.message = "The catalog remains available while another task finishes."
        runtime.monitor.isMonitoringEnabled.toggle()
        await settle(hosting)

        #expect(runtime.page == .marketplace)
        #expect(runtime.marketplace.results.map(\.id) == ids)
        #expect(try #require(resultScroll(in: hosting)).contentView.bounds.origin.y == 300,
                "Unrelated notices and monitoring changes must not jump the user to another row.")
    }

    @Test func replacingCatalogAndChangingFiltersNeverReturnsAnOldSnapshot() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("SkillHangerSnapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = MarketplaceStore(preview: true, home: home)
        let seed = try #require(store.items.first { $0.isCommunity && $0.agents.contains(.codex) })
        var second = seed
        second.id += ":second"
        second.title = "Second package"
        second.category = .documents
        second.keywords += ["focused-fixture"]
        store.items = [seed, second]
        store.query.agent = .codex
        store.query.scope = .community
        #expect(Set(store.snapshot.results.map(\.id)) == [seed.id, second.id])

        store.query.search = "focused-fixture"
        #expect(store.snapshot.results.map(\.id) == [second.id])
        #expect(store.snapshot.total == 1)
        #expect(store.snapshot.counts[.documents] == 1)
        store.query.category = .development
        #expect(store.snapshot.results.isEmpty)
        #expect(store.snapshot.total == 1)

        store.query.clearFilters()
        store.items = [second]
        #expect(store.snapshot.results.map(\.id) == [second.id])
        #expect(store.snapshot.total == 1)
        #expect(store.snapshot.counts[seed.category] == (seed.category == .documents ? 1 : nil))
    }

    @Test func aLongRefreshFailureKeepsTheCompactResultsUsable() async throws {
        let (window, hosting, runtime, home) = try await compactDashboard(items: CatalogLoader.bundled())
        defer { window.close(); try? FileManager.default.removeItem(at: home) }
        runtime.marketplace.message = "Some sources could not refresh. Saved entries are still available.\n" +
            (0..<40).map { "Source \($0): GitHub could not respond. Retry later." }.joined(separator: "\n")
        await settle(hosting)
        let results = try #require(resultScroll(in: hosting))
        #expect(results.contentView.bounds.height >= 200,
                "A source failure must not push the library below a compact window's usable area.")
    }

    @Test func aNoticePresentAtLaunchCannotGrowTheCompactWindow() async throws {
        let (window, hosting, _, home) = try await compactDashboard(items: CatalogLoader.bundled(),
            notice: "GitHub is unavailable. Browse the saved catalog and retry when connected.")
        defer { window.close(); try? FileManager.default.removeItem(at: home) }
        #expect(hosting.bounds.width == 940)
        #expect(hosting.bounds.height == 660)
        #expect(window.contentRect(forFrameRect: window.frame).height == 660)
        #expect(try #require(resultScroll(in: hosting)).visibleRect.height >= 200)
    }

    @Test func packageSelectionSurvivesLibraryFilterAndAgentChanges() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("SkillHangerSelection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let runtime = AppRuntime(preview: true, marketplaceHome: home)
        let store = runtime.marketplace
        let item = try #require(store.items.first { $0.name == "caveman" && $0.agents.contains(.claude) })
        try await store.installSkill(item, for: .claude, files: [
            SkillFile(path: "SKILL.md", data: Data("---\nname: \(item.name)\ndescription: Selection regression fixture\n---".utf8))
        ])
        await Task.yield()
        try await Task.sleep(for: .milliseconds(30))
        #expect(runtime.page == .packageWorkspace)
        let selection = PackageSelection(itemID: item.id, agent: .claude)
        #expect(store.workspaceSelection == selection)

        runtime.page = .marketplace
        store.query.agent = .codex
        store.query.scope = .community
        store.query.search = "unmatched-search"
        #expect(store.snapshot.results.isEmpty)
        #expect(store.selectedWorkspace?.selection == selection)
        runtime.page = .settings
        runtime.page = .marketplace
        #expect(store.query.search == "unmatched-search")
        #expect(store.query.scope == .community)
        #expect(store.query.agent == .codex)

        store.browse()
        #expect(store.query.scope == .all)
        #expect(store.query.search.isEmpty)
        #expect(store.query.category == nil)
        #expect(store.query.sort == .recommended)
        #expect(store.query.agent == .codex)
        #expect(store.selectedWorkspace?.selection == selection)
    }

    /// Records the real APIs consumed by the native library and scroll router.
    /// Elapsed time is diagnostic, while result and scroll assertions stay deterministic.
    @Test func recordCatalogAndNativeScrollCosts() async throws {
        let bundled = try CatalogLoader.bundled()
        for catalog in [bundled, try expandedCatalog(copies: 4)] {
            let start = DispatchTime.now().uptimeNanoseconds
            let (window, hosting, runtime, home) = try await compactDashboard(items: catalog)
            let initialLayout = milliseconds(since: start)
            defer { window.close(); try? FileManager.default.removeItem(at: home) }
            let store = runtime.marketplace
            let index = CatalogIndex(items: catalog)
            for scope in [CatalogScope.all, .community] {
                store.query.scope = scope
                await settle(hosting)
                let expected = store.snapshot
                var checksum = 0
                let snapshotStart = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<24 { checksum += store.snapshot.results.count }
                let snapshotReads = milliseconds(since: snapshotStart)
                #expect(checksum == expected.results.count * 24)

                let countStart = DispatchTime.now().uptimeNanoseconds
                let counts = CatalogCategory.allCases.map { store.count($0) }
                let categoryReads = milliseconds(since: countStart)
                #expect(counts.reduce(0, +) == expected.total)

                let queries = (0..<24).map { number in
                    var query = store.query
                    query.search = ["", "design", "claude", "code", "pdf", "testing"][number % 6]
                    query.sort = CatalogSort.allCases[number % CatalogSort.allCases.count]
                    if number.isMultiple(of: 4) { query.category = .development }
                    return query
                }
                let installed = store.installed[store.query.agent] ?? []
                let originalStart = DispatchTime.now().uptimeNanoseconds
                let original = queries.map { $0.snapshot(in: catalog, installed: installed) }
                let originalFilters = milliseconds(since: originalStart)
                let indexedStart = DispatchTime.now().uptimeNanoseconds
                let indexed = queries.map { index.snapshot(query: $0, installed: installed) }
                let indexedFilters = milliseconds(since: indexedStart)
                #expect(original.map { $0.results.map(\.id) } == indexed.map { $0.results.map(\.id) })
                #expect(original.map(\.counts) == indexed.map(\.counts))
                #expect(original.map(\.total) == indexed.map(\.total))
                print("MARKETPLACE_SEARCH_BENCHMARK catalog=\(catalog.count) scope=\(scope.rawValue) queries=24 original_ms=\(originalFilters) indexed_ms=\(indexedFilters)")

                let results = try #require(resultScroll(in: hosting))
                scroll(results, to: 0)
                let standalone = try scrollEvent(delta: -1)
                let dispatchStart = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<120 { window.sendEvent(standalone) }
                let standaloneScroll = milliseconds(since: dispatchStart)
                #expect(results.contentView.bounds.origin.y == 120)
                scroll(results, to: 0)
                let began = try scrollEvent(delta: -1, phase: .began)
                let changed = try scrollEvent(delta: -1, phase: .changed)
                let ended = try scrollEvent(delta: 0, phase: .ended)
                #expect(began.phase == .began)
                #expect(changed.phase == .changed)
                #expect(ended.phase == .ended)
                let gestureStart = DispatchTime.now().uptimeNanoseconds
                window.sendEvent(began)
                for _ in 0..<119 { window.sendEvent(changed) }
                window.sendEvent(ended)
                let phasedScroll = milliseconds(since: gestureStart)
                #expect(results.contentView.bounds.origin.y == 120)

                print("MARKETPLACE_BENCHMARK catalog=\(catalog.count) agent=claude scope=\(scope.rawValue) results=\(expected.results.count) initial_layout_ms=\(initialLayout) snapshot_24_reads_ms=\(snapshotReads) category_10_reads_ms=\(categoryReads) standalone_120_scrolls_ms=\(standaloneScroll) phased_120_scrolls_ms=\(phasedScroll) native_views=\(descendantCount(hosting))")
            }
        }
    }

    private func expandedCatalog(copies: Int) throws -> [CatalogItem] {
        let bundled = try CatalogLoader.bundled()
        return (0..<copies).flatMap { copy in
            bundled.map { seed in
                var item = seed
                item.id += ":fixture-\(copy)"
                item.name += "-fixture-\(copy)"
                item.title += " Sample \(copy)"
                item.keywords += [copy.isMultiple(of: 2) ? "focused-fixture" : "expanded-fixture"]
                return item
            }
        }
    }

    private func compactDashboard(items: [CatalogItem], notice: String? = nil) async throws -> (DashboardWindow, DashboardHostingView, AppRuntime, URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("SkillHangerPerformance-\(UUID().uuidString)")
        let runtime = AppRuntime(preview: true, marketplaceHome: home)
        runtime.marketplace.items = items
        runtime.marketplace.message = notice
        runtime.marketplace.query.agent = .claude
        runtime.page = .marketplace
        let window = DashboardWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                                     styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = DashboardHostingView(rootView: DashboardView(runtime: runtime))
        window.contentView = hosting
        await settle(hosting)
        return (window, hosting, runtime, home)
    }

    private func settle(_ hosting: NSView) async {
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
    }

    private func resultScroll(in view: NSView) -> NSScrollView? {
        var result = view.subviews.compactMap(resultScroll)
        if let scroll = view as? NSScrollView { result.append(scroll) }
        return result.max { $0.bounds.width < $1.bounds.width }
    }

    private func scroll(_ scroll: NSScrollView, to offset: CGFloat) {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func scrollEvent(delta: Int32, phase: NSEvent.Phase = []) throws -> NSEvent {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                     wheel1: delta, wheel2: 0, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let nativePhase: Int64 = phase == .began ? 1 : phase == .changed ? 2 : phase == .ended ? 4 : 0
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: nativePhase)
        return try #require(NSEvent(cgEvent: cg))
    }

    private func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func descendantCount(_ view: NSView) -> Int {
        1 + view.subviews.reduce(0) { $0 + descendantCount($1) }
    }
}

enum MarketplaceResultTransition: String, CaseIterable {
    case community, search, category, sort, agent
}
