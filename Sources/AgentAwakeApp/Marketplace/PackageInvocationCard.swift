import SwiftUI
import AppKit

struct PackageInvocationCard: View {
    let workspace: InstalledPackage
    @ObservedObject var store: MarketplaceStore
    @ObservedObject var preferences: PackagePreferences
    @State private var copied = false
    private var item: CatalogItem { workspace.item }
    private var selection: PackageSelection { workspace.selection }
    private var modes: [String] { PackageCustomization.modes(item) }
    private var disabled: Bool { store.disabledSkills[workspace.agent]?.contains(item.id) == true || store.pluginEnabled[workspace.agent]?[item.id] == false }
    private var mode: Binding<String> {
        Binding(get: { let value = preferences.mode(for: selection); return modes.contains(value) ? value : "full" },
                set: { preferences.setMode($0, for: selection) })
    }
    private var task: Binding<String> {
        Binding(get: { preferences.task(for: selection) }, set: { preferences.setTask($0, for: selection) })
    }
    private var invocation: String {
        PackageCustomization.invocation(item, agent: workspace.agent, mode: mode.wrappedValue, task: task.wrappedValue, options: preferences.options(for: selection))
    }
    var body: some View {
            Surface {
              VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Customize your invocation", detail: "Saved for \(workspace.agent.title). Copy it into a new agent session to apply.")
                if item.kind == .skill && store.managedSkills[workspace.agent]?.contains(item.id) == true {
                    SwitchRow(title: "Enable skill", detail: "Available to new \(workspace.agent.title) sessions. Disabled skills keep their files and preferences.", symbol: "power",
                              value: Binding(get: { !disabled }, set: { store.setSkillEnabled(item, agent: workspace.agent, enabled: $0) }))
                        .disabled(store.preview || store.busy.contains(workspace.id))
                    Divider()
                }
                if item.kind == .plugin && workspace.agent == .claude {
                    if let enabled = store.pluginEnabled[.claude]?[item.id] {
                        SwitchRow(title: "Enable plugin", detail: "Changes Claude Code’s user-scope plugin setting. Start a new session after changing it.", symbol: "power", value: Binding(get: { enabled }, set: { store.setPluginEnabled(item, agent: .claude, enabled: $0) }))
                            .disabled(store.checking || store.busy.contains(workspace.id) || store.preview)
                    } else {
                        HStack {
                            Text("Plugin status hasn’t been confirmed yet.").font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                            Spacer()
                            Button("Check status") { Task { await store.reconcile() } }.buttonStyle(ProductButtonStyle()).disabled(store.checking || store.preview)
                        }
                    }
                    if let error = store.cliErrors[.claude] { MarketplaceNotice(text: error) }
                    Divider()
                }
                if !modes.isEmpty {
                    SettingRow(title: item.name == "caveman" ? "Reply compression" : "Simplicity mode", symbol: "slider.horizontal.3") {
                        Menu {
                            ForEach(modes, id: \.self) { option in
                                Button { mode.wrappedValue = option } label: {
                                    if option == mode.wrappedValue { Label(option.replacingOccurrences(of: "-", with: " ").capitalized, systemImage: "checkmark") }
                                    else { Text(option.replacingOccurrences(of: "-", with: " ").capitalized) }
                                }
                            }
                        } label: {
                            Text(mode.wrappedValue.replacingOccurrences(of: "-", with: " ").capitalized)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary)
                        }.menuStyle(.borderlessButton).fixedSize().frame(width: 170, alignment: .trailing)
                            .accessibilityLabel("Compression mode, \(mode.wrappedValue)")
                    }
                    Text(PackageCustomization.modeDescription(mode.wrappedValue, item: item))
                        .font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                    Divider()
                }
                PackageOptionControls(item: item, selection: selection, preferences: preferences)
                Text("Task or extra instructions").font(.system(size: 12, weight: .medium))
                TextField("Optional instructions to include when you invoke this package", text: task, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Task or extra instructions for \(item.title)")
                Text("Keep credentials out of saved instructions.").font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                Text(invocation).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ShellPalette.inset, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button(copied ? "Copied" : "Copy invocation") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(invocation, forType: .string)
                        copied = true
                    }.buttonStyle(ProductButtonStyle(prominent: true)).disabled(disabled)
                    if item.name == "caveman" {
                        Button("Copy normal mode") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString("normal mode", forType: .string)
                        }.buttonStyle(ProductButtonStyle())
                    }
                }
                Button("Reset invocation preferences") { preferences.reset(for: selection) }
                    .buttonStyle(ProductButtonStyle())
                    .help("Restores this package’s modes, options, and saved task for this agent. Does not change enable status.")
                if disabled { Text("Re-enable this package before invoking it in a new agent session.").font(.system(size: 11)).foregroundStyle(ShellPalette.muted) }
              }
            }
        .onChange(of: invocation) { _ in copied = false }
    }
}
