import Foundation

public enum LaunchCommand {
    /// Process lifetime equals task lifetime only for finite, non-interactive agent commands.
    public static func isSupported(provider: Provider, command: [String]) -> Bool {
        guard let executable = command.first?.split(separator: "/").last else { return false }
        switch provider {
        case .codex:
            return executable == "codex" && command.dropFirst().contains("exec")
        case .claude:
            return executable == "claude" && command.dropFirst().contains { $0 == "-p" || $0 == "--print" }
        }
    }
}
