import AppKit
import Combine
import SwiftUI

/// Owns the actual macOS status item; the complete battery image is assigned
/// directly to its button rather than extracted from a SwiftUI scene label.
@MainActor
final class UsageMenuBarController: NSObject {
    let statusItem: NSStatusItem
    private let store: UsageStore
    private let prefs: Prefs
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    init(store: UsageStore, prefs: Prefs, onSettings: @escaping () -> Void) {
        self.store = store
        self.prefs = prefs
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.autosaveName = "SkillHanger.usage"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleDetail)
            button.imageScaling = .scaleNone
            button.publisher(for: \.effectiveAppearance)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.update() }
                .store(in: &cancellables)
        }
        let detail = NSHostingController(rootView: DetailView(
            store: store, prefs: prefs,
            onRefresh: { [weak store] in store?.refresh() },
            onSettings: { [weak self] in self?.popover.performClose(nil); onSettings() }
        ))
        detail.sizingOptions = .preferredContentSize
        popover.contentViewController = detail
        popover.behavior = .transient

        store.objectWillChange.merge(with: prefs.objectWillChange)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        update()
    }

    func stop() {
        cancellables.removeAll()
        popover.performClose(nil)
        statusItem.button?.target = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func update() {
        guard let button = statusItem.button else { return }
        let appearance = button.effectiveAppearance
        let scheme: ColorScheme = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        let image = UnifiedMenuLabel(usage: store, prefs: prefs).renderedImage(
            colorScheme: scheme, scale: button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        button.image = image
        button.title = ""
        button.toolTip = image.accessibilityDescription
        button.setAccessibilityLabel(image.accessibilityDescription)
        statusItem.length = ceil(image.size.width) + 8
        statusItem.isVisible = prefs.showMenuBar
        if !prefs.showMenuBar { popover.performClose(nil) }
    }

    @objc private func toggleDetail() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            store.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
