import Foundation

public enum ProbeThermal: String, Sendable {
    case nominal, fair, serious, critical
}

public enum ProbeRestoreReason: String, Sendable {
    case deadline, lowBattery, unknownBattery, thermal, newBoot, powerSourceChanged
}

public enum LidProbePolicy {
    public static func sleepDisabled(in output: String) -> Int? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "SleepDisabled" else { continue }
            guard fields.count == 2, let value = Int(fields[1]), value == 0 || value == 1 else { return nil }
            return value
        }
        return 0
    }

    public static func batteryPercent(in output: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})%"#),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output),
              let value = Int(output[range]), value <= 100 else { return nil }
        return value
    }

    public static func isOnBattery(_ output: String) -> Bool {
        output.contains("Now drawing from 'Battery Power'")
    }

    public static func lidState(in output: String) -> Bool? {
        if output.contains(#""AppleClamshellState" = Yes"#) { return true }
        if output.contains(#""AppleClamshellState" = No"#) { return false }
        return nil
    }

    public static func restoreReason(
        now: Date,
        deadline: Date,
        originalBootTime: TimeInterval,
        currentBootTime: TimeInterval,
        batteryPercent: Int?,
        onBattery: Bool,
        thermal: ProbeThermal
    ) -> ProbeRestoreReason? {
        if abs(currentBootTime - originalBootTime) > 5 { return .newBoot }
        if now >= deadline { return .deadline }
        if thermal == .serious || thermal == .critical { return .thermal }
        if batteryPercent == nil { return .unknownBattery }
        if let batteryPercent, batteryPercent <= 20 { return .lowBattery }
        if !onBattery { return .powerSourceChanged }
        return nil
    }
}
