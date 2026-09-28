import SwiftUI
import AppKit

struct ChatConsoleView: View {
    @ObservedObject var vm: OrchestratorViewModel
    @ObservedObject var versionManager = CodeVersionManager.shared
    @ObservedObject var harness = CodebaseHarnessService.shared
    @ObservedObject var voiceService = VoiceTranscriptionService.shared
    @ObservedObject var totemService = TotemPortListenerService.shared

    @State private var workspaceDir: String = ""
    @State private var isScrolledUp: Bool = false
    @State private var lastScrolledMessageId: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation & Workspace Strip
            topWorkspaceStrip

            // Real-Time Context & Token Gauge Bar
            contextGaugeBar

            Divider().background(Color.white.opacity(0.06))

            // Main Message Stream with Floating Overlays
            ZStack(alignment: .bottomTrailing) {
                ZStack(alignment: .top) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
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
                            .padding(.top, (vm.isThoughtOverlayVisible && !vm.isThoughtOverlayCollapsed && !vm.activeChainOfThought.isEmpty) ? 55 : 8)
                            .padding(.bottom, 24)
                        }
                        .onChange(of: vm.chatMessages.count) { _ in
                            if let last = vm.chatMessages.last {
                                withAnimation(.spring(response: 0.3)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                        .overlay(
                            // Scroll to bottom floating action
                            Group {
                                if !vm.chatMessages.isEmpty {
                                    Button(action: {
                                        if let last = vm.chatMessages.last {
                                            withAnimation {
                                                proxy.scrollTo(last.id, anchor: .bottom)
                                            }
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.down")
                                                .font(CockpitFonts.regular(size: 8))
                                            Text("Latest")
                                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                                        }
                                        .foregroundColor(.white.opacity(0.9))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.75))
                                        .cornerRadius(12)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
                                        .shadow(color: .black.opacity(0.4), radius: 6)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                }
                            }
                        )
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
            }

            // Real-time Process HUD Strip
            if vm.isGenerating || vm.currentProcessState != "IDLE" || !vm.activeChainOfThought.isEmpty {
                processHudStrip
            }

            Divider().background(Color.white.opacity(0.06))

            // Attached Context Chips Bar
            if !vm.attachedItems.isEmpty {
                attachmentsBar
            }

            // Input Dock: Overlaid Context/Command Popups + Modern Input Bar
            ZStack(alignment: .bottomLeading) {
                inputBar

                if vm.isContextSelectorOpen {
                    ContextSelectorPopup(
                        onSelect: { ref in
                            vm.chatInputText += (vm.chatInputText.isEmpty ? "" : " ") + ref + " "
                            vm.isContextSelectorOpen = false
                        },
                        onClose: { vm.isContextSelectorOpen = false }
                    )
                    .offset(x: 10, y: -80)
                    .transition(.scale.combined(with: .opacity))
                }

                if vm.isCommandMenuOpen {
                    CommandMenuPopup(
                        onSelect: { cmd in
                            vm.chatInputText = cmd
                            vm.isCommandMenuOpen = false
                        },
                        onClose: { vm.isCommandMenuOpen = false }
                    )
                    .offset(x: 10, y: -80)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frostyBento()
    }

    // MARK: - Top Workspace Strip & Header
    private var topWorkspaceStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                modelSelectorMenu

                Spacer()

                // Semantic Context Compression
                Button(action: { vm.compressContext() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(CockpitFonts.regular(size: 9))
                        if vm.isCompressing {
                            Text("COMPRESSING")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                        }
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(vm.chatMessages.isEmpty || vm.isGenerating || vm.isCompressing)
                .help("Semantically compress context into memory graph")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
        }
    }

    // MARK: - Real-Time Context & Token Gauge Bar
    private var contextGaugeBar: some View {
        let metrics = vm.contextMetrics
        let percent = metrics.percentage
        let gaugeColor: Color = metrics.isCritical ? .red : (metrics.isWarning ? .yellow : .cyan)

        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(gaugeColor)
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(gaugeColor.opacity(0.6), lineWidth: 1.5).scaleEffect(1.4))

                    Text("CONTEXT")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(gaugeColor)

                    Text("\(metrics.totalTokens.formatted()) / \(metrics.maxContextTokens.formatted()) tokens")
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.white.opacity(0.85))

                    Text("(\(String(format: "%.1f", percent))%)")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(gaugeColor)

                    if percent >= 80.0 {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.badge.automatic.fill")
                                .font(CockpitFonts.regular(size: 7))
                            Text("80% AUTO-COMPACT ACTIVE")
                                .font(CockpitFonts.mono(size: 7, weight: .bold))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.18))
                        .cornerRadius(3)
                        .help("Conversational turns are semantically compacted before dispatching to model context")
                    }
                }

                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [gaugeColor.opacity(0.8), gaugeColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * CGFloat(min(1.0, percent / 100.0))), height: 3)
                        .animation(.easeOut(duration: 0.2), value: percent)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Process HUD Strip
    private var processHudStrip: some View {
        HStack(spacing: 8) {
            if vm.isReasoning {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color.cyan.opacity(0.5), lineWidth: 2).scaleEffect(1.4))

                Text("thinking...")
                    .font(CockpitFonts.mono(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            } else if !vm.currentProcessDetail.isEmpty {
                Text(vm.currentProcessDetail.lowercased())
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.cyan.opacity(0.85))
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

    // MARK: - Attached Context Chips Bar
    private var attachmentsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vm.attachedItems) { item in
                    HStack(spacing: 4) {
                        if item.type == .image, let image = loadPreviewImage(for: item) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 28, height: 28)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        } else if item.type == .file {
                            Image(systemName: "doc.fill")
                                .font(CockpitFonts.regular(size: 10))
                                .foregroundColor(.cyan)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(4)
                        } else {
                            Image(systemName: iconForAttachment(item.type))
                                .font(CockpitFonts.regular(size: 8))
                                .foregroundColor(.cyan)
                        }

                        Text(item.name)
                            .font(CockpitFonts.mono(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)

                        Button(action: { vm.removeAttachment(id: item.id) }) {
                            Image(systemName: "xmark")
                                .font(CockpitFonts.regular(size: 7))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(Color.black.opacity(0.3))
    }

    private func loadPreviewImage(for item: AttachedContextItem) -> NSImage? {
        guard item.type == .image, !item.path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: item.path)
        guard let image = NSImage(contentsOf: url) else { return nil }
        let maxSize: CGFloat = 28
        let ratio = min(maxSize / image.size.width, maxSize / image.size.height)
        let newSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        return resized
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Vertical Toolbar
            VStack(spacing: 6) {
                attachmentUploadMenu
                commandMenuButton
                voiceMicButton
                submitButton
            }
            .padding(.vertical, 4)

            // Multi-line Expanding Chat Input Field
            ChatInputField(
                text: $vm.chatInputText,
                placeholder: voiceService.isRecording ? "Listening... (speak now)" : BuildConfig.chatMessagePlaceholder,
                onSubmit: submitMessage,
                onContextTrigger: {
                    withAnimation { vm.isContextSelectorOpen = true; vm.isCommandMenuOpen = false }
                },
                onCommandTrigger: {
                    withAnimation { vm.isCommandMenuOpen = true; vm.isContextSelectorOpen = false }
                }
            )
            .frame(minHeight: 34, maxHeight: 120)
            .padding(4)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(voiceService.isRecording ? Color.red.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .onDrop(of: ["public.file-url", "public.utf8-plain-text"], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.35))
    }

    // MARK: - Message Rows
    @ViewBuilder
    private func messageRow(for msg: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row: Role, Timestamp, Actions
            HStack(spacing: 8) {
                if msg.role == .user {
                    HStack(spacing: 4) {
                        Circle().fill(Color.blue).frame(width: 5, height: 5)
                        Text("YOU")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                            .foregroundColor(.blue)
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle().fill(Color.cyan).frame(width: 5, height: 5)
                        Text(BuildConfig.chatName)
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                            .foregroundColor(.cyan)

                        if msg.id == vm.chatMessages.last?.id && (vm.isGenerating || vm.currentProcessState != "IDLE") && !vm.currentProcessDetail.isEmpty {
                            Text(vm.currentProcessDetail.lowercased())
                                .font(CockpitFonts.mono(size: 7, weight: .medium))
                                .foregroundColor(.cyan.opacity(0.85))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.cyan.opacity(0.12))
                                .cornerRadius(3)
                        }
                    }
                }

                Spacer()

                Text(msg.timestamp, style: .time)
                    .font(CockpitFonts.code(size: 7))
                    .foregroundColor(.gray)

                // User Message Edit Action
                if msg.role == .user {
                    Button(action: { vm.editPrompt(for: msg) }) {
                        Image(systemName: "pencil")
                            .font(CockpitFonts.regular(size: 8))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Edit prompt in input box")
                }
            }

            // Message Content Blocks (Text and Code Blocks)
            let blocks = msg.parseContentBlocks()
            ForEach(blocks) { block in
                switch block {
                case .text(_, let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(text)
                            .font(CockpitFonts.mono(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(msg.role == .user ? Color.blue.opacity(0.12) : Color.white.opacity(0.04))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(msg.role == .user ? Color.blue.opacity(0.25) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                case .code(_, let lang, let fn, let code):
                    CodeBlockView(
                        language: lang,
                        filename: fn,
                        code: code,
                        onInlineAction: { prompt in
                            vm.sendChatMessage(prompt: prompt)
                        }
                    )
                }
            }

            // Reasoning Chain Disclosure
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
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.15), lineWidth: 1))
                }
                .padding(.top, 2)
            }

            // Render Tool Calls
            if !msg.toolCalls.isEmpty {
                VStack(spacing: 6) {
                    ForEach(msg.toolCalls) { tc in
                        toolCallCard(for: tc)
                    }
                }
            }

            // Assistant Feedback & Action Strip
            if msg.role == .assistant && !msg.content.isEmpty {
                HStack(spacing: 12) {
                    // Thumbs Up
                    Button(action: { vm.setFeedback(for: msg.id, rating: .thumbsUp) }) {
                        Image(systemName: msg.feedback == .thumbsUp ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(CockpitFonts.regular(size: 9))
                            .foregroundColor(msg.feedback == .thumbsUp ? .green : .gray)
                    }
                    .buttonStyle(.plain)
                    .help("Thumbs up feedback")

                    // Thumbs Down
                    Button(action: { vm.setFeedback(for: msg.id, rating: .thumbsDown) }) {
                        Image(systemName: msg.feedback == .thumbsDown ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(CockpitFonts.regular(size: 9))
                            .foregroundColor(msg.feedback == .thumbsDown ? .red : .gray)
                    }
                    .buttonStyle(.plain)
                    .help("Thumbs down feedback")

                    // Regenerate Response
                    if msg.id == vm.chatMessages.last?.id && !vm.isGenerating {
                        Button(action: { vm.regenerateLastResponse() }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .font(CockpitFonts.regular(size: 8))
                                Text("Regenerate")
                                    .font(CockpitFonts.mono(size: 8))
                            }
                            .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate response with previous prompt")
                    }

                    // Copy Full Message
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(msg.content, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(CockpitFonts.regular(size: 8))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Copy full message")

                    Spacer()
                }
                .padding(.top, 2)
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Tool Calls Cards
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
    }

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

    // MARK: - Menus & Subviews
    private var attachmentUploadMenu: some View {
        Menu {
            Button("Attach File(s)...") { chooseAndAttachFiles() }
            Button("Attach Folder...") { chooseAndAttachFolder() }
            Button("Attach Image...") { chooseAndAttachImages() }
        } label: {
            Image(systemName: "paperclip")
                .font(CockpitFonts.regular(size: 13))
                .foregroundColor(.cyan.opacity(0.85))
                .padding(6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .help("Upload files, folders, or images")
    }

    private var commandMenuButton: some View {
        Button(action: {
            withAnimation { vm.isCommandMenuOpen.toggle(); vm.isContextSelectorOpen = false }
        }) {
            Image(systemName: "command")
                .font(CockpitFonts.regular(size: 13))
                .foregroundColor(vm.isCommandMenuOpen ? .cyan : .white.opacity(0.75))
                .padding(6)
                .background(vm.isCommandMenuOpen ? Color.cyan.opacity(0.18) : Color.white.opacity(0.05))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("Command Menu: trigger predefined skills & prompts")
    }

    private var submitButton: some View {
        Group {
            if vm.isGenerating {
                Button(action: { vm.stopGeneration() }) {
                    ZStack {
                        Circle().fill(Color.red.opacity(0.2)).frame(width: 26, height: 26)
                        RoundedRectangle(cornerRadius: 3).fill(Color.red).frame(width: 10, height: 10)
                    }
                }
                .buttonStyle(.plain)
                .help("Stop active token generation")
            } else {
                Button(action: submitMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(CockpitFonts.regular(size: 24))
                        .foregroundColor(vm.chatInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray.opacity(0.4) : .cyan)
                }
                .buttonStyle(.plain)
                .disabled(vm.chatInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send Message (Cmd+Enter or Enter)")
            }
        }
    }

    private var modelSelectorMenu: some View {
        Menu {
            ForEach(totemService.totems) { profile in
                Button(action: {
                    totemService.selectTotem(profile)
                    vm.setEndpoint(url: "http://\(profile.host):\(profile.port)", model: profile.modelId)
                    vm.recalculateContextTokens()
                }) {
                    HStack {
                        if totemService.activeTotem.id == profile.id {
                            Image(systemName: "checkmark")
                        }
                        Text("\(profile.name) (\(profile.modelId))")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 5, height: 5)
                Text(totemService.activeTotem.name)
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                Image(systemName: "chevron.down")
                    .font(CockpitFonts.regular(size: 6))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.04))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
    }

    private var voiceMicButton: some View {
        Button(action: {
            voiceService.toggleRecording(
                onTextChange: { transcribed in
                    self.vm.chatInputText = transcribed
                },
                currentText: self.vm.chatInputText
            )
        }) {
            ZStack {
                if voiceService.isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 26, height: 26)
                        .scaleEffect(1.0 + CGFloat(voiceService.audioLevel) * 0.7)
                }
                Image(systemName: voiceService.isRecording ? "waveform" : "mic.fill")
                    .font(CockpitFonts.regular(size: 12))
                    .foregroundColor(voiceService.isRecording ? .red : .white.opacity(0.75))
            }
            .frame(width: 26, height: 26)
            .background(voiceService.isRecording ? Color.red.opacity(0.15) : Color.white.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(voiceService.isRecording ? Color.red.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyStatePlaceholder: some View {
        VStack(spacing: 16) {
            Text("offcoder")
                .font(CockpitFonts.ultraThin(size: 22))
                .foregroundColor(.white.opacity(0.85))
                .cyanGlow(radius: 8, opacity: 0.35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private var workspaceDirectoryDropdown: some View {
        Menu {
            if let dir = harness.activeProjectDir {
                Button(dir) {}
                    .disabled(true)
            }
            Divider()
            Button("Change Workspace...") {
                chooseWorkspaceDirectory()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(CockpitFonts.regular(size: 7))
                    .foregroundColor(.cyan.opacity(0.7))
                Text((workspaceDir as NSString).lastPathComponent.isEmpty ? "No Workspace" : (workspaceDir as NSString).lastPathComponent)
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(CockpitFonts.regular(size: 5))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.04))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .onAppear {
            workspaceDir = harness.activeProjectDir ?? ""
        }
    }

    // MARK: - Actions
    private func chooseAndAttachFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            vm.attachFiles(urls: panel.urls)
        }
    }

    private func chooseAndAttachFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            vm.attachFolder(url: url)
        }
    }

    private func chooseAndAttachImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        if panel.runModal() == .OK {
            for url in panel.urls {
                let item = AttachedContextItem(type: .image, name: url.lastPathComponent, path: url.path, sizeBytes: 0, content: "[Image Attached: \(url.path)]")
                vm.attachedItems.append(item)
            }
        }
    }

    private func chooseWorkspaceDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            workspaceDir = url.path
            harness.setProjectDir(url.path)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        self.vm.attachFiles(urls: [url])
                    }
                } else if let text = item as? String {
                    DispatchQueue.main.async {
                        self.vm.chatInputText += (self.vm.chatInputText.isEmpty ? "" : "\n") + text
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
        let trimmed = vm.chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        vm.chatInputText = ""
        vm.isContextSelectorOpen = false
        vm.isCommandMenuOpen = false
        vm.sendChatMessage(prompt: trimmed)
    }

    private func iconForAttachment(_ type: AttachmentType) -> String {
        switch type {
        case .file: return "doc.text"
        case .folder: return "folder"
        case .image: return "photo"
        case .codeRef: return "at"
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
}
