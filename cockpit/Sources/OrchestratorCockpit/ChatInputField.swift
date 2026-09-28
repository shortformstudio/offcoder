import SwiftUI
import AppKit

struct ChatInputField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = BuildConfig.isBlank ? "Message your model (Cmd+Enter or Enter to send)..." : "Message Qwythos (Cmd+Enter or Enter to send, Shift+Enter for newline)..."
    var onSubmit: () -> Void
    var onContextTrigger: (() -> Void)? = nil
    var onCommandTrigger: (() -> Void)? = nil
    var onPasteLargeText: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = AutoEnterTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.white
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.placeholderString = placeholder
        textView.onSubmitCallback = {
            self.onSubmit()
        }
        textView.onContextTriggerCallback = {
            self.onContextTrigger?()
        }
        textView.onCommandTriggerCallback = {
            self.onCommandTrigger?()
        }
        textView.onPasteLargeTextCallback = { pasted in
            self.onPasteLargeText?(pasted)
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? AutoEnterTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
        textView.placeholderString = placeholder
        textView.onContextTriggerCallback = {
            self.onContextTrigger?()
        }
        textView.onCommandTriggerCallback = {
            self.onCommandTrigger?()
        }
        textView.onPasteLargeTextCallback = { pasted in
            self.onPasteLargeText?(pasted)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputField

        init(_ parent: ChatInputField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if self.parent.text != textView.string {
                self.parent.text = textView.string
            }
        }
    }
}

final class AutoEnterTextView: NSTextView {
    var onSubmitCallback: (() -> Void)?
    var onContextTriggerCallback: (() -> Void)?
    var onCommandTriggerCallback: (() -> Void)?
    var onPasteLargeTextCallback: ((String) -> Void)?
    var placeholderString: String = ""

    override func paste(_ sender: Any?) {
        if let pasteboardString = NSPasteboard.general.string(forType: .string) {
            let lines = pasteboardString.components(separatedBy: .newlines).count
            if pasteboardString.count > 250 || lines > 4 {
                self.insertText("[pasted text]", replacementRange: self.selectedRange())
                self.didChangeText()
                onPasteLargeTextCallback?(pasteboardString)
                return
            }
        }
        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
        // Return key keyCode is 36, keypad enter is 76
        if event.keyCode == 36 || event.keyCode == 76 {
            let shift = event.modifierFlags.contains(.shift)
            let option = event.modifierFlags.contains(.option)
            let command = event.modifierFlags.contains(.command)
            let control = event.modifierFlags.contains(.control)

            if command || (!shift && !option && !control) {
                // Cmd+Enter or Enter without Shift: submit
                onSubmitCallback?()
                return
            } else {
                // Shift+Enter / Option+Enter: newline
                super.insertNewline(nil)
                return
            }
        }

        // Detect '@' (Shift + 2)
        if event.characters == "@" {
            super.keyDown(with: event)
            onContextTriggerCallback?()
            return
        }

        // Detect '/'
        if event.characters == "/" && (string.isEmpty || string.hasSuffix(" ") || string.hasSuffix("\n")) {
            super.keyDown(with: event)
            onCommandTriggerCallback?()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && !placeholderString.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let rect = NSRect(
                x: textContainerInset.width + 5,
                y: textContainerInset.height,
                width: bounds.width - (textContainerInset.width * 2) - 10,
                height: bounds.height
            )
            (placeholderString as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}
