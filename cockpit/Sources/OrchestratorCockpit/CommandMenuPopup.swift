import SwiftUI

struct CommandItem: Identifiable {
    let id: String
    let command: String
    let summary: String
    let icon: String
    let color: Color
}

struct CommandMenuPopup: View {
    var onSelect: (String) -> Void
    var onClose: () -> Void

    @State private var searchQuery: String = ""

    let commands: [CommandItem] = [
        CommandItem(id: "consensus", command: "/consensus", summary: "Multi-Model Consensus Arena across Local, DeepSeek, Gemini, and Kimi", icon: "square.split.3x1.fill", color: .purple),
        CommandItem(id: "arena", command: "/arena", summary: "Side-by-side model arena and unanimous vs disputed synthesis diff", icon: "arrow.triangle.merge", color: .cyan),
        CommandItem(id: "deepseek", command: "/deepseek", summary: "Hand off prompt + code to DeepSeek for generation & local review", icon: "arrow.triangle.swap", color: .purple),
        CommandItem(id: "handoff", command: "/handoff", summary: "Hand off code to DeepSeek with automatic local model review", icon: "sparkles", color: .indigo),
        CommandItem(id: "remember", command: "/remember", summary: "Traverse Totem knowledge graph for architectural invariants", icon: "brain.head.profile", color: .teal),
        CommandItem(id: "explain", command: "/explain", summary: "Explain code, architecture patterns, or workflow logic", icon: "questionmark.circle", color: .cyan),
        CommandItem(id: "refactor", command: "/refactor", summary: "Propose clean, performant, and idiomatic refactoring", icon: "arrow.triangle.2.circlepath", color: .blue),
        CommandItem(id: "tests", command: "/tests", summary: "Generate unit, regression, and stress test suites", icon: "checkmark.seal", color: .green),
        CommandItem(id: "surf", command: "/surf", summary: "Autonomous browser agent navigation & exploration", icon: "safari", color: .indigo),
        CommandItem(id: "webaudit", command: "/webaudit", summary: "Full accessibility, contrast, and performance audit", icon: "gauge.with.needle", color: .orange),
        CommandItem(id: "freeaudit", command: "/freeaudit", summary: "Deep DOM contrast & accessibility audit", icon: "eye", color: .yellow),
        CommandItem(id: "compress", command: "/compress", summary: "Semantically compress context into memory graph", icon: "arrow.down.right.and.arrow.up.left", color: .cyan),
        CommandItem(id: "clear", command: "/clear", summary: "Erase conversation history and reset token context", icon: "trash", color: .red)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header & Search
            HStack(spacing: 6) {
                Text("/")
                    .font(CockpitFonts.mono(size: 13, weight: .bold))
                    .foregroundColor(.cyan)

                TextField("Type a command...", text: $searchQuery)
                    .font(CockpitFonts.mono(size: 10))
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))

            Divider().background(Color.white.opacity(0.08))

            // Commands List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(filteredCommands) { cmd in
                        Button(action: {
                            onSelect(cmd.command + " ")
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: cmd.icon)
                                    .font(CockpitFonts.regular(size: 10))
                                    .foregroundColor(cmd.color)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cmd.command)
                                        .font(CockpitFonts.mono(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(cmd.summary)
                                        .font(CockpitFonts.mono(size: 8))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 360)
        .background(Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.96))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 10, y: 5)
    }

    private var filteredCommands: [CommandItem] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return commands
        }
        return commands.filter {
            $0.command.localizedCaseInsensitiveContains(searchQuery) ||
            $0.summary.localizedCaseInsensitiveContains(searchQuery)
        }
    }
}
