import SwiftUI

struct InstalledPackagesPage: View {
    @ObservedObject var store: MarketplaceStore
    @Binding var page: AppPage
    @State private var search = ""
    @State private var agentFilter: MarketplaceAgent?
    @State private var uninstallTarget: InstalledPackage?

    private var groups: [InstalledLibraryGroup] {
        InstalledLibraryQuery(search: search).groups(in: store.workspaces)
            .filter { agentFilter == nil || $0.agent == agentFilter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("YOUR WORKSPACE")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.3)
                        .foregroundStyle(ShellPalette.accent)
                    Text("\(store.workspaces.count) installed packages")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("Open a package to edit its settings, or uninstall it from one agent.")
                        .font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(ShellPalette.muted)
                    TextField("Find installed skills and plugins", text: $search)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search installed packages")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(ShellPalette.muted)
                            .accessibilityLabel("Clear search")
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12).frame(height: 38)
                .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ShellPalette.line))

                HStack(spacing: 2) {
                    filterButton("All", agent: nil)
                    ForEach(MarketplaceAgent.allCases) { agent in
                        filterButton(agent.title, agent: agent)
                    }
                }
                .padding(3)
                .background(ShellPalette.inset, in: RoundedRectangle(cornerRadius: 10))
            }

            if groups.isEmpty {
                EmptyPanel(
                    title: store.workspaces.isEmpty ? "No packages installed" : "No matching packages",
                    detail: store.workspaces.isEmpty ? "Find skills and plugins in the Skill Library to add them to your workspace." : "Try another search or choose a different agent.",
                    symbol: "square.stack.3d.up",
                    actionTitle: store.workspaces.isEmpty ? "Browse library" : "Clear filters",
                    action: {
                        if store.workspaces.isEmpty { store.browse(); page = .marketplace }
                        else { search = ""; agentFilter = nil }
                    }
                )
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.agent.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(group.packages.count)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(ShellPalette.muted)
                            Spacer()
                        }
                        .padding(.horizontal, 2)
                        .accessibilityAddTraits(.isHeader)

                        VStack(spacing: 0) {
                            ForEach(Array(group.packages.enumerated()), id: \.element.id) { index, workspace in
                                InstalledManagementRow(
                                    workspace: workspace,
                                    disabled: store.disabledSkills[workspace.agent]?.contains(workspace.item.id) == true || store.pluginEnabled[workspace.agent]?[workspace.item.id] == false,
                                    busy: store.isBusy(workspace.item, agent: workspace.agent),
                                    canUninstall: store.canRemove(workspace.item, agent: workspace.agent) && !store.preview,
                                    edit: {
                                        store.openWorkspace(workspace.item, agent: workspace.agent)
                                        page = .packageWorkspace
                                    },
                                    uninstall: { uninstallTarget = workspace }
                                )
                                if index < group.packages.count - 1 {
                                    Rectangle().fill(ShellPalette.line).frame(height: 1).padding(.leading, 58)
                                }
                            }
                        }
                        .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ShellPalette.line).allowsHitTesting(false))
                    }
                }
            }
            if let message = store.message { MarketplaceNotice(text: message) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(item: $uninstallTarget) { workspace in
            Alert(title: Text("Uninstall \(workspace.item.title) from \(workspace.agent.title)?"),
                  message: Text(store.externalSkills[workspace.agent]?.contains(workspace.item.id) == true ? "The skill folder will move to Trash. You can restore it from Finder." : "This removes the package from this agent. Locally changed skill files are preserved."),
                  primaryButton: .destructive(Text("Uninstall")) { store.remove(workspace.item, agent: workspace.agent) },
                  secondaryButton: .cancel())
        }
    }

    private func filterButton(_ title: String, agent: MarketplaceAgent?) -> some View {
        let selected = agentFilter == agent
        return Button { agentFilter = agent } label: {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.primary : ShellPalette.muted)
                .padding(.horizontal, 10).frame(height: 30)
                .background(selected ? ShellPalette.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct InstalledManagementRow: View {
    let workspace: InstalledPackage
    let disabled: Bool
    let busy: Bool
    let canUninstall: Bool
    let edit: () -> Void
    let uninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: edit) {
                HStack(spacing: 12) {
                    PackageIcon(item: workspace.item, size: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workspace.item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Text("\(workspace.item.kind == .skill ? "Skill" : "Plugin") · \(workspace.item.author)")
                            .font(.system(size: 11))
                            .foregroundStyle(ShellPalette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(workspace.item.title) for \(workspace.agent.title)")
            .help("Open package settings")
            .disabled(busy)

            if busy { ProgressView().controlSize(.small) }
            else { StatusPill(text: disabled ? "Disabled" : "Installed", symbol: disabled ? "pause.circle" : "checkmark.circle") }

            Button(action: edit) {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(ProductButtonStyle())
            .disabled(busy)

            Button(action: uninstall) {
                Image(systemName: "trash").frame(width: 16, height: 16)
            }
            .buttonStyle(ProductButtonStyle())
            .foregroundStyle(ShellPalette.danger)
            .disabled(!canUninstall || busy)
            .accessibilityLabel("Uninstall \(workspace.item.title) from \(workspace.agent.title)")
            .help("Uninstall from \(workspace.agent.title)")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 62)
    }
}
