import SwiftUI
import AppKit

struct CodeBlockView: View {
    let language: String
    let filename: String?
    let code: String
    var onInlineAction: ((String) -> Void)? = nil

    @ObservedObject var versionManager = CodeVersionManager.shared
    @ObservedObject var harness = CodebaseHarnessService.shared

    @State private var isCopied: Bool = false
    @State private var isRunning: Bool = false
    @State private var executionOutput: String? = nil
    @State private var executionExitCode: Int32? = nil
    @State private var isExecutionTrayOpen: Bool = false
    @State private var showPreviewSheet: Bool = false
    @State private var showDiffSheet: Bool = false
    @State private var showArenaSheet: Bool = false
    @State private var showGhostSheet: Bool = false
    @State private var stagingNotice: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            HStack(spacing: 8) {
                // Language Badge
                HStack(spacing: 5) {
                    Image(systemName: iconForLanguage(language))
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(colorForLanguage(language))

                    Text(detectedLanguageDisplayName.uppercased())
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(colorForLanguage(language))

                    if let fn = filename, !fn.isEmpty {
                        Text("•")
                            .font(CockpitFonts.mono(size: 9))
                            .foregroundColor(.gray)
                        Text(fn)
                            .font(CockpitFonts.mono(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }

                Spacer()

                // Actions Bar
                HStack(spacing: 5) {
                    // Preview Button (HTML/JS/CSS)
                    if isPreviewable {
                        Button(action: { showPreviewSheet = true }) {
                            HStack(spacing: 3) {
                                Image(systemName: "safari")
                                    .font(CockpitFonts.regular(size: 8))
                                Text("Preview")
                                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.cyan.opacity(0.12))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Render HTML/JS/CSS in live web view")
                    }

                    // Run / Execute Action
                    Button(action: executeCode) {
                        HStack(spacing: 3) {
                            if isRunning {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(CockpitFonts.regular(size: 8))
                            }
                            Text(isRunning ? "Running" : "Run")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                    .help("Execute snippet in local environment")

                    // Apply / Stage Action
                    Button(action: applyCode) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.merge")
                                .font(CockpitFonts.regular(size: 8))
                            Text("Apply")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Stage code candidate into version manager")

                    // DeepSeek Handoff Action
                    Button(action: {
                        onInlineAction?("/deepseek Refactor and optimize the following implementation:\n```\(language)\n\(code)\n```")
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(CockpitFonts.regular(size: 8))
                            Text("DeepSeek")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Hand off snippet to DeepSeek with automated local model review")

                    // Ghost Diff Action
                    Button(action: {
                        SpeculativeDiffGhostManager.shared.pushSpeculativeCandidate(
                            code: code,
                            summary: filename != nil ? "Block from \(filename!)" : "Proposed code block"
                        )
                        showGhostSheet = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(CockpitFonts.regular(size: 8))
                            Text("Ghost")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Inspect speculative ghost diff with instant scrubbing (Cmd+[ / Cmd+])")

                    // Arena Action
                    Button(action: {
                        Task {
                            await ConsensusEngineService.shared.runConsensus(
                                prompt: "Analyze, optimize, and review implementation patterns for code block",
                                baseCode: code
                            )
                        }
                        showArenaSheet = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "square.split.3x1.fill")
                                .font(CockpitFonts.regular(size: 8))
                            Text("Arena")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Multi-Model Consensus Arena & synthesis diff")

                    // Download / Save File Action
                    Button(action: saveCodeToFile) {
                        Image(systemName: "arrow.down.doc")
                            .font(CockpitFonts.regular(size: 9))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(4)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Save code block to file")

                    // Copy Action
                    Button(action: copyToClipboard) {
                        HStack(spacing: 3) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(CockpitFonts.regular(size: 8))
                            Text(isCopied ? "Copied" : "Copy")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                        }
                        .foregroundColor(isCopied ? .green : .white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isCopied ? Color.green.opacity(0.15) : Color.white.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Copy code to clipboard")

                    // Inline Action Menu
                    Menu {
                        Button("Hand off to DeepSeek & Review") {
                            onInlineAction?("/deepseek Please audit and improve the following implementation:\n```\(language)\n\(code)\n```")
                        }
                        Button("Explain this code") {
                            onInlineAction?("Please explain how this code works in detail:\n```\(language)\n\(code)\n```")
                        }
                        Button("Fix potential bugs") {
                            onInlineAction?("Please analyze this code for bugs, edge cases, and security flaws, then provide the corrected version:\n```\(language)\n\(code)\n```")
                        }
                        Button("Generate unit tests") {
                            onInlineAction?("Please generate comprehensive unit tests covering all edge cases for this code:\n```\(language)\n\(code)\n```")
                        }
                        Button("Suggest refactor") {
                            onInlineAction?("Please propose a cleaner, more performant, and idiomatic refactor of this code:\n```\(language)\n\(code)\n```")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(CockpitFonts.regular(size: 9))
                            .foregroundColor(.gray)
                            .padding(4)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Code actions")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.55))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.08)), alignment: .bottom)

            // Code Content
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(CockpitFonts.code(size: 11))
                    .foregroundColor(Color(red: 0.92, green: 0.94, blue: 0.97))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.05, green: 0.06, blue: 0.08))

            // Notice Banner (e.g. Staging status)
            if let notice = stagingNotice {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(CockpitFonts.regular(size: 8))
                        .foregroundColor(.green)
                    Text(notice)
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.green.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.08))
            }

            // Terminal Execution Tray
            if isExecutionTrayOpen, let out = executionOutput {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(executionExitCode == 0 ? Color.green : Color.red).frame(width: 5, height: 5)
                        Text("TERMINAL OUTPUT (EXIT \(executionExitCode ?? 0))")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Button(action: { isExecutionTrayOpen = false }) {
                            Image(systemName: "xmark")
                                .font(CockpitFonts.regular(size: 7))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(out.isEmpty ? "[Process exited with no output]" : out)
                            .font(CockpitFonts.mono(size: 9))
                            .foregroundColor(executionExitCode == 0 ? .green.opacity(0.9) : .red.opacity(0.9))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(maxHeight: 120)
                }
                .background(Color.black.opacity(0.85))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.cyan.opacity(0.3)), alignment: .top)
            }
        }
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .sheet(isPresented: $showPreviewSheet) {
            CodePreviewSheet(code: code, language: language)
        }
        .sheet(isPresented: $showArenaSheet) {
            ConsensusArenaView()
        }
        .sheet(isPresented: $showGhostSheet) {
            GhostDiffOverlayView()
        }
    }

    private var detectedLanguageDisplayName: String {
        switch language.lowercased() {
        case "py", "python": return "Python"
        case "swift": return "Swift"
        case "ts", "typescript": return "TypeScript"
        case "js", "javascript": return "JavaScript"
        case "rs", "rust": return "Rust"
        case "go", "golang": return "Go"
        case "html": return "HTML"
        case "css": return "CSS"
        case "json": return "JSON"
        case "sh", "bash", "zsh": return "Shell"
        case "sql": return "SQL"
        case "md", "markdown": return "Markdown"
        default: return language.isEmpty ? "Code" : language.capitalized
        }
    }

    private var isPreviewable: Bool {
        let l = language.lowercased()
        return l == "html" || l == "javascript" || l == "js" || l == "css" || code.contains("<html")
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isCopied = false
        }
    }

    private func saveCodeToFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let ext = defaultExtensionForLanguage(language)
        panel.nameFieldStringValue = filename ?? "snippet.\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            try? code.write(to: url, atomically: true, encoding: .utf8)
            harness.recordDeliverable(relativePath: url.lastPathComponent, status: "saved", content: code)
            withAnimation {
                stagingNotice = "Saved to \(url.lastPathComponent)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                stagingNotice = nil
            }
        }
    }

    private func executeCode() {
        guard !isRunning else { return }
        isRunning = true
        isExecutionTrayOpen = true
        executionOutput = "Running..."

        let lang = language.lowercased()
        let projectDir = harness.activeProjectDir

        Task {
            let cmd: String
            switch lang {
            case "py", "python":
                cmd = "python3 -c " + escapeShellArg(code)
            case "js", "javascript":
                cmd = "node -e " + escapeShellArg(code)
            case "sh", "bash", "zsh":
                cmd = code
            case "swift":
                cmd = "swift -e " + escapeShellArg(code)
            default:
                cmd = "echo " + escapeShellArg("Cannot execute \(lang) directly as a single-line script")
            }

            let result = await CLIRunner.shared.execute(command: cmd, workingDirectory: projectDir)
            await MainActor.run {
                self.isRunning = false
                self.executionExitCode = result.exitCode
                let combined = result.stdout + (result.stderr.isEmpty ? "" : "\n[stderr]\n" + result.stderr)
                self.executionOutput = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func applyCode() {
        let targetFile = filename ?? "snippet.\(defaultExtensionForLanguage(language))"
        let fullPath = harness.resolvePath(targetFile)

        // Commit revision through version manager
        let _ = versionManager.commitRevision(
            filePath: targetFile,
            code: code,
            origin: .localModel,
            summary: "Applied from Chat Code Block"
        )
        harness.recordDeliverable(relativePath: targetFile, status: "staged", content: code)

        withAnimation {
            stagingNotice = "Staged revision for \(targetFile)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            stagingNotice = nil
        }
    }

    private func escapeShellArg(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func iconForLanguage(_ lang: String) -> String {
        switch lang.lowercased() {
        case "py", "python": return "curlybraces"
        case "swift": return "swift"
        case "ts", "typescript", "js", "javascript": return "doc.plaintext"
        case "rs", "rust": return "gearshape.2"
        case "html", "css": return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh": return "terminal"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func colorForLanguage(_ lang: String) -> Color {
        switch lang.lowercased() {
        case "py", "python": return .yellow
        case "swift": return .orange
        case "ts", "typescript": return .blue
        case "js", "javascript": return .yellow
        case "rs", "rust": return .red
        case "html": return .orange
        case "css": return .blue
        case "sh", "bash", "zsh": return .mint
        default: return .cyan
        }
    }

    private func defaultExtensionForLanguage(_ lang: String) -> String {
        switch lang.lowercased() {
        case "python", "py": return "py"
        case "swift": return "swift"
        case "typescript", "ts": return "ts"
        case "javascript", "js": return "js"
        case "rust", "rs": return "rs"
        case "html": return "html"
        case "css": return "css"
        case "json": return "json"
        case "sh", "bash", "zsh": return "sh"
        default: return "txt"
        }
    }
}
