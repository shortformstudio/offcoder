import Foundation
import SwiftUI
import WebKit

enum SimulatorMode: String, CaseIterable, Identifiable {
    case browser = "Browser"
    case mobile = "Mobile"
    case miniOS = "OS Viz"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .browser: return "globe"
        case .mobile: return "iphone"
        case .miniOS: return "applescript"
        }
    }
}

struct SystemLogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let source: String // "[QWYTHOS]", "[BUILD]", "[RUN]", "[SERVER]", "[CLI]"
    let level: String // "info", "success", "warn", "error"
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), source: String, level: String = "info", message: String) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.message = message
    }
}

final class ProductionSimulatorService: ObservableObject {
    static let shared = ProductionSimulatorService()

    @Published var simulatorMode: SimulatorMode = .browser
    @Published var currentURLString: String = "http://localhost:3000"
    @Published var isRunning: Bool = false
    @Published var lastExitCode: Int32? = nil
    @Published var reloadTrigger: Bool = false
    @Published var logs: [SystemLogEntry] = [
        SystemLogEntry(source: "[SYSTEM]", level: "info", message: "Production Build & Simulator Engine initialized."),
        SystemLogEntry(source: "[READY]", level: "success", message: "Standby for Qwythos execution or manual build.")
    ]

    // MARK: - Mobile Mode State
    @Published var mobileAppURL: String = "http://localhost:3000"
    @Published var mobileDeviceName: String = "iPhone 15 Pro"
    @Published var mobileCaptureImage: NSImage? = nil

    // MARK: - OS Viz / AppleScript Engine State
    @Published var osVisualImage: NSImage? = nil
    @Published var osAppTitle: String = "AppleScript Interface"
    @Published var osAppResolution: CGSize = CGSize(width: 520, height: 260)
    @Published var lastOSCaptureDate: Date? = nil
    @Published var activeAppleScriptCode: String = """
    display dialog "Offcoder AppleScript Interface" buttons {"Cancel", "Deploy"} default button "Deploy" with title "Qwythos Visual Loop"
    """
    @Published var isExecutingAppleScript: Bool = false
    @Published var showAppleScriptEditor: Bool = false
    @Published var showInspectionOverlay: Bool = false

    private let cliRunner = CLIRunner.shared
    private let harness = CodebaseHarnessService.shared

    func appendLog(source: String, message: String, level: String = "info") {
        DispatchQueue.main.async {
            let entry = SystemLogEntry(source: source, level: level, message: message)
            self.logs.append(entry)
            if self.logs.count > 400 {
                self.logs.removeFirst(self.logs.count - 400)
            }
        }
    }

    func clearLogs() {
        logs.removeAll()
        appendLog(source: "[SYSTEM]", message: "System logs cleared.", level: "info")
    }

    func reloadSimulator() {
        reloadTrigger.toggle()
    }

    /// Automatically detects project stack and runs production build or dev server
    func executeRun(customCommand: String? = nil) {
        guard !isRunning else {
            appendLog(source: "[WARN]", message: "A build or execution process is already active.", level: "warn")
            return
        }

        let projectDir = harness.activeProjectDir ?? harness.qwythosBaseDir
        appendLog(source: "[EXEC]", message: "Initiating execution run in: \(projectDir)", level: "info")

        let commandToRun: String
        if let custom = customCommand, !custom.isEmpty {
            commandToRun = custom
        } else {
            commandToRun = autoDetectRunCommand(in: projectDir)
        }

        appendLog(source: "[BUILD]", message: "$ \(commandToRun)", level: "info")
        isRunning = true

        Task {
            let (stdout, stderr, exitCode) = await cliRunner.execute(command: commandToRun, workingDirectory: projectDir)

            await MainActor.run {
                self.isRunning = false
                self.lastExitCode = exitCode

                if !stdout.isEmpty {
                    for line in stdout.components(separatedBy: .newlines) where !line.isEmpty {
                        self.appendLog(source: "[STDOUT]", message: line, level: "info")
                        self.checkForServerURL(in: line)
                    }
                }

                if !stderr.isEmpty {
                    for line in stderr.components(separatedBy: .newlines) where !line.isEmpty {
                        let isError = line.lowercased().contains("error") || line.lowercased().contains("fail")
                        self.appendLog(source: "[STDERR]", message: line, level: isError ? "error" : "warn")
                        self.checkForServerURL(in: line)
                    }
                }

                if exitCode == 0 {
                    self.appendLog(source: "[DONE]", message: "Process completed successfully (exit code 0).", level: "success")
                } else {
                    self.appendLog(source: "[FAIL]", message: "Process exited with code \(exitCode).", level: "error")
                }

                // Check for static HTML artifact if not on localhost
                self.checkStaticHTMLArtifact(in: projectDir)
                self.reloadSimulator()
            }
        }
    }

    private func autoDetectRunCommand(in dir: String) -> String {
        let fm = FileManager.default
        let pkgJson = (dir as NSString).appendingPathComponent("package.json")
        let pkgSwift = (dir as NSString).appendingPathComponent("Package.swift")
        let mainPy = (dir as NSString).appendingPathComponent("main.py")
        let appPy = (dir as NSString).appendingPathComponent("app.py")
        let indexHtml = (dir as NSString).appendingPathComponent("index.html")

        if fm.fileExists(atPath: pkgJson) {
            return "npm test || npm run build || node index.js"
        } else if fm.fileExists(atPath: pkgSwift) {
            return "swift build"
        } else if fm.fileExists(atPath: mainPy) {
            return "python3 main.py"
        } else if fm.fileExists(atPath: appPy) {
            return "python3 app.py"
        } else if fm.fileExists(atPath: indexHtml) {
            return "echo 'Static HTML build detected: index.html'"
        }
        return "ls -la"
    }

    private func checkForServerURL(in text: String) {
        // Regex look for http://localhost:\d+ or http://127.0.0.1:\d+
        if let match = text.range(of: "http://(localhost|127\\.0\\.0\\.1):[0-9]+", options: .regularExpression) {
            let url = String(text[match])
            self.currentURLString = url
            self.appendLog(source: "[SIMULATOR]", message: "Detected live server at \(url) • Routing simulator viewport.", level: "success")
        }
    }

    private func checkStaticHTMLArtifact(in dir: String) {
        let indexHtml = (dir as NSString).appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: indexHtml) && !currentURLString.hasPrefix("http") {
            currentURLString = "file://\(indexHtml)"
            appendLog(source: "[SIMULATOR]", message: "Loaded local HTML artifact: index.html", level: "success")
        }
    }

    // MARK: - AppleScript & OS Viz Execution Engine
    func runAppleScript(script: String? = nil, file: String? = nil) {
        isExecutingAppleScript = true
        let scriptSource: String
        if let file = file, !file.isEmpty {
            let fullPath = harness.resolvePath(file)
            scriptSource = (try? String(contentsOfFile: fullPath)) ?? activeAppleScriptCode
            appendLog(source: "[APPLESCRIPT]", message: "Running script file: \(file)", level: "info")
        } else {
            scriptSource = script ?? activeAppleScriptCode
            appendLog(source: "[APPLESCRIPT]", message: "Running script: \(scriptSource.prefix(60))...", level: "info")
        }

        Task {
            let tempFile = "/tmp/offcoder_run.applescript"
            try? scriptSource.write(toFile: tempFile, atomically: true, encoding: .utf8)

            let (stdout, stderr, exitCode) = await cliRunner.execute(command: "osascript \(tempFile)")

            await MainActor.run {
                self.isExecutingAppleScript = false
                if exitCode == 0 {
                    let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.appendLog(source: "[APPLESCRIPT]", message: "Output: \(out.isEmpty ? "OK" : out)", level: "success")
                } else {
                    self.appendLog(source: "[APPLESCRIPT]", message: "Error (\(exitCode)): \(stderr)", level: "error")
                }
                self.captureOSVisuals(title: "AppleScript UI", stdoutText: stdout)
            }
        }
    }

    func captureOSVisuals(title: String = "AppleScript Interface", stdoutText: String? = nil) {
        autoreleasepool {
            var image: NSImage? = nil

            // Attempt on-screen capture via CGWindowListCreateImage
            if let cgImage = CGWindowListCreateImage(.null, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
            }

            // High-fidelity native dialog visual snapshot if no external window
            if image == nil || (image?.size.width ?? 0) < 50 {
                image = renderNativeDialogSnapshot(title: title, message: stdoutText ?? "AppleScript application active on macOS.")
            }

            if let img = image {
                self.osVisualImage = img
                self.osAppTitle = title
                self.osAppResolution = img.size
                self.lastOSCaptureDate = Date()

                // Save visual frame to disk for Qwythos visual inspection loop
                if let tiff = img.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "/tmp/offcoder_os_viz.png"))
                    if let prj = harness.activeProjectDir {
                        let dir = (prj as NSString).appendingPathComponent(".agents/visuals")
                        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                        try? png.write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent("latest_app_frame.png")))
                    }
                }
                appendLog(source: "[OS VIZ]", message: "Visual frame captured (\(Int(img.size.width))x\(Int(img.size.height))) for Qwythos review loop.", level: "success")
            }
        }
    }

    private func renderNativeDialogSnapshot(title: String, message: String) -> NSImage {
        let size = NSSize(width: 520, height: 260)
        let image = NSImage(size: size)
        image.lockFocus()

        // Background window fill
        let bgRect = NSRect(origin: .zero, size: size)
        NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0).setFill()
        let path = NSBezierPath(roundedRect: bgRect, xRadius: 10, yRadius: 10)
        path.fill()

        // Window border
        NSColor(white: 1.0, alpha: 0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Title bar
        let titleBarRect = NSRect(x: 0, y: size.height - 32, width: size.width, height: 32)
        NSColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0).setFill()
        let titlePath = NSBezierPath(roundedRect: titleBarRect, xRadius: 10, yRadius: 10)
        titlePath.fill()

        // Traffic light dots
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: size.height - 20, width: 10, height: 10)).fill()
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: NSRect(x: 30, y: size.height - 20, width: 10, height: 10)).fill()
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: NSRect(x: 46, y: size.height - 20, width: 10, height: 10)).fill()

        // Title text
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        (title as NSString).draw(at: NSPoint(x: 70, y: size.height - 22), withAttributes: titleAttrs)

        // Body icon (AppleScript icon / terminal)
        if let icon = NSImage(systemSymbolName: "applescript.fill", accessibilityDescription: nil) ?? NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil) {
            icon.draw(in: NSRect(x: 28, y: size.height - 120, width: 48, height: 48))
        }

        // Body text
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(white: 0.9, alpha: 1.0)
        ]
        let displayMessage = message.isEmpty ? "Native AppleScript process running on macOS." : message
        (displayMessage as NSString).draw(in: NSRect(x: 95, y: size.height - 130, width: 390, height: 80), withAttributes: bodyAttrs)

        // Buttons
        let btnRect1 = NSRect(x: size.width - 120, y: 18, width: 96, height: 28)
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: btnRect1, xRadius: 6, yRadius: 6).fill()
        let btnAttrs1: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        ("OK" as NSString).draw(at: NSPoint(x: size.width - 80, y: 24), withAttributes: btnAttrs1)

        let btnRect2 = NSRect(x: size.width - 230, y: 18, width: 96, height: 28)
        NSColor(white: 0.25, alpha: 1.0).setFill()
        NSBezierPath(roundedRect: btnRect2, xRadius: 6, yRadius: 6).fill()
        let btnAttrs2: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(white: 0.85, alpha: 1.0)
        ]
        ("Cancel" as NSString).draw(at: NSPoint(x: size.width - 200, y: 24), withAttributes: btnAttrs2)

        image.unlockFocus()
        return image
    }

    // MARK: - Mobile Simulator Capture
    func captureMobileScreen() {
        appendLog(source: "[MOBILE]", message: "Capturing mobile app viewport snapshot...", level: "info")
        // Trigger capture and save
        NotificationCenter.default.post(name: NSNotification.Name("CaptureMobileViewport"), object: nil)
    }
}
