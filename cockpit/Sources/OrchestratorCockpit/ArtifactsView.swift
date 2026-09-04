import SwiftUI
import AppKit

struct ArtifactsView: View {
    @ObservedObject var harness = CodebaseHarnessService.shared
    @State private var selectedArtifact: DeliverableItem?
    @State private var previewContent: String = ""
    @State private var filterType: String = "ALL"
    @State private var isRunningFeedback: Bool = false

    private var filteredArtifacts: [DeliverableItem] {
        if filterType == "ALL" {
            return harness.deliverables
        }
        return harness.deliverables.filter { item in
            let ext = (item.path as NSString).pathExtension.lowercased()
            switch filterType {
            case "CODE": return ["py", "swift", "js", "ts", "svelte"].contains(ext)
            case "DOCS": return ["md", "txt", "json", "yaml", "yml"].contains(ext)
            case "SCRIPTS": return ["sh", "mjs", "cjs"].contains(ext)
            default: return true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header & Filter Dropdown
            HStack {
                Text("ARTIFACTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                Menu {
                    Button("All Files (\(harness.deliverables.count))") { filterType = "ALL" }
                    Button("Code (.py, .swift, .js, .svelte)") { filterType = "CODE" }
                    Button("Docs & Data (.md, .json)") { filterType = "DOCS" }
                    Button("Scripts (.sh, .mjs)") { filterType = "SCRIPTS" }
                } label: {
                    HStack(spacing: 4) {
                        Text(filterType)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)

                Button(action: { harness.refreshDeliverables() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .help("Refresh Artifacts")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Verify button (concise)
            Button(action: {
                isRunningFeedback = true
                Task {
                    _ = await harness.runCodeFeedback()
                    await MainActor.run { isRunningFeedback = false }
                }
            }) {
                HStack(spacing: 6) {
                    if isRunningFeedback {
                        ProgressView().controlSize(.mini)
                        Text("Verifying...")
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.cyan)
                        Text("Verify Codebase")
                    }
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isRunningFeedback)
            .padding(.horizontal, 6)

            // Artifacts List
            if filteredArtifacts.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 20))
                        .foregroundColor(.gray.opacity(0.3))
                    Text(harness.activeProjectDir == nil ? "Start a project with 'New'" : "Project workspace empty")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredArtifacts) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: iconForFile(item.path))
                                .font(.system(size: 9))
                                .foregroundColor(colorForStatus(item.status))
                            Text((item.path as NSString).lastPathComponent)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            statusBadge(item.status)
                        }

                        HStack {
                            Text(item.path)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(formatBytes(item.sizeBytes))
                                .font(.system(size: 7, design: .monospaced))
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
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        Spacer()

                        Button("Open") {
                            openFile(path: selected.path)
                        }
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)

                        Button("Close") {
                            previewContent = ""
                            selectedArtifact = nil
                        }
                        .font(.system(size: 8, design: .monospaced))
                        .buttonStyle(.plain)
                        .foregroundColor(.gray)
                    }
                    ScrollView {
                        Text(previewContent)
                            .font(.system(size: 9, design: .monospaced))
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
            .font(.system(size: 7, weight: .bold, design: .monospaced))
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
}
