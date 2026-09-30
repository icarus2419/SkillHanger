import Foundation
import AppKit
import Testing
@testable import AgentAwakeApp

struct SidebarInteractionTests {
    @Test func repeatedSidebarIconRendersReuseTheDecodedImage() throws {
        let item = try #require(CatalogLoader.bundled().first { $0.logoName != nil })
        let first = try #require(PackageIcon(item: item, size: 24).image)
        let second = try #require(PackageIcon(item: item, size: 24).image)
        #expect(first === second)
    }

    @Test func swipeTracksEveryHorizontalPointAndSettlesAtTheReveal() {
        var swipe = InstalledRowSwipe(initiallyOpen: false)
        let tiny = swipe.update(translation: CGSize(width: -2, height: 0))
        #expect(tiny)
        #expect(swipe.offset == -2)
        let moved = swipe.update(translation: CGSize(width: -30, height: 2))
        #expect(moved)
        #expect(swipe.offset == -30)
        #expect(!swipe.finish())
        _ = swipe.update(translation: CGSize(width: -50, height: 2))
        #expect(swipe.finish())
        #expect(!swipe.finish(cancelled: true))
    }

    @Test func longSwipeKeepsTrackingAndCommitsOnlyOnReleaseBeyondThreshold() {
        var swipe = InstalledRowSwipe(initiallyOpen: false)
        _ = swipe.update(translation: CGSize(width: -120, height: 1))
        #expect(swipe.offset == -120)
        #expect(!swipe.commitsFullSwipe())
        _ = swipe.update(translation: CGSize(width: -InstalledRowSwipe.fullSwipeThreshold, height: 1))
        #expect(swipe.commitsFullSwipe())
        #expect(!swipe.commitsFullSwipe(cancelled: true))
        #expect(!swipe.finish())
    }

    @Test func verticalScrollingAndSmallHorizontalMovementsKeepTheRowClosed() {
        var vertical = InstalledRowSwipe(initiallyOpen: false)
        let verticalStart = vertical.update(translation: CGSize(width: -3, height: 12))
        #expect(!verticalStart)
        let diagonalContinuation = vertical.update(translation: CGSize(width: -50, height: 20))
        #expect(!diagonalContinuation)
        #expect(vertical.offset == 0)
        #expect(!vertical.finish())
        var short = InstalledRowSwipe(initiallyOpen: false)
        let small = short.update(translation: CGSize(width: -10, height: 0))
        #expect(small)
        #expect(!short.finish())
        let invalid = short.update(translation: CGSize(width: CGFloat.nan, height: 0))
        #expect(!invalid)
    }

    @Test func reverseSwipeClosesAnOpenRowAndCancelledSwipePreservesItsState() {
        var swipe = InstalledRowSwipe(initiallyOpen: true)
        #expect(swipe.offset == -InstalledRowSwipe.actionWidth)
        let reversed = swipe.update(translation: CGSize(width: 42, height: 2))
        #expect(reversed)
        #expect(!swipe.finish())
        #expect(swipe.finish(cancelled: true))
        let beyond = swipe.update(translation: CGSize(width: 400, height: 3))
        #expect(beyond)
        #expect(swipe.offset == 0)
        #expect(!swipe.finish())
    }

    @Test @MainActor func sidebarRemovalEligibilityUsesTheRowsAgentAndIncludesValidExternalSkills() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = MarketplaceStore(preview: true, home: home)
        let item = try #require(store.items.first { $0.name == "caveman" && $0.kind == .skill })
        let files = [SkillFile(path: "SKILL.md", data: Data("---\nname: caveman\ndescription: Short replies\n---".utf8))]
        try await store.installSkill(item, for: .claude, files: files)
        store.query.agent = .codex
        #expect(store.canRemove(item, agent: .claude))
        #expect(!store.canRemove(item, agent: .codex))
        #expect(!store.canRemove(item))
        let external = home.appendingPathComponent(".agents/skills/caveman")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try files[0].data.write(to: external.appendingPathComponent("SKILL.md"))
        await store.reconcileSkills()
        #expect(store.installed[.codex]?.contains(item.id) == true)
        #expect(store.canRemove(item, agent: .codex))
        #expect(store.canRemove(item, agent: .claude))
    }

    @Test func uninstallingExternalSkillMovesTheCompleteFolderToIsolatedTrash() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let item = try #require(CatalogLoader.bundled().first { $0.name == "caveman" && $0.kind == .skill })
        let source = home.appendingPathComponent(".codex/skills/caveman")
        let trash = home.appendingPathComponent("test-trash/caveman")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let instructions = Data("---\nname: caveman\ndescription: My customized skill\n---\nMy local edits".utf8)
        try instructions.write(to: source.appendingPathComponent("SKILL.md"))
        try Data("Personal reference".utf8).write(to: source.appendingPathComponent("notes.md"))
        let installer = MarketplaceInstaller(home: home, trashItem: { url in
            try FileManager.default.createDirectory(at: trash.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: trash)
        })
        #expect(try installer.canTrashExternalSkill(item, for: .codex))
        try installer.trashExternalSkill(item, for: .codex)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: trash.appendingPathComponent("SKILL.md")) == instructions)
        #expect(try String(contentsOf: trash.appendingPathComponent("notes.md"), encoding: .utf8) == "Personal reference")
        #expect(try installer.skillState(item, for: .codex) == .absent)
    }

    @Test func externalFolderWithoutMatchingMetadataCannotBeTrashed() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let item = try #require(CatalogLoader.bundled().first { $0.name == "caveman" && $0.kind == .skill })
        let root = home.appendingPathComponent(".agents/skills/caveman")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data("---\nname: unrelated\ndescription: Keep these files\n---".utf8)
        try data.write(to: root.appendingPathComponent("SKILL.md"))
        let installer = MarketplaceInstaller(home: home, trashItem: { _ in Issue.record("Unrelated folder must never be trashed") })
        #expect(try !installer.canTrashExternalSkill(item, for: .codex))
        #expect(throws: (any Error).self) { try installer.trashExternalSkill(item, for: .codex) }
        #expect(try Data(contentsOf: root.appendingPathComponent("SKILL.md")) == data)
    }
}
