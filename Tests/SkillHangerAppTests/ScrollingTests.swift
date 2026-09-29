import AppKit
import SwiftUI
import Testing
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct ScrollingTests {
    @Test func installedDashboardKeepsBothAgentsAndOpensTheCorrectEditor() async throws {
        let (window, hosting, _) = try await dashboard(page: .installed)
        defer { window.close() }
        let runtime = hosting.rootView.runtime
        let store = runtime.marketplace
        defer { try? FileManager.default.removeItem(at: store.installer.home) }
        let item = try #require(store.items.first { $0.name == "caveman" && $0.kind == .skill && $0.agents.contains(.codex) && $0.agents.contains(.claude) })
        let file = SkillFile(path: "SKILL.md", data: Data("---\nname: caveman\ndescription: Test package\n---".utf8))
        try await store.installSkill(item, for: .codex, files: [file])
        try await store.installSkill(item, for: .claude, files: [file])
        store.workspaceSelection = nil
        try await Task.sleep(for: .milliseconds(60))
        runtime.page = .installed
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        #expect(store.workspaces.filter { $0.item.id == item.id }.count == 2)
        #expect(InstalledLibraryQuery().groups(in: store.workspaces).map(\.agent) == [.codex, .claude])
        if let output = ProcessInfo.processInfo.environment["SKILLHANGER_INSTALLED_PREVIEW"],
           let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: URL(fileURLWithPath: output)) }
        }
        store.openWorkspace(item, agent: .claude)
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.workspaceSelection?.agent == .claude)
        #expect(runtime.page == .packageWorkspace)
        store.workspaceSelection = nil
        try await Task.sleep(for: .milliseconds(30))
        #expect(runtime.page == .installed)
    }

    @Test func packageDesignControlsRemainReachableInCompactWindow() async throws {
        let (window, hosting, _) = try await dashboard(page: .marketplace)
        defer { window.close() }
        let store = hosting.rootView.runtime.marketplace
        let item = try #require(store.items.first { $0.name == "ui-ux-pro-max" && $0.kind == .skill })
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        // Use the runtime's injected temporary home rather than installing to the user's home.
        let runtime = AppRuntime(preview: true, marketplaceHome: home)
        try await runtime.marketplace.installSkill(item, for: .claude, files: [SkillFile(path: "SKILL.md", data: Data("---\nname: ui-ux-pro-max\ndescription: Interface design\n---".utf8))])
        let selection = try #require(runtime.marketplace.workspaceSelection)
        runtime.marketplace.packagePreferences.setOption("design-system", key: "intent", for: selection)
        runtime.page = .packageWorkspace
        hosting.rootView = DashboardView(runtime: runtime)
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        let scroll = try #require(findScrollView(hosting))
        let document = try #require(scroll.documentView)
        #expect(document.bounds.height > scroll.contentView.bounds.height + 600)
        window.sendEvent(try trackpadEvent(delta: -100_000))
        #expect(scroll.contentView.bounds.origin.y == document.bounds.maxY - scroll.contentView.bounds.height)
        window.sendEvent(try trackpadEvent(delta: 100_000))
        #expect(scroll.contentView.bounds.origin.y == 0)
    }
    @Test(arguments: [NSPoint(x: 450, y: 200), NSPoint(x: 450, y: 300),
                      NSPoint(x: 880, y: 310), NSPoint(x: 450, y: 600),
                      NSPoint(x: 80, y: 300), NSPoint(x: 215, y: 450)])
    func smallTrackpadScrollMovesPageAcrossWindow(point: NSPoint) async throws {
        let (window, hosting, scroll) = try await dashboard(page: .settings)
        defer { window.close() }
        _ = try #require(hosting.hitTest(point))
        let before = scroll.contentView.bounds.origin.y
        let event = try trackpadEvent(delta: -3)
        #expect(event.hasPreciseScrollingDeltas)
        // DashboardWindow intercepts physical scroll events before SwiftUI's
        // child responder can consume them. Exercise that actual dispatch path.
        window.sendEvent(try windowEvent(delta: -3, at: point, in: window, hosting: hosting))
        try await Task.sleep(for: .milliseconds(50))
        #expect(scroll.contentView.bounds.origin.y == before + 3)
        window.sendEvent(try windowEvent(delta: 2, at: point, in: window, hosting: hosting))
        try await Task.sleep(for: .milliseconds(50))
        #expect(scroll.contentView.bounds.origin.y == before + 1)
    }

    @Test func installedSidebarScrollsIndependentlyFromTheLibraryResults() async throws {
        let (window, hosting, _) = try await dashboard(page: .marketplace)
        defer { window.close() }
        let store = hosting.rootView.runtime.marketplace
        defer { try? FileManager.default.removeItem(at: store.installer.home) }
        let items = Array(store.items.filter { $0.kind == .skill && $0.agents.contains(.codex) }.prefix(10))
        for item in items {
            try await store.installSkill(item, for: .codex, files: [SkillFile(path: "SKILL.md", data: Data("---\nname: \(item.name)\ndescription: Test package\n---".utf8))])
        }
        try await Task.sleep(for: .milliseconds(200))
        hosting.rootView.runtime.page = .marketplace
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        let mainScroll = try #require(findScrollView(hosting))
        let sidebar = try #require(allScrollViews(hosting).first { $0.bounds.width < 250 })
        let document = try #require(sidebar.documentView)
        #expect(sidebar.contentView.bounds.height > 40)
        #expect(document.bounds.height > sidebar.contentView.bounds.height)
        sidebar.contentView.scroll(to: .zero)
        sidebar.reflectScrolledClipView(sidebar.contentView)
        let point = sidebar.convert(NSPoint(x: sidebar.bounds.midX, y: sidebar.bounds.midY), to: hosting)
        let before = mainScroll.contentView.bounds.origin.y
        window.sendEvent(try windowEvent(delta: -3, at: point, in: window, hosting: hosting))
        #expect(sidebar.contentView.bounds.origin.y == 3)
        #expect(mainScroll.contentView.bounds.origin.y == before)
        window.sendEvent(try windowEvent(delta: -3, at: NSPoint(x: 450, y: 300), in: window, hosting: hosting))
        #expect(mainScroll.contentView.bounds.origin.y == before + 3)
        #expect(sidebar.contentView.bounds.origin.y == 3)
    }

    @Test func oneTrackpadGestureKeepsItsInitialLibraryScrollTarget() async throws {
        let (window, hosting, _) = try await dashboard(page: .marketplace)
        defer { window.close() }
        let store = hosting.rootView.runtime.marketplace
        defer { try? FileManager.default.removeItem(at: store.installer.home) }
        for item in store.items.filter({ $0.kind == .skill && $0.agents.contains(.codex) }).prefix(10) {
            try await store.installSkill(item, for: .codex, files: [SkillFile(path: "SKILL.md", data: Data("---\nname: \(item.name)\ndescription: Test package\n---".utf8))])
        }
        store.workspaceSelection = nil
        hosting.rootView.runtime.page = .marketplace
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        let main = try #require(allScrollViews(hosting).max(by: { $0.bounds.width < $1.bounds.width }))
        let sidebar = try #require(allScrollViews(hosting).first { $0.bounds.width < 250 })
        let sidebarPoint = sidebar.convert(NSPoint(x: sidebar.bounds.midX, y: sidebar.bounds.midY), to: hosting)
        let mainPoint = NSPoint(x: 450, y: 300)
        window.sendEvent(try windowEvent(delta: -3, phase: .began, at: mainPoint, in: window, hosting: hosting))
        let sidebarBefore = sidebar.contentView.bounds.origin.y
        window.sendEvent(try windowEvent(delta: -3, phase: .changed, at: sidebarPoint, in: window, hosting: hosting))
        #expect(main.contentView.bounds.origin.y == 6)
        #expect(sidebar.contentView.bounds.origin.y == sidebarBefore)
        window.sendEvent(try windowEvent(delta: 0, phase: .ended, at: sidebarPoint, in: window, hosting: hosting))
    }

    @Test func momentumContinuesScrollingOutsidePageContent() async throws {
        let (window, hosting, scroll) = try await dashboard(page: .settings)
        defer { window.close() }
        hosting.scrollWheel(with: try trackpadEvent(delta: -3))
        let before = scroll.contentView.bounds.origin.y
        let event = try trackpadEvent(delta: -6, momentum: CGMomentumScrollPhase(rawValue: 2)!)
        #expect(event.momentumPhase == .changed)
        hosting.scrollWheel(with: event)
        try await Task.sleep(for: .milliseconds(50))
        #expect(scroll.contentView.bounds.origin.y > before)
    }

    @Test func horizontalSidebarSwipeLeavesNavigationAndVerticalScrollUntouched() async throws {
        let (window, hosting, _) = try await dashboard(page: .marketplace)
        defer { window.close() }
        let store = hosting.rootView.runtime.marketplace
        defer { try? FileManager.default.removeItem(at: store.installer.home) }
        for item in store.items.filter({ $0.kind == .skill && $0.agents.contains(.codex) }).prefix(10) {
            try await store.installSkill(item, for: .codex, files: [SkillFile(path: "SKILL.md", data: Data("---\nname: \(item.name)\ndescription: Test package\n---".utf8))])
        }
        try await Task.sleep(for: .milliseconds(200))
        hosting.rootView.runtime.page = .marketplace
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        let sidebar = try #require(allScrollViews(hosting).first { $0.bounds.width < 250 })
        sidebar.contentView.scroll(to: .zero)
        sidebar.reflectScrolledClipView(sidebar.contentView)
        hosting.layoutSubtreeIfNeeded()
        let region = try #require(allSwipeRegions(hosting).first { $0.visibleRect.height >= 40 })
        let point = region.convert(NSPoint(x: region.visibleRect.midX, y: region.visibleRect.midY), to: hosting)
        let originalUpdate = region.onUpdate
        let originalFinish = region.onFinish
        var updates: [CGSize] = []
        var finishes = 0
        region.onUpdate = { value in updates.append(value); return originalUpdate(value) }
        region.onFinish = { value in finishes += 1; originalFinish(value) }
        let selected = store.workspaceSelection
        let scrollPositions = allScrollViews(hosting).map { $0.contentView.bounds.origin.y }
        for phase in [NSEvent.Phase.began, .changed, .ended] {
            window.sendEvent(try windowEvent(delta: 0, horizontal: phase == .ended ? 0 : -20,
                                              phase: phase, at: point, in: window, hosting: hosting))
        }
        try await Task.sleep(for: .milliseconds(250))
        #expect(updates.last?.width == -40)
        #expect(finishes == 1)
        #expect(allScrollViews(hosting).map { $0.contentView.bounds.origin.y } == scrollPositions)
        #expect(store.workspaceSelection == selected)
        #expect(hosting.rootView.runtime.page == .marketplace)
        if let output = ProcessInfo.processInfo.environment["SKILLHANGER_SIDEBAR_PREVIEW"],
           let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: URL(fileURLWithPath: output)) }
        }
    }

    @Test func scrollingOutsideAnOpenInstalledRowClosesItsDeleteAction() async throws {
        let (window, hosting, _) = try await dashboard(page: .marketplace)
        defer { window.close() }
        let store = hosting.rootView.runtime.marketplace
        defer { try? FileManager.default.removeItem(at: store.installer.home) }
        let item = try #require(store.items.first { $0.kind == .skill && $0.agents.contains(.codex) })
        try await store.installSkill(item, for: .codex, files: [SkillFile(path: "SKILL.md", data: Data("---\nname: \(item.name)\ndescription: Test package\n---".utf8))])
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        let region = try #require(allSwipeRegions(hosting).first { $0.visibleRect.height >= 40 })
        let point = region.convert(NSPoint(x: region.visibleRect.midX, y: region.visibleRect.midY), to: hosting)
        for phase in [NSEvent.Phase.began, .changed, .ended] {
            window.sendEvent(try windowEvent(delta: 0, horizontal: phase == .ended ? 0 : -24,
                                              phase: phase, at: point, in: window, hosting: hosting))
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(region.isRevealed)
        window.sendEvent(try windowEvent(delta: -4, at: NSPoint(x: 450, y: 300), in: window, hosting: hosting))
        try await Task.sleep(for: .milliseconds(50))
        #expect(!region.isRevealed)
        for phase in [NSEvent.Phase.began, .changed, .ended] {
            window.sendEvent(try windowEvent(delta: 0, horizontal: phase == .ended ? 0 : -24,
                                              phase: phase, at: point, in: window, hosting: hosting))
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(region.isRevealed)
        window.sendEvent(try windowEvent(delta: -4, phase: .began, at: point, in: window, hosting: hosting))
        window.sendEvent(try windowEvent(delta: 0, phase: .ended, at: point, in: window, hosting: hosting))
        try await Task.sleep(for: .milliseconds(50))
        #expect(!region.isRevealed)
        for phase in [NSEvent.Phase.began, .changed, .ended] {
            window.sendEvent(try windowEvent(delta: 0, horizontal: phase == .ended ? 0 : -24,
                                              phase: phase, at: point, in: window, hosting: hosting))
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(region.isRevealed)
        let outsidePoint = hosting.convert(NSPoint(x: 450, y: 300), to: nil)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: outsidePoint,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 0))
        window.sendEvent(click)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!region.isRevealed)
    }

    @Test func shortPageSafelyAcceptsScrollAndPageChangesKeepWorking() async throws {
        let (window, hosting, _) = try await dashboard(page: .activity)
        defer { window.close() }
        // An empty Activity page fits; forwarding must return without recursion.
        hosting.scrollWheel(with: try trackpadEvent(delta: -3))
        hosting.rootView.runtime.page = .settings
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        let scroll = try #require(findScrollView(hosting))
        let before = scroll.contentView.bounds.origin.y
        hosting.scrollWheel(with: try trackpadEvent(delta: -3))
        try await Task.sleep(for: .milliseconds(50))
        #expect(scroll.contentView.bounds.origin.y == before + 3)
    }

    @Test func realWindowDispatchMovesPageForTrackpadAndWheel() async throws {
        let (window, hosting, scroll) = try await dashboard(page: .settings)
        defer { window.close() }
        let point = hosting.convert(NSPoint(x: 450, y: 300), to: nil)
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                     wheel1: -3, wheel2: 0, wheel3: 0))
        cg.location = window.convertPoint(toScreen: point)
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
        let event = try #require(NSEvent(cgEvent: cg))
        let before = scroll.contentView.bounds.origin.y
        window.sendEvent(event)
        try await Task.sleep(for: .milliseconds(50))
        #expect(scroll.contentView.bounds.origin.y > before)
    }

    @Test func trackpadGesturePhasesMoveImmediately() async throws {
        let (window, _, scroll) = try await dashboard(page: .awake)
        defer { window.close() }
        for phase in [1, 2, 2] {
            let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                         wheel1: -2, wheel2: 0, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
            let before = scroll.contentView.bounds.origin.y
            window.sendEvent(try #require(NSEvent(cgEvent: cg)))
            try await Task.sleep(for: .milliseconds(50))
            #expect(scroll.contentView.bounds.origin.y == before + 2)
        }
    }

    @Test func smallTrackpadAndTrackballDeltasRespectPageEdges() async throws {
        let (window, _, scroll) = try await dashboard(page: .settings)
        defer { window.close() }
        let precise = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                          wheel1: -1, wheel2: 0, wheel3: 0))
        precise.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        window.sendEvent(try #require(NSEvent(cgEvent: precise)))
        #expect(scroll.contentView.bounds.origin.y == 1)
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                        wheel1: -1, wheel2: 0, wheel3: 0))
        let event = try #require(NSEvent(cgEvent: wheel))
        #expect(!event.hasPreciseScrollingDeltas)
        let before = scroll.contentView.bounds.origin.y
        window.sendEvent(event)
        #expect(scroll.contentView.bounds.origin.y > before)
        window.sendEvent(try trackpadEvent(delta: -100_000))
        let bottom = try #require(scroll.documentView).bounds.maxY - scroll.contentView.bounds.height
        #expect(scroll.contentView.bounds.origin.y == bottom)
        window.sendEvent(try trackpadEvent(delta: 100_000))
        #expect(scroll.contentView.bounds.origin.y == 0)
    }

    @Test func marketplaceResultsAcceptSmallPhasedTrackpadDeltas() async throws {
        let (window, hosting, scroll) = try await dashboard(page: .marketplace)
        defer { window.close() }
        for phase in [1, 2, 2] {
            let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                         wheel1: -2, wheel2: 0, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
            let before = scroll.contentView.bounds.origin.y
            window.sendEvent(try #require(NSEvent(cgEvent: cg)))
            try await Task.sleep(for: .milliseconds(50))
            #expect(scroll.contentView.bounds.origin.y == before + 2)
        }
        #expect(hosting.rootView.runtime.marketplace.query.search.isEmpty)
        #expect(hosting.rootView.runtime.marketplace.results.count > 100)
    }

    private func dashboard(page: AppPage) async throws -> (NSWindow, DashboardHostingView, NSScrollView) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("SkillHangerScroll-\(UUID().uuidString)")
        let runtime = AppRuntime(preview: true, marketplaceHome: home)
        runtime.page = page
        let window = DashboardWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = DashboardHostingView(rootView: DashboardView(runtime: runtime))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        return (window, hosting, try #require(findScrollView(hosting)))
    }

    private func findScrollView(_ view: NSView) -> NSScrollView? {
        var candidates = view.subviews.compactMap(findScrollView)
        if let scroll = view as? NSScrollView { candidates.append(scroll) }
        return candidates.max { $0.bounds.width < $1.bounds.width }
    }

    private func allScrollViews(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(allScrollViews)
    }

    private func allSwipeRegions(_ view: NSView) -> [SidebarSwipeRegionView] {
        ((view as? SidebarSwipeRegionView).map { [$0] } ?? []) + view.subviews.flatMap(allSwipeRegions)
    }

    private func windowEvent(delta: Int32, horizontal: Int32 = 0, phase: NSEvent.Phase = .changed, at point: NSPoint, in window: NSWindow, hosting: NSView) throws -> NSEvent {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                     wheel1: delta, wheel2: horizontal, wheel3: 0))
        cg.location = window.convertPoint(toScreen: hosting.convert(point, to: nil))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
        let event = try #require(NSEvent(cgEvent: cg))
        return BoundScrollEvent(event: event, window: window, point: hosting.convert(point, to: nil), phase: phase)
    }

    private func trackpadEvent(delta: Int32, momentum: CGMomentumScrollPhase = .none) throws -> NSEvent {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                     wheel1: delta, wheel2: 0, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
        return try #require(NSEvent(cgEvent: cg))
    }
}

/// Supplies window coordinates for synthetic input even when the test process
/// cannot register windows with WindowServer. This is routing proof, not a
/// physical trackpad check.
private final class BoundScrollEvent: NSEvent {
    private let base: NSEvent
    private let targetWindow: NSWindow
    private let point: NSPoint
    private let gesturePhase: NSEvent.Phase

    init(event: NSEvent, window: NSWindow, point: NSPoint, phase: NSEvent.Phase) {
        self.base = event; self.targetWindow = window; self.point = point
        self.gesturePhase = phase
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not used by these tests") }
    override var type: NSEvent.EventType { .scrollWheel }
    override var window: NSWindow? { targetWindow }
    override var locationInWindow: NSPoint { point }
    override var scrollingDeltaY: CGFloat { base.scrollingDeltaY }
    override var scrollingDeltaX: CGFloat { base.scrollingDeltaX }
    override var phase: NSEvent.Phase { gesturePhase }
    override var momentumPhase: NSEvent.Phase { base.momentumPhase }
    override var hasPreciseScrollingDeltas: Bool { base.hasPreciseScrollingDeltas }
}
