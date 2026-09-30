import Foundation

enum CatalogRefreshSource {
    case plugins(MarketplaceAgent)
    case skills(CatalogSkillSource)

    var title: String {
        switch self {
        case .plugins(let agent): return "\(agent.title) plugins"
        case .skills(let source): return source.repository
        }
    }

    func contains(_ item: CatalogItem) -> Bool {
        switch self {
        case .plugins(let agent): return item.kind == .plugin && item.agents == [agent]
        case .skills(let source): return item.kind == .skill && item.repository == source.repository
        }
    }

    func load(using github: GitHubCatalog) async throws -> [CatalogItem] {
        switch self {
        case .plugins(let agent): return try await github.plugins(agent: agent)
        case .skills(let source): return try await github.skills(source: source)
        }
    }
}

struct CatalogRefreshResult {
    let index: Int
    var items: [CatalogItem]? = nil
    var error: String? = nil
}
