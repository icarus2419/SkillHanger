import AppKit
import SwiftUI

/// A non-interactive background registers the row for native horizontal scroll
/// routing. SwiftUI retains the full-width button and its context menu.
struct SidebarSwipeRegion: NSViewRepresentable {
    let enabled: Bool
    let isRevealed: Bool
    let onBegin: () -> Void
    let onUpdate: (CGSize) -> Bool
    let onFinish: (Bool) -> Void
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> SidebarSwipeRegionView { SidebarSwipeRegionView() }
    func updateNSView(_ view: SidebarSwipeRegionView, context: Context) {
        view.enabled = enabled
        view.isRevealed = isRevealed
        view.onBegin = onBegin; view.onUpdate = onUpdate; view.onFinish = onFinish
        view.onDismiss = onDismiss
    }
}

final class SidebarSwipeRegionView: NSView {
    var enabled = false
    var isRevealed = false
    var onBegin: () -> Void = {}
    var onUpdate: (CGSize) -> Bool = { _ in false }
    var onFinish: (Bool) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    private var translation = CGSize.zero
    private var tracking = false
    private var horizontal = false
    private var settleWork: DispatchWorkItem?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func contains(_ event: NSEvent) -> Bool {
        event.window != nil && event.window === window && !isHiddenOrHasHiddenAncestor &&
        visibleRect.contains(convert(event.locationInWindow, from: nil))
    }

    func handleScroll(_ event: NSEvent) -> Bool {
        guard enabled, event.hasPreciseScrollingDeltas else { return false }
        if !event.momentumPhase.isEmpty {
            let consumed = horizontal
            if event.momentumPhase.contains(.ended) { horizontal = false }
            return consumed
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            settleWork?.cancel()
            translation = .zero; horizontal = false; tracking = true
            onBegin()
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let consumed = horizontal
            settleWork?.cancel()
            if tracking { onFinish(event.phase.contains(.cancelled)) }
            tracking = false
            return consumed
        }
        if !tracking {
            translation = .zero; horizontal = false; tracking = true
            onBegin()
        }
        guard event.scrollingDeltaX.isFinite, event.scrollingDeltaY.isFinite else { return false }
        translation.width += event.scrollingDeltaX
        translation.height += event.scrollingDeltaY
        horizontal = onUpdate(translation)
        // Precise devices without gesture phases still get a bounded settle.
        if event.phase.isEmpty {
            settleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.tracking else { return }
                self.onFinish(false); self.tracking = false; self.horizontal = false
            }
            settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        return horizontal
    }

    deinit { settleWork?.cancel() }
}
