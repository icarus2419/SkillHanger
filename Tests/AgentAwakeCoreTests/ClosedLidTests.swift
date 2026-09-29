import Darwin
import Foundation
import Testing
@testable import AgentAwakeCore

private let boot = "test-boot"
private func lease(enabled: Bool = true, tasks: Int = 1, issued: Double = 100) -> ClosedLidLease {
    ClosedLidLease(enabled: enabled, runningTasks: tasks, issuedUptime: issued, expiresUptime: issued + 8, bootID: boot)
}

@Test func closedLidRequiresFreshOptInActivityAndSafePower() {
    #expect(ClosedLidPolicy.reason(lease: lease(), uptime: 101, bootID: boot, battery: 74, thermal: .nominal, alreadyActive: false) == .active)
    #expect(ClosedLidPolicy.reason(lease: lease(enabled: false), uptime: 101, bootID: boot, battery: 74, thermal: .nominal, alreadyActive: false) == .off)
    #expect(ClosedLidPolicy.reason(lease: lease(tasks: 0), uptime: 101, bootID: boot, battery: 74, thermal: .nominal, alreadyActive: true) == .idle)
    #expect(ClosedLidPolicy.reason(lease: lease(), uptime: 109, bootID: boot, battery: 74, thermal: .nominal, alreadyActive: true) == .expired)
    #expect(ClosedLidPolicy.reason(lease: lease(), uptime: 101, bootID: "other", battery: 74, thermal: .nominal, alreadyActive: true) == .expired)
    #expect(ClosedLidPolicy.reason(lease: lease(issued: 110), uptime: 101, bootID: boot, battery: 74, thermal: .nominal, alreadyActive: false) == .expired)
    #expect(ClosedLidPolicy.reason(lease: lease(tasks: -1), uptime: 101, bootID: boot, battery: 74, thermal: .nominal, alreadyActive: false) == .expired)
    #expect(ClosedLidPolicy.reason(lease: lease(), uptime: 101, bootID: boot, battery: nil, thermal: .nominal, alreadyActive: true) == .battery)
    #expect(ClosedLidPolicy.reason(lease: lease(), uptime: 101, bootID: boot, battery: 29, thermal: .nominal, alreadyActive: false) == .battery)
    #expect(ClosedLidPolicy.reason(lease: lease(), uptime: 101, bootID: boot, battery: 29, thermal: .nominal, alreadyActive: true) == .active)
    #expect(ClosedLidPolicy.reason(lease: lease(), uptime: 101, bootID: boot, battery: 20, thermal: .nominal, alreadyActive: true) == .battery)
    #expect(ClosedLidPolicy.reason(lease: lease(), uptime: 101, bootID: boot, battery: 74, thermal: .serious, alreadyActive: true) == .thermal)
}

private final class Setting: ClosedLidSettingControlling {
    var value = 0
    var refuseRestore = false
    func read() throws -> Int { value }
    func set(_ value: Int) throws {
        if value == 0 && refuseRestore { throw CocoaError(.fileWriteUnknown) }
        self.value = value
    }
}
private final class Marker: ClosedLidRecoveryStoring {
    var exists = false
    func mark() throws { exists = true }
    func clear() throws { exists = false }
}

@Test func closedLidRestoresWhenLastTaskStopsOrLeaseExpires() throws {
    let setting = Setting(), marker = Marker()
    let controller = ClosedLidCoordinator(setting: setting, recovery: marker)
    #expect(try controller.sync(reason: .active) == .active)
    #expect(setting.value == 1 && marker.exists)
    #expect(try controller.sync(reason: .idle) == .idle)
    #expect(setting.value == 0 && !marker.exists)
    _ = try controller.sync(reason: .active)
    #expect(try controller.sync(reason: .expired) == .expired)
    #expect(setting.value == 0 && !marker.exists)
}

@Test func closedLidDoesNotTakeOwnershipOfAnotherUtility() throws {
    let setting = Setting(), marker = Marker()
    setting.value = 1
    let controller = ClosedLidCoordinator(setting: setting, recovery: marker)
    #expect(try controller.sync(reason: .active) == .conflict)
    #expect(try controller.sync(reason: .off) == .off)
    #expect(setting.value == 1 && !marker.exists)
}

@Test func failedRestorationRetainsRecoveryAndStartupRepairsIt() throws {
    let setting = Setting(), marker = Marker()
    let controller = ClosedLidCoordinator(setting: setting, recovery: marker)
    _ = try controller.sync(reason: .active)
    setting.refuseRestore = true
    #expect(throws: (any Error).self) { try controller.sync(reason: .off) }
    #expect(marker.exists && setting.value == 1)
    setting.refuseRestore = false
    let restarted = ClosedLidCoordinator(setting: setting, recovery: marker)
    try restarted.recover()
    #expect(setting.value == 0 && !marker.exists)
}

@Test func secureLeaseFileRejectsSymlinksAndOversizedInput() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("lease.json")
    try Data().write(to: path)
    chmod(path.path, 0o600)
    let file = ClosedLidLeaseFile(url: path, owner: getuid())
    try file.write(lease())
    #expect(try file.read()?.runningTasks == 1)
    try Data(repeating: 65, count: 4097).write(to: path)
    #expect(throws: (any Error).self) { try file.read() }
    try FileManager.default.removeItem(at: path)
    try FileManager.default.createSymbolicLink(at: path, withDestinationURL: dir.appendingPathComponent("target"))
    #expect(throws: (any Error).self) { try file.write(lease()) }
}

@Test func leaseCannotAuthorizeMoreThanEightSecondsOrCrossABoot() {
    let long = ClosedLidLease(enabled: true, runningTasks: 1, issuedUptime: 100, expiresUptime: 110, bootID: boot)
    #expect(ClosedLidPolicy.reason(lease: long, uptime: 101, bootID: boot, battery: 74, thermal: .nominal, alreadyActive: false) == .expired)
    #expect(ClosedLidPolicy.reason(lease: lease(), uptime: 101, bootID: "", battery: 74, thermal: .nominal, alreadyActive: false) == .expired)
}

@Test func externalSleepChangeRequiresOptInReset() throws {
    let setting = Setting(), marker = Marker()
    let controller = ClosedLidCoordinator(setting: setting, recovery: marker)
    _ = try controller.sync(reason: .active)
    setting.value = 0
    #expect(try controller.sync(reason: .active) == .conflict)
    #expect(try controller.sync(reason: .active) == .conflict)
    #expect(setting.value == 0 && !marker.exists)
    _ = try controller.sync(reason: .off)
    #expect(try controller.sync(reason: .active) == .active)
}

@Test func heldLeaseLockCannotBlockRecoveryLoop() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("lease.json")
    try JSONEncoder().encode(lease()).write(to: path)
    chmod(path.path, 0o600)
    let fd = open(path.path, O_RDWR)
    defer { close(fd) }
    #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
    #expect(throws: (any Error).self) { try ClosedLidLeaseFile(url: path, owner: getuid()).read() }
    #expect(flock(fd, LOCK_UN) == 0)
    #expect(throws: (any Error).self) { try ClosedLidLeaseFile(url: path, owner: getuid() + 1).read() }
}
