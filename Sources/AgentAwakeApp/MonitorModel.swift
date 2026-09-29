import AgentAwakeCore
import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var tasks: [TaskRecord] = []
    @Published private(set) var now = Date()
    @Published private(set) var errorMessage: String?
    @Published private(set) var closedLidStatus: ClosedLidStatus?
    @Published private(set) var closedLidError: String?
    @Published private(set) var isKeepingAwake = false
    @Published var isMonitoringEnabled: Bool { didSet { saveAndRefresh(isMonitoringEnabled, "monitoringEnabled") } }
    @Published var preventsIdleSleep: Bool { didSet { saveAndRefresh(preventsIdleSleep, "preventsIdleSleep") } }
    @Published var monitorClaude: Bool { didSet { saveAndRefresh(monitorClaude, "monitorClaude") } }
    @Published var monitorCodex: Bool { didSet { saveAndRefresh(monitorCodex, "monitorCodex") } }
    @Published var animateOverlay: Bool { didSet { if !isPreview { defaults.set(animateOverlay, forKey: "animateOverlay") } } }
    @Published var closedLidEnabled: Bool {
        didSet {
            if !isPreview { defaults.set(closedLidEnabled, forKey: "closedLidEnabled") }
            updateClosedLid()
        }
    }
    @Published var overlayIdleSeconds: Int {
        didSet { if !isPreview { defaults.set(overlayIdleSeconds, forKey: "overlayIdleSeconds"); refresh() } }
    }

    var runningCount: Int { tasks.filter { $0.effectiveState(at: now) == .running }.count }
    var displayTasks: [TaskRecord] {
        tasks.filter { !$0.effectiveState(at: now).isTerminal }
    }

    private let store: TaskStore
    private let coordinator: AssertionCoordinator
    private let overlay = OverlayController()
    private var timer: Timer?
    private var lastPrunedAt: Date?
    private var taskLoadSucceeded = false
    private let closedLid = ClosedLidClient()
    private let isPreview: Bool
    private let defaults: UserDefaults
    private let integratesWithSystem: Bool
    private var previewTasks: [TaskRecord] = []
    private var started = false
    var sleepProtectionActive: Bool { isKeepingAwake || closedLidStatus?.state == .active }
    var policy: MonitoringPolicy {
        MonitoringPolicy(isEnabled: isMonitoringEnabled, preventsIdleSleep: preventsIdleSleep,
                         monitoredProviders: Set([monitorClaude ? Provider.claude : nil, monitorCodex ? .codex : nil].compactMap { $0 }))
    }

    init(preview: Bool = false, defaults: UserDefaults = .standard, taskStore: TaskStore = TaskStore(),
         power: any PowerControlling = IOKitPowerController(), integratesWithSystem: Bool = true) {
        isPreview = preview
        self.defaults = defaults
        self.store = taskStore
        self.coordinator = AssertionCoordinator(power: power)
        self.integratesWithSystem = integratesWithSystem
        isMonitoringEnabled = defaults.object(forKey: "monitoringEnabled") as? Bool ?? true
        preventsIdleSleep = defaults.object(forKey: "preventsIdleSleep") as? Bool ?? true
        monitorClaude = defaults.object(forKey: "monitorClaude") as? Bool ?? true
        monitorCodex = defaults.object(forKey: "monitorCodex") as? Bool ?? true
        animateOverlay = defaults.object(forKey: "animateOverlay") as? Bool ?? true
        closedLidEnabled = preview ? false : defaults.bool(forKey: "closedLidEnabled")
        let saved = defaults.object(forKey: "overlayIdleSeconds") as? Int
        overlayIdleSeconds = saved ?? 60
        if preview {
            let date = Date()
            tasks = [
                TaskRecord(id: "preview-codex", provider: .codex, state: .running, startedAt: date.addingTimeInterval(-173), observedAt: date, expiresAt: date.addingTimeInterval(3600), usage: TokenUsage(input: 24_376, output: 1_234), milestones: 3),
                TaskRecord(id: "preview-claude", provider: .claude, state: .waiting, startedAt: date.addingTimeInterval(-482), observedAt: date, expiresAt: date.addingTimeInterval(3600), milestones: 1)
            ]
            if ProcessInfo.processInfo.arguments.contains("--empty-preview") { tasks = [] }
            previewTasks = tasks
            return
        }
    }

    func start() {
        guard !isPreview, !started else { return }
        started = true
        refresh()
        if integratesWithSystem {
            timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        }
    }

    private func saveAndRefresh(_ value: Bool, _ key: String) {
        if !isPreview { defaults.set(value, forKey: key) }
        if started || isPreview { refresh() }
    }

    func stop() {
        guard started else { return }
        started = false
        timer?.invalidate()
        timer = nil
        try? coordinator.sync(tasks: [])
        isKeepingAwake = false
        overlay.hide()
        if !isPreview, integratesWithSystem, closedLid.status() != nil { try? closedLid.renew(enabled: false, runningTasks: 0) }
    }

    @objc private func refresh() {
        now = Date()
        if isPreview {
            tasks = policy.visibleTasks(from: previewTasks)
            return
        }
        do {
            if lastPrunedAt == nil || now.timeIntervalSince(lastPrunedAt!) >= 60 {
                try store.prune(at: now)
                lastPrunedAt = now
            }
            let loaded = try store.load()
            tasks = policy.visibleTasks(from: loaded).filter { $0.isVisible(at: now) }
            try coordinator.sync(tasks: policy.assertionTasks(from: loaded), now: now)
            isKeepingAwake = coordinator.isHolding
            taskLoadSucceeded = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            try? coordinator.sync(tasks: [], now: now)
            taskLoadSucceeded = false
            isKeepingAwake = false
        }
        updateClosedLid()

        guard integratesWithSystem else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        if OverlayPolicy.shouldShow(tasks: tasks, now: now, idleSeconds: idle, threshold: overlayIdleSeconds) {
            overlay.show(model: self)
        } else {
            overlay.hide()
        }
    }

    private func updateClosedLid() {
        guard !isPreview, integratesWithSystem else { return }
        closedLidStatus = closedLid.status()
        guard closedLidStatus != nil else {
            closedLidError = closedLidEnabled ? "Closed-lid helper unavailable; its activity lease will expire." : nil
            return
        }
        do {
            try closedLid.renew(enabled: closedLidEnabled, runningTasks: taskLoadSucceeded ? runningCount : 0)
            closedLidError = nil
        } catch { closedLidError = error.localizedDescription }
    }

    func showClosedLidSetup() {
        if let url = Bundle.main.url(forResource: "ClosedLidSetup", withExtension: "md") {
            NSWorkspace.shared.open(url)
        }
    }

}
