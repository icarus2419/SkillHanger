import Foundation

struct InstalledLibraryGroup: Identifiable {
    let agent: MarketplaceAgent
    let packages: [InstalledPackage]
    var id: String { agent.id }
}

struct InstalledLibraryQuery {
    var search = ""

    func groups(in packages: [InstalledPackage]) -> [InstalledLibraryGroup] {
        let words = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return MarketplaceAgent.allCases.compactMap { agent in
            let matches = packages.filter { package in
                guard package.agent == agent else { return false }
                let text = package.item.searchText + " " + agent.title.lowercased() + " " + package.item.kind.rawValue
                return words.allSatisfy(text.contains)
            }.sorted { a, b in
                let order = a.item.title.localizedStandardCompare(b.item.title)
                return order == .orderedSame ? a.id < b.id : order == .orderedAscending
            }
            return matches.isEmpty ? nil : InstalledLibraryGroup(agent: agent, packages: matches)
        }
    }
}
