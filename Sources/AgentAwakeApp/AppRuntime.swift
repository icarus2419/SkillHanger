import AppKit
import Combine
import SwiftUI
import UsageCore

enum AppPage: String, CaseIterable, Identifiable {
    case overview, marketplace, installed, usage, awake, activity, settings
    case packageWorkspace = "package"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .marketplace: return "Skill Library"
        case .installed: return "Installed"
        case .usage: return "Usage"
        case .awake: return "Agent Awake"
        case .activity: return "Activity"
        case .settings: return "Settings"
        case .packageWorkspace: return "Skill settings"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .marketplace: return "books.vertical"
        case .installed: return "square.stack.3d.up"
        case .usage: return "chart.bar.xaxis"
        case .awake: return "moon.stars"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        case .packageWorkspace: return "puzzlepiece.extension"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "Your agents, allowance, and sleep protection."
        case .marketplace: return "Discover community skills and plugins for your agents."
        case .installed: return "Manage the skills and plugins on this Mac."
        case .usage: return "Available allowance across your providers."
        case .awake: return "Sleep protection that follows your tasks."
        case .activity: return "A live ledger of your agent sessions."
        case .settings: return "A workspace that works your way."
        case .packageWorkspace: return "Make this capability work your way."
        }
    }
}

@MainActor
final class AppRuntime: NSObject, ObservableObject {
    static let shared = AppRuntime()
    var prefs: Prefs
    let usage: UsageStore
    let marketplace: MarketplaceStore
    var monitor: MonitorModel
    let isPreview: Bool
    @Published var page: AppPage = .marketplace
    @Published var navigationTarget: String?
    @Published var notice: String?
    @Published private(set) var launchAtLogin = LoginItem.isEnabled
    private var window: NSWindow?
    private var widget: WidgetController?
    private let notifier: Notifier
    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    init(preview: Bool = false, marketplaceHome: URL? = nil) {
        let args = ProcessInfo.processInfo.arguments
        isPreview = preview || args.contains("--preview") || args.contains("--render-preview")
        marketplace = MarketplaceStore(preview: isPreview, home: marketplaceHome ?? FileManager.default.homeDirectoryForCurrentUser)
        let defaults: UserDefaults
        if isPreview {
            defaults = UserDefaults(suiteName: "SkillHanger.Preview.\(UUID().uuidString)")!
        } else {
            defaults = .standard
            let legacy = defaults.persistentDomain(forName: "com.icarus2419.UsageBar") ?? [:]
            PreferencesMigration.importUsageBar(from: legacy, into: defaults)
        }
        prefs = Prefs(defaults: defaults)
        monitor = MonitorModel(preview: isPreview, defaults: defaults)
        let now = Date()
        let samples = [
            ProviderUsage(provider: .claude, plan: "Max 5x",
                          session: UsageWindow(kind: .session, label: "5-hour", usedPercent: 24, resetsAt: now.addingTimeInterval(7560), windowSeconds: 18000),
                          weekly: UsageWindow(kind: .weekly, label: "Weekly", usedPercent: 42, resetsAt: now.addingTimeInterval(232000), windowSeconds: 604800),
                          observedAt: now, source: .api),
            ProviderUsage(provider: .openai, plan: "Plus",
                          session: UsageWindow(kind: .session, label: "5-hour", usedPercent: 37, resetsAt: now.addingTimeInterval(11940), windowSeconds: 18000),
                          weekly: UsageWindow(kind: .weekly, label: "Weekly", usedPercent: 19, resetsAt: now.addingTimeInterval(364000), windowSeconds: 604800),
                          observedAt: now, source: .localLog)
        ]
        let scenario = isPreview ? args.firstIndex(of: "--preview-scenario").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } : nil
        var previewUsage = isPreview && !args.contains("--empty-preview") ? samples : []
        var previewErrors: [UsageCore.Provider: UsageError] = [:]
        if scenario == "stale" {
            previewUsage = previewUsage.map { var value = $0; value.observedAt = now.addingTimeInterval(-3600); return value }
        } else if scenario == "error" {
            previewUsage = previewUsage.filter { $0.provider == .openai }
            previewErrors = [.claude: .notSignedIn("Sign in with Claude Code to read your allowance."),
                             .openai: .rateLimited(retryAfter: 120)]
        } else if scenario == "loading" {
            previewUsage = []
        } else if scenario == "disabled" {
            prefs.showClaude = false
            prefs.showOpenAI = false
        } else if scenario == "paused" {
            monitor.isMonitoringEnabled = false
        }
        usage = UsageStore(prefs: prefs, defaults: defaults, initialUsage: previewUsage,
                           initialErrors: previewErrors, initialLoading: scenario == "loading" ? Set(UsageCore.Provider.allCases) : [])
        notifier = Notifier(prefs: prefs)
        super.init()
        if let index = args.firstIndex(of: "--page"), args.indices.contains(index + 1) {
            page = AppPage(rawValue: args[index + 1]) ?? .marketplace
        }
        marketplace.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        marketplace.$removalFailure.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] in self?.notice = $0 }.store(in: &cancellables)
        marketplace.$workspaceSelection.dropFirst().receive(on: RunLoop.main).sink { [weak self] selection in
            if selection != nil { self?.page = .packageWorkspace }
            else if self?.page == .packageWorkspace { self?.page = .installed }
        }.store(in: &cancellables)
        for publisher in [prefs.objectWillChange.eraseToAnyPublisher(),
                          monitor.objectWillChange.eraseToAnyPublisher(),
                          usage.objectWillChange.eraseToAnyPublisher()] {
            publisher.receive(on: RunLoop.main).sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        if !isPreview {
            Task { await marketplace.start() }
            monitor.start()
            widget = WidgetController(store: usage, prefs: prefs)
            widget?.onSettings = { [weak self] in self?.open(.settings) }
            widget?.menu = { [weak self] in self?.widgetMenu() ?? NSMenu() }
            prefs.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.applyPreferences() }
                .store(in: &cancellables)
            prefs.$alerts.dropFirst().filter { $0 }.receive(on: RunLoop.main).sink { [weak self] _ in self?.notifier.requestPermission() }
                .store(in: &cancellables)
            usage.objectWillChange.debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                .sink { [weak self] in
                    guard let self else { return }
                    self.notifier.evaluate(self.usage)
                }.store(in: &cancellables)
            usage.start()
            applyPreferences()
            if prefs.alerts { notifier.requestPermission() }
        }
        open(page, activate: !isPreview && !ProcessInfo.processInfo.arguments.contains("--background"))
    }

    func stop() {
        usage.stop()
        monitor.stop()
        // Hiding at shutdown must not alter the persisted visibility setting.
        widget = nil
    }

    func connectAgent() {
        navigationTarget = "agent-setup"
        page = .awake
    }

    func open(_ page: AppPage = .marketplace, activate: Bool = true) {
        self.page = page
        if page == .marketplace && !isPreview { marketplace.browse() }
        if window == nil {
            let small = ProcessInfo.processInfo.arguments.contains("--compact-preview")
            let created = DashboardWindow(contentRect: NSRect(x: 0, y: 0, width: small ? 940 : 1180, height: small ? 660 : 820),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                   backing: .buffered, defer: false)
            created.title = "SkillHanger"
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.toolbarStyle = .unified
            created.titlebarSeparatorStyle = .none
            created.backgroundColor = .windowBackgroundColor
            created.minSize = NSSize(width: 940, height: 660)
            created.isReleasedWhenClosed = false
            created.contentView = DashboardHostingView(rootView: DashboardView(runtime: self))
            if !isPreview { created.setFrameAutosaveName("SkillHanger.main") }
            created.center()
            if !isPreview { created.fitToVisibleScreen() }
            window = created
            applyPreferences()
        }
        if ProcessInfo.processInfo.arguments.contains("--render-preview") {
            window?.contentView?.layoutSubtreeIfNeeded()
        } else if activate {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window?.orderFrontRegardless()
        }
    }

    func applyPreferences() {
        window?.appearance = prefs.theme.appearance
        let args = ProcessInfo.processInfo.arguments
        if isPreview, let index = args.firstIndex(of: "--appearance"), args.indices.contains(index + 1) {
            window?.appearance = NSAppearance(named: args[index + 1] == "light" ? .aqua : .darkAqua)
        }
        if prefs.widgetVisible {
            if widget?.isVisible == false { widget?.show() }
        } else if widget?.isVisible == true {
            widget?.hide()
        }
    }

    func setLogin(_ enabled: Bool) {
        guard !isPreview else { return }
        do {
            try LoginItem.set(enabled)
            launchAtLogin = LoginItem.isEnabled
            if enabled && !launchAtLogin { notice = "Approve SkillHanger in System Settings → General → Login Items." }
        } catch { notice = error.localizedDescription }
    }

    func resetWidgetPosition() {
        guard !isPreview else { return }
        widget?.resetPosition()
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = "Copied to clipboard."
    }

    var cliPath: String {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            return Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/agent-awake").path
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("dist/SkillHanger.app/Contents/MacOS/agent-awake").path
    }

    func revealTaskFiles() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentAwake/tasks")
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
        else { notice = "Task files appear after your first monitored task." }
    }

    func render(to url: URL) throws {
        if isPreview && ProcessInfo.processInfo.arguments.contains("--marketplace-detail-preview"),
           let item = marketplace.items.first(where: { $0.kind == .skill && $0.name == "pdf" }) {
            let content = MarketplaceDetail(item: item, store: marketplace)
                .preferredColorScheme(window?.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
            let hosting = NSHostingView(rootView: content)
            window?.contentView = hosting
            window?.setContentSize(NSSize(width: 610, height: 590))
        }
        if isPreview && ProcessInfo.processInfo.arguments.contains("--usage-popup-preview") {
            let args = ProcessInfo.processInfo.arguments
            let appearance = args.firstIndex(of: "--appearance").flatMap { index in
                args.indices.contains(index + 1) ? args[index + 1] : nil
            }
            let content = VStack(spacing: 0) {
                Text("Preview · sample usage").font(.caption2).foregroundStyle(.secondary).padding(.top, 8)
                DetailView(store: usage, prefs: prefs, onRefresh: {}, onSettings: {})
            }.background(Color(nsColor: .windowBackgroundColor))
                .preferredColorScheme(appearance == "light" ? .light : .dark)
            window?.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
            let hosting = NSHostingView(rootView: content)
            window?.contentView = hosting
            window?.setContentSize(hosting.fittingSize)
        }
        window?.contentView?.layoutSubtreeIfNeeded()
        if isPreview, let view = window?.contentView,
           let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--preview-scroll-offset"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let offset = Double(ProcessInfo.processInfo.arguments[index + 1]), offset.isFinite {
            func scrollViews(_ parent: NSView) -> [NSScrollView] {
                parent.subviews.flatMap { child in (child as? NSScrollView).map { [$0] } ?? [] } + parent.subviews.flatMap { scrollViews($0) }
            }
            if let scroll = scrollViews(view).max(by: { $0.bounds.width < $1.bounds.width }), let document = scroll.documentView {
                let clip = scroll.contentView
                let maximum = max(document.bounds.minY, document.bounds.maxY - clip.bounds.height)
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(maximum, max(document.bounds.minY, offset))))
                scroll.reflectScrolledClipView(clip)
            }
        }
        window?.displayIfNeeded()
        guard let view = window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    }

    /// Opt-in launch diagnostics for verifying our own window without selecting an app.
    func writeLaunchReport(to url: URL) throws {
        let report: [String: Any] = [
            "page": page.rawValue, "preview": isPreview,
            "marketplaceScope": marketplace.query.scope.rawValue,
            "marketplaceSort": marketplace.query.sort.rawValue,
            "marketplaceTopNames": Array(marketplace.results.prefix(5).map(\.name)),
            "installedWorkspaceCount": marketplace.workspaces.count,
            "appActive": NSApp.isActive, "windowVisible": window?.isVisible ?? false,
            "windowKey": window?.isKeyWindow ?? false,
            "windowNumber": window?.windowNumber ?? -1,
            "windowOnActiveSpace": window?.isOnActiveSpace ?? false,
            "windowExposed": window?.occlusionState.contains(.visible) ?? false,
            "logoBundled": BrandAssets.bundle.bundleURL.deletingLastPathComponent().path == Bundle.main.resourceURL?.path
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }

    private func widgetMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [("Open SkillHanger", #selector(openOverview)), ("Settings…", #selector(openSettings)),
                                 ("Refresh Usage", #selector(refreshUsage)), ("Hide Widget", #selector(hideWidget))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }
    @objc private func openOverview() { open(.overview) }
    @objc private func openSettings() { open(.settings) }
    @objc private func refreshUsage() { usage.refresh() }
    @objc private func hideWidget() { prefs.widgetVisible = false }
}
