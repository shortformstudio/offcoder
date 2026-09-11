import AppKit
import SwiftUI

final class FloatingDiffWindowManager: NSObject, NSWindowDelegate {
    static let shared = FloatingDiffWindowManager()

    private var windowController: NSWindowController?

    func showWindow() {
        if let wc = windowController, let window = wc.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let containerView = FloatingDiffContainerView()
        let hostingView = NSHostingView(rootView: containerView)

        let window = NSPanel(
            contentRect: NSRect(x: 120, y: 120, width: 840, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isFloatingPanel = true
        window.level = .floating
        window.title = "Code Diffs & Version Chain"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 340)
        window.contentView = hostingView
        window.delegate = self
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        window.center()
        let wc = NSWindowController(window: window)
        self.windowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        windowController?.window?.orderOut(nil)
    }

    func toggleWindow() {
        if let win = windowController?.window, win.isVisible {
            win.orderOut(nil)
        } else {
            showWindow()
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Window closed by user
    }
}

struct FloatingDiffContainerView: View {
    @ObservedObject var versionManager = CodeVersionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Window Header / Drag Bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.cyan.opacity(0.4), lineWidth: 2).scaleEffect(1.3))
                    Text("STANDALONE DIFF VIEWER")
                        .font(CockpitFonts.mono(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("•")
                        .foregroundColor(.white.opacity(0.2))
                    Text("Interactive Revision Iterations")
                        .font(CockpitFonts.mono(size: 9))
                        .foregroundColor(.gray)
                }

                WindowDragArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button(action: {
                    FloatingDiffWindowManager.shared.closeWindow()
                }) {
                    Image(systemName: "xmark")
                        .font(CockpitFonts.bold(size: 10))
                        .foregroundColor(.gray)
                        .padding(5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75))

            Divider().background(Color.white.opacity(0.08))

            // Embedded CodeVersionDiffView
            CodeVersionDiffView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CockpitPalette.background)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.7), radius: 20, x: 0, y: 10)
    }
}
