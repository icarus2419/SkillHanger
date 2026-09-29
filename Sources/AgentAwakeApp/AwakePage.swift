import SwiftUI
import AgentAwakeCore

struct AwakePage: View {
    @ObservedObject var runtime: AppRuntime
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ProtectionSummary(runtime: runtime)
            HStack(alignment: .top, spacing: 16) {
                Surface {
                    SectionHeading(title: "Task monitoring", detail: "Activity controls sleep protection.")
                    SwitchRow(title: "Enable monitoring", detail: "Watch local task lifecycle events.", value: $runtime.monitor.isMonitoringEnabled)
                    Divider()
                    SwitchRow(title: "Claude Code tasks", value: $runtime.monitor.monitorClaude).disabled(!runtime.monitor.isMonitoringEnabled)
                    Divider()
                    SwitchRow(title: "Codex tasks", value: $runtime.monitor.monitorCodex).disabled(!runtime.monitor.isMonitoringEnabled)
                    Divider()
                    SwitchRow(title: "Prevent idle system sleep", detail: "Only while a confirmed task is working.", value: $runtime.monitor.preventsIdleSleep)
                }
                Surface {
                    SectionHeading(title: "Dim task display", detail: "A quiet view while you're away.")
                    SettingRow(title: "Show after inactivity") {
                        Menu {
                            ForEach([0, 30, 60, 120, 300], id: \.self) { seconds in
                                Button(seconds == 0 ? "Off" : seconds == 30 ? "30 seconds" : seconds == 60 ? "1 minute" : seconds == 120 ? "2 minutes" : "5 minutes") { runtime.monitor.overlayIdleSeconds = seconds }
                            }
                        } label: {
                            Text(runtime.monitor.overlayIdleSeconds == 0 ? "Off" : runtime.monitor.overlayIdleSeconds == 30 ? "30 seconds" : "\(runtime.monitor.overlayIdleSeconds / 60) min")
                                .font(.system(size: 11))
                        }.menuStyle(.borderlessButton).fixedSize().frame(width: 125, alignment: .trailing)
                            .accessibilityLabel("Dim display delay")
                    }
                    Divider()
                    SwitchRow(title: "Animate task display", detail: "Also respects macOS Reduce Motion.", value: $runtime.monitor.animateOverlay)
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Your terminal keeps working", systemImage: "terminal")
                            .font(.system(size: 12, weight: .medium))
                        Text("Move the mouse or press a key to dismiss the display. The screen can still sleep to save power.")
                            .font(.system(size: 11)).foregroundStyle(ShellPalette.muted).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 14)
                }
            }
            MonitoringSetup(runtime: runtime).id("agent-setup")
            ClosedLidSection(runtime: runtime)
        }
    }
}

struct ClosedLidSection: View {
    @ObservedObject var runtime: AppRuntime
    var body: some View {
        Surface {
            HStack {
                SectionHeading(title: "Closed-lid mode", detail: "Optional · requires the privileged helper.")
                Spacer()
                StatusPill(text: runtime.monitor.closedLidStatus == nil ? "Helper unavailable" : runtime.monitor.closedLidStatus!.state.label,
                           symbol: runtime.monitor.closedLidStatus == nil ? "minus.circle" : "checkmark.circle",
                           color: runtime.monitor.closedLidStatus == nil ? ShellPalette.muted : ShellPalette.accent)
            }
            SwitchRow(title: "Keep working with the lid closed",
                      detail: "Restores normal sleep when the last task ends, waits, or loses its lease.",
                      symbol: "laptopcomputer", value: $runtime.monitor.closedLidEnabled)
                .disabled(runtime.monitor.closedLidStatus == nil && !runtime.monitor.closedLidEnabled)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(runtime.monitor.closedLidError ?? "Starts at 30% battery; stops at 20% or under thermal pressure. Use a hard, ventilated surface.")
                        .font(.system(size: 11)).foregroundStyle(ShellPalette.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Task-controlled closed-lid operation still requires physical verification on this Mac.")
                        .font(.system(size: 10)).foregroundStyle(ShellPalette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ActionButton(title: "Setup instructions", symbol: "doc.text") { runtime.monitor.showClosedLidSetup() }
            }.padding(.top, 16)
        }
    }
}

struct MonitoringSetup: View {
    @ObservedObject var runtime: AppRuntime
    @State private var provider = "codex"
    private var command: String {
        let cli = shellQuoted(runtime.cliPath)
        return provider == "codex" ? "\(cli) run codex -- codex exec --json \"your task\"" :
            "\(cli) run claude -- claude -p --output-format json \"your task\""
    }
    var body: some View {
        Surface {
            HStack {
                SectionHeading(title: "Connect your agent", detail: "Start with a supervised command, or add interactive hooks.")
                Spacer()
                Picker("Agent", selection: $provider) {
                    Text("Codex").tag("codex")
                    Text("Claude Code").tag("claude")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            Text("Run from the folder where your agent should work. This command reports its lifecycle and observed token usage.")
                .font(.system(size: 12)).foregroundStyle(ShellPalette.muted).padding(.top, 16)
            HStack(alignment: .top, spacing: 12) {
                Text(command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Button { runtime.copy(command) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).accessibilityLabel("Copy supervised command").help("Copy command")
            }.padding(14).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8)).padding(.top, 8)
            DisclosureGroup("Interactive sessions: hook setup") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Merge handlers into \(provider == "codex" ? "~/.codex/hooks.json" : "~/.claude/settings.json"). Preserve existing hooks and provider settings.")
                        .font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
                    Text("Hook command").font(.system(size: 11, weight: .semibold))
                    Text("\(shellQuoted(runtime.cliPath)) hook \(provider)")
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text(provider == "codex" ? "Events: UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Stop, Interrupt, SessionEnd. Review loaded hooks with /hooks." :
                            "Events: UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Notification, Stop, StopFailure, SessionEnd.")
                        .font(.system(size: 11)).foregroundStyle(ShellPalette.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Hook-only activity becomes unknown after 120 silent seconds. The supervised wrapper is better for long, quiet batch tasks.")
                        .font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                    ActionButton(title: "Copy hook configuration", symbol: "doc.on.doc") { runtime.copy(hookJSON) }
                }.padding(.top, 12)
            }.font(.system(size: 12, weight: .medium)).padding(.top, 20)
        }
    }
    private func shellQuoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private var hookJSON: String {
        let events = provider == "codex" ?
            ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd"] :
            ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
        let command = "\(shellQuoted(runtime.cliPath)) hook \(provider)"
        var hooks: [String: Any] = [:]
        for event in events {
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            if event == "Notification" { entry["matcher"] = "permission_prompt|idle_prompt" }
            hooks[event] = [entry]
        }
        let data = try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.prettyPrinted, .sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
