import AgentAwakeCore
import Darwin
import Dispatch
import Foundation

private enum ProbePaths {
    static let label = "com.agentawake.lidprobe"
    static let root = URL(fileURLWithPath: "/var/db/com.agentawake.lidprobe", isDirectory: true)
    static let helper = root.appendingPathComponent("agent-awake-lid-probe")
    static let marker = root.appendingPathComponent("active.json")
    static let plist = URL(fileURLWithPath: "/Library/LaunchDaemons/com.agentawake.lidprobe.plist")
}

private struct Marker: Codable {
    let deadline: Date
    let bootTime: TimeInterval
    let reportPath: String
}

private enum ProbeError: Error, LocalizedError {
    case rootRequired, alreadyInstalled, sleepAlreadyDisabled, powerUnavailable, batteryTooLow, thermalPressure
    case commandFailed(String), invalidSleepState, lidUnavailable, failedToRestore

    var errorDescription: String? {
        switch self {
        case .rootRequired: "The probe must be started with administrator privileges."
        case .alreadyInstalled: "A lid probe or its recovery files already exist; inspect or recover it first."
        case .sleepAlreadyDisabled: "Sleep is already disabled by another setting or utility."
        case .powerUnavailable: "Could not verify battery power and charge."
        case .batteryTooLow: "Charge the Mac above 30% before this test."
        case .thermalPressure: "The Mac is already under serious thermal pressure."
        case .commandFailed(let detail): "System command failed: \(detail)"
        case .invalidSleepState: "Could not read a reliable SleepDisabled value."
        case .lidUnavailable: "Could not read the MacBook lid state."
        case .failedToRestore: "Could not verify that normal sleep was restored. The recovery watchdog remains installed."
        }
    }
}

private func systemCommand(_ path: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw ProbeError.commandFailed("\(path) \(arguments.joined(separator: " ")) (exit \(process.terminationStatus)): \(text.prefix(300))")
    }
    return text
}

private func sleepDisabled() throws -> Int {
    guard let value = LidProbePolicy.sleepDisabled(in: try systemCommand("/usr/bin/pmset", ["-g"])) else {
        throw ProbeError.invalidSleepState
    }
    return value
}

private func powerReading() throws -> (onBattery: Bool, percent: Int?) {
    let text = try systemCommand("/usr/bin/pmset", ["-g", "ps"])
    return (LidProbePolicy.isOnBattery(text), LidProbePolicy.batteryPercent(in: text))
}

private func thermalReading() -> ProbeThermal {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: .nominal
    case .fair: .fair
    case .serious: .serious
    case .critical: .critical
    @unknown default: .critical
    }
}

private func bootTime() -> TimeInterval {
    Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
}

private func requireRoot() throws {
    guard geteuid() == 0 else { throw ProbeError.rootRequired }
}

private func readMarker() throws -> Marker? {
    guard FileManager.default.fileExists(atPath: ProbePaths.marker.path) else { return nil }
    return try JSONDecoder().decode(Marker.self, from: Data(contentsOf: ProbePaths.marker))
}

private func makeRootDirectory() throws {
    try FileManager.default.createDirectory(at: ProbePaths.root, withIntermediateDirectories: true)
    guard chown(ProbePaths.root.path, 0, 0) == 0,
          chmod(ProbePaths.root.path, 0o700) == 0 else {
        throw ProbeError.commandFailed("could not protect the probe directory")
    }
}

private func writeMarker(_ marker: Marker) throws {
    let data = try JSONEncoder().encode(marker)
    try data.write(to: ProbePaths.marker, options: .atomic)
    guard chown(ProbePaths.marker.path, 0, 0) == 0,
          chmod(ProbePaths.marker.path, 0o600) == 0 else {
        throw ProbeError.commandFailed("could not protect the recovery marker")
    }
}

private func installWatchdog(_ marker: Marker) throws {
    let files = FileManager.default
    guard !files.fileExists(atPath: ProbePaths.marker.path),
          !files.fileExists(atPath: ProbePaths.plist.path),
          !files.fileExists(atPath: ProbePaths.helper.path) else {
        throw ProbeError.alreadyInstalled
    }
    try makeRootDirectory()
    do {
        let source = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().standardizedFileURL
        try files.copyItem(at: source, to: ProbePaths.helper)
        guard chown(ProbePaths.helper.path, 0, 0) == 0,
              chmod(ProbePaths.helper.path, 0o700) == 0 else {
            throw ProbeError.commandFailed("could not protect the recovery executable")
        }
        try writeMarker(marker)
        let service: [String: Any] = [
            "Label": ProbePaths.label,
            "ProgramArguments": [ProbePaths.helper.path, "watchdog"],
            "RunAtLoad": true,
            "StartInterval": 5,
            "KeepAlive": ["SuccessfulExit": false]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: service, format: .xml, options: 0)
        try data.write(to: ProbePaths.plist, options: .atomic)
        guard chown(ProbePaths.plist.path, 0, 0) == 0,
              chmod(ProbePaths.plist.path, 0o644) == 0 else {
            throw ProbeError.commandFailed("could not protect the recovery service")
        }
        _ = try systemCommand("/bin/launchctl", ["bootstrap", "system", ProbePaths.plist.path])
        _ = try systemCommand("/bin/launchctl", ["print", "system/\(ProbePaths.label)"])
    } catch {
        removeWatchdogFiles()
        throw error
    }
}

private func removeWatchdogFiles() {
    let files = FileManager.default
    for path in [ProbePaths.plist, ProbePaths.helper, ProbePaths.marker] {
        if files.fileExists(atPath: path.path) { try? files.removeItem(at: path) }
    }
    _ = try? systemCommand("/bin/launchctl", ["bootout", "system/\(ProbePaths.label)"])
}

private func recoveryFilesPresent() -> Bool {
    [ProbePaths.marker, ProbePaths.plist, ProbePaths.helper]
        .contains { FileManager.default.fileExists(atPath: $0.path) }
}

private func restoreAndClean() throws {
    if recoveryFilesPresent() {
        // The probe only starts from baseline 0. Restore without depending on
        // a marker decode or status read, which might be why recovery started.
        _ = try systemCommand("/usr/bin/pmset", ["-a", "disablesleep", "0"])
        guard try sleepDisabled() == 0 else { throw ProbeError.failedToRestore }
    }
    removeWatchdogFiles()
}

private func reportFile() throws -> (FileHandle, String) {
    let path = "/var/tmp/AgentAwakeLidProbe-\(UUID().uuidString).csv"
    let fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
    guard fd >= 0 else { throw ProbeError.commandFailed("could not create probe report") }
    guard chmod(path, 0o644) == 0 else {
        close(fd)
        throw ProbeError.commandFailed("could not protect probe report")
    }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    handle.write(Data("wall_time,lid_closed,battery_percent,thermal\n".utf8))
    return (handle, path)
}

private func startProbe() throws {
    try requireRoot()
    guard !FileManager.default.fileExists(atPath: ProbePaths.marker.path),
          !FileManager.default.fileExists(atPath: ProbePaths.plist.path),
          !FileManager.default.fileExists(atPath: ProbePaths.helper.path) else {
        throw ProbeError.alreadyInstalled
    }
    guard try sleepDisabled() == 0 else { throw ProbeError.sleepAlreadyDisabled }
    let power = try powerReading()
    guard power.onBattery, let percent = power.percent else { throw ProbeError.powerUnavailable }
    guard percent >= 30 else { throw ProbeError.batteryTooLow }
    guard ![ProbeThermal.serious, .critical].contains(thermalReading()) else { throw ProbeError.thermalPressure }
    guard LidProbePolicy.lidState(in: try systemCommand("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState"])) == false else {
        throw ProbeError.lidUnavailable
    }
    let (report, reportPath) = try reportFile()
    defer { try? report.close() }
    let marker = Marker(deadline: Date().addingTimeInterval(180), bootTime: bootTime(), reportPath: reportPath)
    try installWatchdog(marker)
    defer {
        do { try restoreAndClean() }
        catch { fputs("Agent Awake: restoration needs attention: \(error.localizedDescription)\n", stderr) }
    }
    _ = try systemCommand("/usr/bin/pmset", ["-a", "disablesleep", "1"])
    guard try sleepDisabled() == 1 else { throw ProbeError.invalidSleepState }

    print("Lid probe active for at most three minutes. Report: \(reportPath)")
    print("Place the Mac on a hard, ventilated surface. Close the lid for about one minute, then reopen it.")
    fflush(stdout)

    let stop = DispatchSemaphore(value: 0)
    let sources = [SIGINT, SIGTERM].map { number in
        Darwin.signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { stop.signal() }
        source.activate()
        return source
    }
    defer { sources.forEach { $0.cancel() } }

    let formatter = ISO8601DateFormatter()
    var sawClosed = false
    var closedSamples = 0
    var maxGap: TimeInterval = 0
    var previous = Date()
    while Date() < marker.deadline {
        let now = Date()
        maxGap = max(maxGap, now.timeIntervalSince(previous))
        previous = now
        let reading = try powerReading()
        let thermal = thermalReading()
        let lidOutput = try systemCommand("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState"])
        guard let closed = LidProbePolicy.lidState(in: lidOutput) else { throw ProbeError.lidUnavailable }
        if closed { sawClosed = true; closedSamples += 1 }
        report.write(Data("\(formatter.string(from: now)),\(closed),\(reading.percent.map(String.init) ?? "unknown"),\(thermal.rawValue)\n".utf8))
        if LidProbePolicy.restoreReason(now: now, deadline: marker.deadline, originalBootTime: marker.bootTime,
                                        currentBootTime: bootTime(), batteryPercent: reading.percent,
                                        onBattery: reading.onBattery, thermal: thermal) != nil { break }
        if sawClosed && !closed && closedSamples >= 45 { break }
        if stop.wait(timeout: .now() + 1) == .success { break }
    }
    try restoreAndClean()
    print("Probe ended. Closed-lid samples: \(closedSamples); largest sample gap: \(String(format: "%.1f", maxGap)) seconds.")
    print("SleepDisabled is \(try sleepDisabled()); report: \(reportPath)")
}

private func watchdog() throws {
    try requireRoot()
    while true {
        let marker: Marker
        do {
            guard let active = try readMarker() else { return }
            marker = active
        } catch {
            // Our root-owned marker exists but cannot be decoded. Restore the
            // system setting before removing the recovery service.
            try restoreAndClean()
            return
        }
        do {
            let reading = try powerReading()
            let reason = LidProbePolicy.restoreReason(
                now: Date(), deadline: marker.deadline, originalBootTime: marker.bootTime,
                currentBootTime: bootTime(), batteryPercent: reading.percent,
                onBattery: reading.onBattery, thermal: thermalReading()
            )
            if let reason {
                fputs("Agent Awake lid probe: restoring sleep (\(reason.rawValue)).\n", stderr)
                try restoreAndClean()
                return
            }
        } catch {
            // A failed status read must not leave sleep disabled. Retry if pmset rejects restoration.
            do { try restoreAndClean(); return }
            catch { fputs("Agent Awake lid probe: restoration retry: \(error.localizedDescription)\n", stderr) }
        }
        Thread.sleep(forTimeInterval: 1)
    }
}

private func status() throws {
    let power = try powerReading()
    print("SleepDisabled: \(try sleepDisabled())")
    print("Power: \(power.onBattery ? "battery" : "external"); charge: \(power.percent.map(String.init) ?? "unknown")%")
    print("Thermal: \(thermalReading().rawValue)")
    print("Recovery service: \(FileManager.default.fileExists(atPath: ProbePaths.plist.path) ? "installed" : "absent")")
}

do {
    switch CommandLine.arguments.dropFirst().first {
    case "status": try status()
    case "start": try startProbe()
    case "watchdog": try watchdog()
    case "recover": try requireRoot(); try restoreAndClean()
    default:
        print("Usage: agent-awake-lid-probe status | start | recover")
        exit(2)
    }
} catch {
    fputs("Agent Awake lid probe: \(error.localizedDescription)\n", stderr)
    exit(1)
}
