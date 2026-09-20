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
        haltOtherInstances()
        if activateExistingInstance() { return }

        NSApp.setActivationPolicy(.regular)

        // Standalone boot: backing services and preloaded context start with the deck.
        ServiceBootstrap.shared.bootBackingServices()
        Task { await PreloadContextService.shared.rebuild() }

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

    func applicationWillTerminate(_ notification: Notification) {
        ServiceBootstrap.shared.shutdown()
    }

    /// Terminates earlier Offcoder/OrchestratorCockpit processes so one icon owns one deck.
    private func haltOtherInstances() {
        let current = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "OrchestratorCockpit$"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let pids = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) } ?? []
        for pid in pids where pid != current {
            kill(pid, SIGTERM)
        }
    }

    /// Adopts an already-running bundle instance instead of opening a second deck.
    private func activateExistingInstance() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        let current = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != current }
        guard let existing = others.first else { return false }
        existing.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return true
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
