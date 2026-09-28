import SwiftUI
import AppKit

struct WorkspaceRegisterView: View {
    @ObservedObject var harness = CodebaseHarnessService.shared
    @State private var hoveredFileId: UUID? = nil
    @State private var inspectingItem: DeliverableItem? = nil
    @State private var isTargetedForDrop = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 46, maximum: 58), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.white.opacity(0.06))
            registerGrid
        }
        .background(Color.white.opacity(0.02))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .popover(item: $inspectingItem) { item in
            fileInspectionPopover(for: item)
        }
    }

    private var headerBar: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "tray.fill")
                    .font(CockpitFonts.regular(size: 8))
                    .foregroundColor(.cyan)
                Text("bucket")
                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer()

            let formattedSize = ByteCountFormatter.string(fromByteCount: harness.totalDirectorySizeBytes, countStyle: .file)
            Text("\(harness.deliverables.count) items (\(formattedSize))")
                .font(CockpitFonts.mono(size: 7))
                .foregroundColor(.gray)

            Button(action: chooseAndUploadFiles) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(CockpitFonts.regular(size: 10))
                    .foregroundColor(.cyan)
            }
            .buttonStyle(.plain)
            .help("Upload files to file bucket")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.5))
    }

    private var registerGrid: some View {
        ZStack {
            Color.black.opacity(0.35)

            if harness.deliverables.isEmpty {
                emptyRegisterPlaceholder
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 10) {
                        ForEach(harness.deliverables) { item in
                            fileIconItem(for: item)
                        }
                    }
                    .padding(8)
                }
            }

            if isTargetedForDrop {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .background(Color.cyan.opacity(0.08))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleIncomingDrop(providers: providers)
        }
    }

    private func fileIconItem(for item: DeliverableItem) -> some View {
        let fileName = (item.path as NSString).lastPathComponent
        let isHovered = hoveredFileId == item.id

        return VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Image(systemName: iconForFile(item.path))
                        .font(CockpitFonts.regular(size: 18))
                        .foregroundColor(iconColorForFile(item.path))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isHovered ? Color.cyan.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1)
                        )

                    Text(fileName)
                        .font(CockpitFonts.mono(size: 7))
                        .foregroundColor(isHovered ? .cyan : .white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 44)
                }

                if isHovered {
                    Button(action: {
                        _ = harness.deleteFile(path: item.path)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(CockpitFonts.regular(size: 9))
                            .foregroundColor(.red)
                            .background(Color.black.clipShape(Circle()))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredFileId = hovering ? item.id : nil
        }
        .onTapGesture {
            inspectingItem = item
        }
        .onDrag {
            let fullPath = harness.resolvePath(item.path)
            let url = URL(fileURLWithPath: fullPath)
            return NSItemProvider(object: url as NSURL)
        }
        .contextMenu {
            Button("Inspect / Preview") {
                inspectingItem = item
            }
            Button("Open in Default App") {
                let fullPath = harness.resolvePath(item.path)
                NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
            }
            Button("Reveal in Finder") {
                let fullPath = harness.resolvePath(item.path)
                NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: "")
            }
            Divider()
            Button("Delete File", role: .destructive) {
                _ = harness.deleteFile(path: item.path)
            }
        }
    }

    private var emptyRegisterPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(CockpitFonts.regular(size: 20))
                .foregroundColor(.gray.opacity(0.4))
            Text("upload")
                .font(CockpitFonts.regular(size: 8))
                .foregroundColor(.gray.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }

    private func fileInspectionPopover(for item: DeliverableItem) -> some View {
        let (content, _) = harness.readFile(path: item.path)
        let fileName = (item.path as NSString).lastPathComponent

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForFile(item.path))
                    .foregroundColor(.cyan)
                Text(fileName)
                    .font(CockpitFonts.mono(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Spacer()

                Button("Open in App") {
                    let fullPath = harness.resolvePath(item.path)
                    NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
                }
                .font(CockpitFonts.mono(size: 9))
                .buttonStyle(.plain)
                .foregroundColor(.blue)

                Button(action: {
                    _ = harness.deleteFile(path: item.path)
                    inspectingItem = nil
                }) {
                    Image(systemName: "trash")
                        .font(CockpitFonts.regular(size: 10))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete File")
            }

            ScrollView {
                Text(content.isEmpty ? "(Empty file)" : content)
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 380, height: 220)
            .padding(8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(6)
        }
        .padding(12)
        .background(CockpitPalette.background)
    }

    private func chooseAndUploadFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    harness.recordDeliverable(relativePath: url.lastPathComponent, status: "uploaded", content: content)
                    _ = harness.writeFile(path: url.lastPathComponent, content: content)
                }
            }
        }
    }

    private func handleIncomingDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.harness.recordDeliverable(relativePath: url.lastPathComponent, status: "uploaded", content: content)
                            _ = self.harness.writeFile(path: url.lastPathComponent, content: content)
                        }
                    }
                }
            }
        }
        return true
    }

    private func iconForFile(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts": return "doc.text"
        case "json": return "curlybraces"
        case "md", "txt": return "text.book.closed"
        case "sh": return "terminal"
        case "png", "jpg", "jpeg": return "photo"
        default: return "doc"
        }
    }

    private func iconColorForFile(_ path: String) -> Color {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return .cyan
        case "js", "ts": return .yellow
        case "json": return .green
        case "md": return .purple
        case "sh": return .mint
        default: return .blue
        }
    }
}
