import AppKit
import SwiftUI
import Testing
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct SidebarNativeTests {
    @Test func trackpadPhasesSettleTheRevealAndMomentumDoesNotReopenIt() {
        let region = SidebarSwipeRegionView()
        region.enabled = true
        var swipe = InstalledRowSwipe(initiallyOpen: false)
        var open = false
        var finishes = 0
        region.onBegin = { swipe = InstalledRowSwipe(initiallyOpen: open) }
        region.onUpdate = { swipe.update(translation: $0) }
        region.onFinish = { cancelled in open = swipe.finish(cancelled: cancelled); finishes += 1 }
        #expect(region.handleScroll(SidebarTestScroll(x: -2, y: 0, phase: .began)))
        #expect(region.handleScroll(SidebarTestScroll(x: -42, y: 1, phase: .changed)))
        #expect(region.handleScroll(SidebarTestScroll(x: 0, y: 0, phase: .ended)))
        #expect(open)
        #expect(finishes == 1)
        #expect(region.handleScroll(SidebarTestScroll(x: -50, y: 1, momentum: .changed)))
        #expect(finishes == 1)
        #expect(region.handleScroll(SidebarTestScroll(x: 0, y: 0, momentum: .ended)))
        #expect(region.handleScroll(SidebarTestScroll(x: 42, y: 0, phase: .began)))
        #expect(region.handleScroll(SidebarTestScroll(x: 0, y: 0, phase: .ended)))
        #expect(!open)
        #expect(finishes == 2)
    }

    @Test func verticalInputFallsThroughAndCancellingARevealDoesNotUninstall() {
        let region = SidebarSwipeRegionView()
        region.enabled = true
        var swipe = InstalledRowSwipe(initiallyOpen: false)
        var open = false
        region.onBegin = { swipe = InstalledRowSwipe(initiallyOpen: open) }
        region.onUpdate = { swipe.update(translation: $0) }
        region.onFinish = { open = swipe.finish(cancelled: $0) }
        #expect(!region.handleScroll(SidebarTestScroll(x: -2, y: -12, phase: .began)))
        #expect(!region.handleScroll(SidebarTestScroll(x: -30, y: -20, phase: .changed)))
        #expect(!region.handleScroll(SidebarTestScroll(x: 0, y: 0, phase: .ended)))
        #expect(!open)
        #expect(region.handleScroll(SidebarTestScroll(x: -40, y: 1, phase: .began)))
        #expect(region.handleScroll(SidebarTestScroll(x: 0, y: 0, phase: .cancelled)))
        #expect(!open)
        region.enabled = false
        #expect(!region.handleScroll(SidebarTestScroll(x: -40, y: 1, phase: .began)))
    }

    @Test func sidebarRowHasAFullWidthNonBlockingHitRegion() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let item = try #require(CatalogLoader.bundled().first { $0.name == "caveman" && $0.kind == .skill })
        let workspace = InstalledPackage(item: item, agent: .codex)
        let row = InstalledPackageSidebarRow(workspace: workspace, selected: false, disabled: false,
            canUninstall: true, busy: false, preview: false, revealedSelection: .constant(nil),
            action: {}, uninstall: {}, fullSwipeUninstall: {})
        let hosting = NSHostingView(rootView: row.padding(12).background(ShellPalette.sidebar).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 188, height: 72),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        let region = try #require(regions(in: hosting).first)
        #expect(region.bounds.width >= 164)
        #expect(region.bounds.height >= 48)
        #expect(region.hitTest(NSPoint(x: 2, y: 2)) == nil)
        #expect(region.hitTest(NSPoint(x: region.bounds.maxX - 2, y: region.bounds.maxY - 2)) == nil)
        // Optional local visual artifact; never captures another app or screen.
        if let output = ProcessInfo.processInfo.environment["SKILLHANGER_ROW_PREVIEW"],
           let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try data.write(to: URL(fileURLWithPath: output))
            }
            hosting.rootView = InstalledPackageSidebarRow(workspace: workspace, selected: false, disabled: false,
                canUninstall: true, busy: false, preview: false, revealedSelection: .constant(workspace.selection),
                action: {}, uninstall: {}, fullSwipeUninstall: {}).padding(12).background(ShellPalette.sidebar).preferredColorScheme(.dark)
            try await Task.sleep(for: .milliseconds(150))
            hosting.layoutSubtreeIfNeeded()
            if let revealedBitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: revealedBitmap)
                if let data = revealedBitmap.representation(using: .png, properties: [:]) {
                    let revealedURL = URL(fileURLWithPath: output).deletingPathExtension().appendingPathExtension("revealed.png")
                    try data.write(to: revealedURL)
                }
            }
        }
    }

    @Test func beginningAnotherRowGestureClosesThePreviousReveal() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let items = try CatalogLoader.bundled().filter { $0.kind == .skill && $0.agents.contains(.codex) }
        let first = try #require(items.first)
        let second = try #require(items.first { $0.id != first.id })
        let firstWorkspace = InstalledPackage(item: first, agent: .codex)
        let secondWorkspace = InstalledPackage(item: second, agent: .codex)
        var selection: PackageSelection? = firstWorkspace.selection
        let binding = Binding<PackageSelection?>(get: { selection }, set: { selection = $0 })
        let rows = VStack {
            InstalledPackageSidebarRow(workspace: firstWorkspace, selected: false, disabled: false,
                canUninstall: true, busy: false, preview: false, revealedSelection: binding,
                action: {}, uninstall: {}, fullSwipeUninstall: {})
            InstalledPackageSidebarRow(workspace: secondWorkspace, selected: false, disabled: false,
                canUninstall: true, busy: false, preview: false, revealedSelection: binding,
                action: {}, uninstall: {}, fullSwipeUninstall: {})
        }
        let hosting = NSHostingView(rootView: rows.frame(width: 220).background(ShellPalette.sidebar))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 104),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
        let region = try #require(regions(in: hosting).last)
        #expect(!region.handleScroll(SidebarTestScroll(x: 0, y: -10, phase: .began)))
        #expect(!region.handleScroll(SidebarTestScroll(x: 0, y: -20, phase: .changed)))
        #expect(selection == nil)
        #expect(!region.handleScroll(SidebarTestScroll(x: 0, y: 0, phase: .ended)))
        #expect(selection == nil)
        #expect(region.handleScroll(SidebarTestScroll(x: -4, y: 0, phase: .began)))
        #expect(region.handleScroll(SidebarTestScroll(x: -30, y: 0, phase: .changed)))
        #expect(selection == nil)
    }

    @Test func fullSwipeRunsTheInstalledRowsRemovalActionOnce() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let item = try #require(CatalogLoader.bundled().first { $0.name == "caveman" && $0.kind == .skill })
        let workspace = InstalledPackage(item: item, agent: .codex)
        var confirmations = 0
        var fullSwipes = 0
        let row = InstalledPackageSidebarRow(workspace: workspace, selected: false, disabled: false,
            canUninstall: true, busy: false, preview: false, revealedSelection: .constant(nil),
            action: {}, uninstall: { confirmations += 1 }, fullSwipeUninstall: { fullSwipes += 1 })
        let hosting = NSHostingView(rootView: row.frame(width: 220).background(ShellPalette.sidebar))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 48),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
        let region = try #require(regions(in: hosting).first)
        #expect(region.handleScroll(SidebarTestScroll(x: -80, y: 0, phase: .began)))
        #expect(region.handleScroll(SidebarTestScroll(x: -80, y: 0, phase: .changed)))
        #expect(region.handleScroll(SidebarTestScroll(x: 0, y: 0, phase: .ended)))
        #expect(fullSwipes == 1)
        #expect(confirmations == 0)
    }

    private func regions(in view: NSView) -> [SidebarSwipeRegionView] {
        ((view as? SidebarSwipeRegionView).map { [$0] } ?? []) + view.subviews.flatMap(regions)
    }
}

private final class SidebarTestScroll: NSEvent {
    private let x: CGFloat
    private let y: CGFloat
    private let gesturePhase: NSEvent.Phase
    private let momentum: NSEvent.Phase
    init(x: CGFloat, y: CGFloat, phase: NSEvent.Phase = [], momentum: NSEvent.Phase = []) {
        self.x = x; self.y = y; self.gesturePhase = phase; self.momentum = momentum
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("Not used by these tests") }
    override var type: NSEvent.EventType { .scrollWheel }
    override var scrollingDeltaX: CGFloat { x }
    override var scrollingDeltaY: CGFloat { y }
    override var hasPreciseScrollingDeltas: Bool { true }
    override var phase: NSEvent.Phase { gesturePhase }
    override var momentumPhase: NSEvent.Phase { momentum }
}
