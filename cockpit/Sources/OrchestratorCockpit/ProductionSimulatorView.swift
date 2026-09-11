import SwiftUI
import WebKit

struct ProductionSimulatorView: View {
    @ObservedObject var simulator = ProductionSimulatorService.shared
    @ObservedObject var harness = CodebaseHarnessService.shared
    @State private var urlInput: String = ""

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
            Image(systemName: "lock.fill")
                .font(CockpitFonts.regular(size: 8))
                .foregroundColor(.green.opacity(0.8))

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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Browser Viewport
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

            // WebKit View
            WebKitCanvasView(
                urlString: simulator.currentURLString,
                reloadTrigger: $simulator.reloadTrigger,
                customUserAgent: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(6)
    }

    // MARK: - Mobile App Viewport (Dedicated Mobile Runtime)
    private var mobileViewport: some View {
        VStack(spacing: 4) {
            Spacer()
            VStack(spacing: 0) {
                // Mobile Status Bar with Dynamic Island
                ZStack {
                    Color.black
                    HStack {
                        Text("9:41")
                            .font(CockpitFonts.code(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.leading, 14)
                        Spacer()
                        // Dynamic Island pill
                        Capsule()
                            .fill(Color(white: 0.08))
                            .frame(width: 58, height: 13)
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "wifi").font(CockpitFonts.regular(size: 8))
                            Image(systemName: "battery.100").font(CockpitFonts.regular(size: 9))
                        }
                        .foregroundColor(.white)
                        .padding(.trailing, 14)
                    }
                }
                .frame(height: 24)

                // Mobile Canvas: Configured with iPhone Safari User-Agent
                WebKitCanvasView(
                    urlString: simulator.currentURLString,
                    reloadTrigger: $simulator.reloadTrigger,
                    customUserAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Mobile Navigation / Home Indicator Bar
                ZStack {
                    Color.black
                    HStack {
                        Text("393 x 852 pt")
                            .font(CockpitFonts.mono(size: 6))
                            .foregroundColor(.gray.opacity(0.6))
                            .padding(.leading, 10)
                        Spacer()
                        Capsule()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 60, height: 3)
                        Spacer()
                        Button(action: { simulator.reloadSimulator() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(CockpitFonts.regular(size: 8))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                    }
                }
                .frame(height: 16)
            }
            .frame(width: 270, height: 460)
            .background(Color.black)
            .cornerRadius(26)
            .overlay(
                RoundedRectangle(cornerRadius: 26)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: Color.cyan.opacity(0.15), radius: 14, x: 0, y: 6)
            Spacer()
        }
        .padding(4)
    }

    // MARK: - Mini-OS / AppleScript OS Viz (Visual Runtime for Qwythos Loop)
    private var miniOSViewport: some View {
        VStack(spacing: 0) {
            // Window Header Bar
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Color.red.opacity(0.7)).frame(width: 7, height: 7)
                    Circle().fill(Color.yellow.opacity(0.7)).frame(width: 7, height: 7)
                    Circle().fill(Color.green.opacity(0.7)).frame(width: 7, height: 7)
                }

                Image(systemName: "applescript.fill")
                    .font(CockpitFonts.regular(size: 10))
                    .foregroundColor(.cyan)

                Text("\(simulator.osAppTitle)")
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.95))

                Spacer()

                HStack(spacing: 6) {
                    Text("\(Int(simulator.osAppResolution.width))x\(Int(simulator.osAppResolution.height))")
                        .font(CockpitFonts.mono(size: 7))
                        .foregroundColor(.gray)

                    Text("QWYTHOS VISUAL LOOP")
                        .font(CockpitFonts.mono(size: 6, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.75))

            Divider().background(Color.white.opacity(0.08))

            // Main OS Viz Canvas: Renders Real Native Window Visuals
            ZStack {
                Color.black.opacity(0.8)

                if let img = simulator.osVisualImage {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(nsImage: img)
                            .interpolation(.high)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 480, maxHeight: 280)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.8), radius: 16, x: 0, y: 8)

                        HStack(spacing: 8) {
                            Text("Visual captured for Qwythos loop review")
                                .font(CockpitFonts.mono(size: 7))
                                .foregroundColor(.cyan.opacity(0.85))

                            if let dt = simulator.lastOSCaptureDate {
                                Text("• \(dt, style: .time)")
                                    .font(CockpitFonts.code(size: 7))
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                } else {
                    // Standby canvas when no script has run yet
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "applescript.fill")
                            .font(CockpitFonts.regular(size: 32))
                            .foregroundColor(.cyan.opacity(0.7))
                            .shadow(color: Color.cyan.opacity(0.4), radius: 8)

                        Text("AppleScript & Native OS Visuals")
                            .font(CockpitFonts.mono(size: 10, weight: .bold))
                            .foregroundColor(.white)

                        Text("Run AppleScript applications to capture and inspect the real window visuals so Qwythos can make iterative adjustments in his loop.")
                            .font(CockpitFonts.mono(size: 7))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)

                        Button(action: { simulator.runAppleScript() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill").font(CockpitFonts.regular(size: 9))
                                Text("RUN APPLESCRIPT & CAPTURE")
                                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Collapsible AppleScript Code Drawer
            if simulator.showAppleScriptEditor {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(Color.white.opacity(0.1))
                    HStack {
                        Text("APPLESCRIPT SOURCE")
                            .font(CockpitFonts.mono(size: 7, weight: .bold))
                            .foregroundColor(.cyan)
                        Spacer()
                        Button("Run") {
                            simulator.runAppleScript()
                        }
                        .font(CockpitFonts.mono(size: 7, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    TextEditor(text: $simulator.activeAppleScriptCode)
                        .font(CockpitFonts.mono(size: 8))
                        .frame(height: 75)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
                .background(Color.black.opacity(0.85))
            }
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
