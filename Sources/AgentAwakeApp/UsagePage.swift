import SwiftUI
import UsageCore

struct UsagePage: View {
    @ObservedObject var runtime: AppRuntime
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                SectionHeading(title: "Plan allowance", detail: "Remaining capacity, updated from your existing logins.")
                Spacer(minLength: 12)
                ChoiceStrip(options: ["lowest", "session", "weekly"],
                            selection: Binding(get: { runtime.prefs.metric.rawValue }, set: { runtime.prefs.metric = Metric(rawValue: $0) ?? .lowest }),
                            label: { $0 == "session" ? "5-hour" : $0 == "weekly" ? "Weekly" : "Lowest" },
                            accessibilityTitle: "Primary limit")
            }
            providerCards
            Surface {
                SectionHeading(title: "Reading preferences")
                SwitchRow(title: "Low-allowance alerts", detail: "Notify at 20%, 10%, depletion, and refill.", symbol: "bell", value: $runtime.prefs.alerts)
                Divider()
                SettingRow(title: "Automatic refresh", detail: "Four minutes balances freshness and fewer requests. Local Codex updates arrive between checks.", symbol: "arrow.clockwise") {
                    refreshPicker
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield").font(.system(size: 15)).foregroundStyle(ShellPalette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Uses your existing Claude Code and Codex logins. No model requests or AI tokens spent.")
                        .font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                    Text("Codex may use local rate-limit snapshots. Provider usage endpoints can change.")
                        .font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                }
            }.padding(.horizontal, 2)
        }
    }

    var providerCards: some View {
        HStack(alignment: .top, spacing: 16) {
            UsageProviderCard(runtime: runtime, provider: .claude)
            UsageProviderCard(runtime: runtime, provider: .openai)
        }
    }
    var refreshPicker: some View {
        Menu {
            ForEach(Prefs.refreshOptions, id: \.self) { minutes in
                Button {
                    runtime.prefs.refreshMinutes = minutes
                } label: {
                    if runtime.prefs.refreshMinutes == minutes { Label("Every \(minutes) min", systemImage: "checkmark") }
                    else { Text("Every \(minutes) min\(minutes == Prefs.defaultRefreshMinutes ? " · Recommended" : "")") }
                }
            }
        } label: {
            Text("Every \(runtime.prefs.refreshMinutes) min").font(.system(size: 11))
        }.menuStyle(.borderlessButton).fixedSize().frame(width: 140, alignment: .trailing)
            .accessibilityLabel("Refresh interval, every \(runtime.prefs.refreshMinutes) minutes")
    }
}

struct UsageProviderCard: View {
    @ObservedObject var runtime: AppRuntime
    let provider: UsageCore.Provider
    var compact = false
    private var enabled: Bool { runtime.prefs.isShown(provider) }
    private var reading: Reading { runtime.usage.reading(for: provider) }
    private var name: String { provider == .claude ? "Claude" : "Codex" }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: compact ? 16 : 24) {
                HStack(spacing: 10) {
                    ProviderMark(provider: provider, size: 21).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.system(size: 13, weight: .semibold))
                        Text(enabled ? (reading.usage?.plan ?? "Plan allowance") : "Checks disabled")
                            .font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                    }
                    Spacer(minLength: 8)
                    if compact {
                        Text(enabled ? (reading.percent.map(UsageFormat.percent) ?? "—") : "—")
                            .font(.system(size: 26, weight: .regular)).monospacedDigit().tracking(-0.8)
                            .foregroundStyle(reading.isStale || !enabled ? ShellPalette.muted : Color.primary)
                            .accessibilityLabel("\(name), \(reading.percent.map(UsageFormat.percent) ?? "no reading") remaining")
                    } else {
                        providerToggle
                    }
                }
                if enabled {
                    if !compact {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(reading.percent.map(UsageFormat.percent) ?? "—")
                                    .font(.system(size: 44, weight: .regular)).monospacedDigit().tracking(-1.8)
                                    .foregroundStyle(reading.isStale ? ShellPalette.muted : Color.primary)
                                Text("remaining").font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
                            }
                            Text(reading.window.map { "Based on your \($0.label.lowercased()) limit" } ?? "Waiting for an allowance reading")
                                .font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: compact ? 14 : 20) {
                        if let usage = reading.usage {
                            ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, window in
                                WindowRow(window: window, now: runtime.usage.now, colorful: runtime.prefs.colorful)
                            }
                        } else {
                            Capsule().fill(Color.primary.opacity(0.09)).frame(height: 5).accessibilityHidden(true)
                            Text(reading.isLoading ? "Checking your existing login…" : "Sign in with \(provider == .claude ? "claude" : "codex login") to see your limits.")
                                .font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
                                .fixedSize(horizontal: false, vertical: true).frame(minHeight: compact ? 36 : 54, alignment: .top)
                        }
                    }
                    if let error = reading.error {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(error.shortLabel, systemImage: "exclamationmark.circle")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(ShellPalette.warning)
                            Text(error.localizedDescription).font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            if let retry = reading.nextCheckAt, retry > runtime.usage.now {
                                Text("Next check in \(UsageFormat.duration(retry.timeIntervalSince(runtime.usage.now)))")
                                    .font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(ShellPalette.warning.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    }
                    if reading.isProjected {
                        Label("Reset passed · awaiting a fresh reading", systemImage: "clock")
                            .font(.system(size: 10)).foregroundStyle(ShellPalette.warning)
                    }
                    VStack(spacing: 12) {
                        Divider()
                        HStack(spacing: 5) {
                            Image(systemName: sourceSymbol)
                            Text(sourceLabel).lineLimit(2)
                            Spacer(minLength: 0)
                            Link(destination: provider.usagePageURL) { Image(systemName: "arrow.up.right").frame(width: 18, height: 18) }
                                .accessibilityLabel("Open \(name) usage page").help("Open \(name) usage page")
                        }.font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                    }
                } else {
                    EmptyPanel(title: "\(name) checks are off", detail: "Enable checks to read your plan allowance.", symbol: "pause.circle",
                               actionTitle: "Enable \(name)") { runtime.prefs.setShown(provider, true) }
                }
            }
        }
    }

    private var providerToggle: some View {
        Toggle("Check \(name) usage", isOn: Binding(get: { enabled }, set: { runtime.prefs.setShown(provider, $0) }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            .accessibilityLabel("Check \(name) usage")
    }
    private var sourceLabel: String {
        if reading.isLoading { return "Checking usage…" }
        guard let usage = reading.usage else { return reading.error?.shortLabel ?? "Waiting for first reading" }
        let source = usage.source == .localLog ? "Local snapshot" : "Usage service"
        return "\(reading.isStale ? "Last known · " : "")\(source) · \(UsageFormat.ago(usage.observedAt, now: runtime.usage.now))"
    }
    private var sourceSymbol: String {
        if reading.isLoading { return "arrow.clockwise" }
        if reading.isStale { return "clock.badge.exclamationmark" }
        if reading.usage == nil { return reading.error == nil ? "clock" : "exclamationmark.circle" }
        return reading.usage?.source == .localLog ? "internaldrive" : "checkmark.circle"
    }
}
