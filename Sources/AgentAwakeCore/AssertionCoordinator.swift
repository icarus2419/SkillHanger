import Foundation
import IOKit.pwr_mgt

public protocol PowerControlling: AnyObject {
    func acquire() throws
    func release()
}

public final class AssertionCoordinator {
    private let power: PowerControlling
    public private(set) var isHolding = false

    public init(power: PowerControlling) { self.power = power }

    public func sync(tasks: [TaskRecord], now: Date = Date()) throws {
        let shouldHold = tasks.contains { $0.effectiveState(at: now) == .running }
        if shouldHold && !isHolding {
            try power.acquire()
            isHolding = true
        } else if !shouldHold && isHolding {
            power.release()
            isHolding = false
        }
    }

    deinit { if isHolding { power.release() } }
}

public enum PowerError: Error, LocalizedError {
    case assertionFailed(Int32)
    public var errorDescription: String? {
        switch self { case .assertionFailed(let code): "macOS rejected the idle sleep assertion (code \(code))." }
    }
}

public final class IOKitPowerController: PowerControlling {
    private var assertionID: IOPMAssertionID?

    public init() {}

    public func acquire() throws {
        guard assertionID == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            "Agent Awake active agent task" as CFString,
            nil, nil, nil, 0, nil, &id
        )
        guard result == kIOReturnSuccess else { throw PowerError.assertionFailed(result) }
        assertionID = id
    }

    public func release() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }

    deinit { release() }
}
