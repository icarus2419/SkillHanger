import Foundation

public struct MonitoringPolicy: Sendable {
    public var isEnabled: Bool
    public var preventsIdleSleep: Bool
    public var monitoredProviders: Set<Provider>

    public init(isEnabled: Bool = true, preventsIdleSleep: Bool = true,
                monitoredProviders: Set<Provider> = Set(Provider.allCases)) {
        self.isEnabled = isEnabled
        self.preventsIdleSleep = preventsIdleSleep
        self.monitoredProviders = monitoredProviders
    }

    public func visibleTasks(from tasks: [TaskRecord]) -> [TaskRecord] {
        guard isEnabled else { return [] }
        return tasks.filter { monitoredProviders.contains($0.provider) }
    }

    public func assertionTasks(from tasks: [TaskRecord]) -> [TaskRecord] {
        preventsIdleSleep ? visibleTasks(from: tasks) : []
    }
}
