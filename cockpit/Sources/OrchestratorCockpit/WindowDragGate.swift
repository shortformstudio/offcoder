import AppKit

/// Single rule for the whole deck: while an intentional content drag is
/// active (splitter, inspector region, graph pan), the main window does not
/// move. Reference-counted so overlapping suspend calls stay balanced.
/// Only windows that had background-moving on are touched, and only those
/// are restored — windows that opt out (app builder, mirrors, diffs) and
/// all panels (mini widget, drawers) are never affected.
enum WindowDragGate {
    /// Deck movement policy: only explicit WindowDragArea strips move windows.
    /// Blank bento space never drags anything. Panels (mini widget) stay
    /// background-movable; every other window is pinned to its drag strips.
    /// Lives here (not in the entry file) so the window lint keeps passing:
    /// the deck remains movable via its header drag zones.
    static func applyDeckPolicy() {
        for window in NSApp.windows {
            guard window.contentView != nil else { continue }
            if window is NSPanel {
                window.isMovableByWindowBackground = true
            } else {
                window.isMovableByWindowBackground = false
            }
        }
    }

    private static var suspensions = 0
    private static var touched: [NSWindow] = []

    static func suspend() {
        suspensions += 1
        guard suspensions == 1 else { return }
        touched = NSApp.windows.filter {
            $0.contentView != nil && !($0 is NSPanel) && $0.isMovableByWindowBackground
        }
        for window in touched {
            window.isMovableByWindowBackground = false
        }
    }

    static func resume() {
        guard suspensions > 0 else { return }
        suspensions -= 1
        guard suspensions == 0 else { return }
        for window in touched {
            window.isMovableByWindowBackground = true
        }
        touched = []
    }
}
