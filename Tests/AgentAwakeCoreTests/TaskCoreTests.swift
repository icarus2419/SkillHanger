import Foundation
import Testing
@testable import AgentAwakeCore

private final class FakePower: PowerControlling {
    var acquisitions = 0
    var releases = 0
    func acquire() throws { acquisitions += 1 }
    func release() { releases += 1 }
}

@Test func concurrentTasksHoldOneAssertionUntilLastEnds() throws {
    let power = FakePower()
    let coordinator = AssertionCoordinator(power: power)
    let now = Date(timeIntervalSince1970: 1_000)
    let a = TaskRecord(id: "a", provider: .codex, state: .running, startedAt: now, observedAt: now, expiresAt: now.addingTimeInterval(120))
    let b = TaskRecord(id: "b", provider: .claude, state: .running, startedAt: now, observedAt: now, expiresAt: now.addingTimeInterval(120))
    try coordinator.sync(tasks: [a], now: now)
    try coordinator.sync(tasks: [a, b], now: now)
    #expect(power.acquisitions == 1)
    try coordinator.sync(tasks: [a.withState(.completed), b], now: now)
    #expect(power.releases == 0)
    #expect(power.acquisitions == 1)
    try coordinator.sync(tasks: [a.withState(.completed), b.withState(.failed)], now: now)
    #expect(power.releases == 1)
}

@Test func staleTaskBecomesUnknownAndReleases() throws {
    let power = FakePower()
    let coordinator = AssertionCoordinator(power: power)
    let now = Date(timeIntervalSince1970: 1_000)
    let task = TaskRecord(id: "a", provider: .codex, state: .running, startedAt: now, observedAt: now, expiresAt: now.addingTimeInterval(5))
    try coordinator.sync(tasks: [task], now: now)
    try coordinator.sync(tasks: [task], now: now.addingTimeInterval(6))
    #expect(power.releases == 1)
    #expect(task.effectiveState(at: now.addingTimeInterval(6)) == .unknown)
    #expect(task.isVisible(at: now.addingTimeInterval(6)))
    #expect(!task.isVisible(at: now.addingTimeInterval(606)))
}

@Test func eventsPreserveObservedUsageAndIgnoreOldEvents() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let running = TaskEvent(provider: .codex, taskID: "s1", state: .running, observedAt: start, leaseSeconds: 120, usage: TokenUsage(input: 12, output: 3))
    let first = TaskRecord.apply(running, to: nil)
    let finished = TaskEvent(provider: .codex, taskID: "s1", state: .completed, observedAt: start.addingTimeInterval(5), leaseSeconds: 120)
    let second = TaskRecord.apply(finished, to: first)
    #expect(second.state == .completed)
    #expect(second.usage == TokenUsage(input: 12, output: 3))
    #expect(TaskRecord.apply(running, to: second) == second)
}

@Test func sessionEndDoesNotEraseFailureOrCancellation() {
    let start = Date(timeIntervalSince1970: 1_000)
    for terminal in [TaskState.failed, .cancelled] {
        let first = TaskRecord.apply(TaskEvent(provider: .claude, taskID: "s", state: terminal, observedAt: start), to: nil)
        let ended = TaskRecord.apply(TaskEvent(provider: .claude, taskID: "s", state: .completed, observedAt: start.addingTimeInterval(1)), to: first)
        #expect(ended.state == terminal)
        let restarted = TaskRecord.apply(TaskEvent(provider: .claude, taskID: "s", state: .running, observedAt: start.addingTimeInterval(2), beginsTurn: true), to: ended)
        #expect(restarted.state == .running)
    }
}

@Test func lateToolEventCannotRestartCompletedTask() {
    let start = Date(timeIntervalSince1970: 1_000)
    let running = TaskRecord.apply(TaskEvent(provider: .codex, taskID: "s", state: .running, observedAt: start, beginsTurn: true), to: nil)
    let completed = TaskRecord.apply(TaskEvent(provider: .codex, taskID: "s", state: .completed, observedAt: start.addingTimeInterval(1)), to: running)
    let lateTool = TaskRecord.apply(TaskEvent(provider: .codex, taskID: "s", state: .running, observedAt: start.addingTimeInterval(2), milestone: true), to: completed)
    #expect(lateTool == completed)
    let nextTurn = TaskRecord.apply(TaskEvent(provider: .codex, taskID: "s", state: .running, observedAt: start.addingTimeInterval(3), beginsTurn: true), to: lateTool)
    #expect(nextTurn.state == .running)
    #expect(nextTurn.startedAt == start.addingTimeInterval(3))
}

@Test func observedMilestonesCountToolEventsWithoutClaimingCompletion() {
    let start = Date(timeIntervalSince1970: 1_000)
    let first = TaskRecord.apply(TaskEvent(provider: .claude, taskID: "s", state: .running, observedAt: start), to: nil)
    let second = TaskRecord.apply(TaskEvent(provider: .claude, taskID: "s", state: .running, observedAt: start.addingTimeInterval(1), milestone: true), to: first)
    #expect(second.milestones == 1)
    let done = TaskRecord.apply(TaskEvent(provider: .claude, taskID: "s", state: .completed, observedAt: start.addingTimeInterval(2)), to: second)
    let restarted = TaskRecord.apply(TaskEvent(provider: .claude, taskID: "s", state: .running, observedAt: start.addingTimeInterval(3), beginsTurn: true), to: done)
    #expect(restarted.milestones == 0)
}

@Test func existingSnapshotsDecodeWithoutMilestoneField() throws {
    let json = Data(#"{"id":"s","provider":"codex","state":"running","startedAt":1000,"observedAt":1000,"expiresAt":1120}"#.utf8)
    let record = try JSONDecoder().decode(TaskRecord.self, from: json)
    #expect(record.milestones == 0)
}

@Test func storePersistsOnlyAllowlistedMetadata() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TaskStore(directory: dir)
    let now = Date(timeIntervalSince1970: 1_000)
    let event = TaskEvent(provider: .claude, taskID: "../../secret", state: .running, observedAt: now, leaseSeconds: 120)
    try store.apply(event)
    let records = try store.load()
    #expect(records.count == 1)
    #expect(records[0].id == "../../secret")
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }.count == 1)
}

@Test func pruningKeepsActiveAndRecentTasksButRemovesExpiredHistory() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TaskStore(directory: dir)
    let start = Date(timeIntervalSince1970: 1_000)
    try store.apply(TaskEvent(provider: .codex, taskID: "old", state: .completed, observedAt: start))
    try store.apply(TaskEvent(provider: .claude, taskID: "recent", state: .failed, observedAt: start.addingTimeInterval(250)))
    try store.apply(TaskEvent(provider: .codex, taskID: "active", state: .running, observedAt: start.addingTimeInterval(300), leaseSeconds: 120))
    try store.prune(at: start.addingTimeInterval(400))
    #expect(Set(try store.load().map(\.id)) == Set(["recent", "active"]))
    try store.prune(at: start.addingTimeInterval(1_100))
    #expect(try store.load().isEmpty)
}

@Test func supervisedHeartbeatPreservesWaitingAndTerminalStates() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TaskStore(directory: dir)
    let start = Date(timeIntervalSince1970: 1_000)
    try store.apply(TaskEvent(provider: .codex, taskID: "wrapped", state: .running, observedAt: start, leaseSeconds: 8, beginsTurn: true))
    try store.apply(TaskEvent(provider: .codex, taskID: "wrapped", state: .waiting, observedAt: start.addingTimeInterval(1), leaseSeconds: 8))
    try store.heartbeat(provider: .codex, id: "wrapped", observedAt: start.addingTimeInterval(2), leaseSeconds: 8)
    let waiting = try #require(store.load().first)
    #expect(waiting.state == .waiting)
    #expect(waiting.expiresAt == start.addingTimeInterval(10))
    try store.apply(TaskEvent(provider: .codex, taskID: "wrapped", state: .completed, observedAt: start.addingTimeInterval(3)))
    try store.heartbeat(provider: .codex, id: "wrapped", observedAt: start.addingTimeInterval(4), leaseSeconds: 8)
    #expect(try store.load().first?.state == .completed)
}

@Test func supervisedExitKeepsProviderFailureAndOverridesFalseCompletion() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TaskStore(directory: dir)
    let start = Date(timeIntervalSince1970: 1_000)
    try store.apply(TaskEvent(provider: .claude, taskID: "failed", state: .failed, observedAt: start))
    try store.finish(provider: .claude, id: "failed", state: .completed, observedAt: start.addingTimeInterval(1))
    #expect(try store.load().first { $0.id == "failed" }?.state == .failed)
    try store.apply(TaskEvent(provider: .codex, taskID: "nonzero", state: .completed, observedAt: start))
    try store.finish(provider: .codex, id: "nonzero", state: .failed, observedAt: start.addingTimeInterval(1))
    #expect(try store.load().first { $0.id == "nonzero" }?.state == .failed)
}

@Test func usageCanArriveAfterProviderStopWithoutRevivingTask() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TaskStore(directory: dir)
    let start = Date(timeIntervalSince1970: 1_000)
    try store.apply(TaskEvent(provider: .claude, taskID: "wrapped", state: .completed, observedAt: start))
    try store.observeUsage(provider: .claude, id: "wrapped", usage: TokenUsage(input: 120, output: 15))
    let record = try #require(store.load().first)
    #expect(record.state == .completed)
    #expect(record.usage == TokenUsage(input: 120, output: 15))
}
