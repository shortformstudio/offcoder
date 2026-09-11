import SwiftUI
import AppKit

struct ArtifactsView: View {
    @ObservedObject var harness = CodebaseHarnessService.shared
    @State private var selectedArtifact: DeliverableItem?
    @State private var previewContent: String = ""

    private var filteredArtifacts: [DeliverableItem] {
        return harness.deliverables
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("ARTIFACTS")
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: { harness.refreshDeliverables() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(CockpitFonts.regular(size: 11))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .help("Refresh Artifacts")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Artifacts List
            if filteredArtifacts.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(CockpitFonts.regular(size: 24))
                        .foregroundColor(.gray.opacity(0.3))
                    Text("no artifacts")
                        .font(CockpitFonts.regular(size: 7))
                        .foregroundColor(.gray.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredArtifacts) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: iconForFile(item.path))
                                .font(CockpitFonts.regular(size: 11))
                                .foregroundColor(colorForStatus(item.status))
                            Text((item.path as NSString).lastPathComponent)
                                .font(CockpitFonts.mono(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            statusBadge(item.status)
                        }

                        HStack {
                            Text("\(kindForFile(item.path)) • \(item.path)")
                                .font(CockpitFonts.mono(size: 7))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(formatBytes(item.sizeBytes))
                                .font(CockpitFonts.mono(size: 6))
                                .foregroundColor(.gray.opacity(0.8))
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedArtifact = item
                        let (content, _) = harness.readFile(path: item.path)
                        previewContent = content
                    }
                    .contextMenu {
                        Button("Open in Default Editor") {
                            openFile(path: item.path)
                        }
                        Button("Reveal in Finder") {
                            revealFile(path: item.path)
                        }
                    }
                    .listRowBackground(
                        selectedArtifact?.id == item.id ? Color.white.opacity(0.06) : Color.clear
                    )
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            // Quick File Preview & Action Bar if selected
            if !previewContent.isEmpty, let selected = selectedArtifact {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text((selected.path as NSString).lastPathComponent)
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                            .foregroundColor(.cyan)
                        Spacer()

                        Button("Open") {
                            openFile(path: selected.path)
                        }
                        .font(CockpitFonts.mono(size: 7, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)

                        Button("Close") {
                            previewContent = ""
                            selectedArtifact = nil
                        }
                        .font(CockpitFonts.mono(size: 7))
                        .buttonStyle(.plain)
                        .foregroundColor(.gray)
                    }
                    ScrollView {
                        Text(previewContent)
                            .font(CockpitFonts.mono(size: 8))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 110)
                    .padding(6)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(4)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
        }
        .padding(4)
    }

    private func openFile(path: String) {
        let fullPath = harness.resolvePath(path)
        NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
    }

    private func revealFile(path: String) {
        let fullPath = harness.resolvePath(path)
        NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: "")
    }

    private func iconForFile(_ path: String) -> String {
        if path.hasSuffix(".py") { return "chevron.left.forwardslash.chevron.right" }
        if path.hasSuffix(".swift") { return "swift" }
        if path.hasSuffix(".ts") || path.hasSuffix(".js") { return "doc.text" }
        if path.hasSuffix(".svelte") { return "flame" }
        if path.hasSuffix(".md") { return "text.book.closed" }
        return "doc"
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "audited": return .cyan
        case "verified": return .green
        case "drafted": return .orange
        default: return .gray
        }
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.uppercased())
            .font(CockpitFonts.mono(size: 6, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(colorForStatus(status).opacity(0.15))
            .foregroundColor(colorForStatus(status))
            .cornerRadius(3)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        return String(format: "%.1f KB", kb)
    }

    private func kindForFile(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "py": return "Python"
        case "swift": return "Swift"
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "svelte": return "Svelte"
        case "html": return "HTML"
        case "css": return "CSS"
        case "json": return "JSON"
        case "md": return "Markdown"
        case "txt": return "Text"
        case "sh": return "Shell"
        case "yml", "yaml": return "YAML"
        default: return ext.isEmpty ? "File" : ext.uppercased()
        }
    }
}
