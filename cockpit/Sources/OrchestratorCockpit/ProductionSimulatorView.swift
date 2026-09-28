import SwiftUI
import WebKit

struct ProductionSimulatorView: View {
    @ObservedObject var simulator = ProductionSimulatorService.shared
    @ObservedObject var harness = CodebaseHarnessService.shared
    @State private var urlInput: String = ""
    @State private var isInspectorEnabled: Bool = false
    var onGroundingCaptured: ((VisualGroundingPayload) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Simulator Control Bar
            simulatorTopBar

            Divider().background(Color.white.opacity(0.08))

            // Main Simulator Canvas
            ZStack {
                Color.black.opacity(0.7)

                browserViewport
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(CockpitPalette.background)
        .onAppear {
            urlInput = simulator.currentURLString
        }
    }

    // MARK: - Top Control Bar
    private var simulatorTopBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(CockpitFonts.regular(size: 8))
                .foregroundColor(.cyan.opacity(0.8))

            TextField("http://localhost:3000", text: $urlInput, onCommit: {
                simulator.currentURLString = urlInput
                simulator.reloadSimulator()
            })
            .textFieldStyle(.plain)
            .font(CockpitFonts.code(size: 8))
            .foregroundColor(.white.opacity(0.9))

            Button(action: {
                simulator.currentURLString = urlInput
                simulator.reloadSimulator()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(CockpitFonts.regular(size: 9))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help("Reload Browser Viewport")

            Spacer()

            // Multimodal Screencast Inspector Toggle
            Button(action: { isInspectorEnabled.toggle() }) {
                HStack(spacing: 3) {
                    Image(systemName: "viewfinder")
                        .font(CockpitFonts.regular(size: 8))
                    Text(isInspectorEnabled ? "INSPECTING" : "INSPECT")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                }
                .foregroundColor(isInspectorEnabled ? .cyan : .white.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isInspectorEnabled ? Color.cyan.opacity(0.18) : Color.white.opacity(0.05))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(isInspectorEnabled ? Color.cyan.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Toggle Interactive Region Selection & DOM Grounding")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Browser Viewport (Multipurpose Visualizer)
    private var browserViewport: some View {
        VStack(spacing: 0) {
            // Browser window chrome
            HStack(spacing: 6) {
                Circle().fill(Color.red.opacity(0.7)).frame(width: 7, height: 7)
                Circle().fill(Color.yellow.opacity(0.7)).frame(width: 7, height: 7)
                Circle().fill(Color.green.opacity(0.7)).frame(width: 7, height: 7)

                Spacer()

                Text(simulator.currentURLString)
                    .font(CockpitFonts.code(size: 7))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.55))

            Divider().background(Color.white.opacity(0.06))

            // WebKit View with Multimodal Screencast Inspector Overlay
            ZStack {
                WebKitCanvasView(
                    urlString: simulator.currentURLString,
                    reloadTrigger: $simulator.reloadTrigger,
                    customUserAgent: nil
                )

                MultimodalScreencastOverlay(
                    isInspectorEnabled: $isInspectorEnabled,
                    onGroundingPayloadCaptured: { payload in
                        onGroundingCaptured?(payload)
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(6)
    }
}

// MARK: - WebKit Canvas View
struct WebKitCanvasView: NSViewRepresentable {
    let urlString: String
    @Binding var reloadTrigger: Bool
    var customUserAgent: String? = nil

    // Single shared process pool across all WebViews to prevent spawning duplicate WebKit XPC processes
    private static let sharedProcessPool = WKProcessPool()

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = WebKitCanvasView.sharedProcessPool
        // Non-persistent data store: saves hundreds of MBs of disk/memory cache for preview targets
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        if customUserAgent != nil {
            config.applicationNameForUserAgent = "Mobile/15E148"
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        if let ua = customUserAgent {
            webView.customUserAgent = ua
        }
        loadPage(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if reloadTrigger {
            DispatchQueue.main.async {
                self.reloadTrigger = false
            }
            loadPage(in: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: ()) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    private func loadPage(in webView: WKWebView) {
        if let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" {
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            webView.load(req)
        } else if urlString.hasPrefix("file://"), let fileURL = URL(string: urlString) {
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            // Fallback placeholder page
            let placeholderHTML = """
            <html>
            <head>
                <style>
                    body {
                        margin: 0;
                        padding: 24px;
                        background: #0a0c10;
                        color: #e2e8f0;
                        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace;
                        display: flex;
                        flex-direction: column;
                        align-items: center;
                        justify-content: center;
                        height: 80vh;
                        text-align: center;
                    }
                    .box {
                        border: 1px solid rgba(255,255,255,0.1);
                        border-radius: 10px;
                        padding: 24px;
                        background: rgba(255,255,255,0.02);
                        max-width: 320px;
                    }
                    h3 { margin: 0 0 8px; font-size: 13px; color: #38bdf8; }
                    p { margin: 0 0 16px; font-size: 10px; color: #94a3b8; line-height: 1.4; }
                    .tag { display: inline-block; padding: 3px 8px; border-radius: 4px; background: rgba(56,189,248,0.15); color: #38bdf8; font-size: 9px; font-weight: bold; }
                </style>
            </head>
            <body>
                <div class="box">
                    <div class="tag">SIMULATOR STANDBY</div>
                    <h3 style="margin-top: 10px;">Production Build Target</h3>
                    <p>Click <b>RUN</b> or ask Qwythos to start your dev server or build files. WebKit viewport automatically hot-reloads.</p>
                </div>
            </body>
            </html>
            """
            webView.loadHTMLString(placeholderHTML, baseURL: nil)
        }
    }
}
