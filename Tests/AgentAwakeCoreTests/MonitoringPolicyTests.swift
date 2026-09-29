import Foundation
import Testing
@testable import AgentAwakeCore

@Test func disablingSleepProtectionReleasesAnExistingAssertion() throws {
    let power = PolicyPower()
    let coordinator = AssertionCoordinator(power: power)
    let task = policyTask(.codex)
    try coordinator.sync(tasks: [task])
    let policy = MonitoringPolicy(preventsIdleSleep: false)
    try coordinator.sync(tasks: policy.assertionTasks(from: [task]))
    #expect(!coordinator.isHolding)
    #expect(power.released)
    #expect(policy.visibleTasks(from: [task]).count == 1)
}

@Test func disablingMonitoringRemovesTasksAndProtection() {
    let policy = MonitoringPolicy(isEnabled: false)
    #expect(policy.visibleTasks(from: [policyTask(.codex)]).isEmpty)
    #expect(policy.assertionTasks(from: [policyTask(.codex)]).isEmpty)
}

@Test func excludedProvidersCannotPreventSleep() throws {
    let policy = MonitoringPolicy(monitoredProviders: [.claude])
    let tasks = [policyTask(.codex), policyTask(.claude)]
    #expect(policy.visibleTasks(from: tasks).map(\.provider) == [.claude])
    let coordinator = AssertionCoordinator(power: PolicyPower())
    try coordinator.sync(tasks: policy.assertionTasks(from: [tasks[0]]))
    #expect(!coordinator.isHolding)
}

private func policyTask(_ provider: Provider) -> TaskRecord {
    let now = Date()
    return TaskRecord(id: provider.rawValue, provider: provider, state: .running,
                      startedAt: now, observedAt: now, expiresAt: now.addingTimeInterval(120))
}

private final class PolicyPower: PowerControlling {
    var released = false
    func acquire() throws {}
    func release() { released = true }
}
