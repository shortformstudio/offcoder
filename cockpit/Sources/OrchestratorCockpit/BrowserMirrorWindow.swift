import AppKit
import SwiftUI

final class BrowserMirrorWindowManager: NSObject, NSWindowDelegate {
    static let shared = BrowserMirrorWindowManager()

    private var windowController: NSWindowController?

    func showWindow(vm: OrchestratorViewModel) {
        if let wc = windowController, let window = wc.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: BrowserMirrorView(vm: vm))

        // Spawn bottom-right corner of the main screen
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 500
        let height: CGFloat = 380
        let inset: CGFloat = 24
        let frame = NSRect(
            x: screen.maxX - width - inset,
            y: screen.minY + inset,
            width: width,
            height: height
        )

        let window = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isFloatingPanel = true
        window.level = .floating
        window.title = "Browser Mirror"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Drag by the top bar (titlebar) only
        window.isMovableByWindowBackground = false
        window.isMovable = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 320)
        window.contentView = hostingView
        window.delegate = self
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)
    }

    func hideWindow() {
        windowController?.window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

struct BrowserMirrorView: View {
    @ObservedObject var vm: OrchestratorViewModel

    private let providers = ["deepseek", "kimi", "other"]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            mirrorCanvas
            Divider().background(Color.white.opacity(0.08))
            providerStrip
        }
        .background(Color.black.opacity(0.88))
        .background(.ultraThinMaterial)
        .padding(1)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle().stroke(Color.green.opacity(0.5), lineWidth: 2).scaleEffect(1.4)
                )

            Text(vm.webReflection.targetWorker.replacingOccurrences(of: "_WEB", with: "").lowercased())
                .font(CockpitFonts.ultraThin(size: 9))
                .foregroundColor(.white.opacity(0.55))

            Spacer()

            Button(action: {
                vm.webReflection.isActive = false
                BrowserMirrorWindowManager.shared.hideWindow()
            }) {
                Image(systemName: "xmark")
                    .font(CockpitFonts.regular(size: 9))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help("Hide Browser Mirror")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.55))
    }

    private var mirrorCanvas: some View {
        ZStack {
            Color.black
            if let frame = vm.currentScreenFrame {
                Image(nsImage: frame)
                    .interpolation(.medium)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("Awaiting Web Frame...")
                        .font(CockpitFonts.ultraThin(size: 8))
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(Color.black.opacity(0.4))
    }

    private var providerStrip: some View {
        HStack(spacing: 14) {
            ForEach(providers, id: \.self) { provider in
                providerDot(provider)
            }
            Spacer()
            let provider = vm.webReflection.selectedProvider
            if provider.isEmpty == false {
                Button(action: {
                    vm.openLoginTab(provider)
                    vm.setBrowserMirrorVisibility(true)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                            .font(CockpitFonts.regular(size: 8))
                        Text("login")
                            .font(CockpitFonts.ultraThin(size: 9))
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Open the login tab and raise the browser so you can log in")
            }
            Button(action: { vm.setBrowserMirrorVisibility(false) }) {
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash.fill")
                        .font(CockpitFonts.regular(size: 8))
                    Text("hide")
                        .font(CockpitFonts.ultraThin(size: 9))
                }
                .foregroundColor(vm.webReflection.browserVisible ? .white.opacity(0.8) : .white.opacity(0.3))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Park the browser offscreen again")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.45))
    }

    private func providerDot(_ provider: String) -> some View {
        Button(action: { vm.setMirrorProvider(provider) }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .opacity(vm.webReflection.presence[provider] == false ? 0.35 : 1.0)
                    .shadow(
                        color: Color.green.opacity(vm.webReflection.presence[provider] == false ? 0.2 : 0.8),
                        radius: vm.webReflection.presence[provider] == false ? 2 : 5
                    )
                Text(provider)
                    .font(CockpitFonts.ultraThin(size: 10))
                    .foregroundColor(vm.webReflection.selectedProvider == provider ? .white : .white.opacity(0.55))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(vm.webReflection.selectedProvider == provider ? Color.white.opacity(0.10) : Color.clear)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(vm.webReflection.selectedProvider == provider ? Color.green.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Mirror: \(provider)")
    }
}
