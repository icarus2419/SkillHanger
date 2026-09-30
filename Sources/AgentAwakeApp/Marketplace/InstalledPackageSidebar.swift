import SwiftUI

struct InstalledPackageSidebar: View {
    @ObservedObject var store: MarketplaceStore
    @Binding var page: AppPage
    @State private var search = ""
    @State private var revealedSelection: PackageSelection?
    @State private var uninstallTarget: InstalledPackage?
    @FocusState private var searchFocused: Bool

    init(store: MarketplaceStore, page: Binding<AppPage>) {
        self.store = store
        self._page = page
        let args = ProcessInfo.processInfo.arguments
        let initial = store.preview ? args.firstIndex(of: "--installed-search-preview").flatMap {
            args.indices.contains($0 + 1) ? args[$0 + 1] : nil
        } ?? "" : ""
        self._search = State(initialValue: initial)
    }

    private var groups: [InstalledLibraryGroup] {
        InstalledLibraryQuery(search: search).groups(in: store.workspaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("INSTALLED").tracking(1)
                Text("\(store.workspaces.count)").monospacedDigit()
                Spacer(minLength: 0)
                Button { page = .installed; revealedSelection = nil } label: {
                    Label("Manage", systemImage: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).frame(height: 26)
                        .background(page == .installed ? ShellPalette.brandHighlight.opacity(0.22) : .white.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityLabel("Manage installed skills and plugins")
                .help("Open installed packages dashboard")
            }.font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 10)
            HStack(spacing: 6) {
                Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain).keyboardShortcut("f", modifiers: [.command, .shift])
                    .accessibilityLabel("Search installed packages").help("Search installed (⇧⌘F)")
                TextField("Find installed…", text: $search)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Filter installed skills and plugins")
                    .onExitCommand { search = ""; searchFocused = false }
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear installed search")
                }
            }.font(.system(size: 11)).padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(searchFocused ? ShellPalette.brandHighlight : .white.opacity(0.10)))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if groups.isEmpty {
                            Text(store.workspaces.isEmpty ? "Nothing installed yet" : "No installed matches").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 10).padding(.top, 8)
                            if !store.workspaces.isEmpty { Button("Clear search") { search = "" }
                                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(ShellPalette.brandHighlight)
                                .padding(.horizontal, 10).padding(.bottom, 8) }
                        }
                        ForEach(groups) { group in
                            HStack {
                                Text(group.agent.title)
                                Spacer()
                                Text("\(group.packages.count)").monospacedDigit()
                            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
                            ForEach(group.packages) { workspace in
                                InstalledPackageSidebarRow(workspace: workspace,
                                    selected: page == .packageWorkspace && store.workspaceSelection == workspace.selection,
                                    disabled: store.disabledSkills[workspace.agent]?.contains(workspace.item.id) == true || store.pluginEnabled[workspace.agent]?[workspace.item.id] == false,
                                    canUninstall: store.canRemove(workspace.item, agent: workspace.agent),
                                    busy: store.isBusy(workspace.item, agent: workspace.agent),
                                    preview: store.preview, revealedSelection: $revealedSelection,
                                    action: {
                                        store.openWorkspace(workspace.item, agent: workspace.agent)
                                        page = .packageWorkspace
                                    }, uninstall: { uninstallTarget = workspace },
                                    fullSwipeUninstall: { store.remove(workspace.item, agent: workspace.agent) }).id(workspace.id)
                            }
                        }
                    }.padding(.trailing, 16).padding(.bottom, 4)
                }.accessibilityLabel("Installed packages by agent")
                    .task(id: page == .packageWorkspace ? store.workspaceSelection : nil) {
                        guard page == .packageWorkspace, let selection = store.workspaceSelection,
                              store.workspaces.contains(where: { $0.selection == selection }) else { return }
                        do { try await Task.sleep(for: .milliseconds(80)) }
                        catch { return }
                        guard page == .packageWorkspace, store.workspaceSelection == selection,
                              revealedSelection == nil else { return }
                        if !groups.flatMap(\.packages).contains(where: { $0.selection == selection }) { search = "" }
                        // Focus once, without leaving a native scroll animation
                        // that could resume after the user returns to the library.
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { proxy.scrollTo(selection.id, anchor: .center) }
                    }
            }
        }.padding(.horizontal, 12).padding(.top, 16)
            .onChange(of: search) { _ in revealedSelection = nil }
            .onChange(of: page) { _ in revealedSelection = nil }
            .alert(item: $uninstallTarget) { workspace in
                Alert(title: Text("Uninstall \(workspace.item.title) from \(workspace.agent.title)?"),
                      message: Text(store.externalSkills[workspace.agent]?.contains(workspace.item.id) == true ? "The skill folder will move to Trash. You can restore it from Finder." : "This removes the package from this agent. Locally changed skill files are preserved."),
                      primaryButton: .destructive(Text("Uninstall")) { store.remove(workspace.item, agent: workspace.agent) },
                      secondaryButton: .cancel())
            }
    }
}
