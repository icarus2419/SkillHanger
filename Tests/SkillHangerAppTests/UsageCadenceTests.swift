import AppKit
import Testing
import UsageCore
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct UsageCadenceTests {
    @Test func automaticChecksWaitFourMinutesAndManualChecksHaveACooldown() async throws {
        let env = Environment()
        defer { env.cleanup() }
        let clock = TestClock()
        let requests = UsageRequests()
        let store = makeStore(env, clock: clock, requests: requests)
        defer { store.stop() }
        store.start()
        await settle(store)
        #expect(await requests.count == 1)
        #expect(store.reading(for: .claude).nextCheckAt == clock.value.addingTimeInterval(240))
        clock.advance(59)
        store.refresh()
        await settle(store)
        #expect(await requests.count == 1)
        clock.advance(1)
        store.refresh()
        await settle(store)
        #expect(await requests.count == 2)
        clock.advance(239)
        store.checkForUpdates()
        await settle(store)
        #expect(await requests.count == 2)
        clock.advance(1)
        store.checkForUpdates()
        await settle(store)
        #expect(await requests.count == 3)
    }

    @Test func restartingKeepsTheLastAttemptAndRateLimitDeadline() async throws {
        let env = Environment()
        defer { env.cleanup() }
        let clock = TestClock()
        let requests = UsageRequests()
        let original = makeStore(env, clock: clock, requests: requests, rateLimited: true)
        original.start()
        await settle(original)
        let deadline = try #require(original.reading(for: .claude).nextCheckAt)
        #expect(deadline == clock.value.addingTimeInterval(900))
        original.stop()
        clock.advance(70)
        let restarted = makeStore(env, clock: clock, requests: requests)
        defer { restarted.stop() }
        restarted.start()
        restarted.refresh()
        await settle(restarted)
        #expect(await requests.count == 1)
        #expect(restarted.reading(for: .claude).nextCheckAt == deadline)
        #expect(restarted.reading(for: .claude).error == .rateLimited(retryAfter: nil))
        clock.value = deadline
        restarted.checkForUpdates()
        await settle(restarted)
        #expect(await requests.count == 2)
        #expect(restarted.reading(for: .claude).error == nil)
    }

    @Test func wakingDoesNotForceAnotherUsageRequestBeforeItIsDue() async throws {
        let env = Environment()
        defer { env.cleanup() }
        let clock = TestClock()
        let requests = UsageRequests()
        let notifications = NotificationCenter()
        let store = makeStore(env, clock: clock, requests: requests, notifications: notifications)
        defer { store.stop() }
        store.start()
        await settle(store)
        clock.advance(60)
        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        // Wait for the actual wake callback, which must use an automatic due check.
        try await Task.sleep(for: .milliseconds(4300))
        await settle(store)
        #expect(await requests.count == 1)
        clock.advance(180)
        store.checkForUpdates()
        await settle(store)
        #expect(await requests.count == 2)
    }

    @Test(arguments: [false, true]) func openingUsageDetailsRespectsTheAutomaticCadence(usingMenuBar: Bool) async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let env = Environment()
        defer { env.cleanup() }
        let clock = TestClock()
        let requests = UsageRequests()
        let store = makeStore(env, clock: clock, requests: requests)
        defer { store.stop() }
        store.start()
        await settle(store)
        clock.advance(75)
        if usingMenuBar {
            let controller = UsageMenuBarController(store: store, prefs: env.prefs, onSettings: {})
            defer { controller.stop() }
            let button = try #require(controller.statusItem.button)
            button.performClick(nil)
            await settle(store)
        } else {
            let controller = WidgetController(store: store, prefs: env.prefs)
            defer { controller.hide() }
            controller.showDetail()
            await settle(store)
        }
        #expect(await requests.count == 1)
        clock.advance(165)
        store.checkForUpdates()
        await settle(store)
        #expect(await requests.count == 2)
    }

    private func makeStore(_ env: Environment, clock: TestClock, requests: UsageRequests,
                           rateLimited: Bool = false, notifications: NotificationCenter = NotificationCenter()) -> UsageStore {
        UsageStore(prefs: env.prefs, defaults: env.defaults,
                   logRoot: URL(fileURLWithPath: "/nonexistent-cadence-test-sessions"),
                   workspaceNotifications: notifications, clock: UsageClock(now: { clock.value })) { _, _ in
            await requests.increment()
            if rateLimited { throw UsageError.rateLimited(retryAfter: 900) }
            return ProviderUsage(provider: .claude, plan: "Test", session:
                UsageWindow(kind: .session, label: "5-hour", usedPercent: 25, resetsAt: nil, windowSeconds: 18_000),
                weekly: nil, observedAt: Date(), source: .api)
        }
    }

    private func settle(_ store: UsageStore) async {
        for _ in 0..<40 where !store.loading.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private struct Environment {
        let suite = "SkillHanger.Cadence.Tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let prefs: Prefs
        init() {
            defaults = UserDefaults(suiteName: suite)!
            prefs = Prefs(defaults: defaults)
            prefs.showOpenAI = false
            prefs.alerts = false
        }
        func cleanup() { defaults.removePersistentDomain(forName: suite) }
    }
}

@MainActor private final class TestClock {
    var value = Date()
    func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
}

private actor UsageRequests {
    private(set) var count = 0
    func increment() { count += 1 }
}
