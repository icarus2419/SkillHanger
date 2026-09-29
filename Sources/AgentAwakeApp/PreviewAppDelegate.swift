import AppKit

@MainActor
final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = AppRuntime.shared
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--package-workspaces-verify"), args.indices.contains(index + 1) {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await PackageWorkspaceVerification.run(output: URL(fileURLWithPath: args[index + 1]))
                NSApp.terminate(nil)
            }
            return
        }
        if let index = args.firstIndex(of: "--marketplace-verify"), args.indices.contains(index + 1) {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await MarketplaceVerification.run(output: URL(fileURLWithPath: args[index + 1]))
                NSApp.terminate(nil)
            }
            return
        }
        NSApp.setActivationPolicy(args.contains("--render-preview") ? .prohibited : runtime.isPreview ? .accessory : .regular)
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: icon) {
            NSApp.applicationIconImage = image
        }
        if !runtime.isPreview, let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.activationPolicy == .regular }) {
            let background = args.contains("--background")
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("SkillHanger.open"),
                                                                         object: (background ? "background:" : "") + runtime.page.rawValue)
            if !background { existing.activate(options: [.activateIgnoringOtherApps]) }
            NSApp.terminate(nil)
            return
        }
        if !runtime.isPreview {
          DistributedNotificationCenter.default().addObserver(forName: Notification.Name("SkillHanger.open"), object: nil, queue: .main) { notification in
            MainActor.assumeIsolated {
                let request = notification.object as? String ?? "overview"
                let background = request.hasPrefix("background:")
                let page = background ? String(request.dropFirst("background:".count)) : request
                AppRuntime.shared.open(AppPage(rawValue: page) ?? .overview, activate: !background)
            }
          }
        }
        runtime.start()
        if runtime.isPreview && args.contains("--preview-connect-agent") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                runtime.connectAgent()
            }
        }
        if let index = args.firstIndex(of: "--launch-report"), args.indices.contains(index + 1) {
            let output = URL(fileURLWithPath: args[index + 1])
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                do { try runtime.writeLaunchReport(to: output) }
                catch { fputs("SkillHanger launch report: \(error.localizedDescription)\n", stderr) }
            }
        }
        if let index = args.firstIndex(of: "--render-preview"), args.indices.contains(index + 1) {
            let output = URL(fileURLWithPath: args[index + 1])
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                do { try runtime.render(to: output) }
                catch { fputs("SkillHanger preview: \(error.localizedDescription)\n", stderr) }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppRuntime.shared.open(AppRuntime.shared.page, activate: NSApp.isActive)
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { AppRuntime.shared.stop() }
}
