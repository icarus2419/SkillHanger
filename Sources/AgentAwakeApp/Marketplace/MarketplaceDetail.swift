import SwiftUI
import AppKit

struct MarketplaceDetail: View {
    let item: CatalogItem
    @ObservedObject var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var removing = false
    @State private var sourceText: String?
    @State private var sourceError: String?
    @State private var loadingSource = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                PackageIcon(item: item, size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 24, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text("\(item.author) · \(item.kind.rawValue.capitalized) · \(item.category.rawValue)").font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(ProductButtonStyle()).accessibilityLabel("Close library details").keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.detail).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeading(title: "Package details")
                        detail("Works with", item.agents.map(\.title).joined(separator: ", "))
                        detail("Publisher", item.author)
                        detail("GitHub", item.repository)
                        if let stars = item.repositoryStars, let checked = item.popularityCheckedAt {
                            detail("Repo popularity", "\(stars.formatted()) GitHub stars · checked \(checked)")
                        }
                        if let version = item.version { detail("Version", version) }
                        if let license = item.license { detail("License", license) }
                        if let marketplace = item.marketplace { detail("Catalog", marketplace) }
                        detail("Source revision", item.revision.count == 40 ? String(item.revision.prefix(12)) : item.revision)
                        Link(destination: item.githubURL) { Label("View source on GitHub", systemImage: "arrow.up.right.square") }
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(ShellPalette.accent)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeading(title: "Install for \(store.query.agent.title)")
                if item.kind == .skill {
                            Text("The complete skill folder is downloaded at this revision. Its scripts are stored without being run during installation.").font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
                            Text("~/\(store.query.agent.skillsDirectory)/\(item.name)").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        } else {
                            Text("Installed at user scope by \(store.query.agent.title)'s plugin manager. Plugins can include skills, tools, and hooks. Account connections and any trust prompts are handled by your agent.").font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
                        }
                        Text("Start a new agent session after installing. Review third-party source code before adding capabilities.").font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                    }
                    if item.kind == .skill {
                        Button(loadingSource ? "Loading instructions…" : "Read SKILL.md") { Task { await loadSource() } }
                            .buttonStyle(ProductButtonStyle()).disabled(loadingSource || store.preview)
                        if let sourceError { Text(sourceError).font(.system(size: 11)).foregroundStyle(ShellPalette.danger) }
                        if let sourceText { Text(sourceText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    }
                    if let message = store.message { MarketplaceNotice(text: message) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if store.isInstalled(item) {
                    Button("Customize") { store.openWorkspace(item); dismiss() }.buttonStyle(ProductButtonStyle())
                    if store.canRemove(item) {
                        Button("Remove…") { removing = true }.buttonStyle(ProductButtonStyle())
                    } else { Text("Existing installation · managed elsewhere").font(.system(size: 10)).foregroundStyle(ShellPalette.muted) }
                    if item.kind == .skill {
                        Button("Show in Finder") {
                            if let url = try? store.installer.existingSkillURL(item, for: store.query.agent) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }.buttonStyle(ProductButtonStyle())
                    }
                }
                Spacer()
                MarketplaceInstallButton(item: item, store: store)
            }.padding(20)
        }
        .frame(width: 610, height: 590).background(ShellPalette.canvas).tint(ShellPalette.accent)
        .alert("Remove \(item.title)?", isPresented: $removing) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { store.remove(item) }
        } message: { Text(store.externalSkills[store.query.agent]?.contains(item.id) == true ? "The skill folder will move to Trash. You can restore it from Finder." : "Remove this installation from \(store.query.agent.title). SkillHanger preserves locally edited skill files.") }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(ShellPalette.muted).frame(width: 104, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
    }
    private func loadSource() async {
        loadingSource = true; sourceError = nil
        defer { loadingSource = false }
        do {
            let data = try await store.github.raw(repository: item.repository, revision: item.revision, path: item.skillManifestPath)
            sourceText = String(data: data, encoding: .utf8) ?? "This file could not be displayed as text."
        } catch { sourceError = error.localizedDescription }
    }
}
