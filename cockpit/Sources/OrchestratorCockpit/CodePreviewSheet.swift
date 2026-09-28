import SwiftUI
import WebKit

struct CodePreviewSheet: View {
    let code: String
    let language: String
    @Environment(\.dismiss) private var dismiss

    @State private var viewportWidth: CGFloat = 800
    @State private var deviceMode: DeviceMode = .desktop

    enum DeviceMode: String, CaseIterable {
        case desktop = "Desktop"
        case tablet = "Tablet"
        case mobile = "Mobile"

        var width: CGFloat {
            switch self {
            case .desktop: return 840
            case .tablet: return 600
            case .mobile: return 375
            }
        }

        var icon: String {
            switch self {
            case .desktop: return "display"
            case .tablet: return "ipad"
            case .mobile: return "iphone"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("LIVE WEB PREVIEW")
                        .font(CockpitFonts.mono(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                // Device Viewport Toggles
                HStack(spacing: 4) {
                    ForEach(DeviceMode.allCases, id: \.self) { mode in
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                deviceMode = mode
                                viewportWidth = mode.width
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                    .font(CockpitFonts.regular(size: 9))
                                Text(mode.rawValue)
                                    .font(CockpitFonts.mono(size: 9, weight: .medium))
                            }
                            .foregroundColor(deviceMode == mode ? .black : .white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(deviceMode == mode ? Color.cyan : Color.white.opacity(0.06))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().frame(height: 16).background(Color.white.opacity(0.15))

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(CockpitFonts.regular(size: 14))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.6))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.08)), alignment: .bottom)

            // WebView Frame with centered responsive width
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()

                WebViewRepresentable(htmlContent: preparedHTML)
                    .frame(width: viewportWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                    .padding(16)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(Color.black.opacity(0.85))
    }

    private var preparedHTML: String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if language.lowercased() == "html" || trimmed.lowercased().contains("<html") || trimmed.lowercased().contains("<!doctype") {
            return trimmed
        }
        // Wrap raw fragment or JS/CSS
        if language.lowercased() == "javascript" || language.lowercased() == "js" {
            return """
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="utf-8">
              <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #121316; color: #f0f0f0; padding: 20px; }
                #log { font-family: ui-monospace, Menlo, monospace; font-size: 12px; background: #000; padding: 12px; border-radius: 6px; white-space: pre-wrap; }
              </style>
            </head>
            <body>
              <h3>JavaScript Execution Console</h3>
              <div id="log"></div>
              <script>
                const logEl = document.getElementById('log');
                const origLog = console.log;
                console.log = function(...args) {
                  logEl.textContent += args.join(' ') + '\\n';
                  origLog.apply(console, args);
                };
                try {
                  \(trimmed)
                } catch(e) {
                  logEl.textContent += 'Error: ' + e.message + '\\n';
                }
              </script>
            </body>
            </html>
            """
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0e0f12; color: #ffffff; padding: 20px; }
          </style>
        </head>
        <body>
          \(trimmed)
        </body>
        </html>
        """
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let htmlContent: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(htmlContent, baseURL: nil)
    }
}
