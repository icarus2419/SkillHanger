import SwiftUI
import AppKit

struct MarketplaceRowState: Equatable {
    var agent: MarketplaceAgent
    var installed: Bool
    var busy: Bool
    var disabled: Bool
    var canInstall: Bool
}

/// Values keep an unrelated package operation from redrawing every visible row.
struct MarketplaceRow: View, Equatable {
    let item: CatalogItem
    let state: MarketplaceRowState
    var showDetail: () -> Void
    var install: () -> Void
    var customize: () -> Void
    var cancel: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.item == rhs.item && lhs.state == rhs.state }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: showDetail) {
                HStack(alignment: .top, spacing: 12) {
                    PackageIcon(item: item, size: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(2)
                            Spacer(minLength: 0)
                            Text(item.kind.rawValue.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(0.5)
                                .foregroundStyle(ShellPalette.muted)
                        }
                        Text(item.summary).font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 5) {
                            Text(item.author).lineLimit(1)
                            Text("·")
                            Text(item.category.rawValue).lineLimit(1)
                            if state.installed {
                                Image(systemName: state.disabled ? "pause.circle" : "checkmark.circle").foregroundStyle(ShellPalette.accent)
                            }
                        }.font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).focused($focused)
                .accessibilityLabel("Open \(item.title) details").help("View \(item.title) by \(item.author)")
            MarketplacePackageAction(item: item, state: state, install: install, customize: customize, cancel: cancel)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? ShellPalette.inset : ShellPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? ShellPalette.accent : ShellPalette.line, lineWidth: focused ? 2 : 1).allowsHitTesting(false))
            .onHover { hovered = $0 }
            .contextMenu {
                Button("View details", action: showDetail)
                Link("View source on GitHub", destination: item.githubURL)
                Button("Copy source link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.githubURL.absoluteString, forType: .string)
                }
            }
    }
}

struct MarketplaceInstallButton: View {
    let item: CatalogItem
    @ObservedObject var store: MarketplaceStore
    var agent: MarketplaceAgent? = nil
    var body: some View {
        let target = agent ?? store.query.agent
        MarketplacePackageAction(item: item, state: store.rowState(item, agent: target),
            install: { store.install(item, agent: target) },
            customize: { store.openWorkspace(item, agent: target) },
            cancel: { store.cancel(item, agent: target) })
    }
}

private struct MarketplacePackageAction: View {
    let item: CatalogItem
    let state: MarketplaceRowState
    var install: () -> Void
    var customize: () -> Void
    var cancel: () -> Void
    var body: some View {
        Group {
            if state.busy {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    if !state.installed {
                        Button("Cancel", action: cancel).font(.system(size: 10)).buttonStyle(.plain)
                            .accessibilityLabel("Cancel installation of \(item.title)")
                    }
                }.frame(width: 88).accessibilityLabel("Updating \(item.title)")
            } else if state.installed {
                Button(action: customize) { Label("Customize", systemImage: "slider.horizontal.3").frame(minWidth: 72) }
                    .buttonStyle(ProductButtonStyle())
                    .accessibilityLabel("Customize \(item.title) for \(state.agent.title)").help("Open settings for this installation")
            } else {
                Button(action: install) { Label("Install", systemImage: "arrow.down.to.line").frame(minWidth: 54) }
                    .buttonStyle(ProductButtonStyle(prominent: true)).disabled(!state.canInstall)
                    .help("Install \(item.title) for \(state.agent.title)")
                    .accessibilityLabel("Install \(item.title) for \(state.agent.title)")
            }
        }
    }
}
