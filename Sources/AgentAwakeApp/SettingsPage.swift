import SwiftUI

struct SettingsPage: View {
    @ObservedObject var runtime: AppRuntime
    @State private var category = "General"
    init(runtime: AppRuntime) {
        self.runtime = runtime
        let args = ProcessInfo.processInfo.arguments
        if runtime.isPreview, let index = args.firstIndex(of: "--settings-tab"), args.indices.contains(index + 1) {
            _category = State(initialValue: args[index + 1] == "widget" ? "Widget" : args[index + 1] == "awake" ? "Awake" : "General")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ChoiceStrip(options: ["General", "Widget", "Awake"], selection: $category,
                        label: { $0 == "Widget" ? "Floating widget" : $0 == "Awake" ? "Agent Awake" : "General" },
                        accessibilityTitle: "Settings section")
            if category == "General" { general }
            else if category == "Widget" { widget }
            else { awake }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 24) {
            Surface {
                SectionHeading(title: "Appearance & startup", detail: "Keep SkillHanger close while you work.")
                SettingRow(title: "Appearance", detail: "Applies to the window and floating widget.", symbol: "circle.lefthalf.filled") {
                    Picker("Appearance", selection: $runtime.prefs.theme) {
                        ForEach(Theme.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                }
                Divider()
                SwitchRow(title: "Launch at login", detail: "Have SkillHanger ready when you sign in.", symbol: "power",
                          value: Binding(get: { runtime.launchAtLogin }, set: { runtime.setLogin($0) }))
                    .disabled(runtime.isPreview || !LoginItem.isAvailable)
                Divider()
                SwitchRow(title: "Show in menu bar", detail: "Quick usage readings and sleep controls.", symbol: "menubar.rectangle",
                          value: $runtime.prefs.showMenuBar)
                Divider()
                SwitchRow(title: "Show floating widget", detail: "A small, draggable view of your plan allowance.", symbol: "rectangle.on.rectangle",
                          value: $runtime.prefs.widgetVisible)
            }
            Surface {
                SectionHeading(title: "Providers & updates", detail: "Choose the allowance readings you want to follow.")
                SwitchRow(title: "Claude usage", detail: "Uses your existing Claude Code login.", symbol: "asterisk", value: $runtime.prefs.showClaude)
                Divider()
                SwitchRow(title: "Codex usage", detail: "Uses your Codex login and local usage snapshots.", symbol: "hexagon", value: $runtime.prefs.showOpenAI)
                Divider()
                SettingRow(title: "Automatic refresh", detail: "Four minutes is recommended. Retry windows and live local updates are respected.", symbol: "arrow.clockwise") {
                    UsagePage(runtime: runtime).refreshPicker
                }
                Divider()
                SwitchRow(title: "Usage notifications", detail: "Low allowance, depletion, and refill alerts.", symbol: "bell", value: $runtime.prefs.alerts)
            }
            about
        }
    }

    private var widget: some View {
        VStack(alignment: .leading, spacing: 24) {
            Surface {
                HStack {
                    SectionHeading(title: "Widget preview", detail: "Uses your current readings and preferences.")
                    Spacer()
                    StatusPill(text: runtime.prefs.widgetVisible ? "Visible" : "Hidden",
                               symbol: runtime.prefs.widgetVisible ? "eye" : "eye.slash")
                }
                WidgetPreviewStage(runtime: runtime).padding(.top, 16)
            }
            Surface {
                SectionHeading(title: "Display")
                SwitchRow(title: "Show widget", value: $runtime.prefs.widgetVisible)
                Divider()
                SettingRow(title: "Layout", symbol: "rectangle.split.2x1") {
                    Picker("Widget layout", selection: $runtime.prefs.layout) {
                        ForEach(Layout.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
                Divider()
                SettingRow(title: "Size", symbol: "arrow.up.left.and.arrow.down.right") {
                    Picker("Widget size", selection: $runtime.prefs.size) {
                        ForEach(WidgetSize.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                }
                Divider()
                SettingRow(title: "Opacity", symbol: "circle.dotted") {
                    HStack(spacing: 12) {
                        Slider(value: $runtime.prefs.opacity, in: 0.3...1).frame(width: 150).accessibilityLabel("Widget opacity")
                        Text("\(Int(runtime.prefs.opacity * 100))%").font(.system(size: 11, design: .monospaced)).frame(width: 38)
                    }
                }
                Divider()
                SwitchRow(title: "Provider names", detail: "Show names beside the allowance bars.", value: $runtime.prefs.showNames)
                Divider()
                SwitchRow(title: "Colorful allowance bars", detail: "Green, amber, and red indicate remaining capacity.", value: $runtime.prefs.colorful)
                Divider()
                SettingRow(title: "Primary limit", detail: "Choose what the widget and menu bar show.") {
                    Picker("Primary allowance", selection: $runtime.prefs.metric) {
                        ForEach(Metric.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 185)
                }
            }
            Surface {
                SectionHeading(title: "Position & behavior")
                SettingRow(title: "Placement") {
                    Picker("Widget placement", selection: $runtime.prefs.placement) {
                        ForEach(Placement.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 210)
                }
                Divider()
                SwitchRow(title: "Lock position", detail: "Prevents accidental dragging.", value: $runtime.prefs.locked)
                Divider()
                SwitchRow(title: "Snap to screen edges", detail: "Position is remembered between launches.", value: $runtime.prefs.snapToEdges)
                Divider()
                SettingRow(title: "Reset widget position", detail: "Move it beneath the menu bar on the main screen.") {
                    ActionButton(title: "Reset position", symbol: "arrow.counterclockwise") { runtime.resetWidgetPosition() }
                }
            }
        }
    }

    private var awake: some View {
        VStack(alignment: .leading, spacing: 24) {
            Surface {
                SectionHeading(title: "Task & sleep preferences")
                SwitchRow(title: "Enable task monitoring", value: $runtime.monitor.isMonitoringEnabled)
                Divider()
                SwitchRow(title: "Prevent idle system sleep", detail: "Only for confirmed running tasks.", value: $runtime.monitor.preventsIdleSleep)
                Divider()
                SwitchRow(title: "Monitor Claude Code tasks", value: $runtime.monitor.monitorClaude)
                Divider()
                SwitchRow(title: "Monitor Codex tasks", value: $runtime.monitor.monitorCodex)
                Divider()
                SettingRow(title: "Dim task display after idle") {
                    Picker("Dim display delay", selection: $runtime.monitor.overlayIdleSeconds) {
                        Text("Off").tag(0)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }.labelsHidden().frame(width: 145)
                }
                Divider()
                SwitchRow(title: "Animate task display", detail: "Respects macOS Reduce Motion.", value: $runtime.monitor.animateOverlay)
            }
            ClosedLidSection(runtime: runtime)
        }
    }

    private var about: some View {
        HStack(alignment: .top, spacing: 12) {
            BrandMark(size: 40).padding(10).background(ShellPalette.sidebar, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("SkillHanger 0.2").font(.system(size: 12, weight: .semibold))
                Text("Agent activity and plan allowance. No prompts or transcripts stored.")
                    .font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
            }
            Spacer()
            ActionButton(title: "Task setup", symbol: "terminal") { runtime.connectAgent() }
        }.padding(8)
    }
}
