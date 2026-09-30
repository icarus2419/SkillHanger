import SwiftUI

@main
struct SkillHangerApp: App {
    @NSApplicationDelegateAdaptor(PreviewAppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime.shared

    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            CommandMenu("Go") {
                Button("Skill Library") { runtime.open(.marketplace) }.keyboardShortcut("1", modifiers: .command)
                Button("Overview") { runtime.open(.overview) }.keyboardShortcut("2", modifiers: .command)
                Button("Usage") { runtime.open(.usage) }.keyboardShortcut("3", modifiers: .command)
                Button("Agent Awake") { runtime.open(.awake) }.keyboardShortcut("4", modifiers: .command)
                Button("Activity") { runtime.open(.activity) }.keyboardShortcut("5", modifiers: .command)
                Button("Installed packages") { runtime.open(.installed) }.keyboardShortcut("6", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { runtime.open(.settings) }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
