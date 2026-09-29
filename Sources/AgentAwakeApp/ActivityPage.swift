import AppKit
import AgentAwakeCore
import SwiftUI

struct ActivityPage: View {
    @ObservedObject var runtime: AppRuntime
    @State private var search = ""
    @State private var filter = "All"
    init(runtime: AppRuntime) {
        self.runtime = runtime
        let args = ProcessInfo.processInfo.arguments
        if runtime.isPreview, let i = args.firstIndex(of: "--activity-filter"), args.indices.contains(i + 1),
           ["All", "Working", "Waiting", "Finished"].contains(args[i + 1]) {
            _filter = State(initialValue: args[i + 1])
        }
    }
    private var tasks: [TaskRecord] {
        runtime.monitor.tasks.filter { task in
            let state = task.effectiveState(at: runtime.monitor.now)
            let matchesState = filter == "All" || (filter == "Working" && state == .running)
                || (filter == "Waiting" && state == .waiting) || (filter == "Finished" && state.isTerminal)
            let matchesSearch = search.isEmpty || "\(task.provider.displayName) \(task.id) \(state.label)"
                .localizedCaseInsensitiveContains(search)
            return matchesState && matchesSearch
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ActivitySummary(tasks: runtime.monitor.tasks, now: runtime.monitor.now, selected: filter) { filter = $0 }
            HStack(spacing: 16) {
                ChoiceStrip(options: ["All", "Working", "Waiting", "Finished"], selection: $filter,
                            accessibilityTitle: "Task state")
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(ShellPalette.muted).font(.system(size: 11))
                    TextField("Search sessions", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                        .accessibilityLabel("Search activity")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(ShellPalette.muted) }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 9).frame(width: 210)
                .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ShellPalette.line))
            }
            Surface(padding: 0) {
                HStack {
                    Text("Sessions").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(tasks.count) recent").font(.system(size: 11, design: .monospaced)).foregroundStyle(ShellPalette.muted)
                }.padding(.horizontal, 20).padding(.vertical, 16)
                Divider()
                if tasks.isEmpty {
                    if search.isEmpty && filter == "All" {
                        ActivityEmptyView(paused: !runtime.monitor.isMonitoringEnabled) {
                            if runtime.monitor.isMonitoringEnabled { runtime.connectAgent() }
                            else { runtime.page = .awake }
                        }
                    } else {
                        EmptyPanel(title: "No matching sessions", detail: "Try another state or clear your search.",
                                   symbol: "line.3.horizontal.decrease.circle", actionTitle: "Clear filters") { search = ""; filter = "All" }
                    }
                } else {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskActivityRow(task: task, now: runtime.monitor.now, showID: true)
                        if index < tasks.count - 1 { Divider().padding(.leading, 68) }
                    }
                }
                HStack(spacing: 7) {
                    Image(systemName: "clock").font(.system(size: 10))
                    Text("Finished sessions remain for 5 minutes.")
                    Spacer(minLength: 12)
                    Button("Show task files") { runtime.revealTaskFiles() }
                        .buttonStyle(.plain).foregroundStyle(ShellPalette.accent)
                }
                .font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                .padding(.horizontal, 20).padding(.vertical, 13)
                .background(ShellPalette.inset.opacity(0.6))
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "lock.shield").font(.system(size: 11))
                Text("Only task state and reported usage. Your prompts and conversations stay with your agent.")
                    .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(ShellPalette.muted).padding(.horizontal, 2)
        }
    }
}

struct ActivitySummary: View {
    let tasks: [TaskRecord]
    let now: Date
    var selected = "All"
    var onSelect: ((String) -> Void)?
    private func count(_ predicate: (TaskState) -> Bool) -> Int {
        tasks.filter { predicate($0.effectiveState(at: now)) }.count
    }
    var body: some View {
        HStack(spacing: 12) {
            metric("Working", count: count { $0 == .running }, symbol: "bolt.fill", color: ShellPalette.accent)
            metric("Waiting", count: count { $0 == .waiting }, symbol: "pause.fill", color: ShellPalette.warning)
            metric("Finished", count: count { $0.isTerminal }, symbol: "checkmark", color: ShellPalette.accent)
        }
    }
    private func metric(_ title: String, count: Int, symbol: String, color: Color) -> some View {
        ActivityMetricTile(title: title, count: count, symbol: symbol, color: color,
                           selected: selected == title, action: onSelect.map { callback in
            { callback(selected == title ? "All" : title) }
        })
    }
}

private struct ActivityMetricTile: View {
    let title: String
    let count: Int
    let symbol: String
    let color: Color
    let selected: Bool
    let action: (() -> Void)?
    @FocusState private var focused: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    var body: some View {
        Group {
            if let action {
                Button(action: action) { tile }.buttonStyle(.plain).focused($focused)
                    .accessibilityLabel("\(count) \(title.lowercased()) tasks, filter sessions")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .help(selected ? "Click again to show all sessions" : "Show \(title.lowercased()) sessions")
            } else { tile.accessibilityElement(children: .combine) }
        }.onHover { hovered = $0 }
            .offset(y: hovered && action != nil && !reduceMotion ? -2 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: hovered)
    }
    private var tile: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(ShellPalette.muted)
                Text(count.formatted(.number.precision(.integerLength(2))))
                    .font(.system(size: 32, weight: .semibold)).tracking(-0.8)
                    .foregroundStyle(count > 0 ? color : Color.primary)
            }
            Spacer(minLength: 4)
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(color).frame(width: 32, height: 32)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? ShellPalette.tint : ShellPalette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? ShellPalette.accent : selected ? color.opacity(0.5) : hovered ? ShellPalette.accent.opacity(0.3) : ShellPalette.line, lineWidth: focused ? 2 : 1).allowsHitTesting(false))
    }
}

private struct ActivityEmptyView: View {
    var paused: Bool
    let action: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                AgentBadge(claude: true, size: 44)
                Rectangle().fill(ShellPalette.line).frame(width: 24, height: 1)
                BrandMark(size: 44).padding(6).background(ShellPalette.sidebar, in: RoundedRectangle(cornerRadius: 12))
                Rectangle().fill(ShellPalette.line).frame(width: 24, height: 1)
                AgentBadge(claude: false, size: 44)
            }.accessibilityHidden(true)
            VStack(spacing: 7) {
                Text(paused ? "Monitoring is paused" : "Ready to track your next task")
                    .font(.system(size: 19, weight: .medium)).tracking(-0.3)
                Text(paused ? "Enable monitoring to see task activity here." : "Connect Claude Code or Codex with a supervised\ncommand or lifecycle hooks.")
                    .font(.system(size: 12)).foregroundStyle(ShellPalette.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ActionButton(title: paused ? "Open monitoring" : "Set up your agent", symbol: "arrow.right", prominent: true, action: action)
        }.frame(maxWidth: .infinity).padding(.vertical, 46)
    }
}

struct TaskActivityRow: View {
    let task: TaskRecord
    let now: Date
    var showID = false
    private var state: TaskState { task.effectiveState(at: now) }
    private var color: Color {
        switch state {
        case .running: return ShellPalette.accent
        case .completed: return .secondary
        case .waiting, .unknown: return ShellPalette.warning
        case .failed: return ShellPalette.danger
        case .cancelled: return .secondary
        }
    }
    var body: some View {
        HStack(spacing: 14) {
            AgentBadge(claude: task.provider == .claude, size: 34)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.provider.displayName).font(.system(size: 12, weight: .semibold))
                if showID {
                    Text(String(task.id.prefix(28))).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ShellPalette.muted).lineLimit(1).textSelection(.enabled)
                } else {
                    Text("\(task.milestones) tool action\(task.milestones == 1 ? "" : "s")")
                        .font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                }
            }
            Spacer(minLength: 12)
            if showID {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(task.usage.map { "\($0.input.formatted()) in / \($0.output.formatted()) out" } ?? "Not reported")
                        .font(.system(size: 10, design: .monospaced))
                    Text("Tokens · \(task.milestones) tool action\(task.milestones == 1 ? "" : "s")")
                        .font(.system(size: 9)).foregroundStyle(ShellPalette.muted)
                }
            }
            VStack(alignment: .trailing, spacing: 6) {
                Text(duration).font(.system(size: 11, design: .monospaced))
                Text(state.isTerminal ? "Duration" : "Elapsed").font(.system(size: 9)).foregroundStyle(ShellPalette.muted)
            }.frame(width: 65, alignment: .trailing)
            StatusPill(text: state.label, symbol: symbol, color: color).frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(task.id, forType: .string)
            } label: { Label("Copy session ID", systemImage: "doc.on.doc") }
        }
        .help("Right-click to copy the session ID")
    }
    private var duration: String {
        let end = state.isTerminal ? task.observedAt : now
        let seconds = max(0, Int(end.timeIntervalSince(task.startedAt)))
        return seconds >= 3600 ? "\(seconds / 3600)h \(seconds % 3600 / 60)m" : "\(seconds / 60)m \(seconds % 60)s"
    }
    private var symbol: String {
        switch state {
        case .running: return "bolt.fill"
        case .waiting: return "pause.fill"
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        case .cancelled: return "xmark"
        case .unknown: return "questionmark"
        }
    }
}
