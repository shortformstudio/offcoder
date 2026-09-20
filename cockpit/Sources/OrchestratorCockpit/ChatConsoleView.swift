import SwiftUI
import AppKit

struct ChatConsoleView: View {
    @ObservedObject var vm: OrchestratorViewModel
    @ObservedObject var versionManager = CodeVersionManager.shared
    @ObservedObject var harness = CodebaseHarnessService.shared
    @ObservedObject var voiceService = VoiceTranscriptionService.shared

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                TextField("Conversation", text: $vm.conversationName)
                    .font(CockpitFonts.mono(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 200)
                
                Spacer()
                


                if vm.isCompressing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("COMPRESSING...")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                }

                Button(action: { vm.compressContext() }) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.cyan)
                        .padding(5)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(vm.chatMessages.isEmpty || vm.isGenerating || vm.isCompressing)
                .help("Semantically compress context via Qwythos while archiving literal log")

                Button(action: { vm.clearChat() }) {
                    Image(systemName: "trash")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.gray)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .help("Clear Chat")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))

            Divider().background(Color.white.opacity(0.06))

            // Message Stream with Collapsible Chain of Thought Hyperwindow Overlay
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if vm.chatMessages.isEmpty {
                                emptyStatePlaceholder
                            } else {
                                ForEach(vm.chatMessages) { msg in
                                    messageRow(for: msg)
                                        .id(msg.id)
                                }
                            }
                        }
                        .padding(14)
                        .padding(.top, (vm.isThoughtOverlayVisible && !vm.isThoughtOverlayCollapsed && !vm.activeChainOfThought.isEmpty) ? 55 : 10)
                    }
                    .onChange(of: vm.chatMessages.count) { _ in
                        if let last = vm.chatMessages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Collapsible Chain of Thought Hyperwindow Overlay
                if vm.isThoughtOverlayVisible && (!vm.activeChainOfThought.isEmpty || vm.isReasoning) {
                    GeometryReader { geo in
                        ChainOfThoughtHyperwindow(
                            thoughtText: vm.activeChainOfThought,
                            isReasoning: vm.isReasoning,
                            processStatus: vm.currentProcessDetail,
                            isCollapsed: $vm.isThoughtOverlayCollapsed,
                            maxHeight: geo.size.height * 0.50
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            // Real-time Process HUD Strip
            if vm.isGenerating || vm.currentProcessState != "IDLE" || !vm.activeChainOfThought.isEmpty {
                HStack(spacing: 8) {
                    if vm.isReasoning {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                                    .scaleEffect(1.4)
                            )

                        Text("thinking...")
                            .font(CockpitFonts.mono(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }

                    Spacer()

                    if !vm.activeChainOfThought.isEmpty {
                        Button(action: {
                            withAnimation {
                                vm.isThoughtOverlayVisible.toggle()
                                if vm.isThoughtOverlayVisible { vm.isThoughtOverlayCollapsed = false }
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "brain.head.profile")
                                    .font(CockpitFonts.regular(size: 8))
                                Text(vm.isThoughtOverlayVisible ? "Hide CoT" : "Show CoT")
                                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.12))
                            .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.45))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.cyan.opacity(0.15)), alignment: .top)
            }

            Divider().background(Color.white.opacity(0.06))

            if let voiceError = voiceService.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(CockpitFonts.regular(size: 8))
                        .foregroundColor(.yellow)
                    Text(voiceError)
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.yellow.opacity(0.9))
                    Spacer()
                    Button(action: { voiceService.errorMessage = nil }) {
                        Image(systemName: "xmark")
                            .font(CockpitFonts.regular(size: 8))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.yellow.opacity(0.08))
            }

            // Input bar: File Upload, Voice Transcription, Chat Input, Send
            HStack(alignment: .bottom, spacing: 8) {
                // File Upload
                Button(action: chooseAndAttachFile) {
                    Image(systemName: "paperclip")
                        .font(CockpitFonts.regular(size: 14))
                        .foregroundColor(.cyan.opacity(0.85))
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Upload file into workspace / attach to prompt")

                // Voice to Text Transcription
                Button(action: {
                    voiceService.toggleRecording(
                        onTextChange: { transcribed in
                            self.inputText = transcribed
                        },
                        currentText: self.inputText
                    )
                }) {
                    ZStack {
                        if voiceService.isRecording {
                            Circle()
                                .fill(Color.red.opacity(0.25))
                                .frame(width: 28, height: 28)
                                .scaleEffect(1.0 + CGFloat(voiceService.audioLevel) * 0.7)
                        }
                        Image(systemName: voiceService.isRecording ? "waveform" : "mic.fill")
                            .font(CockpitFonts.regular(size: 13))
                            .foregroundColor(voiceService.isRecording ? .red : .white.opacity(0.75))
                    }
                    .frame(width: 30, height: 30)
                    .background(voiceService.isRecording ? Color.red.opacity(0.15) : Color.white.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(voiceService.isRecording ? Color.red.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(voiceService.isRecording ? "Stop voice transcription" : "Voice to text transcription")

                ChatInputField(
                    text: $inputText,
                    placeholder: voiceService.isRecording ? "Listening... (speak now)" : BuildConfig.chatMessagePlaceholder,
                    onSubmit: submitMessage
                )
                .frame(minHeight: 34, maxHeight: 90)
                .padding(4)
                .background(Color.black.opacity(0.4))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(voiceService.isRecording ? Color.red.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1))
                .onDrop(of: ["public.file-url", "public.utf8-plain-text"], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }

                // Upward Arrow Send Button
                Button(action: submitMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(CockpitFonts.regular(size: 26))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray.opacity(0.5) : .cyan)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isGenerating)
            }
            .padding(10)
            .background(Color.black.opacity(0.25))
        }
        .frostyBento()
    }

    private var emptyStatePlaceholder: some View {
        VStack(spacing: 18) {
            Text("let's code")
                .font(CockpitFonts.ultraThin(size: 32))
                .foregroundColor(.white.opacity(0.85))
                .cyanGlow(radius: 8, opacity: 0.35)

            repoSelectorMenu
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private var repoSelectorMenu: some View {
        VStack(spacing: 6) {
            Text("choose a repo or begin anew")
                .font(CockpitFonts.mono(size: 8))
                .foregroundColor(.gray.opacity(0.9))

            Menu {
                if vm.githubRepos.isEmpty {
                    Text("Fetching repositories…")
                }
                ForEach(vm.githubRepos) { repo in
                    Button {
                        vm.selectedRepo = repo.id
                        vm.pullRepository(repo.id)
                    } label: {
                        Label(repo.name, systemImage: "folder.fill")
                    }
                }
                Divider()
                Button {
                    vm.showFreshProjectSheet = true
                } label: {
                    Label("begin anew", systemImage: "sparkles")
                }
            } label: {
                HStack(spacing: 6) {
                    if vm.isPullingRepo {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle()
                            .fill(Color.cyan.opacity(0.8))
                            .frame(width: 5, height: 5)
                    }
                    Text(selectedRepoName ?? "choose a repo")
                        .font(CockpitFonts.mono(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    Image(systemName: "chevron.down")
                        .font(CockpitFonts.regular(size: 7))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)

            if let notice = vm.registeredRepoNotice {
                Text(notice)
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(notice.contains("Error") ? .red : .green)
                    .lineLimit(1)
            }
        }
    }

    private var selectedRepoName: String? {
        guard let id = vm.selectedRepo else { return nil }
        return vm.githubRepos.first(where: { $0.id == id })?.name
    }

    @ViewBuilder
    private func messageRow(for msg: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if msg.role == .user {
                    Text("YOU")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(.blue)
                } else {
                    HStack(spacing: 6) {
                        Text(BuildConfig.chatName)
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                            .foregroundColor(.cyan)

                        // Appearing and disappearing status disclaimer for what Qwythos is actually doing
                        if msg.id == vm.chatMessages.last?.id && (vm.isGenerating || vm.currentProcessState != "IDLE") && !vm.currentProcessDetail.isEmpty {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.cyan)
                                    .frame(width: 5, height: 5)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.cyan.opacity(0.6), lineWidth: 1.5)
                                            .scaleEffect(1.4)
                                    )
                                Text(vm.currentProcessDetail.lowercased())
                                    .font(CockpitFonts.mono(size: 7, weight: .medium))
                                    .foregroundColor(.cyan.opacity(0.85))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.12))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.9)),
                                removal: .opacity
                            ))
                        }
                    }
                }

                Spacer()
                Text(msg.timestamp, style: .time)
                    .font(CockpitFonts.code(size: 7))
                    .foregroundColor(.gray)
            }

            if !msg.content.isEmpty {
                Text(msg.content)
                    .font(CockpitFonts.mono(size: 9, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(msg.role == .user ? Color.blue.opacity(0.12) : Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(msg.role == .user ? Color.blue.opacity(0.25) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            }

            if let thought = msg.thought, !thought.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("REASONING CHAIN")
                        .font(CockpitFonts.mono(size: 7, weight: .bold))
                        .foregroundColor(Color.cyan.opacity(0.8))
                    Text(thought)
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.cyan.opacity(0.15), lineWidth: 1)
                        )
                }
                .padding(.top, 4)
            }

            // Render Tool Calls
            if !msg.toolCalls.isEmpty {
                VStack(spacing: 6) {
                    ForEach(msg.toolCalls) { tc in
                        toolCallCard(for: tc)
                    }
                }
            }
        }
    }

    private func toolCallCard(for tc: ToolCallItem) -> some View {
        let artifactFullPath = artifactPathFor(tc)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconForTool(tc.name))
                    .font(CockpitFonts.regular(size: 11))
                    .foregroundColor(colorForTool(tc.name))
                Text(tc.name.uppercased())
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(colorForTool(tc.name))

                Spacer()

                statusBadge(for: tc.status)

                if let full = artifactFullPath {
                    Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: full)) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(CockpitFonts.regular(size: 7))
                            Text("OPEN")
                                .font(CockpitFonts.mono(size: 7, weight: .bold))
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Open artifact: \(full)")
                }
            }

            if let output = tc.output, !output.isEmpty {
                ScrollView(.horizontal) {
                    Text(output)
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.green.opacity(0.9))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .padding(6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if let full = artifactFullPath {
                NSWorkspace.shared.open(URL(fileURLWithPath: full))
            }
        }
        .contextMenu {
            if let full = artifactFullPath {
                Button("Open in Default App") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: full))
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(full, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    /// Resolves a written file path from a tool call so the chat card can open the artifact.
    private func artifactPathFor(_ tc: ToolCallItem) -> String? {
        let writers = ["write_file", "replace_file_content", "save_code_revision"]
        guard writers.contains(tc.name),
              let data = tc.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["path"] as? String, !path.isEmpty else { return nil }
        let full = harness.resolvePath(path)
        guard FileManager.default.fileExists(atPath: full) else { return nil }
        return full
    }

    private func statusBadge(for status: ToolCallStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .pending, .executing:
                ProgressView().controlSize(.mini)
                Text("RUNNING")
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.yellow)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(CockpitFonts.regular(size: 8))
                    .foregroundColor(.green)
                Text("DONE")
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(CockpitFonts.regular(size: 8))
                    .foregroundColor(.red)
                Text("FAILED")
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.red)
            }
        }
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "consult_deepseek": return "cpu"
        case "consult_gemini": return "sparkles"
        case "consult_kimi": return "paintpalette.fill"
        case "read_file": return "doc.text.magnifyingglass"
        case "write_file": return "square.and.pencil"
        case "replace_file_content": return "pencil.and.outline"
        case "list_dir": return "folder"
        case "grep_search": return "magnifyingglass"
        case "code_feedback": return "checkmark.seal.fill"
        case "durable_memory": return "brain.head.profile"
        case "run_command": return "terminal.fill"
        case "save_code_revision": return "tray.and.arrow.down.fill"
        default: return "wrench.and.screwdriver"
        }
    }

    private func colorForTool(_ name: String) -> Color {
        switch name {
        case "consult_deepseek": return .cyan
        case "consult_gemini": return .blue
        case "consult_kimi": return .purple
        case "read_file", "list_dir", "grep_search": return .blue
        case "write_file", "replace_file_content": return .indigo
        case "code_feedback": return .green
        case "durable_memory": return .teal
        case "run_command": return .mint
        case "save_code_revision": return .orange
        default: return .gray
        }
    }

    private func chooseAndAttachFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    harness.recordDeliverable(relativePath: url.lastPathComponent, status: "uploaded", content: content)
                    if inputText.isEmpty {
                        inputText = "Inspect uploaded file `\(url.lastPathComponent)`:\n```\n\(content.prefix(2000))\n```"
                    } else {
                        inputText += "\n\n[Attached: \(url.lastPathComponent)]"
                    }
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        if let content = try? String(contentsOf: url, encoding: .utf8) {
                            self.harness.recordDeliverable(relativePath: url.lastPathComponent, status: "uploaded", content: content)
                            if self.inputText.isEmpty {
                                self.inputText = "Inspect file `\(url.lastPathComponent)`:\n```\n\(content.prefix(2000))\n```"
                            } else {
                                self.inputText += "\n[Attached: \(url.lastPathComponent)]"
                            }
                        } else {
                            self.inputText += "\n\(url.path)"
                        }
                    }
                } else if let text = item as? String {
                    DispatchQueue.main.async {
                        self.inputText += "\n\(text)"
                    }
                }
            }
        }
        return true
    }

    private func submitMessage() {
        if voiceService.isRecording {
            voiceService.stopRecording()
        }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        vm.sendChatMessage(prompt: trimmed)
    }
}
