import Combine
import AppKit
import Testing
@testable import AgentAwakeApp

@Suite(.serialized) @MainActor struct DashboardObservationTests {
    @Test func copyingSetupKeepsThePageUsableWithoutOpeningAnAlert() {
        let runtime = AppRuntime(preview: true)
        runtime.page = .awake
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            pasteboard.clearContents()
            let items = saved.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        runtime.copy("isolated setup command")
        #expect(pasteboard.string(forType: .string) == "isolated setup command")
        #expect(runtime.page == .awake)
        #expect(runtime.notice == nil)
        #expect(runtime.feedback == "Copied to clipboard")
    }

    @Test func librarySearchAndTaskTicksDoNotInvalidateTheEntireShell() async throws {
        let runtime = AppRuntime(preview: true)
        var changes = 0
        let subscription = runtime.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        runtime.marketplace.query.search = "design"
        runtime.monitor.isMonitoringEnabled.toggle()
        try await Task.sleep(for: .milliseconds(50))
        #expect(changes == 0)
        #expect(runtime.marketplace.results.allSatisfy { $0.searchText.contains("design") })
    }

    @Test func taskPagesStillReceiveMonitoringUpdates() async throws {
        let runtime = AppRuntime(preview: true)
        runtime.page = .activity
        var changes = 0
        let subscription = runtime.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        runtime.monitor.isMonitoringEnabled = false
        try await Task.sleep(for: .milliseconds(50))
        #expect(changes > 0)
        #expect(runtime.monitor.tasks.isEmpty)
    }
}
