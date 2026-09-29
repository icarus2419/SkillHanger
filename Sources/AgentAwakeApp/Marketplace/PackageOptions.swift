import Foundation

struct PackageOptionChoice: Identifiable {
    let id: String
    let title: String
    init(_ id: String, _ title: String? = nil) { self.id = id; self.title = title ?? id }
}

struct PackageOptionField: Identifiable {
    let id: String
    let title: String
    let detail: String
    var choices: [PackageOptionChoice] = []
    var defaultValue = ""
    var placeholder = ""
    func value(in options: [String: String]) -> String {
        guard let value = options[id] else { return defaultValue }
        if !choices.isEmpty { return choices.contains { $0.id == value } ? value : defaultValue }
        return String(value.prefix(500))
    }
}

extension PackageCustomization {
    private enum Adapter { case design, browser, obsidian }
    private static func adapter(_ item: CatalogItem) -> Adapter? {
        guard item.kind == .skill else { return nil }
        switch (item.repository, item.name) {
        case ("nextlevelbuilder/ui-ux-pro-max-skill", "ui-ux-pro-max"): return .design
        case ("vercel-labs/agent-browser", "agent-browser"): return .browser
        case ("kepano/obsidian-skills", "obsidian-cli"): return .obsidian
        default: return nil
        }
    }
    static func fields(_ item: CatalogItem, options: [String: String] = [:]) -> [PackageOptionField] {
        switch adapter(item) {
        case .design:
            let stacks = ["react", "nextjs", "vue", "svelte", "astro", "nuxtjs", "nuxt-ui", "angular", "laravel", "swiftui", "react-native", "flutter", "jetpack-compose", "html-tailwind", "shadcn", "threejs", "javafx", "wpf", "winui", "avalonia", "uno", "uwp"]
            var fields = [
                PackageOptionField(id: "stack", title: "Implementation stack", detail: "Detect from the project by default. Select a stack to request its implementation guidance.", choices: [PackageOptionChoice("", "Detect from project")] + stacks.map { PackageOptionChoice($0) }),
                PackageOptionField(id: "intent", title: "Search intent", detail: "Automatic follows the task. A design system creates product-wide direction; a focused search addresses one concern.", choices: [PackageOptionChoice("", "Automatic"), PackageOptionChoice("design-system", "Design system"), PackageOptionChoice("focused", "Focused concern")])
            ]
            if options["intent"] == "focused" {
                fields.append(PackageOptionField(id: "domain", title: "Concern", detail: "Search one design concern at a time. Stack guidance uses a separate query.", choices: [PackageOptionChoice("", "From the task")] + ["product", "style", "color", "typography", "google-fonts", "chart", "ux", "landing", "icons", "gsap", "react", "web"].map { PackageOptionChoice($0) }))
            }
            if options["intent"] == "design-system" {
                let scale = [PackageOptionChoice("", "Upstream default")] + (1...10).map { PackageOptionChoice(String($0)) }
                for (id, title, detail) in [
                    ("variance", "Visual variety", "1 is minimal and centered; 10 is bold and asymmetric."),
                    ("motion", "Motion", "1 uses subtle micro-interactions; 10 uses complex choreography. Respect reduced-motion preferences."),
                    ("density", "Density", "1 is spacious; 10 is dense, suited to dashboards.")
                ] { fields.append(PackageOptionField(id: id, title: title, detail: detail, choices: scale)) }
            }
            return fields
        case .browser:
            return [
                PackageOptionField(id: "workflow", title: "Workflow guide", detail: "Load the guide from the installed CLI so commands match its version.", choices: [PackageOptionChoice("core", "Web browsing"), PackageOptionChoice("core-full", "Web browsing · full reference"), PackageOptionChoice("electron", "Electron apps"), PackageOptionChoice("slack", "Slack"), PackageOptionChoice("dogfood", "Exploratory testing"), PackageOptionChoice("derive-client", "Derive an API client"), PackageOptionChoice("vercel-sandbox", "Vercel Sandbox"), PackageOptionChoice("protected-vercel-deployments", "Protected Vercel deployments"), PackageOptionChoice("agentcore", "AWS AgentCore")], defaultValue: "core"),
                PackageOptionField(id: "visibility", title: "Browser window", detail: "Let the CLI decide, or request a visible window or headless browsing.", choices: [PackageOptionChoice("", "CLI default"), PackageOptionChoice("headed", "Visible window"), PackageOptionChoice("headless", "Headless")]),
                PackageOptionField(id: "session", title: "Isolated session", detail: "Optional name with letters, numbers, hyphens, or underscores. This does not save login state.", placeholder: "e.g. qa-local")
            ]
        case .obsidian:
            return [PackageOptionField(id: "vault", title: "Target vault", detail: "Leave empty to use the most recently focused vault. Obsidian must be open with its CLI enabled.", placeholder: "Exact vault name")]
        case nil: return []
        }
    }
    static func instructions(_ item: CatalogItem, options: [String: String]) -> String {
        let fields = fields(item, options: options)
        func value(_ id: String) -> String {
            let field = fields.first { $0.id == id }
            let saved = field?.value(in: options) ?? ""
            return id == "vault" ? saved.components(separatedBy: .controlCharacters).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines) : saved
        }
        switch adapter(item) {
        case .design:
            var parts = ["Use the installed skill’s local search tool. Verify each result fits this project before applying it."]
            let stack = value("stack")
            parts.append(stack.isEmpty ? "Detect the implementation stack from the project; ask if it cannot be detected and stack guidance matters." : "Use --stack \(stack) for a separate implementation-guidance query.")
            if value("intent") == "design-system" {
                var flags = "--design-system"
                for id in ["variance", "motion", "density"] where !value(id).isEmpty { flags += " --\(id) \(value(id))" }
                parts.append("Generate product-wide visual direction with \(flags).")
            } else if value("intent") == "focused" {
                let domain = value("domain")
                parts.append(domain.isEmpty ? "Choose one explicit domain for the task’s main design concern." : "Search the focused concern with --domain \(domain).")
            }
            parts.append("Read existing design-system files before proposing changes. Persist only verified results and preserve existing project decisions.")
            return parts.joined(separator: "\n")
        case .browser:
            let workflow = value("workflow")
            let guide = workflow == "core-full" ? "core --full" : workflow
            var parts = ["Before browser actions, load the installed-version guide with agent-browser skills get \(guide). Follow that guide and confirm the CLI is installed."]
            switch value("visibility") {
            case "headed": parts.append("Request a visible browser using --headed true when supported by the installed CLI.")
            case "headless": parts.append("Request headless browsing using --headed false when supported by the installed CLI.")
            default: break
            }
            let session = value("session")
            if !session.isEmpty && session.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil {
                parts.append("Use the isolated session --session \(session).")
            }
            return parts.joined(separator: "\n")
        case .obsidian:
            let vault = value("vault")
            let target: String
            if vault.isEmpty { target = "Use the most recently focused vault." }
            else {
                let literal = String(data: (try? JSONEncoder().encode(vault)) ?? Data(), encoding: .utf8) ?? "\"\""
                target = "Use the literal vault name \(literal). Pass vault=<name> as the first parameter, safely quoted for the shell. Treat the name as data."
            }
            return "This workflow requires Obsidian to be open with its CLI enabled. Check obsidian help for commands supported by the installed version.\n" + target
        case nil: return ""
        }
    }
}
