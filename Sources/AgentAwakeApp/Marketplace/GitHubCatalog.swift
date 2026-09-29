import Foundation

private final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

actor GitHubCatalog {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = ["User-Agent": "SkillHanger-Marketplace", "Accept": "application/vnd.github+json"]
        session = URLSession(configuration: config, delegate: GitHubRedirectPolicy(), delegateQueue: nil)
    }
    func data(_ url: URL) async throws -> Data {
        guard url.scheme == "https", ["api.github.com", "raw.githubusercontent.com"].contains(url.host ?? ""),
              url.user == nil, url.password == nil else { throw MarketplaceError.invalid("Only public GitHub HTTPS sources are supported.") }
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MarketplaceError.transport(status == 403 || status == 429 ? "GitHub's public request limit was reached. Try again later; the saved catalog is still available." : "GitHub could not load this source (HTTP \(status)). Try again.")
        }
        guard response.expectedContentLength <= 20_000_000 else { throw MarketplaceError.invalid("This GitHub response exceeds the download limit.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 20_000_000 else { throw MarketplaceError.invalid("This GitHub response exceeds the download limit.") }
            data.append(byte)
        }
        return data
    }
    func raw(repository: String, revision: String, path: String) async throws -> Data {
        try MarketplaceSafety.validateRepository(repository); try MarketplaceSafety.validatePath(path)
        try MarketplaceSafety.validateName(revision)
        let components = [repository, revision, path].joined(separator: "/")
        guard let url = URL(string: "https://raw.githubusercontent.com/" + components.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else { throw MarketplaceError.invalid("Invalid GitHub file URL.") }
        return try await data(url)
    }
    func tree(repository: String) async throws -> (String, [[String: Any]]) {
        try MarketplaceSafety.validateRepository(repository)
        let payload = try await data(URL(string: "https://api.github.com/repos/\(repository)/git/trees/HEAD?recursive=1")!)
        guard let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let sha = json["sha"] as? String, let entries = json["tree"] as? [[String: Any]],
              json["truncated"] as? Bool != true else { throw MarketplaceError.invalid("GitHub returned an incomplete repository tree.") }
        return (sha, entries)
    }
    func skillFiles(_ item: CatalogItem) async throws -> [SkillFile] {
        try MarketplaceSafety.validateRepository(item.repository)
        if !item.path.isEmpty { try MarketplaceSafety.validatePath(item.path) }
        guard item.revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { throw MarketplaceError.invalid("This skill needs a verified GitHub commit before installation. Refresh the catalog.") }
        let payload = try await data(URL(string: "https://api.github.com/repos/\(item.repository)/git/trees/\(item.revision)?recursive=1")!)
        guard let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let entries = json["tree"] as? [[String: Any]], json["truncated"] as? Bool != true else { throw MarketplaceError.invalid("The package's file list is incomplete.") }
        let prefix = item.path.isEmpty ? "" : item.path + "/"
        let selected = entries.filter { ($0["path"] as? String)?.hasPrefix(prefix) == true && $0["type"] as? String != "tree" }
        guard !selected.isEmpty, selected.count <= 300 else { throw MarketplaceError.invalid("The skill is empty or has more than 300 files.") }
        var total = 0
        for entry in selected {
            guard entry["type"] as? String == "blob", ["100644", "100755"].contains(entry["mode"] as? String ?? "") else { throw MarketplaceError.invalid("Linked files and submodules are not supported in skill packages.") }
            total += entry["size"] as? Int ?? 0
        }
        guard total <= 20_000_000 else { throw MarketplaceError.invalid("This skill exceeds the 20 MB download limit.") }
        var files: [SkillFile] = []
        for entry in selected {
            try Task.checkCancellation()
            let full = entry["path"] as! String
            let path = String(full.dropFirst(prefix.count))
            try MarketplaceSafety.validatePath(path)
            let payload = try await raw(repository: item.repository, revision: item.revision, path: full)
            files.append(SkillFile(path: path, data: payload, executable: entry["mode"] as? String == "100755"))
        }
        return files
    }
    func skills(source: CatalogSkillSource) async throws -> [CatalogItem] {
        let repository = source.repository
        let (sha, entries) = try await tree(repository: repository)
        let paths = entries.compactMap { $0["path"] as? String }.filter(source.includes)
        guard source.packages.allSatisfy({ paths.contains($0.path.isEmpty ? "SKILL.md" : $0.path + "/SKILL.md") }) else {
            throw MarketplaceError.invalid("A reviewed skill moved or disappeared. The saved source is preserved.")
        }
        var items: [CatalogItem] = []
        for path in paths {
            let raw = try await raw(repository: repository, revision: sha, path: path)
            guard let text = String(data: raw, encoding: .utf8) else { continue }
            let metadata = try SkillMetadata.parse(text)
            let directory = path == "SKILL.md" ? "" : String(path.dropLast("/SKILL.md".count))
            let category = CatalogCategory.infer(metadata.name + " " + metadata.description.prefix(100))
            items.append(CatalogItem(id: repository + ":" + directory, name: metadata.name,
                                     title: metadata.name.replacingOccurrences(of: "-", with: " ").capitalized,
                                     summary: metadata.description, detail: metadata.description,
                                     author: repository.split(separator: "/")[0].description, category: category,
                                     kind: .skill, agents: [.codex, .claude], repository: repository, path: directory,
                                     revision: sha, license: metadata.license,
                                     featured: ["frontend-design", "webapp-testing", "test-driven-development", "pdf", "react-best-practices"].contains(metadata.name)))
        }
        return items.map(source.curate)
    }
    func plugins(agent: MarketplaceAgent) async throws -> [CatalogItem] {
        let repo = agent == .codex ? "openai/plugins" : "anthropics/claude-plugins-official"
        let manifestPath = agent == .codex ? ".agents/plugins/marketplace.json" : ".claude-plugin/marketplace.json"
        let (sha, _) = try await tree(repository: repo)
        let manifest = try await raw(repository: repo, revision: sha, path: manifestPath)
        guard let json = try JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let name = json["name"] as? String, let plugins = json["plugins"] as? [[String: Any]] else { throw MarketplaceError.invalid("The plugin catalog is malformed.") }
        var result: [CatalogItem] = []
        for plugin in plugins {
            try Task.checkCancellation()
            guard let pluginName = plugin["name"] as? String else { continue }
            try MarketplaceSafety.validateName(pluginName)
            var sourceRepo = repo, path = "", revision = sha
            var metadata = plugin
            if let source = plugin["source"] as? String { path = source.hasPrefix("./") ? String(source.dropFirst(2)) : source }
            if let source = plugin["source"] as? [String: Any] {
                guard source["source"] as? String != "command" else { continue }
                path = source["path"] as? String ?? ""
                if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
                if let url = source["url"] as? String {
                    guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host == "github.com" else { continue }
                    sourceRepo = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if sourceRepo.hasSuffix(".git") { sourceRepo = String(sourceRepo.dropLast(4)) }
                    revision = source["sha"] as? String ?? source["ref"] as? String ?? "HEAD"
                }
            }
            try MarketplaceSafety.validateRepository(sourceRepo)
            if agent == .codex {
                let payload = try await raw(repository: sourceRepo, revision: revision, path: (path.isEmpty ? "" : path + "/") + ".codex-plugin/plugin.json")
                metadata = (try JSONSerialization.jsonObject(with: payload) as? [String: Any]) ?? plugin
            }
            let interface = metadata["interface"] as? [String: Any] ?? [:]
            let summary = interface["shortDescription"] as? String ?? metadata["description"] as? String ?? ""
            guard !summary.isEmpty else { continue }
            let author = (metadata["author"] as? [String: Any])?["name"] as? String ?? (agent == .codex ? "OpenAI catalog" : sourceRepo.split(separator: "/")[0].description)
            let categoryText = plugin["category"] as? String ?? interface["category"] as? String ?? pluginName
            result.append(CatalogItem(id: "\(agent.rawValue):\(name):\(pluginName)", name: pluginName,
                title: interface["displayName"] as? String ?? pluginName.replacingOccurrences(of: "-", with: " ").capitalized,
                summary: summary, detail: interface["longDescription"] as? String ?? metadata["description"] as? String ?? summary,
                author: author, category: CatalogCategory.infer(categoryText), kind: .plugin, agents: [agent],
                repository: sourceRepo, path: path, revision: revision, marketplace: name,
                version: metadata["version"] as? String, license: metadata["license"] as? String,
                keywords: metadata["keywords"] as? [String] ?? [],
                featured: ["superpowers", "build-macos-apps", "frontend-design", "cloudflare", "figma", "code-review"].contains(pluginName),
                logoName: (interface["logo"] as? String)?.lowercased().hasSuffix(".png") == true ? PackageLogo.assetName(itemID: "\(agent.rawValue):\(name):\(pluginName)") : nil))
        }
        return result
    }
}

enum CatalogLoader {
    static func skillSources() throws -> [CatalogSkillSource] {
        guard let url = BrandAssets.bundle.url(forResource: "marketplace-sources", withExtension: "json") else { throw MarketplaceError.invalid("The library source list is missing.") }
        return try JSONDecoder().decode([CatalogSkillSource].self, from: Data(contentsOf: url))
    }
    static func bundled() throws -> [CatalogItem] {
        guard let url = BrandAssets.bundle.url(forResource: "marketplace-catalog", withExtension: "json") else { throw MarketplaceError.invalid("The bundled library catalog is missing.") }
        return try JSONDecoder().decode([CatalogItem].self, from: Data(contentsOf: url))
    }
}
