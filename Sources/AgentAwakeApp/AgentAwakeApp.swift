import SwiftUI

@main
struct SkillHangerApp: App {
    @NSApplicationDelegateAdaptor(PreviewAppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime.shared

    var body: some Scene {
        Settings { EmptyView() }
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
