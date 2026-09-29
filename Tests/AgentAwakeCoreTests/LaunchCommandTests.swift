import Testing
@testable import AgentAwakeCore

@Test func supervisedLaunchAcceptsOnlyFiniteAgentCommands() {
    #expect(LaunchCommand.isSupported(provider: .codex, command: ["codex", "exec", "--json", "task"]))
    #expect(LaunchCommand.isSupported(provider: .claude, command: ["/usr/local/bin/claude", "-p", "task"]))
    #expect(!LaunchCommand.isSupported(provider: .codex, command: ["codex", "task"]))
    #expect(!LaunchCommand.isSupported(provider: .claude, command: ["claude"]))
    #expect(!LaunchCommand.isSupported(provider: .codex, command: ["/bin/sleep", "10"]))
}
