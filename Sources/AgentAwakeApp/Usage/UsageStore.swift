import AppKit
import Combine
import UsageCore

struct UsageClock {
    var now: () -> Date = Date.init
}

/// Everything one battery needs to draw itself.
struct Reading {
    var provider: Provider
    /// Usage projected to "now", so windows whose reset time has passed show as refilled.
    var usage: ProviderUsage?
    /// The window picked by the user's metric.
    var window: UsageWindow?
    var error: UsageError?
    var isStale: Bool
    var isLoading: Bool
    var nextCheckAt: Date? = nil
    var isProjected = false

    var percent: Double? { window?.remainingPercent }
}

/// Polls both providers, caches the last good reading and projects resets forward in time.
@MainActor
final class UsageStore: ObservableObject {
    typealias FetchUsage = @Sendable (Provider, URLSession) async throws -> ProviderUsage
    @Published private(set) var usage: [Provider: ProviderUsage] = [:]
    @Published private(set) var errors: [Provider: UsageError] = [:]
    @Published private(set) var loading: Set<Provider> = []
    @Published private(set) var now = Date()

    private let prefs: Prefs
    private let defaults: UserDefaults
    private let fetchUsage: FetchUsage
    private let clock: UsageClock
    private let logRoot: URL?
    private let session: URLSession
    private let workspaceNotifications: NotificationCenter
    private var ticker: Timer?
    private var lastFetch: [Provider: Date] = [:]
    private var retryAt: [Provider: Date] = [:]
    private var failures: [Provider: Int] = [:]
    private let logReader: CodexLocalLog.Reader
    private lazy var logWatcher = CodexLogWatcher(root: logRoot) { [weak self] in
        MainActor.assumeIsolated { self?.pollCodexLog() }
    }
    private var readingCodexLog = false
    private var logChangePending = false
    private var sleepReasons: Set<String> = []
    private var asleep: Bool { !sleepReasons.isEmpty }
    private var tasks: [Provider: Task<Void, Never>] = [:]
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    private static let cacheKey = "usageCache.v1"
    private static let pollingKey = "usagePolling.v1"
    private static let manualCooldown: TimeInterval = 60

    private struct PollingState: Codable {
        var lastFetch: [Provider: Date]
        var retryAt: [Provider: Date]
        var failures: [Provider: Int]
        var rateLimited: Set<Provider>
    }

    init(prefs: Prefs, defaults: UserDefaults = .standard, logRoot: URL? = nil,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         clock: UsageClock = UsageClock(),
         initialUsage: [ProviderUsage] = [],
         initialErrors: [Provider: UsageError] = [:], initialLoading: Set<Provider> = [],
         fetchUsage: @escaping FetchUsage = { provider, session in
             switch provider {
             case .claude: return try await ClaudeSource.fetch(session: session)
             case .openai: return try await CodexSource.fetch(session: session)
             }
         }) {
        self.prefs = prefs
        self.defaults = defaults
        self.logRoot = logRoot
        self.workspaceNotifications = workspaceNotifications
        self.logReader = CodexLocalLog.Reader(root: logRoot)
        self.fetchUsage = fetchUsage
        self.clock = clock
        now = clock.now()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
        loadCache()
        loadPollingState()
        for entry in initialUsage { usage[entry.provider] = entry }
        errors.merge(initialErrors) { _, new in new }
        loading = initialLoading
    }

    private var interval: TimeInterval { TimeInterval(max(1, prefs.refreshMinutes) * 60) }

    /// A reading older than this is drawn dimmed.
    private var staleAfter: TimeInterval { max(interval * 3, 10 * 60) }

    func start() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdates() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer

        let center = workspaceNotifications
        for (sleep, wake, reason) in [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "system"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display")
        ] {
            observers.append(center.addObserver(forName: sleep, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sleepReasons.insert(reason)
                    self.logWatcher.stop()
                    self.tasks.values.forEach { $0.cancel() }
                }
            })
            observers.append(center.addObserver(forName: wake, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.sleepReasons.remove(reason) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    guard let self, self.ticker != nil, !self.asleep else { return }
                    self.updateWatcher()
                    self.checkForUpdates()
                }
            })
        }

        // Fetch straight away when a provider is switched on or the interval shortens.
        prefs.$showClaude.merge(with: prefs.$showOpenAI).map { _ in () }
            .merge(with: prefs.$refreshMinutes.map { _ in () })
            .dropFirst(3)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                for provider in Provider.allCases where !self.prefs.isShown(provider) {
                    self.tasks[provider]?.cancel()
                }
                self.updateWatcher()
                self.checkForUpdates()
            }
            .store(in: &cancellables)

        updateWatcher()
        checkForUpdates()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        logWatcher.stop()
        tasks.values.forEach { $0.cancel() }
        observers.forEach { workspaceNotifications.removeObserver($0) }
        observers.removeAll()
        cancellables.removeAll()
    }

    private func updateWatcher() {
        if prefs.showOpenAI && !asleep { logWatcher.start() } else { logWatcher.stop() }
    }

    /// Manual refresh: ignores the poll interval but still honours rate-limit back-off.
    func refresh() {
        guard !asleep else { return }
        now = clock.now()
        for provider in prefs.providers { fetchIfDue(provider, force: true) }
        pollCodexLog()
    }

    func checkForUpdates() {
        guard !asleep else { return }
        now = clock.now()
        updateWatcher()
        for provider in prefs.providers { fetchIfDue(provider, force: false) }
        pollCodexLog()
    }

    // MARK: Fetching

    private func fetchIfDue(_ provider: Provider, force: Bool) {
        guard !loading.contains(provider) else { return }
        if force, let last = lastFetch[provider], now.timeIntervalSince(last) < Self.manualCooldown { return }
        if let retry = retryAt[provider], retry > now {
            let rateLimited: Bool
            if case .rateLimited = errors[provider] { rateLimited = true } else { rateLimited = false }
            if !force || rateLimited { return }
        }
        if !force, retryAt[provider] == nil, let last = lastFetch[provider], now.timeIntervalSince(last) < interval {
            return
        }
        fetch(provider)
    }

    private func fetch(_ provider: Provider) {
        loading.insert(provider)
        lastFetch[provider] = clock.now()
        savePollingState()
        let session = session
        tasks[provider] = Task {
            defer {
                loading.remove(provider)
                tasks[provider] = nil
            }
            do {
                let result = try await fetchUsage(provider, session)
                guard !Task.isCancelled else { return }
                errors[provider] = nil
                failures[provider] = 0
                retryAt[provider] = nil
                savePollingState()
                accept(result)
            } catch {
                guard !Task.isCancelled else { return }
                fail(provider, error as? UsageError ?? .network(error.localizedDescription))
            }
        }
    }

    private func fail(_ provider: Provider, _ error: UsageError) {
        errors[provider] = error
        let count = (failures[provider] ?? 0) + 1
        failures[provider] = count
        switch error {
        case .rateLimited(let retryAfter):
            let backoff = min(interval * pow(2, Double(count)), 30 * 60)
            retryAt[provider] = clock.now().addingTimeInterval(max(retryAfter ?? 0, backoff))
        case .network, .badResponse:
            // Retry sooner than a full interval the first time, then back off.
            let backoff = min(30 * pow(2, Double(count - 1)), max(interval, 15 * 60))
            retryAt[provider] = clock.now().addingTimeInterval(backoff)
        case .notSignedIn, .tokenExpired, .unauthorized:
            // Rechecking the local login is cheap; keep the normal cadence so sign-ins show up quickly.
            retryAt[provider] = nil
        }
        savePollingState()
        if provider == .openai { pollCodexLog() }
    }

    /// Keeps whichever reading is newer, so a fresh local-log snapshot can beat an older API one.
    private func accept(_ new: ProviderUsage) {
        if let old = usage[new.provider], old.observedAt > new.observedAt { return }
        var updated = new
        if updated.plan == nil { updated.plan = usage[new.provider]?.plan }
        guard updated != usage[new.provider] else { return }
        now = clock.now()
        usage[new.provider] = updated
        saveCache()
    }

    /// File events deliver live updates; the timer is a fallback if events are missed.
    private func pollCodexLog() {
        guard prefs.showOpenAI, !asleep else { return }
        guard !readingCodexLog else {
            logChangePending = true
            return
        }
        readingCodexLog = true
        Task {
            let usage = await logReader.latest()
            readingCodexLog = false
            if prefs.showOpenAI, !asleep, let usage { accept(usage) }
            if logChangePending {
                logChangePending = false
                pollCodexLog()
            }
        }
    }

    // MARK: Reading

    func reading(for provider: Provider) -> Reading {
        let projected = usage[provider]?.projected(at: now)
        let window: UsageWindow?
        switch prefs.metric {
        case .lowest: window = projected?.tightest
        case .session: window = projected?.session ?? projected?.tightest
        case .weekly: window = projected?.weekly ?? projected?.tightest
        }
        let stale = projected.map { now.timeIntervalSince($0.observedAt) > staleAfter } ?? false
        return Reading(provider: provider, usage: projected, window: window, error: errors[provider],
                       isStale: stale, isLoading: loading.contains(provider),
                       nextCheckAt: retryAt[provider] ?? lastFetch[provider]?.addingTimeInterval(interval),
                       isProjected: usage[provider]?.windows.contains { $0.hasReset(at: now) } ?? false)
    }

    var lastUpdated: Date? {
        prefs.providers.compactMap { usage[$0]?.observedAt }.max()
    }

    /// Keep every refresh control honest about the same cooldown and retry gate.
    var canRefresh: Bool {
        prefs.providers.contains { provider in
            guard !loading.contains(provider), !asleep else { return false }
            if let last = lastFetch[provider], now.timeIntervalSince(last) < Self.manualCooldown { return false }
            if case .rateLimited = errors[provider], let retry = retryAt[provider], retry > now { return false }
            return true
        }
    }

    var refreshHelp: String {
        if !loading.isEmpty { return "Checking your plan allowance" }
        if prefs.providers.isEmpty { return "Enable a provider in Usage or Settings" }
        if !canRefresh { return "Automatic checks continue. Recent requests and provider retry windows are respected." }
        return "Check usage now (⌘R)"
    }

    // MARK: Cache

    private func loadCache() {
        guard let data = defaults.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode([ProviderUsage].self, from: data) else { return }
        for entry in cached { usage[entry.provider] = entry }
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(Array(usage.values)) {
            defaults.set(data, forKey: Self.cacheKey)
        }
    }

    private func loadPollingState() {
        guard let data = defaults.data(forKey: Self.pollingKey),
              let saved = try? JSONDecoder().decode(PollingState.self, from: data) else { return }
        // Discard impossible attempt dates after a system clock correction.
        lastFetch = saved.lastFetch.filter { $0.value <= now }
        retryAt = saved.retryAt.filter { $0.value > now && $0.value.timeIntervalSince(now) <= 86_400 }
        failures = saved.failures.mapValues { min(10, max(0, $0)) }
        for provider in saved.rateLimited where retryAt[provider] != nil {
            errors[provider] = .rateLimited(retryAfter: nil)
        }
    }

    private func savePollingState() {
        let rateLimited = Set(errors.compactMap { provider, error in
            if case .rateLimited = error { return provider }; return nil
        })
        let saved = PollingState(lastFetch: lastFetch, retryAt: retryAt, failures: failures, rateLimited: rateLimited)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.pollingKey) }
    }
}
