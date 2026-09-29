import AppKit
import SwiftUI
import UsageCore

@MainActor
struct UnifiedMenuLabel: View {
    @ObservedObject var usage: UsageStore
    @ObservedObject var prefs: Prefs
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    init(runtime: AppRuntime) {
        self.init(usage: runtime.usage, prefs: runtime.prefs)
    }

    init(usage: UsageStore, prefs: Prefs) {
        self.usage = usage
        self.prefs = prefs
    }

    var body: Image {
        Image(nsImage: renderedImage(colorScheme: colorScheme, scale: displayScale))
            .renderingMode(.original)
    }

    func renderedImage(colorScheme: ColorScheme, scale: CGFloat) -> NSImage {
        let readings = prefs.providers.map { usage.reading(for: $0) }
        let content = Group {
            if readings.isEmpty {
                BrandMark(size: 18)
            } else {
                MenuBarLabel(readings: readings)
            }
        }
        .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = false
        image.accessibilityDescription = readings.isEmpty ? "SkillHanger" : readings.map { reading in
            let value = reading.percent.map { "\(Int($0.rounded())) percent remaining" } ?? "No reading"
            return "\(reading.provider.displayName), \(value)"
        }.joined(separator: "; ")
        return image
    }
}

struct QuickMenuView: View {
    @ObservedObject var runtime: AppRuntime
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                BrandMark(size: 28).padding(3).background(ShellPalette.sidebar, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("SkillHanger").font(.system(size: 15, weight: .semibold))
                    Text(runtime.monitor.runningCount == 0 ? "Ready for your next task" : "\(runtime.monitor.runningCount) task working")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { runtime.open(.overview) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain).help("Open SkillHanger").accessibilityLabel("Open SkillHanger")
            }
            Divider()
            if runtime.prefs.providers.isEmpty {
                Text("Usage checks are disabled.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(runtime.prefs.providers) { provider in
                let reading = runtime.usage.reading(for: provider)
                HStack(spacing: 10) {
                    ProviderMark(provider: provider, size: 15)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider == .claude ? "Claude" : "Codex").font(.system(size: 12, weight: .medium))
                        Text(reading.error?.shortLabel ?? reading.window?.label ?? "No reading yet")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    BatteryView(percent: reading.percent, color: Palette.level(reading.percent, colorful: runtime.prefs.colorful),
                                scale: 1.05, dimmed: reading.isStale || reading.percent == nil, monochrome: !runtime.prefs.colorful)
                }
            }
            Divider()
            SwitchRow(title: "Prevent idle sleep during tasks", value: $runtime.monitor.preventsIdleSleep)
            SwitchRow(title: "Floating widget", value: $runtime.prefs.widgetVisible)
            Text(runtime.monitor.sleepProtectionActive ? "Idle system sleep is prevented." : "Normal system sleep is allowed.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                ActionButton(title: "Open app", symbol: "macwindow", prominent: true) { runtime.open(.overview) }
                Spacer()
                Button { runtime.open(.settings) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Settings").accessibilityLabel("Open settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.plain).help("Quit SkillHanger").accessibilityLabel("Quit SkillHanger")
            }
        }.padding(20).frame(width: 340).background(ShellPalette.surface).tint(ShellPalette.accent)
    }
}
