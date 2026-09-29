import AgentAwakeCore
import SwiftUI

extension TaskState {
    var label: String {
        switch self {
        case .running: "Working"
        case .waiting: "Waiting for input"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .unknown: "Status unknown"
        }
    }
}

private extension Provider {
    var accent: Color { self == .claude ? Color(red: 0.86, green: 0.55, blue: 0.42) : ShellPalette.brandHighlight }
}

private func elapsed(_ record: TaskRecord, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(record.startedAt)))
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m \(seconds % 60)s"
}

private func usage(_ record: TaskRecord) -> String {
    guard let value = record.usage else { return "Tokens unavailable" }
    return "\(value.input.formatted()) in · \(value.output.formatted()) out"
}

struct OverlayView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var previewReduceMotion: Bool? = nil

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.04, blue: 0.042).opacity(0.95)
            VStack(spacing: 26) {
                HStack(spacing: 8) {
                    BrandMark(size: 26)
                    Text("SKILLHANGER").font(.caption.weight(.semibold)).tracking(3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                HStack(spacing: 24) {
                    ForEach(model.displayTasks) { task in
                        let state = task.effectiveState(at: model.now)
                        VStack(spacing: 14) {
                            OrbitMark(color: task.provider.accent, state: state, milestones: task.milestones, animated: model.animateOverlay && !(previewReduceMotion ?? reduceMotion))
                                .frame(width: 88, height: 88)
                            Text(task.provider.displayName).font(.title3.weight(.medium))
                            Text(state.label)
                                .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                            Text(elapsed(task, now: model.now))
                                .font(.system(.title2, design: .rounded).monospacedDigit())
                            Text(usage(task))
                                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                            if task.milestones > 0 {
                                Text("\(task.milestones) tool action\(task.milestones == 1 ? "" : "s") observed")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.42))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 220)
                        .padding(24)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                Text("Move the mouse or press a key to return")
                    .font(.caption).foregroundStyle(.white.opacity(0.38))
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Agent Awake task display")
    }
}

private struct OrbitMark: View {
    let color: Color
    let state: TaskState
    let milestones: Int
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated || state != .running)) { context in
            let angle = animated && state == .running ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8 * 360 : 0
            ZStack {
                Circle().stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: state == .unknown ? [3, 4] : []))
                Circle().trim(from: 0, to: min(0.18 + Double(milestones) * 0.02, 0.42))
                    .stroke(color.opacity(state == .running ? 1 : 0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(angle))
                Circle().fill(color.opacity(0.7)).frame(width: 9, height: 9)
            }
        }
    }
}
