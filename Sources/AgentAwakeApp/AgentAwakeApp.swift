import SwiftUI

@main
struct SkillHangerApp: App {
    @NSApplicationDelegateAdaptor(PreviewAppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime.shared

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { !runtime.isPreview && runtime.prefs.showMenuBar },
                                       set: { if !runtime.isPreview { runtime.prefs.showMenuBar = $0 } })) {
            DetailView(store: runtime.usage, prefs: runtime.prefs,
                       onRefresh: { runtime.usage.refresh() },
                       onSettings: { runtime.open(.settings) })
        } label: {
            UnifiedMenuLabel(runtime: runtime)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { runtime.open(.settings) }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Open SkillHanger") { runtime.open(.marketplace) }.keyboardShortcut("1", modifiers: .command)
            }
        }
    }
}
