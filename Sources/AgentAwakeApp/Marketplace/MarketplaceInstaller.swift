import Foundation
import CryptoKit

private struct SkillReceipt: Codable {
    var itemID: String
    var repository: String
    var revision: String
    var digest: String
    var installedAt: Date
}

final class MarketplaceInstaller: @unchecked Sendable {
    let home: URL
    private let fm = FileManager.default
    private let receiptName = ".skillhanger-receipt.json"
    private let trashItem: @Sendable (URL) throws -> Void
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         trashItem: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.trashItem = trashItem
        var ancestor = home, missing: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missing.append(ancestor.lastPathComponent); ancestor.deleteLastPathComponent()
        }
        self.home = missing.reversed().reduce(ancestor.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
    }

    func skillURL(_ item: CatalogItem, for agent: MarketplaceAgent) throws -> URL {
        try MarketplaceSafety.validateName(item.name)
        return home.appendingPathComponent(agent.skillsDirectory).appendingPathComponent(item.name)
    }
    func skillState(_ item: CatalogItem, for agent: MarketplaceAgent) throws -> SkillInstallState {
        let disabled = try disabledSkillURL(item, for: agent)
        if let data = try? Data(contentsOf: disabled.appendingPathComponent(receiptName)),
           let receipt = try? JSONDecoder().decode(SkillReceipt.self, from: data), receipt.itemID == item.id { return .disabled }
        let destination = try skillURL(item, for: agent)
        if fm.fileExists(atPath: destination.path) {
            if let data = try? Data(contentsOf: destination.appendingPathComponent(receiptName)),
               let receipt = try? JSONDecoder().decode(SkillReceipt.self, from: data), receipt.itemID == item.id { return .managed }
            return .external
        }
        if agent == .codex && fm.fileExists(atPath: home.appendingPathComponent(".codex/skills/\(item.name)/SKILL.md").path) { return .external }
        return .absent
    }
    func existingSkillURL(_ item: CatalogItem, for agent: MarketplaceAgent) throws -> URL {
        if try skillState(item, for: agent) == .disabled { return try disabledSkillURL(item, for: agent) }
        let destination = try skillURL(item, for: agent)
        if !fm.fileExists(atPath: destination.path), agent == .codex {
            let legacy = home.appendingPathComponent(".codex/skills/\(item.name)")
            if fm.fileExists(atPath: legacy.appendingPathComponent("SKILL.md").path) { return legacy }
        }
        return destination
    }
    func installSkill(_ item: CatalogItem, for agent: MarketplaceAgent, files: [SkillFile]) async throws -> URL {
        guard item.kind == .skill, item.agents.contains(agent) else { throw MarketplaceError.invalid("This item does not support \(agent.title).") }
        let destination = try skillURL(item, for: agent)
        guard try skillState(item, for: agent) == .absent else { throw MarketplaceError.conflict }
        guard files.count <= 300, files.reduce(0, { $0 + $1.data.count }) <= 20_000_000,
              let manifest = files.first(where: { $0.path == "SKILL.md" }),
              let text = String(data: manifest.data, encoding: .utf8) else { throw MarketplaceError.invalid("The skill is incomplete or exceeds the package limit.") }
        let metadata = try SkillMetadata.parse(text)
        guard metadata.name == item.name else { throw MarketplaceError.invalid("The downloaded skill's name does not match the catalog.") }
        guard Set(files.map(\.path)).count == files.count else { throw MarketplaceError.invalid("The package has duplicate file paths.") }
        for file in files {
            try MarketplaceSafety.validatePath(file.path)
            guard file.path != receiptName else { throw MarketplaceError.invalid("The package contains a reserved installer file.") }
        }
        let parent = destination.deletingLastPathComponent()
        try ensureNoSymlinkAncestors(parent)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".skillhanger-stage-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        for file in files {
            try Task.checkCancellation()
            let url = staging.appendingPathComponent(file.path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: file.executable ? 0o700 : 0o600], ofItemAtPath: url.path)
        }
        let receipt = SkillReceipt(itemID: item.id, repository: item.repository, revision: item.revision,
                                   digest: try digest(staging), installedAt: Date())
        try JSONEncoder().encode(receipt).write(to: staging.appendingPathComponent(receiptName), options: .atomic)
        try ensureNoSymlinkAncestors(parent)
        try Task.checkCancellation()
        guard !fm.fileExists(atPath: destination.path) else { throw MarketplaceError.conflict }
        try fm.moveItem(at: staging, to: destination)
        return destination
    }
    func removeSkill(_ item: CatalogItem, for agent: MarketplaceAgent) throws {
        let destination = try existingSkillURL(item, for: agent)
        try ensureNoSymlinkAncestors(destination)
        let state = try skillState(item, for: agent)
        guard state == .managed || state == .disabled else { throw MarketplaceError.modified }
        try verifyReceipt(item, at: destination)
        try fm.removeItem(at: destination)
    }
    func canTrashExternalSkill(_ item: CatalogItem, for agent: MarketplaceAgent) throws -> Bool {
        guard item.kind == .skill, item.agents.contains(agent), try skillState(item, for: agent) == .external else { return false }
        let destination = try existingSkillURL(item, for: agent)
        let manifest = destination.appendingPathComponent("SKILL.md")
        try ensureNoSymlinkAncestors(manifest)
        guard fm.fileExists(atPath: manifest.path),
              try (manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_000_000 else { return false }
        let data = try Data(contentsOf: manifest)
        guard data.count <= 1_000_000, let text = String(data: data, encoding: .utf8) else { return false }
        return try SkillMetadata.parse(text).name == item.name
    }
    func trashExternalSkill(_ item: CatalogItem, for agent: MarketplaceAgent) throws {
        guard try canTrashExternalSkill(item, for: agent) else { throw MarketplaceError.modified }
        let destination = try existingSkillURL(item, for: agent)
        try ensureNoSymlinkAncestors(destination)
        try trashItem(destination)
    }
    private func disabledSkillURL(_ item: CatalogItem, for agent: MarketplaceAgent) throws -> URL {
        try MarketplaceSafety.validateName(item.name)
        return home.appendingPathComponent("Library/Application Support/SkillHanger/DisabledSkills")
            .appendingPathComponent(agent.rawValue).appendingPathComponent(item.name)
    }
    func setSkillEnabled(_ item: CatalogItem, for agent: MarketplaceAgent, enabled: Bool) throws {
        guard item.kind == .skill, item.agents.contains(agent) else { throw MarketplaceError.invalid("This skill does not support \(agent.title).") }
        let state = try skillState(item, for: agent)
        guard state == .managed || state == .disabled else { throw MarketplaceError.modified }
        if enabled == (state == .managed) { return }
        let source = try existingSkillURL(item, for: agent)
        let target = try enabled ? skillURL(item, for: agent) : disabledSkillURL(item, for: agent)
        try ensureNoSymlinkAncestors(source)
        try ensureNoSymlinkAncestors(target)
        try verifyReceipt(item, at: source)
        guard !fm.fileExists(atPath: target.path) else { throw MarketplaceError.conflict }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try ensureNoSymlinkAncestors(target)
        try fm.moveItem(at: source, to: target)
    }
    private func verifyReceipt(_ item: CatalogItem, at destination: URL) throws {
        guard
              let data = try? Data(contentsOf: destination.appendingPathComponent(receiptName)),
              let receipt = try? JSONDecoder().decode(SkillReceipt.self, from: data),
              receipt.itemID == item.id,
              receipt.digest == (try digest(destination)) else { throw MarketplaceError.modified }
    }
    private func ensureNoSymlinkAncestors(_ url: URL) throws {
        var check = url
        // The caller supplies a trusted home; macOS itself aliases /var to
        // /private/var. Reject links within our install destination only.
        while check.path != home.path, check.path != "/" {
            if (try? check.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw MarketplaceError.invalid("The destination contains a symbolic link. Its files were preserved.") }
            check.deleteLastPathComponent()
        }
    }
    private func digest(_ directory: URL) throws -> String {
        guard let enumerator = fm.enumerator(atPath: directory.path) else { throw MarketplaceError.modified }
        var files: [String] = []
        for case let path as String in enumerator {
            let url = directory.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw MarketplaceError.modified }
            if values.isRegularFile == true && path != receiptName { files.append(path) }
        }
        var hash = SHA256()
        for path in files.sorted() {
            let url = directory.appendingPathComponent(path)
            hash.update(data: Data(path.utf8)); hash.update(data: Data([0]))
            hash.update(data: SHA256.hash(data: try Data(contentsOf: url)).withUnsafeBytes { Data($0) })
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct NativeAgentCLI: Sendable {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var environment: [String: String]? = nil
    func executable(_ agent: MarketplaceAgent) -> URL? {
        let paths = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let name = agent == .codex ? "codex" : "claude"
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    func run(_ agent: MarketplaceAgent, arguments: [String], timeout: TimeInterval = 180) async throws -> Data {
        guard let executable = executable(agent) else { throw MarketplaceError.missingCLI(agent.title) }
        return try await run(executable: executable, arguments: arguments, timeout: timeout)
    }
    func run(executable: URL, arguments: [String], timeout: TimeInterval = 180) async throws -> Data {
        let operation = Task.detached(priority: .userInitiated) { () throws -> Data in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("skillhanger-cli-\(UUID().uuidString)")
            let errors = output.appendingPathExtension("stderr")
            FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
            FileManager.default.createFile(atPath: errors.path, contents: nil, attributes: [.posixPermissions: 0o600])
            defer { try? FileManager.default.removeItem(at: output); try? FileManager.default.removeItem(at: errors) }
            let handle = try FileHandle(forWritingTo: output)
            let errorHandle = try FileHandle(forWritingTo: errors)
            defer { try? handle.close(); try? errorHandle.close() }
            let process = Process()
            process.executableURL = executable; process.arguments = arguments
            process.currentDirectoryURL = home
            var env = environment ?? ProcessInfo.processInfo.environment
            env["PATH"] = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
            env["GIT_TERMINAL_PROMPT"] = "0"
            process.environment = env
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = handle; process.standardError = errorHandle
            try process.run()
            defer { if process.isRunning { process.terminate() } }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Task.isCancelled || Date() > deadline {
                    process.terminate()
                    throw MarketplaceError.command(Task.isCancelled ? "Installation cancelled." : "The agent installer timed out. Check its plugin list before retrying.")
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            let data = try Data(contentsOf: output)
            guard process.terminationStatus == 0 else {
                let diagnostic = (try? Data(contentsOf: errors)) ?? Data()
                let text = String(data: (diagnostic.isEmpty ? data : diagnostic).suffix(1800), encoding: .utf8) ?? "The agent installer returned an error."
                throw MarketplaceError.command(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return data
        }
        return try await withTaskCancellationHandler(operation: { try await operation.value }, onCancel: { operation.cancel() })
    }
}
