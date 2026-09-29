import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case claude, codex

    public var displayName: String { self == .claude ? "Claude Code" : "Codex" }
}

public enum TaskState: String, Codable, Sendable {
    case running, waiting, completed, failed, cancelled, unknown

    public var isTerminal: Bool { [.completed, .failed, .cancelled].contains(self) }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public let input: Int
    public let output: Int

    public init(input: Int, output: Int) {
        self.input = max(0, input)
        self.output = max(0, output)
    }
}

public struct TaskEvent: Sendable {
    public let provider: Provider
    public let taskID: String
    public let state: TaskState
    public let observedAt: Date
    public let leaseSeconds: TimeInterval
    public let usage: TokenUsage?
    public let milestone: Bool
    public let beginsTurn: Bool

    public init(provider: Provider, taskID: String, state: TaskState, observedAt: Date = Date(), leaseSeconds: TimeInterval = 120, usage: TokenUsage? = nil, milestone: Bool = false, beginsTurn: Bool = false) {
        self.provider = provider
        self.taskID = taskID
        self.state = state
        self.observedAt = observedAt
        self.leaseSeconds = max(1, min(leaseSeconds, 3600))
        self.usage = usage
        self.milestone = milestone
        self.beginsTurn = beginsTurn
    }
}

public struct TaskRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let provider: Provider
    public let state: TaskState
    public let startedAt: Date
    public let observedAt: Date
    public let expiresAt: Date
    public let usage: TokenUsage?
    public let milestones: Int

    public init(id: String, provider: Provider, state: TaskState, startedAt: Date, observedAt: Date, expiresAt: Date, usage: TokenUsage? = nil, milestones: Int = 0) {
        self.id = id
        self.provider = provider
        self.state = state
        self.startedAt = startedAt
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.usage = usage
        self.milestones = milestones
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, state, startedAt, observedAt, expiresAt, usage, milestones
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        provider = try values.decode(Provider.self, forKey: .provider)
        state = try values.decode(TaskState.self, forKey: .state)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        observedAt = try values.decode(Date.self, forKey: .observedAt)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        usage = try values.decodeIfPresent(TokenUsage.self, forKey: .usage)
        milestones = try values.decodeIfPresent(Int.self, forKey: .milestones) ?? 0
    }

    public func effectiveState(at date: Date) -> TaskState {
        if !state.isTerminal && date > expiresAt { return .unknown }
        return state
    }

    public func isVisible(at date: Date) -> Bool {
        if state.isTerminal { return date.timeIntervalSince(observedAt) < 300 }
        return date.timeIntervalSince(expiresAt) < 600
    }

    public func withState(_ state: TaskState) -> TaskRecord {
        TaskRecord(id: id, provider: provider, state: state, startedAt: startedAt, observedAt: observedAt, expiresAt: expiresAt, usage: usage, milestones: milestones)
    }

    public static func apply(_ event: TaskEvent, to previous: TaskRecord?) -> TaskRecord {
        if let previous, previous.observedAt > event.observedAt { return previous }
        if let previous, previous.state.isTerminal, !event.beginsTurn { return previous }
        let newTurn = previous == nil || (previous?.state.isTerminal == true && event.beginsTurn)
        return TaskRecord(
            id: event.taskID,
            provider: event.provider,
            state: event.state,
            startedAt: newTurn ? event.observedAt : previous!.startedAt,
            observedAt: event.observedAt,
            expiresAt: event.observedAt.addingTimeInterval(event.leaseSeconds),
            usage: event.usage ?? (newTurn ? nil : previous?.usage),
            milestones: (newTurn ? 0 : previous?.milestones ?? 0) + (event.milestone ? 1 : 0)
        )
    }
}
