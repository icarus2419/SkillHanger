import SwiftUI

/// A single, consistent reading of the monitor and the protection it actually holds.
struct ProtectionSummary: View {
    @ObservedObject var runtime: AppRuntime
    private var active: Bool { runtime.monitor.sleepProtectionActive }
    private var attention: Bool { runtime.monitor.errorMessage != nil }
    private var status: String {
        if attention { return "Needs attention" }
        if !runtime.monitor.isMonitoringEnabled { return "Paused" }
        return active ? "Protected" : "Standby"
    }
    private var title: String {
        if attention { return "Monitoring needs attention" }
        if !runtime.monitor.isMonitoringEnabled { return "Task monitoring is paused" }
        if runtime.monitor.runningCount > 0 {
            return "\(runtime.monitor.runningCount) task\(runtime.monitor.runningCount == 1 ? "" : "s") working"
        }
        return "Ready for your next task"
    }
    private var detail: String {
        if let error = runtime.monitor.errorMessage { return error }
        if active { return "Your Mac stays awake until the work ends or needs your input." }
        if !runtime.monitor.isMonitoringEnabled { return "Resume monitoring to follow your agents' activity." }
        if !runtime.monitor.preventsIdleSleep { return "Idle sleep protection is off. Your Mac follows its normal sleep settings." }
        return "Sleep protection begins with a confirmed task. Normal sleep is allowed now."
    }
    private var actionTitle: String { runtime.page == .awake ? "View activity" : "Sleep settings" }
    private var statusColor: Color { attention ? ShellPalette.warning : active ? ShellPalette.accent : ShellPalette.muted }
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Image(systemName: active ? "bolt.shield" : "moon.stars")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(statusColor)
                .frame(width: 56, height: 56)
                .background(ShellPalette.inset, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Sleep protection").font(.system(size: 11, weight: .medium)).foregroundStyle(ShellPalette.muted)
                    StatusPill(text: status, symbol: attention ? "exclamationmark.circle" : active ? "checkmark.shield" : "moon", color: statusColor)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                    Text(detail).font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 470, alignment: .leading)
                }
                if runtime.isPreview {
                    Text("Sample status · no power settings changed")
                        .font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                }
            }.accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            ActionButton(title: actionTitle, symbol: "arrow.up.right") {
                runtime.page = runtime.page == .awake ? .activity : .awake
            }.fixedSize()
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ShellPalette.line).allowsHitTesting(false))
    }
}
