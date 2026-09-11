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
        .commands {
            // Single-window app: no New Window / duplicate window actions
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var positionedMainWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyWindowFlags()
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyWindowFlags()
        }
        DispatchQueue.main.async { [weak self] in
            self?.applyWindowFlags()
            self?.positionMainWindowIfNeeded()
        }
        FaultRegistry.shared.installUncaughtHandler()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyWindowFlags()
    }

    private func positionMainWindowIfNeeded() {
        guard !positionedMainWindow else { return }
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) }) else { return }
        let screen = window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let inset: CGFloat = 24
        let size = window.frame.size
        let frame = NSRect(
            x: visibleFrame.minX + inset,
            y: visibleFrame.maxY - size.height - inset,
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true)
        positionedMainWindow = true
    }

    private func applyWindowFlags() {
        for window in NSApp.windows {
            // Top-titlebar drag only; background drag stays off everywhere
            window.isMovableByWindowBackground = false
            window.titlebarAppearsTransparent = true
        }
    }
}
