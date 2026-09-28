import SwiftUI

struct GhostDiffOverlayView: View {
    @ObservedObject var ghost = SpeculativeDiffGhostManager.shared
    var onAccept: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Floating Instant Rollback HUD Bar
            rollbackHUDBar

            Divider().background(Color.white.opacity(0.1))

            // Ghost Code Lines
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(ghost.ghostLines) { line in
                        ghostLineRow(line)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color.black.opacity(0.85))
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.cyan.opacity(0.15), radius: 10, x: 0, y: 4)
    }

    // MARK: - HUD Bar
    private var rollbackHUDBar: some View {
        HStack(spacing: 8) {
            // Live Status Indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 7, height: 7)
                    .shadow(color: .cyan, radius: 4)
                Text("SPECULATIVE GHOST")
                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                    .foregroundColor(.cyan)
            }

            // Stats badge
            HStack(spacing: 4) {
                Text("+\(ghost.additionsCount)")
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.green)
                Text("-\(ghost.deletionsCount)")
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.06))
            .cornerRadius(4)

            Spacer()

            // Scrubber Chain Controls
            HStack(spacing: 4) {
                Button(action: { ghost.scrubBackward() }) {
                    Image(systemName: "chevron.left")
                        .font(CockpitFonts.regular(size: 8))
                        .foregroundColor(ghost.activeScrubIndex > 0 ? .white : .gray.opacity(0.4))
                        .padding(4)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .disabled(ghost.activeScrubIndex <= 0)
                .help("Scrub Backward (Cmd + [)")

                Text("v\(ghost.activeScrubIndex) of \(max(0, ghost.speculativeChain.count - 1))")
                    .font(CockpitFonts.mono(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Button(action: { ghost.scrubForward() }) {
                    Image(systemName: "chevron.right")
                        .font(CockpitFonts.regular(size: 8))
                        .foregroundColor(ghost.activeScrubIndex < ghost.speculativeChain.count - 1 ? .white : .gray.opacity(0.4))
                        .padding(4)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .disabled(ghost.activeScrubIndex >= ghost.speculativeChain.count - 1)
                .help("Scrub Forward (Cmd + ])")
            }

            Divider().frame(height: 14).background(Color.white.opacity(0.2))

            // Action Buttons
            HStack(spacing: 5) {
                Button(action: {
                    _ = ghost.acceptCurrentGhost()
                    onAccept?()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(CockpitFonts.regular(size: 8))
                        Text("Accept")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Accept and stage candidate (Enter)")

                Button(action: {
                    ghost.discardGhost()
                    onDiscard?()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(CockpitFonts.regular(size: 8))
                        Text("Discard")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Discard ghost diff (Esc)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.65))
    }

    // MARK: - Line Renderer
    private func ghostLineRow(_ line: GhostLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Line numbers / gutter
            HStack(spacing: 3) {
                if let old = line.oldLineNumber {
                    Text("\(old)")
                        .frame(width: 22, alignment: .trailing)
                } else {
                    Text(" ")
                        .frame(width: 22)
                }

                if let new = line.newLineNumber {
                    Text("\(new)")
                        .frame(width: 22, alignment: .trailing)
                } else {
                    Text(" ")
                        .frame(width: 22)
                }
            }
            .font(CockpitFonts.mono(size: 8))
            .foregroundColor(.gray.opacity(0.5))

            // Prefix indicator
            Group {
                switch line.type {
                case .addition:
                    Text("+")
                        .foregroundColor(.green)
                        .fontWeight(.bold)
                case .deletion:
                    Text("-")
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                case .unchanged:
                    Text(" ")
                        .foregroundColor(.clear)
                }
            }
            .font(CockpitFonts.mono(size: 9))
            .frame(width: 10)

            // Content
            Text(line.content.isEmpty ? " " : line.content)
                .font(CockpitFonts.mono(size: 10))
                .foregroundColor(colorForLine(line.type))
                .strikethrough(line.type == .deletion, color: .red.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(backgroundForLine(line.type))
    }

    private func colorForLine(_ type: GhostLineType) -> Color {
        switch type {
        case .addition: return Color.green.opacity(0.95)
        case .deletion: return Color.red.opacity(0.7)
        case .unchanged: return Color.white.opacity(0.85)
        }
    }

    private func backgroundForLine(_ type: GhostLineType) -> Color {
        switch type {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        case .unchanged: return Color.clear
        }
    }
}
