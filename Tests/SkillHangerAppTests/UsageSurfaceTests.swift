import AppKit
import SwiftUI
import Testing
import UsageCore
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct UsageSurfaceTests {
    @Test func menuBarReceivesAnImageInsteadOfFlatteningBatteriesIntoText() {
        let runtime = AppRuntime(preview: true)
        // MenuBarExtra extracts text/images from its label; arbitrary battery
        // shapes must be rendered into a single image to preserve both cells.
        #expect((UnifiedMenuLabel(runtime: runtime).body as Any) is Image)
    }

    @Test func bothMenuBarBatteriesFitAndRedrawWhenTheMetricChanges() throws {
        let runtime = AppRuntime(preview: true)
        let label = UnifiedMenuLabel(runtime: runtime)
        let image = label.renderedImage(colorScheme: .dark, scale: 2)
        #expect(image.size.width > 70)
        #expect(image.size.height <= 22)
        #expect(!image.isTemplate)
        #expect(image.accessibilityDescription?.contains("Claude") == true)
        #expect(image.accessibilityDescription?.contains("OpenAI") == true)
        runtime.prefs.metric = .weekly
        let changed = label.renderedImage(colorScheme: .dark, scale: 2)
        #expect(changed.size == image.size)
        #expect(changed.tiffRepresentation != image.tiffRepresentation)
        runtime.prefs.showClaude = false
        #expect(label.renderedImage(colorScheme: .light, scale: 2).size.width < image.size.width)
        if let directory = ProcessInfo.processInfo.environment["SKILLHANGER_USAGE_PREVIEWS"] {
            for appearance in [ColorScheme.light, .dark] {
                runtime.prefs.showClaude = true
                let rendered = label.renderedImage(colorScheme: appearance, scale: 2)
                let data = try #require(rendered.tiffRepresentation)
                let bitmap = try #require(NSBitmapImageRep(data: data))
                try #require(bitmap.representation(using: .png, properties: [:])).write(
                    to: URL(fileURLWithPath: directory).appendingPathComponent("menubar-\(appearance).png"))
            }
        }
    }

    @Test func nativeMenuBarOwnsTwoVisibleBatteriesAndFollowsPreferences() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let runtime = AppRuntime(preview: true)
        let controller = UsageMenuBarController(store: runtime.usage, prefs: runtime.prefs, onSettings: {})
        defer { controller.stop() }
        let item = controller.statusItem
        let button = try #require(item.button)
        let image = try #require(button.image)
        #expect(item.isVisible)
        #expect(image.size.width > 70)
        #expect(item.length >= image.size.width)
        #expect(button.accessibilityLabel()?.contains("Claude") == true)
        #expect(button.accessibilityLabel()?.contains("OpenAI") == true)
        runtime.prefs.metric = .weekly
        try await Task.sleep(for: .milliseconds(150))
        #expect(button.image?.tiffRepresentation != image.tiffRepresentation)
        runtime.prefs.showMenuBar = false
        try await Task.sleep(for: .milliseconds(150))
        #expect(!item.isVisible)
        runtime.prefs.showMenuBar = true
        try await Task.sleep(for: .milliseconds(150))
        #expect(item.isVisible)
        #expect(button.image != nil)
    }

    @Test func floatingWidgetPollsAutomaticallyWhileTheAppIsInactive() async throws {
        let name = "SkillHanger.Poll.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Prefs(defaults: defaults)
        prefs.showClaude = false
        prefs.alerts = false
        prefs.refreshMinutes = 1
        let requests = PollRequests()
        let store = UsageStore(prefs: prefs, defaults: defaults,
                               logRoot: URL(fileURLWithPath: "/nonexistent-test-sessions"),
                               workspaceNotifications: NotificationCenter()) { _, _ in
            let number = await requests.next()
            return ProviderUsage(provider: .openai, plan: "Test", session:
                UsageWindow(kind: .session, label: "5-hour", usedPercent: number == 1 ? 20 : 55,
                            resetsAt: nil, windowSeconds: 18000),
                weekly: nil, observedAt: Date(), source: .api)
        }
        let controller = WidgetController(store: store, prefs: prefs)
        let panel = try #require(Mirror(reflecting: controller).children.first { $0.label == "panel" }?.value as? WidgetPanel)
        let container = try #require(panel.contentView as? WidgetContainerView)
        defer { store.stop(); panel.close() }
        store.start()
        for _ in 0..<320 where container.toolTip?.contains("45%") != true {
            try await Task.sleep(for: .milliseconds(250))
        }
        #expect(await requests.count >= 2)
        #expect(store.reading(for: .openai).percent == 45)
        #expect(container.toolTip?.contains("45%") == true)
        #expect(!panel.isKeyWindow)
        #expect(!panel.isMainWindow)
    }

    @Test func floatingWidgetRedrawsAfterLocalUsageChangesWithoutAClick() async throws {
        let name = "SkillHanger.Widget.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let prefs = Prefs(defaults: defaults)
        prefs.showClaude = false
        prefs.alerts = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: name)
        }
        let file = root.appendingPathComponent("rollout.jsonl")
        func write(used: Int, at date: Date) throws {
            let stamp = ISO8601DateFormatter().string(from: date)
            try Data("{\"timestamp\":\"\(stamp)\",\"payload\":{\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":\(used),\"window_minutes\":300}}}}\n".utf8).write(to: file)
        }
        try write(used: 30, at: Date().addingTimeInterval(-2))
        let store = UsageStore(prefs: prefs, defaults: defaults, logRoot: root,
                               workspaceNotifications: NotificationCenter()) { _, _ in
            throw UsageError.network("Offline regression test")
        }
        let controller = WidgetController(store: store, prefs: prefs)
        let panel = try #require(Mirror(reflecting: controller).children.first { $0.label == "panel" }?.value as? WidgetPanel)
        let container = try #require(panel.contentView as? WidgetContainerView)
        defer { store.stop(); panel.close() }
        store.start()
        for _ in 0..<80 where store.reading(for: .openai).percent != 70 {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(300))
        let before = try rendered(container.hosting)
        try write(used: 65, at: Date())
        for _ in 0..<80 where container.toolTip?.contains("35%") != true {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.reading(for: .openai).percent == 35)
        #expect(container.toolTip?.contains("35%") == true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(try rendered(container.hosting) != before)
        #expect(!panel.isKeyWindow)
        #expect(!panel.isMainWindow)
    }

    private func rendered(_ view: NSView) throws -> Data {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

private actor PollRequests {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}
