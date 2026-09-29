import Foundation
import CryptoKit

enum MarketplaceAgent: String, Codable, CaseIterable, Identifiable {
    case codex, claude
    var id: String { rawValue }
    var title: String { self == .codex ? "Codex" : "Claude Code" }
    var skillsDirectory: String { self == .codex ? ".agents/skills" : ".claude/skills" }
}

enum CatalogKind: String, Codable { case skill, plugin }
enum CatalogScope: String, CaseIterable, Identifiable {
    case all = "Browse", community = "Community", skills = "Skills", plugins = "Plugins", installed = "Installed"
    var id: String { rawValue }
}
enum CatalogSort: String, CaseIterable, Identifiable {
    case recommended = "Featured first", name = "Name A–Z", publisher = "Publisher"
    var id: String { rawValue }
}
enum CatalogCategory: String, Codable, CaseIterable, Identifiable {
    case codingStyles = "Coding styles"
    case development = "Development", design = "Design", documents = "Documents"
    case productivity = "Productivity", data = "Data & research", security = "Security"
    case infrastructure = "Infrastructure", testing = "Testing", integrations = "Integrations"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .codingStyles: return "curlybraces"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .design: return "paintbrush.pointed"
        case .documents: return "doc.text"
        case .productivity: return "checklist"
        case .data: return "chart.xyaxis.line"
        case .security: return "shield.lefthalf.filled"
        case .infrastructure: return "server.rack"
        case .testing: return "checkmark.seal"
        case .integrations: return "puzzlepiece.extension"
        }
    }
    static func infer(_ value: String) -> Self {
        let text = value.lowercased()
        let patterns: [(Self, [String])] = [
            (.security, ["security", "vulnerability", "audit", "threat"]),
            (.testing, ["testing", "test-driven", "debugging", "verification", "playwright"]),
            (.documents, ["document", "pdf", "xlsx", "spreadsheet", "pptx", "presentation", "docx"]),
            (.design, ["design", "figma", "canva", "creative", "art", "image", "video", "game"]),
            (.infrastructure, ["cloudflare", "infrastructure", "deployment", "devops", "vercel", "hosting"]),
            (.data, ["data", "research", "science", "analytics", "visualization"]),
            (.development, ["development", "developer", "code", "programming", "frontend", "sdk", "api", "git", "superpowers"]),
            (.productivity, ["productivity", "planning", "notion", "calendar", "task", "comms", "writing"])
        ]
        return patterns.first { $0.1.contains(where: text.contains) }?.0 ?? .integrations
    }
}

struct CatalogItem: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var title: String
    var summary: String
    var detail: String
    var author: String
    var category: CatalogCategory
    var kind: CatalogKind
    var agents: [MarketplaceAgent]
    var repository: String
    var path: String
    var revision: String
    var marketplace: String? = nil
    var version: String? = nil
    var license: String? = nil
    var keywords: [String] = []
    var featured: Bool = false
    var community: Bool? = nil
    var repositoryStars: Int? = nil
    var popularityCheckedAt: String? = nil
    /// Editorial placement of recognizable packages; not a measured popularity score.
    var featuredPriority: Int? = nil
    var logoName: String? = nil
    var skillManifestPath: String { path.isEmpty ? "SKILL.md" : path + "/SKILL.md" }
    var isCommunity: Bool { community == true }
    var githubURL: URL {
        var components = URLComponents(string: "https://github.com")!
        components.path = "/\(repository)/tree/\(revision)/\(path)"
        return components.url!
    }
    var searchText: String { ([title, name, summary, author, category.rawValue, repository] + keywords).joined(separator: " ").lowercased() }
}

struct CatalogSnapshot {
    let results: [CatalogItem]
    let counts: [CatalogCategory: Int]
    let total: Int
}

struct CatalogQuery {
    var search = ""
    var category: CatalogCategory? = nil
    var scope: CatalogScope = .all
    var agent: MarketplaceAgent = .codex
    var sort: CatalogSort = .recommended
    mutating func clearFilters() { search = ""; category = nil }
    func results(in items: [CatalogItem], installed: Set<String>) -> [CatalogItem] {
        snapshot(in: items, installed: installed).results
    }
    func snapshot(in items: [CatalogItem], installed: Set<String>) -> CatalogSnapshot {
        let words = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        var filtered: [CatalogItem] = []
        var counts: [CatalogCategory: Int] = [:]
        var total = 0
        for item in items where item.agents.contains(agent) &&
            (scope != .skills || item.kind == .skill) && (scope != .plugins || item.kind == .plugin) &&
            (scope != .community || item.isCommunity) &&
            (scope != .installed || installed.contains(item.id)) && words.allSatisfy(item.searchText.contains) {
            total += 1
            counts[item.category, default: 0] += 1
            if category == nil || item.category == category { filtered.append(item) }
        }
        filtered.sort { a, b in
            if sort == .recommended {
                if (a.featuredPriority ?? 0) != (b.featuredPriority ?? 0) { return (a.featuredPriority ?? 0) > (b.featuredPriority ?? 0) }
                if a.featured != b.featured { return a.featured }
                if a.featured && a.isCommunity != b.isCommunity { return a.isCommunity }
                if a.featured && (a.repositoryStars ?? 0) != (b.repositoryStars ?? 0) { return (a.repositoryStars ?? 0) > (b.repositoryStars ?? 0) }
            }
            if sort == .publisher && a.author != b.author { return a.author.localizedStandardCompare(b.author) == .orderedAscending }
            if a.title == b.title { return a.id < b.id }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        return CatalogSnapshot(results: filtered, counts: counts, total: total)
    }
}

enum MarketplaceError: LocalizedError {
    case invalid(String), conflict, modified, missingCLI(String), transport(String), command(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message), .transport(let message), .command(let message): return message
        case .conflict: return "A skill with this name already exists. Your existing files were preserved."
        case .modified: return "This installation has local changes or belongs to another installer. Its files were preserved."
        case .missingCLI(let agent): return "Install the \(agent) CLI to manage its plugins, then try again."
        }
    }
}

enum MarketplaceSafety {
    static func validateName(_ name: String) throws {
        guard name.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$", options: .regularExpression) != nil,
              name != ".", name != ".." else { throw MarketplaceError.invalid("Invalid package name.") }
    }
    static func validateRepository(_ repository: String) throws {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw MarketplaceError.invalid("Use a GitHub repository in owner/repository form.") }
        for part in parts { try validateName(String(part)) }
    }
    static func validatePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              path.utf8.count < 1024 else { throw MarketplaceError.invalid("The package contains an unsafe file path.") }
    }
}

struct SkillMetadata {
    var name: String
    var description: String
    var license: String?
    static func parse(_ text: String) throws -> Self {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else {
            throw MarketplaceError.invalid("The skill is missing its SKILL.md metadata.")
        }
        var values: [String: String] = [:]
        var key: String?
        for line in lines[1..<end] {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if let key { values[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces) }
            } else if let colon = line.firstIndex(of: ":") {
                key = String(line[..<colon])
                var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if [">", ">-", "|", "|-"].contains(value) { value = "" }
                if value.count >= 2 && ((value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'")) { value = String(value.dropFirst().dropLast()) }
                values[key!] = value
            }
        }
        guard let name = values["name"], let description = values["description"], !description.isEmpty else {
            throw MarketplaceError.invalid("The skill must have a name and description.")
        }
        try MarketplaceSafety.validateName(name)
        return Self(name: name, description: description.trimmingCharacters(in: .whitespaces), license: values["license"])
    }
}

struct SkillFile { var path: String; var data: Data; var executable = false }
enum SkillInstallState { case absent, external, managed, disabled }

enum PluginCommand {
    static func setEnabled(_ item: CatalogItem, enabled: Bool, agent: MarketplaceAgent) throws -> [String] {
        guard item.kind == .plugin, agent == .claude else { throw MarketplaceError.invalid("This agent does not expose a native plugin enable switch.") }
        let selector = try install(item, agent: agent)[2]
        return ["plugin", enabled ? "enable" : "disable", selector, "--scope", "user", "--json"]
    }
    static func install(_ item: CatalogItem, agent: MarketplaceAgent) throws -> [String] {
        try MarketplaceSafety.validateName(item.name)
        guard let marketplace = item.marketplace else { throw MarketplaceError.invalid("No plugin catalog is available.") }
        try MarketplaceSafety.validateName(marketplace)
        return agent == .codex ? ["plugin", "add", "\(item.name)@\(marketplace)", "--json"] :
            ["plugin", "install", "\(item.name)@\(marketplace)", "--scope", "user"]
    }
    static func remove(_ item: CatalogItem, agent: MarketplaceAgent) throws -> [String] {
        var args = try install(item, agent: agent)
        args[1] = agent == .codex ? "remove" : "uninstall"
        return args
    }
}

enum PackageLogo {
    static func assetName(itemID: String) -> String {
        "catalog-" + SHA256.hash(data: Data(itemID.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
}
