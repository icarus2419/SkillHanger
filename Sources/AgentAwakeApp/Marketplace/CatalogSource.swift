import Foundation

/// Shared, reviewed sources for bundled discovery and live refresh.
struct CatalogSkillSource: Codable {
    var repository: String
    var root: String
    var community: Bool
    var packages: [Package]
    var repositoryStars: Int?
    var popularityCheckedAt: String?

    struct Package: Codable {
        var path: String
        var title: String
        var summary: String
        var detail: String
        var category: CatalogCategory
        var featured: Bool
        var featuredPriority: Int? = nil
        var logoName: String? = nil
    }

    func includes(_ path: String) -> Bool {
        if !packages.isEmpty { return packages.contains { path == ($0.path.isEmpty ? "SKILL.md" : $0.path + "/SKILL.md") } }
        return path.hasPrefix(root + "/") && path.hasSuffix("/SKILL.md")
    }

    func curate(_ item: CatalogItem) -> CatalogItem {
        var result = item
        result.community = community
        result.repositoryStars = repositoryStars
        result.popularityCheckedAt = popularityCheckedAt
        if let package = packages.first(where: { $0.path == item.path }) {
            result.title = package.title; result.summary = package.summary
            result.detail = package.detail; result.category = package.category
            result.featured = package.featured
            result.featuredPriority = package.featuredPriority
            result.logoName = package.logoName
        }
        return result
    }
}
