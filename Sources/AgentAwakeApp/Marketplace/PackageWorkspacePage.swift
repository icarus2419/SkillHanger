import SwiftUI
import AppKit

struct PackageIcon: View {
    let item: CatalogItem
    var size: CGFloat = 40
    private static let imageCache = NSCache<NSString, NSImage>()
    var image: NSImage? {
        guard let name = item.logoName else { return nil }
        if let cached = Self.imageCache.object(forKey: name as NSString) { return cached }
        guard name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              let url = BrandAssets.bundle.url(forResource: name, withExtension: "png") else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        Self.imageCache.setObject(image, forKey: name as NSString)
        return image
    }
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: item.category.symbol).font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(ShellPalette.accent)
            }
        }.frame(width: size, height: size)
            .background(ShellPalette.tint, in: RoundedRectangle(cornerRadius: size * 0.25))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

struct PackageWorkspacePage: View {
    let workspace: InstalledPackage
    @ObservedObject var store: MarketplaceStore
    @ObservedObject var preferences: PackagePreferences
    @State private var removing = false
    @State private var instructions: String?
    @State private var instructionError: String?
    @State private var loading = false
    private var item: CatalogItem { workspace.item }
    private var selection: PackageSelection { workspace.selection }
    private var disabled: Bool { store.disabledSkills[workspace.agent]?.contains(item.id) == true }
    private var invocation: String {
        PackageCustomization.invocation(item, agent: workspace.agent, mode: preferences.mode(for: selection), task: preferences.task(for: selection), options: preferences.options(for: selection))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Surface {
                HStack(alignment: .top, spacing: 16) {
                    PackageIcon(item: item, size: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.summary).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        Text("\(item.author) · \(workspace.agent.title) · \(item.kind.rawValue.capitalized)")
                            .font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                        StatusPill(text: disabled ? "Disabled" : "Installed", symbol: disabled ? "pause.circle" : "checkmark.circle")
                    }
                    Spacer(minLength: 0)
                }
            }
            PackageInvocationCard(workspace: workspace, store: store, preferences: preferences)
            Surface {
              VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "How to use \(item.title)")
                Text(item.detail).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if item.kind == .skill {
                    Button(loading ? "Loading instructions…" : "Read installed SKILL.md") { Task { await loadInstructions() } }
                        .buttonStyle(ProductButtonStyle()).disabled(loading)
                } else {
                    Text("Service connections, hook trust, and provider-specific plugin settings are managed in \(workspace.agent.title). Use the package source below for its supported customization options.")
                        .font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                }
                if let instructionError { Text(instructionError).font(.system(size: 11)).foregroundStyle(ShellPalette.danger) }
                if let instructions { Text(instructions).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
              }
            }
            Surface {
              VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Installation & source")
                Text(item.repository).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                Text("Revision \(item.revision.prefix(12))").font(.system(size: 11, design: .monospaced)).foregroundStyle(ShellPalette.muted)
                HStack {
                    Link("View package on GitHub", destination: item.githubURL).font(.system(size: 12))
                    if item.kind == .skill {
                        Button("Show in Finder") {
                            if let url = try? store.installer.existingSkillURL(item, for: workspace.agent) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }.buttonStyle(ProductButtonStyle()).disabled(store.preview)
                    }
                    Spacer()
                    if store.canRemove(item, agent: workspace.agent) {
                        Button("Remove…") { removing = true }.buttonStyle(ProductButtonStyle()).disabled(store.preview)
                    }
                }
                if let message = store.message { MarketplaceNotice(text: message) }
              }
            }
        }
        .alert("Remove \(item.title) from \(workspace.agent.title)?", isPresented: $removing) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { store.remove(item, agent: workspace.agent) }
        } message: { Text(store.externalSkills[workspace.agent]?.contains(item.id) == true ? "The skill folder will move to Trash. You can restore it from Finder." : "Locally changed skill files are preserved.") }
    }
    private func loadInstructions() async {
        loading = true; instructionError = nil
        defer { loading = false }
        do {
            if store.preview {
                instructions = "Sample package guidance\n\n\(item.detail)\n\n\(invocation)"
            } else {
                let root = try store.installer.existingSkillURL(item, for: workspace.agent)
                let url = root.appendingPathComponent("SKILL.md")
                guard try (url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else { throw MarketplaceError.invalid("This instruction file is too large to display.") }
                instructions = try String(contentsOf: url, encoding: .utf8)
            }
        } catch { instructionError = error.localizedDescription }
    }
}
