import SwiftUI

struct ConsensusArenaView: View {
    @ObservedObject var arena = ConsensusEngineService.shared
    @Environment(\.dismiss) private var dismiss
    var onAdoptCode: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            arenaHeader

            Divider().background(Color.white.opacity(0.1))

            // Consensus Points & Synthesis Banner
            consensusSynthesisSection

            Divider().background(Color.white.opacity(0.1))

            // Multi-Model Arena Split Columns
            arenaColumnsGrid
        }
        .frame(minWidth: 960, minHeight: 650)
        .background(Color.black.opacity(0.92))
    }

    // MARK: - Header
    private var arenaHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "square.split.3x1.fill")
                    .font(CockpitFonts.bold(size: 12))
                    .foregroundColor(.purple)
                Text("MULTI-MODEL CONSENSUS ARENA")
                    .font(CockpitFonts.mono(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer()

            if arena.isRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("FANNING OUT CONCURRENT QUERIES...")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.cyan)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.12))
                .cornerRadius(4)
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(CockpitFonts.regular(size: 16))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.6))
    }

    // MARK: - Synthesis Section
    private var consensusSynthesisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CONSENSUS SYNTHESIS & AGREEMENT MATRIX")
                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                    .foregroundColor(.purple.opacity(0.9))

                Spacer()

                Text("Prompt: \"\(arena.activePrompt.prefix(60))...\"")
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.gray)
            }

            // Consensus Points Badges
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(arena.consensusPoints) { point in
                        consensusPointCard(point)
                    }
                }
            }

            // Synthesis Summary Diff
            if !arena.synthesizedDiffSummary.isEmpty {
                Text(arena.synthesizedDiffSummary)
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.purple.opacity(0.06))
    }

    private func consensusPointCard(_ point: ConsensusPoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(badgeColor(for: point.type))
                    .frame(width: 6, height: 6)
                Text(point.type.rawValue)
                    .font(CockpitFonts.mono(size: 7, weight: .bold))
                    .foregroundColor(badgeColor(for: point.type))
                Spacer()
            }

            Text(point.title)
                .font(CockpitFonts.mono(size: 9, weight: .bold))
                .foregroundColor(.white)

            Text(point.description)
                .font(CockpitFonts.mono(size: 8))
                .foregroundColor(.gray)
                .lineLimit(2)
        }
        .padding(8)
        .frame(width: 240, alignment: .leading)
        .background(Color.black.opacity(0.5))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(badgeColor(for: point.type).opacity(0.3), lineWidth: 1))
    }

    private func badgeColor(for type: ConsensusAgreementType) -> Color {
        switch type {
        case .unanimous: return .green
        case .disputed: return .orange
        case .uniqueInsight: return .cyan
        }
    }

    // MARK: - Arena Split Columns Grid
    private var arenaColumnsGrid: some View {
        HStack(spacing: 1) {
            ForEach(arena.candidates) { candidate in
                modelColumnView(candidate)
            }
        }
        .background(Color.white.opacity(0.08))
    }

    private func modelColumnView(_ candidate: ConsensusModelCandidate) -> some View {
        VStack(spacing: 0) {
            // Column Header
            HStack(spacing: 6) {
                Circle().fill(candidate.color).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.modelName)
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Text(candidate.role)
                        .font(CockpitFonts.mono(size: 7))
                        .foregroundColor(.gray)
                }

                Spacer()

                if candidate.latencyMs > 0 {
                    Text("\(candidate.latencyMs)ms")
                        .font(CockpitFonts.mono(size: 7))
                        .foregroundColor(.gray)
                }

                // Adopt CTA Button
                Button(action: {
                    onAdoptCode?(candidate.outputText)
                    SpeculativeDiffGhostManager.shared.pushSpeculativeCandidate(
                        code: candidate.outputText,
                        summary: "Candidate from \(candidate.modelName)"
                    )
                    dismiss()
                }) {
                    Text("Adopt")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(candidate.color)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(candidate.outputText.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))

            Divider().background(Color.white.opacity(0.06))

            // Output Body
            ScrollView {
                if candidate.isStreaming {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Streaming generation...")
                            .font(CockpitFonts.mono(size: 9))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                } else if candidate.isError {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(candidate.errorMessage ?? "Query failed")
                            .font(CockpitFonts.mono(size: 9))
                            .foregroundColor(.orange)
                    }
                    .padding(14)
                } else {
                    Text(candidate.outputText)
                        .font(CockpitFonts.code(size: 9))
                        .foregroundColor(.white.opacity(0.9))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.black.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.85))
    }
}
