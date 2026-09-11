import SwiftUI
import WebKit

struct AppBuilderBrowserView: View {
    @ObservedObject var simulator = ProductionSimulatorService.shared
    @State private var isPoppedOut = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            if isPoppedOut {
                VStack(spacing: 8) {
                    Text("browser popped out")
                        .font(CockpitFonts.regular(size: 8))
                        .foregroundColor(.gray)
                    
                    Button {
                        isPoppedOut = false
                        AppBuilderWindowController.shared.hideWindow()
                    } label: {
                        Text("restore")
                            .font(CockpitFonts.regular(size: 8))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text(simulator.currentURLString.isEmpty ? "No URL" : simulator.currentURLString)
                            .font(CockpitFonts.code(size: 7))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Spacer()
                        
                        Button {
                            // simple reload mechanism could go here, but for now it's just a UI button
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            isPoppedOut = true
                            AppBuilderWindowController.shared.showWindow()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.8))
                    
                    AppBuilderWebView(url: simulator.currentURLString)
                }
            }
        }
        .onAppear {
            AppBuilderWindowController.shared.onWindowClosed = {
                isPoppedOut = false
            }
        }
    }
}

struct AppBuilderWebView: NSViewRepresentable {
    let url: String
    
    static let processPool = WKProcessPool()
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = Self.processPool
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        if let targetUrl = URL(string: url) {
            webView.load(URLRequest(url: targetUrl))
        }
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        if let targetUrl = URL(string: url) {
            if webView.url?.absoluteString != targetUrl.absoluteString {
                webView.load(URLRequest(url: targetUrl))
            }
        }
    }
    
    static func dismantleNSView(_ webView: WKWebView, coordinator: ()) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }
}
