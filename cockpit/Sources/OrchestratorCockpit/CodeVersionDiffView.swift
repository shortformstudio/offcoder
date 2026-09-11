import SwiftUI

struct CodeVersionDiffView: View {
    @ObservedObject var versionManager = CodeVersionManager.shared
    @State private var showingDiffMode = true // true = Diff, false = Full Code

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(CockpitFonts.regular(size: 10))
                        .foregroundColor(.blue)
                    Text("VERSION DIFF CHAIN")
                        .font(CockpitFonts.mono(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                Picker("", selection: $showingDiffMode) {
                    Text("DIFF").tag(true)
                    Text("FULL CODE").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))

            Divider().background(Color.white.opacity(0.06))

            // File & Revision Chain Selector
            if versionManager.activeChain.isEmpty {
                emptyRevisionsPlaceholder
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Revision breadcrumb chain
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(versionManager.activeChain) { rev in
                                revisionChip(for: rev)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(Color.black.opacity(0.3))

                    Divider().background(Color.white.opacity(0.04))

                    if let selected = versionManager.selectedRevision ?? versionManager.latestRevision {
                        revisionDetailsHeader(for: selected)
                            .padding(.horizontal, 12)

                        // Diff / Code Content Area
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                if showingDiffMode {
                                    renderDiffLines(selected.diffFromPrevious)
                                } else {
                                    Text(selected.code)
                                        .font(CockpitFonts.mono(size: 11))
                                        .foregroundColor(.white.opacity(0.9))
                                        .textSelection(.enabled)
                                        .padding(10)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(6)
                        .padding(10)
                    }
                }
            }
        }
        .frostyBento()
    }

    private var emptyRevisionsPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(CockpitFonts.regular(size: 28))
                .foregroundColor(.gray.opacity(0.5))
            Text("No Code Versions Committed Yet")
                .font(CockpitFonts.mono(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
            Text("When the local model sends code to DeepSeek or Kimi, original baselines and audited diffs are tracked here automatically.")
                .font(CockpitFonts.mono(size: 10))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func revisionChip(for rev: CodeRevision) -> some View {
        let isSelected = (versionManager.selectedRevision?.id ?? versionManager.latestRevision?.id) == rev.id
        return Button(action: { versionManager.selectedRevision = rev }) {
            HStack(spacing: 4) {
                Text("v\(rev.versionIndex)")
                    .font(CockpitFonts.mono(size: 10, weight: .bold))
                Text("[\(rev.origin.rawValue)]")
                    .font(CockpitFonts.mono(size: 8, weight: .medium))
                    .foregroundColor(colorForOrigin(rev.origin))
            }
            .foregroundColor(isSelected ? .white : .gray)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.25) : Color.white.opacity(0.04))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func revisionDetailsHeader(for rev: CodeRevision) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("v\(rev.versionIndex): \(rev.summary)")
                        .font(CockpitFonts.mono(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("•")
                        .foregroundColor(.gray)
                    Text(rev.filePath)
                        .font(CockpitFonts.mono(size: 9))
                        .foregroundColor(.blue)
                }
                Text("Committed \(rev.timestamp, style: .time) via \(rev.origin.rawValue)")
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: {
                _ = versionManager.rollback(to: rev)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(CockpitFonts.regular(size: 9))
                    Text("Rollback to v\(rev.versionIndex)")
                        .font(CockpitFonts.mono(size: 9, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func renderDiffLines(_ diffText: String) -> some View {
        let lines = diffText.components(separatedBy: .newlines)
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            diffLineView(line)
        }
    }

    @ViewBuilder
    private func diffLineView(_ line: String) -> some View {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            Text(line)
                .font(CockpitFonts.mono(size: 10))
                .foregroundColor(.green)
                .padding(.horizontal, 4)
                .background(Color.green.opacity(0.12))
                .cornerRadius(2)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            Text(line)
                .font(CockpitFonts.mono(size: 10))
                .foregroundColor(.red)
                .padding(.horizontal, 4)
                .background(Color.red.opacity(0.12))
                .cornerRadius(2)
        } else if line.hasPrefix("---") || line.hasPrefix("+++") {
            Text(line)
                .font(CockpitFonts.mono(size: 10, weight: .bold))
                .foregroundColor(.cyan)
                .padding(.horizontal, 4)
        } else {
            Text(line)
                .font(CockpitFonts.mono(size: 10))
                .foregroundColor(.white.opacity(0.65))
                .padding(.horizontal, 4)
        }
    }

    private func colorForOrigin(_ origin: RevisionOrigin) -> Color {
        switch origin {
        case .userOriginal: return .gray
        case .localModel: return .blue
        case .deepseekAudit: return .cyan
        case .kimiDesign: return .purple
        case .cliOutput: return .green
        }
    }
}
