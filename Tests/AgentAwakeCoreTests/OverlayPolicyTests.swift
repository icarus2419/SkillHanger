import Foundation
import Testing
@testable import AgentAwakeCore

@Test func overlayWaitsForIdleAndDismissesOnInputWithoutChangingTask() {
    let now = Date(timeIntervalSince1970: 1_000)
    let task = TaskRecord(id: "one", provider: .codex, state: .running, startedAt: now, observedAt: now, expiresAt: now.addingTimeInterval(120))
    #expect(!OverlayPolicy.shouldShow(tasks: [task], now: now, idleSeconds: 29, threshold: 30))
    #expect(OverlayPolicy.shouldShow(tasks: [task], now: now, idleSeconds: 30, threshold: 30))
    #expect(!OverlayPolicy.shouldShow(tasks: [task], now: now, idleSeconds: 0, threshold: 30))
    #expect(OverlayPolicy.shouldShow(tasks: [task.withState(.waiting)], now: now, idleSeconds: 30, threshold: 30))
    #expect(!OverlayPolicy.shouldShow(tasks: [task.withState(.completed)], now: now, idleSeconds: 30, threshold: 30))
    #expect(!OverlayPolicy.shouldShow(tasks: [task], now: now, idleSeconds: 30, threshold: 0))
}
