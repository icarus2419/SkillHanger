import SwiftUI
import UsageCore

struct DashboardView: View {
    @ObservedObject var runtime: AppRuntime
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @FocusState private var themeFocused: Bool
    var body: some View {
        HStack(spacing: 8) {
            sidebar.frame(width: 244).padding(.leading, 12).padding(.top, 40).padding(.bottom, 12)
            VStack(spacing: 0) {
                header
                if runtime.page == .marketplace {
                    MarketplacePage(store: runtime.marketplace).equatable().padding(.horizontal, 28).padding(.bottom, 16)
                } else {
                ScrollViewReader { proxy in
                  ScrollView {
                    Group {
                        switch runtime.page {
                        case .overview: OverviewPage(runtime: runtime)
                        case .marketplace: EmptyView()
                        case .installed: InstalledPackagesPage(store: runtime.marketplace, page: $runtime.page)
                        case .usage: UsagePage(runtime: runtime)
                        case .awake: AwakePage(runtime: runtime)
                        case .activity: ActivityPage(runtime: runtime)
                        case .settings: SettingsPage(runtime: runtime)
                        case .packageWorkspace:
                            if let workspace = runtime.marketplace.selectedWorkspace {
                                PackageWorkspacePage(workspace: workspace, store: runtime.marketplace, preferences: runtime.marketplace.packagePreferences).id(workspace.id)
                            } else {
                                EmptyPanel(title: "Choose an installed package", detail: "Select a skill or plugin to customize it here.", symbol: "puzzlepiece.extension", actionTitle: "All installed", action: { runtime.open(.installed, activate: false) })
                            }
                        }
                    }
                    .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 28)
                    .frame(maxWidth: 1100, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                    Color.clear.frame(height: 1).id("page-bottom")
                  }.id(runtime.page)
                  .onAppear {
                      if runtime.isPreview && ProcessInfo.processInfo.arguments.contains("--preview-bottom") {
                          Task { @MainActor in
                              try? await Task.sleep(for: .milliseconds(200))
                              proxy.scrollTo("page-bottom", anchor: .bottom)
                          }
                      }
                  }
                  .onChange(of: runtime.navigationTarget) { target in
                      guard let target else { return }
                      Task { @MainActor in
                          try? await Task.sleep(for: .milliseconds(80))
                          if runtime.page == .awake { proxy.scrollTo(target, anchor: .top) }
                          runtime.navigationTarget = nil
                      }
                  }
                }
                }
                footer
            }
        }
        .background(ShellPalette.canvas)
        .environment(\.forceReducedMotion, runtime.isPreview && ProcessInfo.processInfo.arguments.contains("--reduce-motion-preview"))
        .transaction { if runtime.isPreview && ProcessInfo.processInfo.arguments.contains("--render-preview") { $0.disablesAnimations = true } }
        .ignoresSafeArea()
        .tint(ShellPalette.accent)
        .overlay(alignment: .bottomTrailing) {
            if let feedback = runtime.feedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ShellPalette.accent)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ShellPalette.line))
                    .padding(.trailing, 28).padding(.bottom, 52)
                    .allowsHitTesting(false).accessibilityElement(children: .combine)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(previewAppearance ?? (runtime.prefs.theme == .system ? nil : runtime.prefs.theme == .dark ? .dark : .light))
        .alert("SkillHanger", isPresented: Binding(get: { runtime.notice != nil }, set: { if !$0 { runtime.notice = nil } })) {
            Button("OK") { runtime.notice = nil }
        } message: { Text(runtime.notice ?? "") }
    }

    private var previewAppearance: ColorScheme? {
        let args = ProcessInfo.processInfo.arguments
        guard runtime.isPreview, let i = args.firstIndex(of: "--appearance"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1] == "dark" ? .dark : .light
    }

    private var sidebar: some View {
        GeometryReader { geometry in
            sidebarContent(compact: geometry.size.height < 700)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
        .background(ShellPalette.sidebar, in: RoundedRectangle(cornerRadius: 26))
        .preferredColorScheme(.dark)
    }

    private func sidebarContent(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SkillHanger").font(.system(size: 16, weight: .bold, design: .rounded)).tracking(-0.4)
                    Text("Your workspace").font(.system(size: 10)).foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.horizontal, 20).padding(.top, compact ? 20 : 24).padding(.bottom, compact ? 20 : 36)
            DashboardNavigation(monitor: runtime.monitor, page: $runtime.page, compact: compact)
            InstalledPackageSidebar(store: runtime.marketplace, page: $runtime.page)
            Spacer(minLength: 12)
            DashboardMonitoringStatus(monitor: runtime.monitor)
                .padding(.horizontal, 24).padding(.bottom, compact ? 14 : 22)
            Rectangle().fill(.white.opacity(0.09)).frame(height: 1).padding(.horizontal, 20)
            NavigationItem(page: .settings, selected: runtime.page == .settings, compact: compact) { runtime.page = .settings }
                .padding(.horizontal, 12).padding(.vertical, compact ? 10 : 14)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(runtime.page == .packageWorkspace ? runtime.marketplace.selectedWorkspace?.item.title ?? runtime.page.title : runtime.page.title).font(.system(size: 30, weight: .semibold)).tracking(-0.9)
                    .accessibilityAddTraits(.isHeader)
                Text(runtime.page.subtitle).font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
            }
            Spacer(minLength: 8)
            Button {
                runtime.prefs.theme = colorScheme == .dark ? .light : .dark
            } label: {
                Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                    .frame(width: 16, height: 16)
            }.buttonStyle(ProductButtonStyle()).focused($themeFocused)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(themeFocused ? ShellPalette.accent : .clear, lineWidth: 2).padding(-2).allowsHitTesting(false))
                .accessibilityLabel(colorScheme == .dark ? "Switch to light appearance" : "Switch to dark appearance")
                .help(colorScheme == .dark ? "Light appearance" : "Dark appearance")
            if runtime.isPreview { StatusPill(text: "Sample data", symbol: "eye", color: ShellPalette.warning) }
            if runtime.page == .settings {
                Label("All changes saved", systemImage: "checkmark.circle")
                    .font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
            } else if runtime.page == .activity {
                ActionButton(title: "Connect agent", symbol: "plus") { runtime.connectAgent() }
            } else if runtime.page == .awake {
                ActionButton(title: "View activity", symbol: "arrow.up.right") { runtime.page = .activity }
            } else if runtime.page == .packageWorkspace {
                ActionButton(title: "All installed", symbol: "square.stack.3d.up") { runtime.page = .installed }
            } else if runtime.page == .installed {
                ActionButton(title: "Browse library", symbol: "books.vertical") { runtime.page = .marketplace; runtime.marketplace.browse() }
            } else if runtime.page == .marketplace {
                MarketplaceRefreshButton(store: runtime.marketplace)
            } else {
                ActionButton(title: runtime.usage.loading.isEmpty ? "Refresh" : "Checking…", symbol: "arrow.clockwise") {
                    if !runtime.isPreview { runtime.usage.refresh() }
                }
                .disabled(!runtime.isPreview && !runtime.usage.canRefresh)
                .help(runtime.usage.refreshHelp)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 20)
    }

    private var footer: some View {
        DashboardFooter(store: runtime.usage, marketplace: runtime.page == .marketplace)
    }
}

private struct DashboardNavigation: View {
    @ObservedObject var monitor: MonitorModel
    @Binding var page: AppPage
    var compact: Bool
    var body: some View {
        VStack(spacing: 5) {
            ForEach(AppPage.allCases.filter { $0 != .settings && $0 != .packageWorkspace && $0 != .installed }) { destination in
                NavigationItem(page: destination, selected: page == destination,
                               count: destination == .activity ? monitor.runningCount : 0,
                               compact: compact) { page = destination }
            }
        }.padding(.horizontal, 12)
    }
}

private struct DashboardMonitoringStatus: View {
    @ObservedObject var monitor: MonitorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(monitor.isMonitoringEnabled ? "Monitoring" : "Monitoring paused",
                  systemImage: monitor.isMonitoringEnabled ? "dot.radiowaves.left.and.right" : "pause.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(monitor.isMonitoringEnabled ? ShellPalette.brandHighlight : .white.opacity(0.65))
            Text("Local on this Mac").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct DashboardFooter: View {
    @ObservedObject var store: UsageStore
    var marketplace: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock").foregroundStyle(ShellPalette.muted)
            Text(marketplace ? "Skills & plugins from GitHub" : "Private on this Mac").foregroundStyle(ShellPalette.muted)
            Spacer()
            if marketplace {
                Text("User-scope installs · Codex & Claude Code").foregroundStyle(ShellPalette.muted)
            } else if let date = store.lastUpdated {
                Text("Usage checked \(UsageFormat.ago(date, now: store.now))").foregroundStyle(ShellPalette.muted)
            } else { Text("No usage reading yet").foregroundStyle(ShellPalette.muted) }
        }
        .font(.system(size: 10)).padding(.horizontal, 28).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(ShellPalette.line).frame(height: 1) }
    }
}

private struct NavigationItem: View {
    let page: AppPage
    let selected: Bool
    var count = 0
    var compact = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).font(.system(size: 14, weight: .medium)).frame(width: 22)
                    .foregroundStyle(selected ? ShellPalette.brandHighlight : .white.opacity(0.60))
                Text(page.title).font(.system(size: 12, weight: selected ? .semibold : .medium, design: .rounded))
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)").font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShellPalette.brandHighlight)
                }
            }
            .foregroundStyle(.white.opacity(selected ? 1 : 0.70))
            .padding(.horizontal, 12).padding(.vertical, compact ? 8 : 12)
            .frame(minHeight: compact ? 34 : 40)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 15).fill(ShellPalette.brandHighlight.opacity(0.16))
                } else {
                    RoundedRectangle(cornerRadius: 15).fill(.white.opacity(hovered ? 0.06 : 0))
                }
            }
            .overlay(alignment: .leading) {
                if selected { Capsule().fill(ShellPalette.brandHighlight).frame(width: 2, height: 16) }
            }
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(focused ? ShellPalette.brandHighlight : .clear))
        }
        .buttonStyle(.plain).focused($focused).onHover { hovered = $0 }
        .offset(x: hovered && !reduceMotion ? 2 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        .accessibilityLabel(page.title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
