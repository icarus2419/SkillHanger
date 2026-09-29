import Foundation
import Testing
@testable import AgentAwakeApp

struct InstalledLibraryTests {
    private func packages() throws -> [InstalledPackage] {
        let catalog = try CatalogLoader.bundled()
        let caveman = try #require(catalog.first { $0.name == "caveman" && $0.kind == .skill })
        let humanizer = try #require(catalog.first { $0.name == "humanizer" && $0.kind == .skill })
        let plugin = try #require(catalog.first { $0.name == "frontend-design" && $0.kind == .plugin && $0.agents.contains(.claude) })
        return [InstalledPackage(item: humanizer, agent: .codex),
                InstalledPackage(item: caveman, agent: .claude),
                InstalledPackage(item: plugin, agent: .claude),
                InstalledPackage(item: caveman, agent: .codex)]
    }

    @Test func installedSearchMatchesWordsAcrossPackageAndAgentWithoutMixingInstallations() throws {
        let installed = try packages()
        let query = InstalledLibraryQuery(search: "  CAVEMAN  claude \n")
        let groups = query.groups(in: installed)
        #expect(groups.count == 1)
        #expect(groups.first?.agent == .claude)
        #expect(groups.first?.packages.map(\.item.name) == ["caveman"])
        #expect(InstalledLibraryQuery(search: "plugin frontend").groups(in: installed).first?.packages.map(\.item.name) == ["frontend-design"])
        #expect(InstalledLibraryQuery(search: "blader").groups(in: installed).first?.packages.map(\.item.name) == ["humanizer"])
        #expect(InstalledLibraryQuery(search: "not-installed").groups(in: installed).isEmpty)
        #expect(installed.count == 4)
    }

    @Test func installedGroupsAreStableAndCountEachAgentsInstallationSeparately() throws {
        let installed = try packages()
        let groups = InstalledLibraryQuery(search: " \n ").groups(in: installed)
        #expect(groups.map(\.agent) == [.codex, .claude])
        #expect(groups.map { $0.packages.count } == [2, 2])
        #expect(groups.first?.packages.map(\.item.name) == ["caveman", "humanizer"])
        #expect(Set(groups.flatMap(\.packages).map(\.id)).count == 4)
        #expect(InstalledLibraryQuery().groups(in: []).isEmpty)
    }

    @Test func clearingLibraryFiltersKeepsTheSelectedScopeAgentAndSort() throws {
        let catalog = try CatalogLoader.bundled()
        let caveman = try #require(catalog.first { $0.name == "caveman" && $0.kind == .skill })
        var query = CatalogQuery(search: "no matches", category: .documents, scope: .installed, agent: .claude, sort: .name)
        query.clearFilters()
        #expect(query.search.isEmpty)
        #expect(query.category == nil)
        #expect(query.scope == .installed)
        #expect(query.agent == .claude)
        #expect(query.sort == .name)
        #expect(query.results(in: catalog, installed: [caveman.id]).map(\.id) == [caveman.id])
    }
}
