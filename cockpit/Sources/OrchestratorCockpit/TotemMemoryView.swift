import SwiftUI
import AppKit

struct TotemMemoryView: View {
    @ObservedObject var totem = TotemPortListenerService.shared
    @State private var showingPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TotemHeaderView(port: totem.activePort)
            Divider().background(Color.white.opacity(0.06))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TotemRawCaptureCard(totem: totem)
                    TotemFilterCard(totem: totem)
                    TotemBiodynamicCard(totem: totem, showingPreview: $showingPreview)
                    TotemTickerRow(log: totem.lastConsoleLog)

                    if showingPreview {
                        TotemPreviewCard(text: totem.generateSynthesizedContext())
                    }
                }
                .padding(8)
            }
        }
        .background(Color.black.opacity(0.2))
    }
}

// MARK: - Subviews

private struct TotemHeaderView: View {
    let port: Int

    var body: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(CockpitFonts.bold(size: 11))
                .foregroundColor(.cyan)

            Text("TOTEM // PORT \(port)")
                .font(CockpitFonts.mono(size: 10, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("LISTENING")
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.12))
            .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}

private struct TotemRawCaptureCard: View {
    @ObservedObject var totem: TotemPortListenerService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RAW API LISTENER")
                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                    .foregroundColor(.cyan)
                Spacer()
                Text("local records - \(totem.activePort)")
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.gray)
            }

            Text("Unconditional raw capture of all request inputs & response outputs streaming on port \(totem.activePort).")
                .font(CockpitFonts.mono(size: 10))
                .foregroundColor(.white.opacity(0.8))

            HStack(spacing: 8) {
                Text("Transactions: \(totem.totalTransactionsRecorded)")
                    .font(CockpitFonts.mono(size: 9, weight: .semibold))
                    .foregroundColor(.cyan)

                Spacer()

                Button(action: { totem.openLocalRecordsFolder() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(CockpitFonts.regular(size: 8))
                        Text("Open Records")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.4))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct TotemFilterCard: View {
    @ObservedObject var totem: TotemPortListenerService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MODULAR MEMORY FILTER")
                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                    .foregroundColor(.yellow)
                Spacer()
            }

            Menu {
                ForEach(TotemFilterType.allCases) { filter in
                    Button(filter.rawValue) {
                        totem.activeFilter = filter
                    }
                }
            } label: {
                HStack {
                    Text(totem.activeFilter.rawValue)
                        .font(CockpitFonts.mono(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(CockpitFonts.regular(size: 8))
                        .foregroundColor(.gray)
                }
                .padding(6)
                .background(Color.white.opacity(0.06))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)

            Text(totem.activeFilter.description)
                .font(CockpitFonts.mono(size: 9))
                .foregroundColor(.gray)
                .lineSpacing(2)
        }
        .padding(8)
        .background(Color.black.opacity(0.4))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct TotemBiodynamicCard: View {
    @ObservedObject var totem: TotemPortListenerService
    @Binding var showingPreview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BIODYNAMIC CONSOLIDATION")
                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                    .foregroundColor(.green)
                Spacer()
                if let last = totem.lastConsolidatedAt {
                    Text(last, style: .time)
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray)
                }
            }

            VStack(spacing: 4) {
                TotemTierRow(icon: "🏛️", name: "Layer 4: Legacy Invariants (L)", count: totem.legacyCount, color: .purple)
                TotemTierRow(icon: "📜", name: "Layer 3: Distilled Wisdom (W)", count: totem.wisdomCount, color: .orange)
                TotemTierRow(icon: "🧠", name: "Layer 2: Working Knowledge (K)", count: totem.workingKnowledgeCount, color: .cyan)
                TotemTierRow(icon: "📌", name: "Layer 1: Ground Truth Facts (F)", count: totem.factsCount, color: .green)
                TotemTierRow(icon: "🧭", name: "Layer 0: Memory Atlas (A)", count: 4, color: .blue)
            }

            HStack(spacing: 8) {
                Button(action: { totem.runConsolidation() }) {
                    HStack(spacing: 4) {
                        if totem.isConsolidating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "sparkles")
                                .font(CockpitFonts.regular(size: 8))
                        }
                        Text("Consolidate Memory")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(totem.isConsolidating)

                Spacer()

                Button(action: { showingPreview.toggle() }) {
                    Text(showingPreview ? "Hide Context" : "View MEMORY.md")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(8)
        .background(Color.black.opacity(0.4))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct TotemTierRow: View {
    let icon: String
    let name: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(CockpitFonts.regular(size: 10))
            Text(name)
                .font(CockpitFonts.mono(size: 8))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Text("\(count)")
                .font(CockpitFonts.mono(size: 9, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.03))
        .cornerRadius(3)
    }
}

private struct TotemTickerRow: View {
    let log: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.cyan.opacity(0.7)).frame(width: 4, height: 4)
            Text(log)
                .font(CockpitFonts.mono(size: 8))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
    }
}

private struct TotemPreviewCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SYNTHESIZED MEMORY CONTEXT")
                .font(CockpitFonts.mono(size: 8, weight: .bold))
                .foregroundColor(.cyan)

            ScrollView {
                Text(text)
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
        }
        .padding(6)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }
}
