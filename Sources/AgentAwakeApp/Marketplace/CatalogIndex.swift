import Foundation

/// Build the searchable text and sort orders once per catalog, not per redraw.
struct CatalogIndex {
    private struct Entry {
        let item: CatalogItem
        let searchText: String
    }
    private let orders: [CatalogSort: [Entry]]
    private let agentCategories: [MarketplaceAgent: [CatalogCategory]]

    init(items: [CatalogItem]) {
        let entries = items.map { Entry(item: $0, searchText: $0.searchText) }
        orders = Dictionary(uniqueKeysWithValues: CatalogSort.allCases.map { sort in
            (sort, entries.sorted { Self.precedes($0.item, $1.item, sort: sort) })
        })
        agentCategories = Dictionary(uniqueKeysWithValues: MarketplaceAgent.allCases.map { agent in
            let available = Set(items.filter { $0.agents.contains(agent) }.map(\.category))
            return (agent, CatalogCategory.allCases.filter(available.contains))
        })
    }

    func categories(for agent: MarketplaceAgent) -> [CatalogCategory] { agentCategories[agent] ?? [] }

    func snapshot(query: CatalogQuery, installed: Set<String>) -> CatalogSnapshot {
        let words = query.search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        var results: [CatalogItem] = []
        var counts: [CatalogCategory: Int] = [:]
        var total = 0
        for entry in orders[query.sort] ?? [] {
            let item = entry.item
            guard item.agents.contains(query.agent),
                  query.scope != .skills || item.kind == .skill,
                  query.scope != .plugins || item.kind == .plugin,
                  query.scope != .community || item.isCommunity,
                  query.scope != .installed || installed.contains(item.id),
                  words.allSatisfy(entry.searchText.contains) else { continue }
            total += 1
            counts[item.category, default: 0] += 1
            if query.category == nil || query.category == item.category { results.append(item) }
        }
        return CatalogSnapshot(results: results, counts: counts, total: total)
    }

    private static func precedes(_ a: CatalogItem, _ b: CatalogItem, sort: CatalogSort) -> Bool {
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
}
