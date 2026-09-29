import SwiftUI

struct InstalledPackageSidebarRow: View {
    let workspace: InstalledPackage
    let selected: Bool
    let disabled: Bool
    let canUninstall: Bool
    let busy: Bool
    let preview: Bool
    @Binding var revealedSelection: PackageSelection?
    let action: () -> Void
    let uninstall: () -> Void
    let fullSwipeUninstall: () -> Void
    @FocusState private var focused: Bool
    @State private var hovered = false
    @State private var swipe = InstalledRowSwipe(initiallyOpen: false)
    @State private var swiping = false
    @State private var suppressClick = false
    @State private var committingRemoval = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion

    private var revealed: Bool { revealedSelection == workspace.selection }
    private var canSwipe: Bool { canUninstall && !busy }
    private var canConfirmUninstall: Bool { canSwipe && !preview }
    private var offset: CGFloat { swiping ? swipe.offset : revealed ? -InstalledRowSwipe.actionWidth : 0 }
    private var commitProgress: CGFloat {
        if committingRemoval { return 1 }
        return min(1, max(0, (-offset - 120) / (InstalledRowSwipe.fullSwipeThreshold - 120)))
    }
    private var subtitle: String {
        (workspace.item.kind == .skill ? "Skill" : "Plugin") + (disabled ? " · Disabled" : "")
    }

    var body: some View {
        GeometryReader { geometry in
          let exposed = committingRemoval ? geometry.size.width : min(geometry.size.width, max(0, -offset))
          let iconX = geometry.size.width - exposed / 2
              - (geometry.size.width - exposed) / 2 * commitProgress
          ZStack(alignment: .leading) {
              RoundedRectangle(cornerRadius: 12).fill(ShellPalette.destructiveFill)
              Button(role: .destructive, action: requestUninstall) {
                  Image(systemName: "trash")
                      .font(.system(size: 15, weight: .semibold))
                      .foregroundStyle(.white)
                      .scaleEffect(0.9 + 0.1 * min(1, exposed / InstalledRowSwipe.actionWidth))
                      .opacity(Double(min(1, max(0, (exposed - 4) / CGFloat(32)))))
                      .position(x: iconX, y: 24)
                      .frame(width: geometry.size.width, height: 48)
                      .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .disabled(!canConfirmUninstall)
              .allowsHitTesting(revealed && !swiping && !committingRemoval)
              .accessibilityHidden(!revealed)
              .accessibilityLabel("Uninstall \(workspace.item.title) from \(workspace.agent.title)")
              .help("Uninstall from \(workspace.agent.title)")
              openButton.frame(width: geometry.size.width)
                  .offset(x: offset)
                  .opacity(1 - commitProgress)
                  .allowsHitTesting(!committingRemoval && commitProgress < 1)
          }
          .frame(width: geometry.size.width, height: 48, alignment: .leading)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .transaction { if swiping { $0.disablesAnimations = true } }
        }
        .frame(maxWidth: .infinity).frame(height: 48)
        .clipped()
        .contentShape(Rectangle())
        .background(SidebarSwipeRegion(enabled: canSwipe, isRevealed: revealed, onBegin: beginSwipe,
                                       onUpdate: updateSwipe, onFinish: finishSwipe,
                                       onDismiss: dismissReveal))
        .simultaneousGesture(DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard canSwipe else { return }
                if !swiping { beginSwipe() }
                _ = updateSwipe(value.translation)
            }
            .onEnded { _ in finishSwipe(false) })
        .contextMenu {
            Button("Open settings") { revealedSelection = nil; action() }
            Divider()
            Button(role: .destructive, action: requestUninstall) { Label("Uninstall…", systemImage: "trash") }
                .disabled(!canConfirmUninstall)
            if !canUninstall { Text("Uninstall unavailable for this installation") }
        }
        .onExitCommand { animate { revealedSelection = nil } }
        .onChange(of: canSwipe) { enabled in if !enabled { finishSwipe(true); if revealed { revealedSelection = nil } } }
        .onChange(of: revealedSelection) { selection in
            if selection != workspace.selection && !swiping { swipe = InstalledRowSwipe(initiallyOpen: false) }
        }
        .onChange(of: busy) { active in
            if !active { committingRemoval = false }
        }
    }

    private var openButton: some View {
        Button(action: open) {
            InstalledSidebarRowContent(item: workspace.item, subtitle: subtitle, busy: busy,
                                       chevronActive: hovered || selected).equatable()
        }
        .buttonStyle(InstalledSidebarButtonStyle(selected: selected, hovered: hovered, focused: focused))
        .focused($focused).onHover { hovered = $0 }.disabled(busy)
        .help("\(workspace.item.title) for \(workspace.agent.title) — \(subtitle). Right-click or swipe left for uninstall.")
        .accessibilityLabel("Customize \(workspace.item.title) for \(workspace.agent.title), \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: Text("Show uninstall button")) {
            guard canSwipe else { return }
            animate { revealedSelection = workspace.selection }
        }
    }

    private func open() {
        guard !suppressClick, swipe.axis != .horizontal else { return }
        if revealed { animate { revealedSelection = nil }; return }
        revealedSelection = nil
        action()
    }

    private func requestUninstall() {
        guard canConfirmUninstall else { return }
        animate { revealedSelection = nil }
        uninstall()
    }

    private func dismissReveal() {
        guard revealed || swiping else { return }
        animate {
            revealedSelection = nil
            swiping = false
            swipe = InstalledRowSwipe(initiallyOpen: false)
        }
    }

    private func beginSwipe() {
        swipe = InstalledRowSwipe(initiallyOpen: revealed)
        swiping = true
        if !revealed && revealedSelection != nil { animate { revealedSelection = nil } }
    }

    private func updateSwipe(_ translation: CGSize) -> Bool {
        guard canSwipe else { return false }
        if !swiping { beginSwipe() }
        let horizontal = swipe.update(translation: translation)
        return horizontal
    }

    private func finishSwipe(_ cancelled: Bool) {
        guard swiping else { return }
        let horizontal = swipe.axis == .horizontal
        let fullSwipe = canConfirmUninstall && swipe.commitsFullSwipe(cancelled: cancelled)
        let shouldReveal = swipe.finish(cancelled: cancelled)
        if horizontal {
            suppressClick = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                suppressClick = false
            }
        }
        if fullSwipe {
            committingRemoval = true
            revealedSelection = nil
            swiping = false
            fullSwipeUninstall()
            return
        }
        animate {
            if shouldReveal { revealedSelection = workspace.selection }
            else if revealed { revealedSelection = nil }
            swiping = false
            swipe = InstalledRowSwipe(initiallyOpen: shouldReveal)
        }
    }

    private func animate(_ changes: () -> Void) {
        withAnimation(systemReduceMotion || forcedReduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), changes)
    }
}

/// This content is stable while the card tracks a finger; only the swipe transforms change.
private struct InstalledSidebarRowContent: View, Equatable {
    let item: CatalogItem
    let subtitle: String
    let busy: Bool
    let chevronActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            PackageIcon(item: item, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.mini).frame(width: 9) }
            else {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(chevronActive ? 0.65 : 0.3))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct InstalledSidebarButtonStyle: ButtonStyle {
    let selected: Bool
    let hovered: Bool
    let focused: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(selected ? 1 : 0.88))
            .background(selected ? ShellPalette.brandHighlight.opacity(configuration.isPressed ? 0.24 : 0.16) : .white.opacity(configuration.isPressed ? 0.12 : hovered ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 11))
            .background(ShellPalette.sidebar, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(focused ? ShellPalette.brandHighlight : .white.opacity(selected ? 0.12 : hovered ? 0.1 : 0.06)))
    }
}
