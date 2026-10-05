import SwiftUI
import WebKit
import AppKit

struct VisualGroundingPayload {
    let selector: String
    let tagName: String
    let innerText: String
    let bounds: CGRect
    let styles: [String: String]
    let snapshotBase64: String?
}

struct MultimodalScreencastOverlay: View {
    @Binding var isInspectorEnabled: Bool
    var onGroundingPayloadCaptured: ((VisualGroundingPayload) -> Void)? = nil

    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var capturedPayload: VisualGroundingPayload? = nil
    @State private var isAnalyzing: Bool = false

    var body: some View {
        ZStack {
            if isInspectorEnabled {
                // Interactive Drag Overlay
                Color.black.opacity(0.01)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                if dragStart == nil {
                                    dragStart = value.startLocation
                                    WindowDragGate.suspend()
                                }
                                dragCurrent = value.location
                            }
                            .onEnded { value in
                                WindowDragGate.resume()
                                let start = value.startLocation
                                let end = value.location
                                let rect = CGRect(
                                    x: min(start.x, end.x),
                                    y: min(start.y, end.y),
                                    width: abs(end.x - start.x),
                                    height: abs(end.y - start.y)
                                )
                                dragStart = nil
                                dragCurrent = nil
                                if rect.width > 10 && rect.height > 10 {
                                    performVisualGrounding(rect: rect)
                                }
                            }
                    )

                // Render live drag box
                if let start = dragStart, let current = dragCurrent {
                    let rect = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    )
                    selectionBoundingBox(rect)
                }

                // Render Grounded Payload Callout
                if let payload = capturedPayload {
                    groundedCalloutCard(payload)
                }

                // Active Inspector Mode Banner
                VStack {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "viewfinder")
                                .font(CockpitFonts.bold(size: 9))
                                .foregroundColor(.cyan)
                            Text("MULTIMODAL INSPECTOR ACTIVE — DRAG RECT OVER UI")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                                .foregroundColor(.cyan)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cyan.opacity(0.5), lineWidth: 1))

                        Spacer()

                        Button(action: {
                            isInspectorEnabled = false
                            capturedPayload = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(CockpitFonts.regular(size: 13))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    Spacer()
                }
            }
        }
    }

    private func selectionBoundingBox(_ rect: CGRect) -> some View {
        ZStack {
            Rectangle()
                .path(in: rect)
                .fill(Color.cyan.opacity(0.15))

            Rectangle()
                .path(in: rect)
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

            // Dimension badge
            VStack {
                Text("\(Int(rect.width)) × \(Int(rect.height))")
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.cyan)
                    .cornerRadius(3)
            }
            .position(x: rect.midX, y: max(15, rect.minY - 12))
        }
    }

    private func groundedCalloutCard(_ payload: VisualGroundingPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("GROUNDED DOM ELEMENT")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(.green)
                }
                Spacer()
                Button(action: { capturedPayload = nil }) {
                    Image(systemName: "xmark").font(.system(size: 8)).foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Text(payload.selector)
                .font(CockpitFonts.code(size: 9))
                .foregroundColor(.cyan)
                .lineLimit(2)

            if !payload.innerText.isEmpty {
                Text("\"\(payload.innerText)\"")
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Button(action: {
                    onGroundingPayloadCaptured?(payload)
                    capturedPayload = nil
                    isInspectorEnabled = false
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "paperplane.fill")
                            .font(CockpitFonts.regular(size: 8))
                        Text("Send to Prompt")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(10)
        .frame(width: 280)
        .background(Color.black.opacity(0.88))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
        .position(x: min(max(150, payload.bounds.midX), 260), y: min(max(100, payload.bounds.midY), 240))
    }

    private func performVisualGrounding(rect: CGRect) {
        let midX = rect.midX
        let midY = rect.midY

        // Script to inspect DOM element directly under the center of the drag rect
        let script = """
        (function() {
            var el = document.elementFromPoint(\(midX), \(midY));
            if (!el) return JSON.stringify({ selector: 'body', tag: 'BODY', text: '', styles: {} });
            var path = [];
            var cur = el;
            while (cur && cur.nodeType === 1 && cur.tagName !== 'HTML') {
                var sel = cur.tagName.toLowerCase();
                if (cur.id) {
                    sel += '#' + cur.id;
                    path.unshift(sel);
                    break;
                }
                if (cur.className && typeof cur.className === 'string') {
                    var cls = cur.className.trim().split(/\\s+/).slice(0, 2).join('.');
                    if (cls) sel += '.' + cls;
                }
                path.unshift(sel);
                cur = cur.parentElement;
            }
            var text = (el.innerText || el.textContent || '').trim().substring(0, 80);
            return JSON.stringify({
                selector: path.join(' > '),
                tag: el.tagName,
                text: text,
                styles: {
                    display: window.getComputedStyle(el).display
                }
            });
        })();
        """

        let bridge = BrowserEvalBridge.shared
        bridge.evaluateJS(script) { result in
            DispatchQueue.main.async {
                var selector = "element @ [\(Int(rect.origin.x)), \(Int(rect.origin.y))]"
                var tag = "DIV"
                var innerText = ""
                var styles: [String: String] = [:]

                if let jsonStr = result as? String,
                   let data = jsonStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    selector = obj["selector"] as? String ?? selector
                    tag = obj["tag"] as? String ?? tag
                    innerText = obj["text"] as? String ?? innerText
                    styles = obj["styles"] as? [String: String] ?? styles
                }

                let payload = VisualGroundingPayload(
                    selector: selector,
                    tagName: tag,
                    innerText: innerText,
                    bounds: rect,
                    styles: styles,
                    snapshotBase64: nil
                )
                self.capturedPayload = payload
            }
        }
    }
}
