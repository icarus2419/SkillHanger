import Foundation

public enum OverlayPolicy {
    public static func shouldShow(tasks: [TaskRecord], now: Date, idleSeconds: Double, threshold: Int) -> Bool {
        guard threshold > 0, idleSeconds.isFinite, idleSeconds >= Double(threshold) else { return false }
        return tasks.contains { !$0.effectiveState(at: now).isTerminal }
    }
}
