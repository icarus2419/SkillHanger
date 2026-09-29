import SwiftUI

struct MarketplaceRow: View {
    let item: CatalogItem
    @ObservedObject var store: MarketplaceStore
    var showDetail: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: showDetail) {
                PackageIcon(item: item, size: 40)
            }.buttonStyle(.plain).accessibilityLabel("Details for \(item.title)")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button(action: showDetail) { Text(item.title).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.leading) }
                        .buttonStyle(.plain).accessibilityLabel("Open \(item.title) details")
                    Text(item.kind.rawValue.uppercased()).font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(ShellPalette.muted).padding(.horizontal, 5).padding(.vertical, 3)
                        .background(ShellPalette.inset, in: RoundedRectangle(cornerRadius: 4))
                }
                Text("\(item.author) · \(item.category.rawValue)").font(.system(size: 10)).foregroundStyle(ShellPalette.muted)
                Text(item.summary).font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            MarketplaceInstallButton(item: item, store: store).padding(.top, 2)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ShellPalette.line))
    }
}

struct MarketplaceInstallButton: View {
    let item: CatalogItem
    @ObservedObject var store: MarketplaceStore
    var body: some View {
        Group {
            if store.isBusy(item) {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { store.cancel(item) }.font(.system(size: 10)).buttonStyle(.plain)
                }.frame(width: 80).accessibilityLabel("Installing \(item.title)")
            } else if store.isInstalled(item) {
                Button { store.openWorkspace(item) } label: { Label("Customize", systemImage: "slider.horizontal.3").frame(minWidth: 72) }
                    .buttonStyle(ProductButtonStyle())
                    .accessibilityLabel("Customize \(item.title) for \(store.query.agent.title)")
            } else {
                Button { store.install(item) } label: { Label("Install", systemImage: "arrow.down.to.line").frame(minWidth: 54) }
                    .buttonStyle(ProductButtonStyle(prominent: true))
                    .disabled(store.preview || (item.kind == .plugin && store.checking))
                    .help("Install \(item.title) for \(store.query.agent.title)")
                    .accessibilityLabel("Install \(item.title) for \(store.query.agent.title)")
            }
        }
    }
}
