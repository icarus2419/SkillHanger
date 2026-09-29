import AgentAwakeCore
import Darwin
import Dispatch
import Foundation

private enum HelperError: Error, LocalizedError {
    case rootRequired, invalidUser, alreadyInstalled, unsafePath, commandFailed, commandTimeout
    var errorDescription: String? {
        switch self {
        case .rootRequired: "This command requires administrator privileges."
        case .invalidUser: "A non-root local user ID is required."
        case .alreadyInstalled: "Helper files already exist. Uninstall or recover the existing helper first."
        case .unsafePath: "A helper path failed ownership or file-type validation."
        case .commandFailed: "A system power or service command failed."
        case .commandTimeout: "A system command timed out; recovery will retry."
        }
    }
}

private func commandResult(_ path: String, _ args: [String]) throws -> (output: String, status: Int32) {
    let process = Process(), output = Pipe(), finished = DispatchSemaphore(value: 0)
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.standardOutput = output
    process.standardError = output
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    guard finished.wait(timeout: .now() + 3) == .success else {
        process.terminate()
        if finished.wait(timeout: .now() + 1) != .success { kill(process.processIdentifier, SIGKILL) }
        throw HelperError.commandTimeout
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard data.count <= 65_536 else { throw HelperError.commandFailed }
    return (String(decoding: data, as: UTF8.self), process.terminationStatus)
}

private func command(_ path: String, _ args: [String]) throws -> String {
    let result = try commandResult(path, args)
    guard result.status == 0 else { throw HelperError.commandFailed }
    return result.output
}

private func stopService() throws {
    _ = try commandResult("/bin/launchctl", ["bootout", "system/\(ClosedLidPaths.label)"])
    let check = try commandResult("/bin/launchctl", ["print", "system/\(ClosedLidPaths.label)"])
    // launchctl returns 113 for an absent system service on this macOS.
    guard check.status == 113 else { throw HelperError.commandFailed }
}

private func requireRoot() throws {
    guard geteuid() == 0 else { throw HelperError.rootRequired }
}

/// Only fixed, root-owned directories. Never follow an existing directory symlink.
private func directory(_ url: URL, mode: mode_t) throws {
    var info = stat()
    if lstat(url.path, &info) == 0 {
        guard info.st_uid == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o022 == 0 else { throw HelperError.unsafePath }
    } else {
        guard errno == ENOENT, mkdir(url.path, mode) == 0 else { throw HelperError.unsafePath }
    }
    guard chown(url.path, 0, 0) == 0, chmod(url.path, mode) == 0 else { throw HelperError.unsafePath }
}

private final class PowerSetting: ClosedLidSettingControlling {
    func read() throws -> Int {
        guard let value = LidProbePolicy.sleepDisabled(in: try command("/usr/bin/pmset", ["-g"])) else {
            throw ClosedLidError.settingUnconfirmed
        }
        return value
    }
    func set(_ value: Int) throws {
        guard value == 0 || value == 1 else { throw ClosedLidError.settingUnconfirmed }
        _ = try command("/usr/bin/pmset", ["-a", "disablesleep", String(value)])
    }
}

private final class RecoveryMarker: ClosedLidRecoveryStoring {
    var exists: Bool { FileManager.default.fileExists(atPath: ClosedLidPaths.marker.path) }
    func mark() throws {
        let fd = open(ClosedLidPaths.marker.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw HelperError.unsafePath }
        defer { close(fd) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: Data("owned\n".utf8))
        guard fsync(fd) == 0 else { throw HelperError.unsafePath }
        syncDirectory()
    }
    func clear() throws {
        if exists { try FileManager.default.removeItem(at: ClosedLidPaths.marker) }
        syncDirectory()
    }
    private func syncDirectory() {
        let fd = open(ClosedLidPaths.recovery.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if fd >= 0 { _ = fsync(fd); close(fd) }
    }
}

private func thermal() -> ProbeThermal {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: .nominal
    case .fair: .fair
    case .serious: .serious
    case .critical: .critical
    @unknown default: .critical
    }
}

private func publish(_ state: ClosedLidState, uid: uid_t) throws {
    let status = ClosedLidStatus(state: state, uptime: ProcessInfo.processInfo.systemUptime,
                                bootID: ClosedLidPaths.bootID(), userID: uid)
    try JSONEncoder().encode(status).write(to: ClosedLidPaths.status, options: .atomic)
    guard chmod(ClosedLidPaths.status.path, 0o644) == 0 else { throw HelperError.unsafePath }
}

private func serve(uid: uid_t) throws {
    try requireRoot()
    try directory(ClosedLidPaths.recovery, mode: 0o700)
    let coordinator = ClosedLidCoordinator(setting: PowerSetting(), recovery: RecoveryMarker())
    // Repair an interrupted session before exposing the user-writable lease.
    try coordinator.recover()
    try directory(ClosedLidPaths.runtime, mode: 0o755)
    if FileManager.default.fileExists(atPath: ClosedLidPaths.lease.path) {
        try FileManager.default.removeItem(at: ClosedLidPaths.lease)
    }
    let fd = open(ClosedLidPaths.lease.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw HelperError.unsafePath }
    guard fchown(fd, uid, 0) == 0, fchmod(fd, 0o600) == 0 else { close(fd); throw HelperError.unsafePath }
    close(fd)
    let lease = ClosedLidLeaseFile(url: ClosedLidPaths.lease, owner: uid)
    let stop = DispatchSemaphore(value: 0)
    let signals = [SIGINT, SIGTERM].map { number in
        Darwin.signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { stop.signal() }
        source.activate()
        return source
    }
    defer { signals.forEach { $0.cancel() } }
    while true {
        do {
            let currentLease = try? lease.read()
            let power = try command("/usr/bin/pmset", ["-g", "ps"])
            let reason = ClosedLidPolicy.reason(lease: currentLease,
                uptime: ProcessInfo.processInfo.systemUptime, bootID: ClosedLidPaths.bootID(),
                battery: LidProbePolicy.batteryPercent(in: power), thermal: thermal(), alreadyActive: coordinator.isHolding)
            try publish(coordinator.sync(reason: reason), uid: uid)
        } catch {
            do { try coordinator.recover() }
            catch { fputs("Agent Awake: sleep restoration needs attention; retrying.\n", stderr) }
            try? publish(.error, uid: uid)
        }
        if stop.wait(timeout: .now() + 1) == .success {
            try coordinator.recover()
            try publish(.off, uid: uid)
            return
        }
    }
}

private func install(uid: uid_t) throws {
    try requireRoot()
    guard !FileManager.default.fileExists(atPath: ClosedLidPaths.helper.path),
          !FileManager.default.fileExists(atPath: ClosedLidPaths.plist.path) else { throw HelperError.alreadyInstalled }
    try directory(ClosedLidPaths.recovery, mode: 0o700)
    guard !RecoveryMarker().exists else { throw HelperError.alreadyInstalled }
    guard try PowerSetting().read() == 0 else { throw ClosedLidError.settingUnconfirmed }
    let parent = ClosedLidPaths.helper.deletingLastPathComponent()
    try directory(parent, mode: 0o755)
    try directory(ClosedLidPaths.plist.deletingLastPathComponent(), mode: 0o755)
    let source = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().standardizedFileURL
    try FileManager.default.copyItem(at: source, to: ClosedLidPaths.helper)
    guard chown(ClosedLidPaths.helper.path, 0, 0) == 0, chmod(ClosedLidPaths.helper.path, 0o755) == 0 else { throw HelperError.unsafePath }
    let plist: [String: Any] = [
        "Label": ClosedLidPaths.label,
        "ProgramArguments": [ClosedLidPaths.helper.path, "serve", String(uid)],
        "RunAtLoad": true,
        "KeepAlive": true,
        "ThrottleInterval": 2,
        "ExitTimeOut": 15
    ]
    do {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: ClosedLidPaths.plist, options: .atomic)
        guard chown(ClosedLidPaths.plist.path, 0, 0) == 0, chmod(ClosedLidPaths.plist.path, 0o644) == 0 else { throw HelperError.unsafePath }
        _ = try command("/bin/launchctl", ["bootstrap", "system", ClosedLidPaths.plist.path])
        _ = try command("/bin/launchctl", ["print", "system/\(ClosedLidPaths.label)"])
    } catch {
        // Keep the recovery executable and service files if shutdown or
        // restoration cannot be confirmed. Do not strand a running daemon.
        do {
            try stopService()
            try ClosedLidCoordinator(setting: PowerSetting(), recovery: RecoveryMarker()).recover()
            try? FileManager.default.removeItem(at: ClosedLidPaths.plist)
            try? FileManager.default.removeItem(at: ClosedLidPaths.helper)
        } catch {
            fputs("Agent Awake: installation cleanup needs attention. Recovery files have been retained.\n", stderr)
        }
        throw error
    }
    print("Helper installed for user \(uid). Closed-lid mode stays off until enabled in Agent Awake.")
}

private func uninstall() throws {
    try requireRoot()
    try stopService()
    // Do not remove the recovery marker if restoration cannot be verified.
    try directory(ClosedLidPaths.recovery, mode: 0o700)
    try ClosedLidCoordinator(setting: PowerSetting(), recovery: RecoveryMarker()).recover()
    for path in [ClosedLidPaths.plist, ClosedLidPaths.helper] {
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
    if ClosedLidPaths.runtimeIsSafe() {
        for path in [ClosedLidPaths.lease, ClosedLidPaths.status] {
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        }
        _ = rmdir(ClosedLidPaths.runtime.path)
    }
    _ = rmdir(ClosedLidPaths.recovery.path)
    print("Helper removed. Its owned sleep setting has been restored.")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "status":
        if let status = ClosedLidClient().status() { print(status.state.label) }
        else { print("No active helper for this user.") }
    case "install", "serve":
        guard let text = args.first == "install" ? ProcessInfo.processInfo.environment["SUDO_UID"] : args.dropFirst().first,
              let uid = uid_t(text), uid >= 501, getpwuid(uid) != nil else { throw HelperError.invalidUser }
        if args.first == "install" { try install(uid: uid) } else { try serve(uid: uid) }
    case "recover":
        try requireRoot()
        try stopService()
        try directory(ClosedLidPaths.recovery, mode: 0o700)
        try ClosedLidCoordinator(setting: PowerSetting(), recovery: RecoveryMarker()).recover()
        print("Helper stopped and its owned sleep setting restored. It remains installed for the next boot.")
    case "uninstall": try uninstall()
    default:
        print("Usage: agent-awake-closed-lid status | install | recover | uninstall")
        exit(2)
    }
} catch {
    fputs("Agent Awake closed-lid helper: \(error.localizedDescription)\n", stderr)
    exit(1)
}
