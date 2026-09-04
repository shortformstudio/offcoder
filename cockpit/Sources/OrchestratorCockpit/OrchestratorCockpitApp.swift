import SwiftUI

@main
struct OrchestratorCockpitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            OrchestratorMainCockpit()
                .frame(minWidth: 1080, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyWindowFlags()
        FaultRegistry.shared.installUncaughtHandler()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyWindowFlags()
    }

    private func applyWindowFlags() {
        for window in NSApp.windows {
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
        }
    }
}
