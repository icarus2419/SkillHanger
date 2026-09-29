import Darwin
import Foundation

public struct ClosedLidLease: Codable, Sendable {
    public let enabled: Bool
    public let runningTasks: Int
    public let issuedUptime: Double
    public let expiresUptime: Double
    public let bootID: String

    public init(enabled: Bool, runningTasks: Int, issuedUptime: Double, expiresUptime: Double, bootID: String) {
        self.enabled = enabled
        self.runningTasks = runningTasks
        self.issuedUptime = issuedUptime
        self.expiresUptime = expiresUptime
        self.bootID = bootID
    }
}

public enum ClosedLidState: String, Codable, Sendable {
    case off, idle, active, expired, battery, thermal, conflict, error

    public var label: String {
        switch self {
        case .off: "Closed-lid mode off"
        case .idle: "Ready for the next task"
        case .active: "Closed-lid mode active"
        case .expired: "Activity lease expired; sleep restored"
        case .battery: "Paused for battery charge"
        case .thermal: "Paused for thermal pressure"
        case .conflict: "Another sleep setting is in control"
        case .error: "Helper needs attention; check sleep status"
        }
    }
}

public enum ClosedLidPolicy {
    public static func reason(lease: ClosedLidLease?, uptime: Double, bootID: String, battery: Int?, thermal: ProbeThermal, alreadyActive: Bool) -> ClosedLidState {
        guard let lease else { return .expired }
        guard lease.bootID == bootID, !bootID.isEmpty,
              lease.issuedUptime.isFinite, lease.expiresUptime.isFinite,
              lease.issuedUptime <= uptime, lease.expiresUptime > uptime,
              lease.expiresUptime - lease.issuedUptime > 0,
              lease.expiresUptime - lease.issuedUptime <= 8,
              (0...128).contains(lease.runningTasks) else { return .expired }
        guard lease.enabled else { return .off }
        guard lease.runningTasks > 0 else { return .idle }
        guard thermal != .serious && thermal != .critical else { return .thermal }
        guard let battery, (0...100).contains(battery), battery >= (alreadyActive ? 21 : 30) else { return .battery }
        return .active
    }
}

public protocol ClosedLidSettingControlling: AnyObject {
    func read() throws -> Int
    func set(_ value: Int) throws
}

public protocol ClosedLidRecoveryStoring: AnyObject {
    var exists: Bool { get }
    func mark() throws
    func clear() throws
}

public enum ClosedLidError: Error, LocalizedError {
    case unsafeFile, unavailable, settingUnconfirmed
    public var errorDescription: String? {
        switch self {
        case .unsafeFile: "The closed-lid helper file failed validation."
        case .unavailable: "The closed-lid helper is unavailable."
        case .settingUnconfirmed: "The helper could not confirm the sleep setting."
        }
    }
}

/// The recovery marker is persisted before activation. A failed restoration
/// retains it so the next daemon start can retry before processing any lease.
public final class ClosedLidCoordinator {
    private let setting: any ClosedLidSettingControlling
    private let recovery: any ClosedLidRecoveryStoring
    public private(set) var isHolding = false
    private var conflictNeedsReset = false

    public init(setting: any ClosedLidSettingControlling, recovery: any ClosedLidRecoveryStoring) {
        self.setting = setting
        self.recovery = recovery
    }

    public func recover() throws {
        if isHolding || recovery.exists {
            try setting.set(0)
            guard try setting.read() == 0 else { throw ClosedLidError.settingUnconfirmed }
            try recovery.clear()
            isHolding = false
        }
    }

    public func sync(reason: ClosedLidState) throws -> ClosedLidState {
        if reason == .off { conflictNeedsReset = false }
        guard reason == .active else { try recover(); return reason }
        if conflictNeedsReset { return .conflict }
        let current = try setting.read()
        if isHolding {
            if current == 1 { return .active }
            // Another utility changed our global setting; require off/on.
            try recover()
            conflictNeedsReset = true
            return .conflict
        }
        guard current == 0 else { return .conflict }
        try recovery.mark()
        isHolding = true
        try setting.set(1)
        guard try setting.read() == 1 else { throw ClosedLidError.settingUnconfirmed }
        return .active
    }
}

/// No file creation or path supplied by a lease. The daemon creates this
/// single user-owned file inside its root-owned directory. Nonblocking locks
/// prevent a writer from stalling the privileged recovery loop.
public struct ClosedLidLeaseFile: Sendable {
    public let url: URL
    public let owner: uid_t
    public init(url: URL, owner: uid_t) { self.url = url; self.owner = owner }

    private func withFile<T>(writing: Bool, _ body: (Int32) throws -> T) throws -> T {
        let fd = open(url.path, (writing ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw ClosedLidError.unavailable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o777 == 0o600,
              info.st_nlink == 1, info.st_size <= 4096 else { throw ClosedLidError.unsafeFile }
        guard flock(fd, (writing ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else { throw ClosedLidError.unavailable }
        defer { flock(fd, LOCK_UN) }
        return try body(fd)
    }

    public func read() throws -> ClosedLidLease? {
        try withFile(writing: false) { fd in
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            let data = try handle.read(upToCount: 4097) ?? Data()
            guard data.count <= 4096 else { throw ClosedLidError.unsafeFile }
            if data.isEmpty { return nil }
            return try JSONDecoder().decode(ClosedLidLease.self, from: data)
        }
    }

    public func write(_ lease: ClosedLidLease) throws {
        let data = try JSONEncoder().encode(lease)
        guard data.count <= 4096 else { throw ClosedLidError.unsafeFile }
        try withFile(writing: true) { fd in
            guard ftruncate(fd, 0) == 0 else { throw ClosedLidError.unavailable }
            try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
        }
    }
}

public enum ClosedLidPaths {
    public static let label = "com.agentawake.closedlid"
    public static let runtime = URL(fileURLWithPath: "/var/run/com.agentawake.closedlid", isDirectory: true)
    public static let lease = runtime.appendingPathComponent("lease.json")
    public static let status = runtime.appendingPathComponent("status.json")
    public static let recovery = URL(fileURLWithPath: "/var/db/com.agentawake.closedlid", isDirectory: true)
    public static let marker = recovery.appendingPathComponent("owned")
    public static let helper = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.agentawake.closedlid")
    public static let plist = URL(fileURLWithPath: "/Library/LaunchDaemons/com.agentawake.closedlid.plist")

    public static func bootID() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0, size < 256 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func runtimeIsSafe() -> Bool {
        var info = stat()
        return lstat(runtime.path, &info) == 0 && info.st_uid == 0 && info.st_mode & S_IFMT == S_IFDIR && info.st_mode & 0o777 == 0o755
    }
}

public struct ClosedLidStatus: Codable, Sendable {
    public let state: ClosedLidState
    public let uptime: Double
    public let bootID: String
    public let userID: uid_t
    public init(state: ClosedLidState, uptime: Double, bootID: String, userID: uid_t) {
        self.state = state; self.uptime = uptime; self.bootID = bootID; self.userID = userID
    }
}

public struct ClosedLidClient {
    public init() {}
    public func status() -> ClosedLidStatus? {
        guard ClosedLidPaths.runtimeIsSafe() else { return nil }
        let fd = open(ClosedLidPaths.status.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o777 == 0o644, info.st_nlink == 1, info.st_size <= 4096,
              let data = try? FileHandle(fileDescriptor: fd, closeOnDealloc: false).read(upToCount: 4097),
              let status = try? JSONDecoder().decode(ClosedLidStatus.self, from: data),
              status.userID == getuid(), status.bootID == ClosedLidPaths.bootID(),
              status.uptime <= ProcessInfo.processInfo.systemUptime,
              ProcessInfo.processInfo.systemUptime - status.uptime < 5 else { return nil }
        return status
    }
    public func renew(enabled: Bool, runningTasks: Int) throws {
        guard ClosedLidPaths.runtimeIsSafe() else { throw ClosedLidError.unavailable }
        let uptime = ProcessInfo.processInfo.systemUptime
        try ClosedLidLeaseFile(url: ClosedLidPaths.lease, owner: getuid()).write(
            ClosedLidLease(enabled: enabled, runningTasks: runningTasks, issuedUptime: uptime, expiresUptime: uptime + 8, bootID: ClosedLidPaths.bootID()))
    }
}
