import Foundation

/// Codex reserves its cloud directory name. A separate local catalog delegates
/// downloads to Codex while pointing at the exact GitHub source we browsed.
enum GitHubPluginMarketplace {
    static let name = "skillhanger-github-openai"
    static func translated(_ item: CatalogItem) -> CatalogItem {
        var result = item
        if item.marketplace == "openai-curated" { result.marketplace = name }
        return result
    }
    static func selectors(_ item: CatalogItem) -> [String] {
        let original = item.name + "@" + (item.marketplace ?? "")
        let translated = translated(item)
        let managed = translated.name + "@" + (translated.marketplace ?? "")
        return managed == original ? [original] : [managed, original]
    }
    static func prepare(_ item: CatalogItem, home: URL) throws -> (CatalogItem, URL) {
        try MarketplaceSafety.validateRepository(item.repository)
        try MarketplaceSafety.validateName(item.name)
        try MarketplaceSafety.validateName(item.revision)
        if !item.path.isEmpty { try MarketplaceSafety.validatePath(item.path) }
        let root = home.appendingPathComponent("Library/Application Support/SkillHanger/GitHubPlugins")
        let destination = root.appendingPathComponent(".agents/plugins/marketplace.json")
        var plugins: [[String: Any]] = []
        if let data = try? Data(contentsOf: destination),
           let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            plugins = existing["plugins"] as? [[String: Any]] ?? []
        }
        plugins.removeAll { $0["name"] as? String == item.name }
        var source: [String: Any] = ["source": item.path.isEmpty ? "url" : "git-subdir", "url": "https://github.com/\(item.repository).git"]
        if !item.path.isEmpty { source["path"] = item.path }
        source[item.revision.count == 40 ? "sha" : "ref"] = item.revision
        plugins.append(["name": item.name, "source": source,
                        "policy": ["installation": "AVAILABLE", "authentication": "ON_INSTALL"],
                        "category": item.category.rawValue,
                        "interface": ["displayName": item.title, "shortDescription": item.summary]])
        let catalog: [String: Any] = ["name": name, "interface": ["displayName": "SkillHanger · GitHub"], "plugins": plugins]
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys]).write(to: destination, options: .atomic)
        return (translated(item), root)
    }
}
