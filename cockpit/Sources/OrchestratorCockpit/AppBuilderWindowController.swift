import AppKit
import SwiftUI

final class AppBuilderWindowController: NSObject, NSWindowDelegate {
    static let shared = AppBuilderWindowController()
    
    private var windowController: NSWindowController?
    var onWindowClosed: (() -> Void)?
    
    func showWindow() {
        if let wc = windowController {
            wc.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "App Builder"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 400, height: 300)
        window.backgroundColor = NSColor(white: 0.1, alpha: 0.95)
        window.delegate = self
        
        let contentView = AppBuilderWebView(url: ProductionSimulatorService.shared.currentURLString)
        window.contentView = NSHostingView(rootView: contentView)
        
        let wc = NSWindowController(window: window)
        self.windowController = wc
        wc.showWindow(nil)
    }
    
    func hideWindow() {
        windowController?.close()
        windowController = nil
    }
    
    // MARK: - NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onWindowClosed?()
        hideWindow()
        return false
    }
    
    func windowWillMiniaturize(_ notification: Notification) {
        onWindowClosed?()
    }
}
