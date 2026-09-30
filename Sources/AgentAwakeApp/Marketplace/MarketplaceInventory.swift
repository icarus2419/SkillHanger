import Foundation

struct MarketplaceSkillInventory: Sendable {
    var found: Set<String> = []
    var owned: Set<String> = []
    var disabled: Set<String> = []
    var external: Set<String> = []

    static func read(items: [CatalogItem], installer: MarketplaceInstaller) async -> [MarketplaceAgent: Self] {
        await Task.detached(priority: .utility) {
            var inventories: [MarketplaceAgent: Self] = [:]
            for agent in MarketplaceAgent.allCases {
                var inventory = Self()
                let directories = [agent.skillsDirectory,
                    "Library/Application Support/SkillHanger/DisabledSkills/\(agent.rawValue)"] +
                    (agent == .codex ? [".codex/skills"] : [])
                let names = Set(directories.flatMap {
                    (try? FileManager.default.contentsOfDirectory(atPath: installer.home.appendingPathComponent($0).path)) ?? []
                })
                for item in items where item.kind == .skill && item.agents.contains(agent) && names.contains(item.name) {
                    guard let state = try? installer.skillState(item, for: agent), state != .absent else { continue }
                    inventory.found.insert(item.id)
                    if state == .managed || state == .disabled { inventory.owned.insert(item.id) }
                    if state == .disabled { inventory.disabled.insert(item.id) }
                    if state == .external, (try? installer.canTrashExternalSkill(item, for: agent)) == true { inventory.external.insert(item.id) }
                }
                inventories[agent] = inventory
            }
            return inventories
        }.value
    }
}

struct MarketplacePluginInventoryResult {
    var agent: MarketplaceAgent
    var data: Data?
    var error: String?
}
