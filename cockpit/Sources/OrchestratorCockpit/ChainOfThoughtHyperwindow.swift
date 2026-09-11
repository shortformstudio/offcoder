import SwiftUI
import AppKit

struct ChainOfThoughtHyperwindow: View {
    let thoughtText: String
    let isReasoning: Bool
    let processStatus: String
    @Binding var isCollapsed: Bool
    let maxHeight: CGFloat

    @State private var copiedNotice: Bool = false

    private var estimatedTokens: Int {
        let words = thoughtText.split { $0.isWhitespace || $0.isNewline }.count
        return Int(Double(words) * 1.33)
    }

    /// Dynamically calculates body height so the window is small initially,
    /// expanding as text streams in, up to a maximum of halfway across the parent view.
    private var dynamicContentHeight: CGFloat {
        let trimmed = thoughtText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }
        let lines = trimmed.components(separatedBy: .newlines).count
        let chars = trimmed.count
        let estimatedHeight = CGFloat(max(lines * 22, (chars / 45) * 22) + 24)
        let maxAllowed = max(36, maxHeight - 36)
        return min(estimatedHeight, maxAllowed)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            // Body content: small initially, expands as thoughtText fills, no "waiting" placeholder
            if !isCollapsed && !thoughtText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().background(Color.cyan.opacity(0.2))

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        Text(thoughtText)
                            .font(CockpitFonts.mono(size: 8))
                            .foregroundColor(Color(red: 0.88, green: 0.94, blue: 1.0))
                            .textSelection(.enabled)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .id("thought_bottom")
                    }
                    .frame(height: dynamicContentHeight)
                    .onChange(of: thoughtText) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            scrollProxy.scrollTo("thought_bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(
            Color(red: 0.04, green: 0.06, blue: 0.10).opacity(0.92)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.45), Color.purple.opacity(0.25), Color.cyan.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.cyan.opacity(0.12), radius: 10, x: 0, y: 3)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: thoughtText.isEmpty)
        .animation(.easeInOut(duration: 0.18), value: dynamicContentHeight)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if isReasoning {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .stroke(Color.cyan.opacity(0.6), lineWidth: 2)
                                .scaleEffect(1.4)
                        )
                } else {
                    Circle()
                        .fill(Color.cyan.opacity(0.5))
                        .frame(width: 6, height: 6)
                }

                Image(systemName: "brain.head.profile")
                    .font(CockpitFonts.bold(size: 13))
                    .foregroundColor(.cyan)

                if !processStatus.isEmpty {
                    Text("[\(processStatus)]")
                        .font(CockpitFonts.mono(size: 7))
                        .foregroundColor(.cyan.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            if estimatedTokens > 0 {
                Text("~\(estimatedTokens) tok")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(3)
            }

            if copiedNotice {
                Text("COPIED")
                    .font(CockpitFonts.mono(size: 7, weight: .bold))
                    .foregroundColor(.green)
            }

            Button(action: copyToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(CockpitFonts.regular(size: 11))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help("Copy Chain of Thought to Clipboard")

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            }) {
                HStack(spacing: 3) {
                    Text(isCollapsed ? "EXPAND" : "COLLAPSE")
                        .font(CockpitFonts.mono(size: 7, weight: .bold))
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(CockpitFonts.bold(size: 9))
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.cyan.opacity(0.12))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.65))
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(thoughtText, forType: .string)
        copiedNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedNotice = false
        }
    }
}
