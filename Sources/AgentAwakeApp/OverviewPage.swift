import SwiftUI

struct OverviewPage: View {
    @ObservedObject var runtime: AppRuntime
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProtectionSummary(runtime: runtime)
            Surface(padding: 0) {
                HStack(spacing: 0) {
                    QuickSwitchTile(title: "Idle protection", detail: "While tasks work", symbol: "bolt.shield", value: $runtime.monitor.preventsIdleSleep)
                    Divider().frame(height: 36)
                    QuickSwitchTile(title: "Floating widget", detail: "Usage at a glance", symbol: "rectangle.on.rectangle", value: $runtime.prefs.widgetVisible)
                    Divider().frame(height: 36)
                    QuickSwitchTile(title: "Usage alerts", detail: "Low allowance & refills", symbol: "bell.badge", value: $runtime.prefs.alerts)
                }
            }
            HStack {
                SectionHeading(title: "Plan allowance")
                Spacer()
                ActionButton(title: "View usage", symbol: "arrow.up.right") { runtime.page = .usage }
            }
            HStack(alignment: .top, spacing: 16) {
                UsageProviderCard(runtime: runtime, provider: .claude, compact: true)
                UsageProviderCard(runtime: runtime, provider: .openai, compact: true)
            }
            HStack {
                SectionHeading(title: "Recent sessions")
                Spacer()
                ActionButton(title: "View activity", symbol: "arrow.up.right") { runtime.page = .activity }
            }
            Surface(padding: 0) {
                if runtime.monitor.tasks.isEmpty {
                    EmptyPanel(title: runtime.monitor.isMonitoringEnabled ? "Ready to track a task" : "Monitoring is paused",
                               detail: "Connect your agent to see its task state and reported usage.",
                               symbol: "terminal", actionTitle: "Connect agent") { runtime.connectAgent() }
                } else {
                    ForEach(Array(runtime.monitor.tasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                        TaskActivityRow(task: task, now: runtime.monitor.now)
                        if index < min(runtime.monitor.tasks.count, 3) - 1 { Divider().padding(.leading, 68) }
                    }
                }
            }
        }
    }
}
