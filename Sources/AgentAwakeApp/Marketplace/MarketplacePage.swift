import SwiftUI

struct MarketplacePage: View, Equatable {
    @ObservedObject var store: MarketplaceStore
    @State private var selected: CatalogItem?
    @FocusState private var searchFocused: Bool
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.store === rhs.store }
    var body: some View {
        let snapshot = store.snapshot
        VStack(alignment: .leading, spacing: 16) {
            toolbar
            if let notice = store.catalogNotice { MarketplaceNotice(text: notice, tone: .warning) }
            if let message = store.message {
                MarketplaceNotice(text: message) { store.message = nil }
            }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    categories(counts: snapshot.counts, total: snapshot.total)
                }.frame(width: 138).accessibilityLabel("Library categories")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(snapshot.results.count) \(store.query.scope.resultLabel(for: snapshot.results.count))")
                            .font(.system(size: 12, weight: .semibold))
                        if store.checking { ProgressView().controlSize(.small); Text("Checking installs…").font(.system(size: 10)).foregroundStyle(ShellPalette.muted) }
                        Spacer()
                        Picker("Sort", selection: $store.query.sort) {
                            Text("Featured").tag(CatalogSort.recommended)
                            Text("Name").tag(CatalogSort.name)
                            Text("Publisher").tag(CatalogSort.publisher)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                            .accessibilityLabel("Sort library results")
                    }
                    HStack(spacing: 8) {
                        Text(store.query.category?.rawValue ?? store.query.scope.detail)
                            .font(.system(size: 10)).foregroundStyle(ShellPalette.muted).lineLimit(1)
                        Spacer(minLength: 0)
                        if store.query.hasFilters {
                            Button("Clear filters") { store.query.clearFilters() }
                                .font(.system(size: 10, weight: .medium)).buttonStyle(.plain)
                                .foregroundStyle(ShellPalette.accent).help("Clear the search and category")
                        }
                    }
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if snapshot.results.isEmpty {
                                EmptyPanel(title: store.checking && store.query.scope == .installed ? "Finding your installed packages" : hasNoInstalls ? "Nothing installed for \(store.query.agent.title) yet" : "No matching \(store.query.scope.resultLabel)",
                                    detail: store.checking && store.query.scope == .installed ? "Your local skills are checked first, followed by the agent’s plugin list." : hasNoInstalls ? "Browse the library to add your first skill or plugin." : "Try a broader search or another category for \(store.query.agent.title).", symbol: hasNoInstalls ? "books.vertical" : "magnifyingglass",
                                    actionTitle: hasNoInstalls ? "Browse library" : "Clear filters", action: { if hasNoInstalls { store.browse() } else { store.query.clearFilters() } })
                                    .padding(.vertical, 16)
                            }
                            ForEach(snapshot.results) { item in
                                let agent = store.query.agent
                                MarketplaceRow(item: item, state: store.rowState(item), showDetail: { selected = item },
                                    install: { store.install(item, agent: agent) },
                                    customize: { store.openWorkspace(item, agent: agent) },
                                    cancel: { store.cancel(item, agent: agent) }).equatable()
                            }
                        }.padding(.trailing, 4).padding(.bottom, 16)
                    }.id(store.query).accessibilityLabel("Skill Library results")
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .task { await store.start() }
        .onChange(of: store.query.scope) { scope in
            if scope == .installed { Task { await store.reconcile(force: false) } }
        }
        .onChange(of: store.query.agent) { _ in Task { await store.reconcile(force: false) } }
        .sheet(item: $selected) { item in MarketplaceDetail(item: item, store: store) }
    }

    private var hasNoInstalls: Bool {
        store.query.scope == .installed && !store.checking && (store.installed[store.query.agent] ?? []).isEmpty
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.plain).foregroundStyle(ShellPalette.muted)
                        .keyboardShortcut("f", modifiers: .command)
                        .accessibilityLabel("Focus library search").help("Search library (⌘F)")
                    TextField("Search skills, plugins, or publishers", text: $store.query.search)
                        .textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("Search Skill Library")
                        .onExitCommand { store.query.search = ""; searchFocused = false }
                    if !store.query.search.isEmpty {
                        Button { store.query.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear library search")
                    }
                }.padding(12).background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(searchFocused ? ShellPalette.accent : ShellPalette.line).allowsHitTesting(false))
                VStack(alignment: .leading, spacing: 5) {
                    Text("INSTALL FOR").font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(ShellPalette.muted)
                    Picker("Agent", selection: $store.query.agent) {
                        ForEach(MarketplaceAgent.allCases) { agent in Text(agent.title).tag(agent) }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Agent to browse and install for")
                }.frame(width: 190)
            }
            HStack {
                Picker("Browse", selection: $store.query.scope) {
                    ForEach(CatalogScope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 410).accessibilityLabel("Library section")
                Spacer(minLength: 8)
                Label("\(store.items.count) packages", systemImage: "shippingbox")
                    .font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
            }
        }
    }
    private func categories(counts: [CatalogCategory: Int], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CATEGORIES").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                .foregroundStyle(ShellPalette.muted).padding(.bottom, 8)
            categoryButton(nil, title: "All categories", symbol: "square.grid.2x2", count: total)
            ForEach(store.categories) { category in
                categoryButton(category, title: category.rawValue, symbol: category.symbol,
                               count: counts[category, default: 0])
            }
            Divider().padding(.vertical, 12)
            Label("From GitHub", systemImage: "shippingbox").font(.system(size: 10, weight: .medium))
            Text("Publisher catalogs & community skills")
                .font(.system(size: 10)).foregroundStyle(ShellPalette.muted).fixedSize(horizontal: false, vertical: true)
            if let date = store.lastRefreshed {
                Text("Refreshed \(date.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 9)).foregroundStyle(ShellPalette.muted)
            } else { Text("Bundled · Sep 2026").font(.system(size: 9)).foregroundStyle(ShellPalette.muted) }
        }
    }
    private func categoryButton(_ category: CatalogCategory?, title: String, symbol: String, count: Int) -> some View {
        Button { store.query.category = category } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).frame(width: 14)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)").font(.system(size: 9, design: .monospaced)).foregroundStyle(ShellPalette.muted)
            }.font(.system(size: 10, weight: store.query.category == category ? .semibold : .regular))
                .padding(.horizontal, 8).padding(.vertical, 8)
                .foregroundStyle(store.query.category == category ? ShellPalette.accent : Color.primary)
                .background(store.query.category == category ? ShellPalette.tint : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityLabel("\(title), \(count) results")
            .accessibilityAddTraits(store.query.category == category ? .isSelected : [])
    }
}

struct MarketplaceNotice: View {
    let text: String
    var tone: Tone = .information
    var dismiss: (() -> Void)? = nil
    @State private var showingDetails = false
    enum Tone { case information, warning }
    private var color: Color { tone == .warning ? ShellPalette.warning : ShellPalette.accent }
    private var summary: String {
        let first = text.components(separatedBy: .newlines).first ?? text
        return first.count > 180 ? String(first.prefix(180)) + "…" : first
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone == .warning ? "exclamationmark.circle" : "info.circle").foregroundStyle(color)
            Text(summary).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if text != summary {
                Button("Details") { showingDetails = true }.buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(color)
                    .popover(isPresented: $showingDetails) {
                        ScrollView {
                            Text(text).font(.system(size: 12)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        }.frame(width: 440, height: 280)
                    }
            }
            if let dismiss { Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss library notice") }
        }.padding(12).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MarketplaceRefreshButton: View {
    @ObservedObject var store: MarketplaceStore
    private var title: String {
        guard store.refreshing else { return "Refresh catalog" }
        return store.canCancelRefresh ? "\(store.refreshedSourceCount)/\(store.refreshSourceCount) · Cancel" : "Finishing…"
    }
    var body: some View {
        ActionButton(title: title, symbol: store.refreshing && store.canCancelRefresh ? "xmark" : "arrow.clockwise") {
            if store.refreshing { store.cancelRefresh() }
            else { Task { await store.refresh() } }
        }.disabled(store.preview || (store.refreshing && !store.canCancelRefresh))
            .keyboardShortcut("r", modifiers: .command)
            .help(store.refreshing ? store.canCancelRefresh ? "Cancel refresh and keep the saved catalog" : "Finishing the catalog update" : "Check GitHub for catalog updates (⌘R)")
    }
}
