import AppKit
import SwiftUI

enum DashboardWindowFrame {
    static let margin: CGFloat = 12

    static func usableFrame(in visible: NSRect) -> NSRect {
        let horizontal = min(margin, max(0, visible.width / 4))
        let vertical = min(margin, max(0, visible.height / 4))
        return visible.insetBy(dx: horizontal, dy: vertical)
    }

    static func minimumSize(in visible: NSRect) -> NSSize {
        let usable = usableFrame(in: visible)
        return NSSize(width: min(940, usable.width), height: min(660, usable.height))
    }

    static func fit(_ frame: NSRect, in visible: NSRect) -> NSRect {
        let usable = usableFrame(in: visible)
        guard usable.width > 0, usable.height > 0 else { return frame }
        let width = frame.width.isFinite && frame.width > 0 ? min(frame.width, usable.width) : usable.width
        let height = frame.height.isFinite && frame.height > 0 ? min(frame.height, usable.height) : usable.height
        let x = frame.minX.isFinite ? min(max(frame.minX, usable.minX), usable.maxX - width) : usable.minX
        let y = frame.minY.isFinite ? min(max(frame.minY, usable.minY), usable.maxY - height) : usable.minY
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

/// Routes native scrolling before SwiftUI's child views can consume the gesture.
final class DashboardWindow: NSWindow {
    private var screenObservers: [NSObjectProtocol] = []
    private var adjustingFrame = false

    func fitToVisibleScreen() {
        guard !adjustingFrame else { return }
        let intersectingScreens = NSScreen.screens.filter { $0.visibleFrame.intersects(frame) }
        guard let target = intersectingScreens.max(by: {
            let first = $0.visibleFrame.intersection(frame)
            let second = $1.visibleFrame.intersection(frame)
            return first.width * first.height < second.width * second.height
        }) ?? screen ?? NSScreen.main else { return }
        adjustingFrame = true
        defer { adjustingFrame = false }
        let visible = target.visibleFrame
        minSize = DashboardWindowFrame.minimumSize(in: visible)
        maxSize = DashboardWindowFrame.usableFrame(in: visible).size
        let fitted = DashboardWindowFrame.fit(frame, in: visible)
        if fitted != frame { setFrame(fitted, display: true) }
        if screenObservers.isEmpty {
            for name in [NSApplication.didChangeScreenParametersNotification, NSWindow.didChangeScreenNotification] {
                screenObservers.append(NotificationCenter.default.addObserver(forName: name, object: name == NSWindow.didChangeScreenNotification ? self : nil,
                    queue: .main) { [weak self] _ in self?.fitToVisibleScreen() })
            }
        }
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let target = screen ?? self.screen else { return super.constrainFrameRect(frameRect, to: screen) }
        return DashboardWindowFrame.fit(frameRect, in: target.visibleFrame)
    }

    deinit { screenObservers.forEach(NotificationCenter.default.removeObserver) }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, attachedSheet == nil,
           let dashboard = contentView as? DashboardHostingView {
            dashboard.dismissSwipes()
        }
        if (event.type == .leftMouseDown || event.type == .rightMouseDown), attachedSheet == nil,
           let dashboard = contentView as? DashboardHostingView {
            dashboard.dismissSwipes(unlessContaining: event)
        }
        if event.type == .scrollWheel, attachedSheet == nil,
           let dashboard = contentView as? DashboardHostingView {
            dashboard.scrollWheel(with: event)
            return
        }
        super.sendEvent(event)
    }
}

/// Keeps two-finger scrolling available over the dashboard's header and margins.
final class DashboardHostingView: NSHostingView<DashboardView> {
    private weak var activeSwipeRegion: SidebarSwipeRegionView?
    private weak var activeScrollView: NSScrollView?
    private let registeredSwipeRegions = NSHashTable<SidebarSwipeRegionView>.weakObjects()

    required init(rootView: DashboardView) {
        super.init(rootView: rootView)
        // The native window owns its screen-aware size. A notice or long page
        // must scroll within that window, rather than expand its minimum size.
        sizingOptions = []
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    func registerSwipeRegion(_ region: SidebarSwipeRegionView) { registeredSwipeRegions.add(region) }

    private var swipeRegions: [SidebarSwipeRegionView] {
        registeredSwipeRegions.allObjects.filter { $0.window === window && $0.isDescendant(of: self) }
    }
    override func scrollWheel(with event: NSEvent) {
        let beginning = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        let ending = event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended)
        if beginning { activeSwipeRegion = nil; activeScrollView = nil }
        if let activeSwipeRegion, activeSwipeRegion.handleScroll(event) { return }
        self.activeSwipeRegion = nil
        if !beginning, let activeScrollView, activeScrollView.window === window {
            if ending { self.activeScrollView = nil }
            applyVerticalScroll(event, to: activeScrollView)
            return
        }
        activeScrollView = nil
        let regionUnderPointer = swipeRegions.first(where: { $0.contains(event) })
        if let region = regionUnderPointer, region.handleScroll(event) {
            activeSwipeRegion = region
            return
        }
        if regionUnderPointer == nil || abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            dismissSwipes()
        }
        let candidates = scrollViews(in: self)
        let underPointer: NSScrollView? = event.window === window && event.window != nil ? candidates.first {
            $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) &&
            ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height
        } : nil
        // The sidebar can now contain installed-package tabs. Header/margin
        // gestures still belong to the main page, which has the widest viewport.
        guard let scrollView = underPointer ?? candidates.max(by: { $0.bounds.width < $1.bounds.width }),
              scrollView.documentView != nil else {
            super.scrollWheel(with: event)
            return
        }
        // Some devices send standalone changed events without a began/ended
        // pair. Cache only gestures with a clear start, so separate events can
        // still choose the scroll view under their own pointer position.
        if !ending && (beginning || !event.momentumPhase.isEmpty) { activeScrollView = scrollView }
        applyVerticalScroll(event, to: scrollView)
    }

    private func applyVerticalScroll(_ event: NSEvent, to scrollView: NSScrollView) {
        guard let document = scrollView.documentView else { return }
        // SwiftUI's scroll view can reject phased trackpad events forwarded from
        // another responder. Apply each native delta to its clip view instead.
        // Precise deltas already use points; a wheel/trackball uses line increments.
        let clip = scrollView.contentView
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : scrollView.verticalLineScroll)
        guard delta.isFinite, delta != 0 else { return }
        let minimum = document.bounds.minY
        let maximum = max(minimum, document.bounds.maxY - clip.bounds.height)
        var origin = clip.bounds.origin
        origin.y = min(maximum, max(minimum, origin.y - delta))
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    func dismissSwipes(unlessContaining event: NSEvent? = nil) {
        for region in swipeRegions where region.isRevealed {
            if let event, region.contains(event) { continue }
            region.onDismiss()
        }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        for child in view.subviews {
            // A page viewport is the routing boundary. Do not walk every row,
            // text field, and image inside its document on every wheel event.
            if let scroll = child as? NSScrollView { result.append(scroll) }
            else { result += scrollViews(in: child) }
        }
        return result
    }
}
