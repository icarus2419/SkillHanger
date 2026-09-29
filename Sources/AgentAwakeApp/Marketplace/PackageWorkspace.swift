import Foundation
import Combine

struct PackageSelection: Codable, Hashable, Identifiable {
    var itemID: String
    var agent: MarketplaceAgent
    var id: String { agent.rawValue + ":" + itemID }
}

struct InstalledPackage: Identifiable {
    let item: CatalogItem
    let agent: MarketplaceAgent
    var selection: PackageSelection { PackageSelection(itemID: item.id, agent: agent) }
    var id: String { selection.id }
}

@MainActor
final class PackagePreferences: ObservableObject {
    let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    func mode(for selection: PackageSelection) -> String {
        defaults.string(forKey: "package.mode." + selection.id) ?? "full"
    }
    func setMode(_ mode: String, for selection: PackageSelection) {
        objectWillChange.send()
        defaults.set(mode, forKey: "package.mode." + selection.id)
    }
    func task(for selection: PackageSelection) -> String {
        defaults.string(forKey: "package.task." + selection.id) ?? ""
    }
    func setTask(_ task: String, for selection: PackageSelection) {
        objectWillChange.send()
        defaults.set(String(task.prefix(4000)), forKey: "package.task." + selection.id)
    }
    func options(for selection: PackageSelection) -> [String: String] {
        defaults.dictionary(forKey: "package.options." + selection.id) as? [String: String] ?? [:]
    }
    func setOption(_ value: String, key: String, for selection: PackageSelection) {
        guard key.count <= 64 else { return }
        var saved = options(for: selection)
        saved[key] = String(value.prefix(500))
        objectWillChange.send()
        defaults.set(saved, forKey: "package.options." + selection.id)
    }
    func reset(for selection: PackageSelection) {
        objectWillChange.send()
        for prefix in ["package.mode.", "package.task.", "package.options."] { defaults.removeObject(forKey: prefix + selection.id) }
    }
}

enum PackageCustomization {
    static func modes(_ item: CatalogItem) -> [String] {
        if item.repository == "JuliusBrussee/caveman" && item.name == "caveman" {
            return ["lite", "full", "ultra", "wenyan-lite", "wenyan-full", "wenyan-ultra", "off"]
        }
        if item.repository == "DietrichGebert/ponytail" && item.name == "ponytail" { return ["lite", "full", "ultra"] }
        return []
    }
    static func invocation(_ item: CatalogItem, agent: MarketplaceAgent, mode: String, task: String = "", options: [String: String] = [:]) -> String {
        let availableModes = modes(item)
        let selectedMode = availableModes.contains(mode) ? mode : "full"
        let base = item.kind == .skill ? (agent == .codex ? "$" : "/") + item.name : "Use the \(item.title) plugin"
        let command = base + (availableModes.isEmpty ? "" : " " + selectedMode)
        let prompt = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration = instructions(item, options: options)
        return ([command, configuration, prompt].filter { !$0.isEmpty }).joined(separator: "\n\n")
    }
    static func modeDescription(_ mode: String, item: CatalogItem) -> String {
        if item.name == "ponytail" {
            switch mode {
            case "lite": return "Suggest simpler alternatives while following your chosen approach."
            case "ultra": return "Challenge unnecessary abstractions and push for the smallest correct solution."
            default: return "Prefer existing code, native features, and the standard library."
            }
        }
        switch mode {
        case "lite": return "Short, readable sentences with less filler."
        case "ultra": return "Maximum compression. Best when you already know the context."
        case "wenyan-lite": return "Semi-classical Chinese with more sentence structure."
        case "wenyan-full": return "Terse Classical Chinese."
        case "wenyan-ultra": return "Maximum Classical Chinese compression."
        case "off": return "Return to normal replies in the agent session."
        default: return "Terse technical fragments; code and exact errors stay intact."
        }
    }
}
