import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private var panels: [NSPanel] = []

    func show(model: MonitorModel) {
        guard panels.isEmpty else { return }
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: OverlayView(model: model))
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }
}
