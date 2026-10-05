import SwiftUI
import AppKit

extension Notification.Name {
    static let offcoderMinimizeToMini = Notification.Name("offcoder.minimizeToMini")
    static let offcoderRestoreFromMini = Notification.Name("offcoder.restoreFromMini")
}

/// Interactive screen-region capture (`screencapture -s`).
/// The user drags a selection; the PNG lands in `~/.offcoder/screenshots/`
/// and is handed back for staging into the current conversation.
enum ScreenshotCaptureService {
    static func captureSelection(completion: @escaping (URL?) -> Void) {
        let dir = NSString(string: "~/.offcoder/screenshots").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let path = (dir as NSString).appendingPathComponent("offcoder-screenshot-\(stamp).png")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-s", "-t", "png", path]
        proc.terminationHandler = { _ in
            let ok = FileManager.default.fileExists(atPath: path)
            DispatchQueue.main.async {
                completion(ok ? URL(fileURLWithPath: path) : nil)
            }
        }
        do {
            try proc.run()
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
    }
}

/// Floating supervisor widget pinned to the top-left of the screen.
/// Shown when the deck minimizes; hidden again when the deck restores.
final class MiniWidgetWindowController {
    static let shared = MiniWidgetWindowController()

    private var panel: NSPanel?
    private var boundVM: OrchestratorViewModel?
    private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .offcoderMinimizeToMini, object: nil, queue: .main
            ) { [weak self] note in
                guard let vm = note.object as? OrchestratorViewModel else { return }
                self?.show(vm: vm)
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .offcoderRestoreFromMini, object: nil, queue: .main
            ) { [weak self] _ in
                self?.hide(restoreMain: true)
            }
        )
    }

    func show(vm: OrchestratorViewModel) {
        if panel == nil || boundVM !== vm {
            boundVM = vm
            let content = NSHostingView(rootView: MiniWidgetView(vm: vm))
            content.frame = NSRect(x: 0, y: 0, width: 300, height: 264)
            let fresh = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 264),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            fresh.contentView = content
            fresh.level = .floating
            fresh.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            fresh.isMovableByWindowBackground = true
            fresh.titlebarAppearsTransparent = true
            fresh.title = ""
            fresh.backgroundColor = .clear
            fresh.isOpaque = false
            panel = fresh
        }
        positionTopLeft()
        WindowDragGate.applyDeckPolicy()
        for window in NSApp.windows where window != panel {
            if window.isVisible && !(window is NSPanel) && window.contentView != nil {
                window.miniaturize(nil)
            }
        }
        panel?.orderFrontRegardless()
    }

    func hide(restoreMain: Bool) {
        panel?.orderOut(nil)
        if restoreMain {
            for window in NSApp.windows where window != panel {
                if window.isMiniaturized && !(window is NSPanel) {
                    window.deminiaturize(nil)
                }
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func positionTopLeft() {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.minX + 16, y: visible.maxY - size.height - 36))
    }
}

struct MiniWidgetView: View {
    @ObservedObject var vm: OrchestratorViewModel
    @ObservedObject private var voice = VoiceTranscriptionService.shared

    @State private var isCapturingScreenshot = false
    @State private var screenshotNotice: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            Divider().background(Color.white.opacity(0.08))
            missionBlock
            processBlock
            controlsRow
            if let notice = screenshotNotice {
                Text(notice)
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(Color.black.opacity(0.88))
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.modelStatus == .connected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text("offcoder mini")
                .font(CockpitFonts.mono(size: 9, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button(action: { vm.restoreFromMiniWidget() }) {
                Image(systemName: "arrow.down.left")
                    .font(CockpitFonts.regular(size: 10))
                    .foregroundColor(.cyan)
                    .frame(width: 24, height: 24)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Reopen Offcoder")
        }
    }

    private var missionBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("mission")
                .font(CockpitFonts.mono(size: 7, weight: .bold))
                .foregroundColor(.gray)
            HStack(spacing: 5) {
                Circle()
                    .fill(vm.marquee?.level.color ?? Color.gray.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(vm.marquee?.text ?? "no active mission")
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            }
            Text("\(vm.chatMessages.count) turns · \(vm.attachedItems.count) staged")
                .font(CockpitFonts.mono(size: 7))
                .foregroundColor(.gray)
        }
    }

    private var processBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("process")
                .font(CockpitFonts.mono(size: 7, weight: .bold))
                .foregroundColor(.gray)
            HStack(spacing: 5) {
                if vm.isGenerating {
                    ProgressView().controlSize(.mini)
                }
                Text("\(vm.currentProcessState) — \(vm.currentProcessDetail)")
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(vm.isGenerating ? .cyan : .white.opacity(0.75))
                    .lineLimit(2)
            }
            if voice.isRecording {
                Text("voice note recording… tap mic to stop")
                    .font(CockpitFonts.mono(size: 7, weight: .bold))
                    .foregroundColor(.red)
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button(action: toggleVoiceNote) {
                ZStack {
                    if voice.isRecording {
                        Circle()
                            .fill(Color.red.opacity(0.25))
                            .frame(width: 26, height: 26)
                            .scaleEffect(1.0 + CGFloat(voice.audioLevel) * 0.7)
                    }
                    Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                        .font(CockpitFonts.regular(size: 11))
                        .foregroundColor(voice.isRecording ? .red : .white.opacity(0.8))
                }
                .frame(width: 30, height: 30)
                .background(voice.isRecording ? Color.red.opacity(0.15) : Color.white.opacity(0.05))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(voice.isRecording ? Color.red.opacity(0.6) : Color.white.opacity(0.10), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(voice.isRecording ? "Stop voice note (transcript stays in the deck input)" : "Record voice note into the current conversation")

            Button(action: captureScreenshot) {
                HStack(spacing: 4) {
                    if isCapturingScreenshot {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "camera.viewfinder")
                            .font(CockpitFonts.regular(size: 11))
                    }
                    Text("select")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(height: 30)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isCapturingScreenshot)
            .help("Capture a screen selection into the current conversation, ready to send")

            Spacer()

            if !vm.attachedItems.isEmpty {
                Text("\(vm.attachedItems.count) ready")
                    .font(CockpitFonts.mono(size: 7, weight: .bold))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(4)
            }
        }
    }

    private func toggleVoiceNote() {
        voice.toggleRecording(
            onTextChange: { transcribed in self.vm.chatInputText = transcribed },
            currentText: self.vm.chatInputText
        )
    }

    private func captureScreenshot() {
        guard !isCapturingScreenshot else { return }
        isCapturingScreenshot = true
        screenshotNotice = "drag a selection on screen…"
        ScreenshotCaptureService.captureSelection { url in
            isCapturingScreenshot = false
            if let url {
                vm.attachScreenshot(url: url)
                screenshotNotice = "\(url.lastPathComponent) staged — add text in the deck, press enter to send"
            } else {
                screenshotNotice = "capture cancelled — nothing staged"
            }
        }
    }
}
