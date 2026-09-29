import CryptoKit
import Darwin
import Foundation

public enum StoreError: Error, LocalizedError {
    case invalidTaskID
    case invalidTerminalState
    case lockFailed

    public var errorDescription: String? {
        switch self {
        case .invalidTaskID: "Task ID must be 1 to 128 UTF-8 bytes."
        case .invalidTerminalState: "A supervised task must finish with a terminal state."
        case .lockFailed: "Could not lock Agent Awake task storage."
        }
    }
}

public struct TaskStore: Sendable {
    public let directory: URL

    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AgentAwake/tasks", isDirectory: true)) {
        self.directory = directory
    }

    public func apply(_ event: TaskEvent) throws {
        guard !event.taskID.isEmpty, event.taskID.utf8.count <= 128 else { throw StoreError.invalidTaskID }
        try withLock {
            let url = fileURL(for: event.provider, id: event.taskID)
            let previous = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(TaskRecord.self, from: $0) }
            let record = TaskRecord.apply(event, to: previous)
            let data = try JSONEncoder().encode(record)
            try data.write(to: url, options: .atomic)
            chmod(url.path, 0o600)
        }
    }

    /// Renews a supervised task's lease without undoing a provider hook's
    /// waiting or terminal state. Uses the same lock as hook writes.
    public func heartbeat(provider: Provider, id: String, observedAt: Date = Date(), leaseSeconds: TimeInterval = 8) throws {
        guard !id.isEmpty, id.utf8.count <= 128 else { throw StoreError.invalidTaskID }
        try withLock {
            let url = fileURL(for: provider, id: id)
            guard let data = try? Data(contentsOf: url),
                  let previous = try? JSONDecoder().decode(TaskRecord.self, from: data),
                  !previous.state.isTerminal else { return }
            let event = TaskEvent(provider: provider, taskID: id, state: previous.state,
                                  observedAt: max(observedAt, previous.observedAt), leaseSeconds: leaseSeconds)
            let record = TaskRecord.apply(event, to: previous)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            chmod(url.path, 0o600)
        }
    }

    /// Process exit is authoritative for a supervised run, while an explicit
    /// provider failure or cancellation remains visible after a zero exit.
    public func finish(provider: Provider, id: String, state: TaskState, observedAt: Date = Date()) throws {
        guard !id.isEmpty, id.utf8.count <= 128 else { throw StoreError.invalidTaskID }
        guard state.isTerminal else { throw StoreError.invalidTerminalState }
        try withLock {
            let url = fileURL(for: provider, id: id)
            let previous = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(TaskRecord.self, from: $0) }
            let resolved: TaskState = if state == .cancelled || previous?.state == .cancelled {
                .cancelled
            } else if state == .failed || previous?.state == .failed {
                .failed
            } else {
                .completed
            }
            let date = max(observedAt, previous?.observedAt ?? observedAt)
            let record = TaskRecord(id: id, provider: provider, state: resolved,
                                    startedAt: previous?.startedAt ?? date, observedAt: date,
                                    expiresAt: date.addingTimeInterval(8), usage: previous?.usage,
                                    milestones: previous?.milestones ?? 0)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            chmod(url.path, 0o600)
        }
    }

    /// A final provider usage event can arrive after its Stop hook. Add the
    /// observed counts without changing the task or assertion state.
    public func observeUsage(provider: Provider, id: String, usage: TokenUsage) throws {
        guard !id.isEmpty, id.utf8.count <= 128 else { throw StoreError.invalidTaskID }
        try withLock {
            let url = fileURL(for: provider, id: id)
            guard let data = try? Data(contentsOf: url),
                  let previous = try? JSONDecoder().decode(TaskRecord.self, from: data) else { return }
            let record = TaskRecord(id: id, provider: provider, state: previous.state,
                                    startedAt: previous.startedAt, observedAt: previous.observedAt,
                                    expiresAt: previous.expiresAt, usage: usage,
                                    milestones: previous.milestones)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            chmod(url.path, 0o600)
        }
    }

    public func load() throws -> [TaskRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(TaskRecord.self, from: data)
            }
            .sorted { $0.observedAt > $1.observedAt }
    }

    public func prune(at date: Date = Date()) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try withLock {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let record = try? JSONDecoder().decode(TaskRecord.self, from: data),
                      !record.isVisible(at: date) else { continue }
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try prepareDirectory()
        let lockPath = directory.appendingPathComponent(".lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw StoreError.lockFailed }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw StoreError.lockFailed }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        chmod(directory.path, 0o700)
    }

    private func fileURL(for provider: Provider, id: String) -> URL {
        let digest = SHA256.hash(data: Data("\(provider.rawValue):\(id)".utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).json")
    }
}
