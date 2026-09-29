import AgentAwakeCore
import Foundation
import Testing
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct MonitorSettingsTests {
    @Test func controlsReleaseProtectionImmediatelyWithoutDeletingTaskRecords() throws {
        let name = "SkillHanger.Monitor.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: folder)
        }
        let store = TaskStore(directory: folder)
        try store.apply(TaskEvent(provider: .codex, taskID: "task", state: .running))
        let power = SettingsPower()
        let model = MonitorModel(defaults: defaults, taskStore: store, power: power, integratesWithSystem: false)
        #expect(power.acquisitions == 0)
        model.start()
        defer { model.stop() }
        #expect(model.isKeepingAwake)
        model.preventsIdleSleep = false
        #expect(!model.isKeepingAwake)
        #expect(model.tasks.count == 1)
        model.preventsIdleSleep = true
        #expect(model.isKeepingAwake)
        model.monitorCodex = false
        #expect(!model.isKeepingAwake)
        #expect(model.tasks.isEmpty)
        model.monitorCodex = true
        #expect(model.isKeepingAwake)
        model.isMonitoringEnabled = false
        #expect(!model.isKeepingAwake)
        #expect(try store.load().count == 1)
        #expect(defaults.bool(forKey: "monitoringEnabled") == false)
    }
}

private final class SettingsPower: PowerControlling {
    var acquisitions = 0
    func acquire() throws { acquisitions += 1 }
    func release() {}
}
