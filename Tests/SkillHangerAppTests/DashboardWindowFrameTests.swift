import AppKit
import Testing
@testable import AgentAwakeApp

struct DashboardWindowFrameTests {
    @Test func oversizedSavedWindowFitsCompletelyInsideTheVisibleScreen() {
        let saved = NSRect(x: 1001, y: -899, width: 1187, height: 1843)
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let fitted = DashboardWindowFrame.fit(saved, in: visible)
        #expect(fitted.width == 1187)
        #expect(fitted.height == 920)
        #expect(visible.contains(fitted))
    }

    @Test func validWindowKeepsItsSizeAndPosition() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let window = NSRect(x: 100, y: 100, width: 940, height: 660)
        #expect(DashboardWindowFrame.fit(window, in: visible) == window)
    }

    @Test func compactScreenAllowsAWindowSmallerThanTheOldMinimum() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 600)
        let fitted = DashboardWindowFrame.fit(NSRect(x: 0, y: 0, width: 1180, height: 820), in: visible)
        let minimum = DashboardWindowFrame.minimumSize(in: visible)
        #expect(visible.contains(fitted))
        #expect(minimum.width <= fitted.width)
        #expect(minimum.height <= fitted.height)
    }
}
