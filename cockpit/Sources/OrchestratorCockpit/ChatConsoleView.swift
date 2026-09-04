import SwiftUI

struct ChatConsoleView: View {
    @ObservedObject var vm: OrchestratorViewModel
    @ObservedObject var versionManager = CodeVersionManager.shared
    @ObservedObject var harness = CodebaseHarnessService.shared

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isGenerating ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text("OFFCODER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("• \(vm.activeModelName)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                }

                Spacer()

                if vm.isGenerating {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("GENERATING...")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                if vm.isCompressing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("COMPRESSING...")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }

                Button(action: { vm.compressContext() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 9))
                        Text("Compress")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(vm.chatMessages.isEmpty || vm.isGenerating || vm.isCompressing)
                .help("Semantically compress context via Qwythos while archiving literal log")

                Button(action: { vm.clearChat() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .help("Clear Chat")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))

            Divider().background(Color.white.opacity(0.06))

            // Message Stream
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
                }
                .onChange(of: vm.chatMessages.count) { _ in
                    if let last = vm.chatMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider().background(Color.white.opacity(0.06))

            // Quick suggestion chips
            quickActionChips
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            // Input bar
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Offcoder (Cmd+Enter to send)...", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .focused($isInputFocused)
                    .onSubmit {
                        if NSEvent.modifierFlags.contains(.command) {
                            submitMessage()
                        }
                    }

                Button(action: submitMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .cyan)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isGenerating)
            }
            .padding(12)
            .background(Color.black.opacity(0.2))
        }
        .frostyBento()
    }

    private var emptyStatePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 28))
                .foregroundColor(.cyan.opacity(0.7))
            Text("Offcoder")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
            Text("Ready for coding, audits, feedback verification, and file operations.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func messageRow(for msg: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(msg.role == .user ? "YOU" : "OFFCODER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(msg.role == .user ? .blue : .cyan)
                Spacer()
                Text(msg.timestamp, style: .time)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray)
            }

            if !msg.content.isEmpty {
                Text(msg.content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(msg.role == .user ? Color.blue.opacity(0.12) : Color.white.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(msg.role == .user ? Color.blue.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 1)
                    )
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconForTool(tc.name))
                    .font(.system(size: 10))
                    .foregroundColor(colorForTool(tc.name))
                Text(tc.name.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(colorForTool(tc.name))

                Spacer()

                statusBadge(for: tc.status)
            }

            if let output = tc.output, !output.isEmpty {
                ScrollView(.horizontal) {
                    Text(output)
                        .font(.system(size: 10, design: .monospaced))
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

    private func statusBadge(for status: ToolCallStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .pending, .executing:
                ProgressView().controlSize(.mini)
                Text("RUNNING")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
                Text("DONE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                Text("FAILED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "consult_deepseek": return "cpu"
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

    private var quickActionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                quickChip(label: "Compress Context", icon: "arrow.down.right.and.arrow.up.left") {
                    vm.compressContext()
                }
                quickChip(label: "DeepSeek Audit", icon: "cpu") {
                    inputText = "Audit the current code with DeepSeek."
                }
                quickChip(label: "Verify Codebase", icon: "checkmark.seal.fill") {
                    inputText = "Run execution feedback (linters, typecheck, tests)."
                }
                quickChip(label: "Inspect Artifacts", icon: "tray.fill") {
                    inputText = "List tracked artifacts in the workspace."
                }
                quickChip(label: "Durable Memory", icon: "brain.head.profile") {
                    inputText = "Read .agents/memory/MEMORY.md and summarize project facts."
                }
                quickChip(label: "Kimi Design", icon: "paintpalette.fill") {
                    inputText = "Review styling and UI aesthetics with Kimi."
                }
            }
        }
    }

    private func quickChip(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(label).font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func submitMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        vm.sendChatMessage(prompt: trimmed)
    }
}
