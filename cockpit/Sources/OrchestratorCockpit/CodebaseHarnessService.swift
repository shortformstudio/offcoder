import Foundation

struct DeliverableItem: Identifiable, Codable {
    let id: UUID
    let path: String
    let status: String // "drafted", "audited", "verified", "existing"
    let lastModified: Date
    let sizeBytes: Int

    init(id: UUID = UUID(), path: String, status: String, lastModified: Date = Date(), sizeBytes: Int = 0) {
        self.id = id
        self.path = path
        self.status = status
        self.lastModified = lastModified
        self.sizeBytes = sizeBytes
    }
}

final class CodebaseHarnessService: ObservableObject {
    static let shared = CodebaseHarnessService()

    let qwythosBaseDir: String = "/Users/stevenjackson/code/qwythos-agent"

    @Published var activeProjectDir: String? = nil
    @Published var activeProjectName: String? = nil
    @Published var deliverables: [DeliverableItem] = []
    @Published var lastFeedbackOutput: String = ""
    @Published var lastFeedbackPassed: Bool = true

    private let fileManager = FileManager.default
    private let versionManager = CodeVersionManager.shared
    private let cliRunner = CLIRunner.shared

    // O(1) extension filter lookup set
    private let allowedExtensions: Set<String> = [
        "py", "swift", "js", "ts", "svelte", "html", "css", "json", "md", "sh", "txt"
    ]

    init() {
        refreshDeliverables()
    }

    /// Initializes a dedicated new project folder inside Qwythos workspace
    func startProject(name: String, masterPlan: String? = nil) {
        let sanitized = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .joined()
        let projectName = sanitized.isEmpty ? "project-\(Int(Date().timeIntervalSince1970))" : sanitized
        let projectFolder = (qwythosBaseDir as NSString).appendingPathComponent("projects/\(projectName)")

        do {
            try fileManager.createDirectory(atPath: projectFolder, withIntermediateDirectories: true, attributes: nil)
            let memoryFolder = (projectFolder as NSString).appendingPathComponent(".agents/memory")
            try fileManager.createDirectory(atPath: memoryFolder, withIntermediateDirectories: true, attributes: nil)

            let memoryPath = (memoryFolder as NSString).appendingPathComponent("MEMORY.md")
            let initialMemory = """
# Project: \(projectName)
**Created**: \(ISO8601DateFormatter().string(from: Date()))
**Workspace**: \(projectFolder)

## Objective & Specification
\(masterPlan ?? "No initial specification provided.")
"""
            try initialMemory.write(toFile: memoryPath, atomically: true, encoding: .utf8)

            DispatchQueue.main.async {
                self.activeProjectDir = projectFolder
                self.activeProjectName = projectName
                self.refreshDeliverables()
            }

            appendWorkLog(
                category: "project_init",
                summary: "Initialized fresh project folder in Qwythos directory: projects/\(projectName)",
                details: initialMemory
            )
        } catch {
            print("Failed to start project in Qwythos directory: \(error)")
        }
    }

    func setProjectDir(_ path: String) {
        let expanded = NSString(string: path).expandingTildeInPath
        if fileManager.fileExists(atPath: expanded) {
            activeProjectDir = expanded
            activeProjectName = (expanded as NSString).lastPathComponent
            refreshDeliverables()
        }
    }

    // MARK: - Artifacts & Deliverables Tracking (O(N) with O(1) hash lookups)
    func refreshDeliverables() {
        guard let currentDir = activeProjectDir, fileManager.fileExists(atPath: currentDir) else {
            DispatchQueue.main.async {
                self.deliverables = []
            }
            return
        }

        var items: [DeliverableItem] = []
        let url = URL(fileURLWithPath: currentDir)
        let prefixToRemove = currentDir.hasSuffix("/") ? currentDir : currentDir + "/"

        if let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if allowedExtensions.contains(ext) {
                    let relative = fileURL.path.replacingOccurrences(of: prefixToRemove, with: "")
                    if !relative.hasPrefix(".git/") && !relative.contains("node_modules/") && !relative.contains(".build/") {
                        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                        let modDate = values?.contentModificationDate ?? Date()
                        let size = values?.fileSize ?? 0
                        items.append(DeliverableItem(path: relative, status: "existing", lastModified: modDate, sizeBytes: size))
                    }
                }
            }
        }
        DispatchQueue.main.async {
            self.deliverables = items.sorted(by: { $0.lastModified > $1.lastModified })
        }
    }

    func recordDeliverable(relativePath: String, status: String, content: String) {
        DispatchQueue.main.async {
            if let idx = self.deliverables.firstIndex(where: { $0.path == relativePath }) {
                self.deliverables[idx] = DeliverableItem(
                    id: self.deliverables[idx].id,
                    path: relativePath,
                    status: status,
                    lastModified: Date(),
                    sizeBytes: content.utf8.count
                )
            } else {
                self.deliverables.insert(
                    DeliverableItem(path: relativePath, status: status, lastModified: Date(), sizeBytes: content.utf8.count),
                    at: 0
                )
            }
        }
    }

    // MARK: - File Operations (Zero-alloc UTF8 string conversions)
    func resolvePath(_ path: String) -> String {
        guard let base = activeProjectDir else {
            return (qwythosBaseDir as NSString).appendingPathComponent(path)
        }
        if path.hasPrefix("/") {
            return path
        }
        return (base as NSString).appendingPathComponent(path)
    }

    func readFile(path: String, offset: Int? = nil, length: Int? = nil) -> (content: String, error: String?) {
        let fullPath = resolvePath(path)
        guard let fileHandle = FileHandle(forReadingAtPath: fullPath) else {
            return ("", "Error: file does not exist at '\(fullPath)'")
        }
        defer { try? fileHandle.close() }

        do {
            if let offset = offset {
                try fileHandle.seek(toOffset: UInt64(max(0, offset)))
                let readLength = length ?? Int.max
                let data = fileHandle.readData(ofLength: readLength)
                return (String(data: data, encoding: .utf8) ?? "", nil)
            } else {
                let data = fileHandle.readDataToEndOfFile()
                return (String(data: data, encoding: .utf8) ?? "", nil)
            }
        } catch {
            return ("", "Error reading file: \(error.localizedDescription)")
        }
    }

    func writeFile(path: String, content: String) -> (success: Bool, message: String) {
        if activeProjectDir == nil {
            startProject(name: "worktree-\(Int(Date().timeIntervalSince1970))")
        }
        let fullPath = resolvePath(path)
        let dir = (fullPath as NSString).deletingLastPathComponent
        do {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
            try content.write(toFile: fullPath, atomically: true, encoding: .utf8)

            let prefix = activeProjectDir != nil ? (activeProjectDir! + "/") : ""
            let relPath = fullPath.replacingOccurrences(of: prefix, with: "")
            recordDeliverable(relativePath: relPath, status: "drafted", content: content)

            _ = versionManager.commitRevision(
                filePath: relPath,
                code: content,
                origin: .localModel,
                summary: "Written via offcoder harness tool"
            )

            appendWorkLog(
                category: "file_write",
                summary: "Wrote \(content.utf8.count) bytes to \(relPath)",
                details: content
            )

            return (true, "Successfully wrote \(content.utf8.count) bytes to \(path)")
        } catch {
            return (false, "Error writing file: \(error.localizedDescription)")
        }
    }

    func replaceFileContent(path: String, target: String, replacement: String) -> (success: Bool, message: String) {
        let fullPath = resolvePath(path)
        let (existing, error) = readFile(path: fullPath)
        guard error == nil else { return (false, error!) }

        guard existing.contains(target) else {
            return (false, "Error: target block not found in \(path)")
        }

        let updated = existing.replacingOccurrences(of: target, with: replacement)
        return writeFile(path: path, content: updated)
    }

    func listDir(path: String? = nil) -> String {
        let targetPath = resolvePath(path ?? "")
        guard let items = try? fileManager.contentsOfDirectory(atPath: targetPath) else {
            return "Error: failed to list directory at \(targetPath)"
        }
        let filtered = items.filter { !$0.hasPrefix(".") && $0 != "node_modules" && $0 != ".build" }
        return filtered.joined(separator: "\n")
    }

    func grepSearch(query: String, path: String? = nil) async -> String {
        guard let currentDir = activeProjectDir else {
            return "No active project folder. Initialize a project first with 'New'."
        }
        let searchDir = resolvePath(path ?? "")
        let cmd = "grep -rnI --exclude-dir=node_modules --exclude-dir=.build --exclude-dir=.git '\(query)' '\(searchDir)' | head -n 30"
        let (stdout, stderr, _) = await cliRunner.execute(command: cmd, workingDirectory: currentDir)
        if !stdout.isEmpty { return stdout }
        if !stderr.isEmpty { return stderr }
        return "No matches found for '\(query)'."
    }

    // MARK: - Execution Feedback Loop
    func runCodeFeedback() async -> (pass: Bool, summary: String) {
        guard let currentDir = activeProjectDir else {
            return (true, "No active project folder. Start a project first to run tests.")
        }
        var report = "=== OFFCODER EXECUTION FEEDBACK ===\n"
        var allPassed = true

        let packageJsonPath = (currentDir as NSString).appendingPathComponent("package.json")
        if fileManager.fileExists(atPath: packageJsonPath) {
            let (lintOut, _, lintCode) = await cliRunner.execute(command: "npm run lint || true", workingDirectory: currentDir)
            if !lintOut.isEmpty { report += "--- LINT ---\n\(lintOut)\n" }

            let (tscOut, _, tscCode) = await cliRunner.execute(command: "npx tsc --noEmit || true", workingDirectory: currentDir)
            if !tscOut.isEmpty { report += "--- TYPECHECK ---\n\(tscOut)\n" }

            let (testOut, _, testCode) = await cliRunner.execute(command: "npm test || true", workingDirectory: currentDir)
            if !testOut.isEmpty { report += "--- TESTS ---\n\(testOut)\n" }
            if lintCode != 0 || tscCode != 0 || testCode != 0 { allPassed = false }
        }

        let pytestCheck = (currentDir as NSString).appendingPathComponent("pytest.ini")
        let pyTestsDir = (currentDir as NSString).appendingPathComponent("tests")
        if fileManager.fileExists(atPath: pytestCheck) || fileManager.fileExists(atPath: pyTestsDir) {
            let (pyOut, _, pyCode) = await cliRunner.execute(command: "pytest -q || true", workingDirectory: currentDir)
            if !pyOut.isEmpty { report += "--- PYTEST ---\n\(pyOut)\n" }
            if pyCode != 0 { allPassed = false }
        }

        let packageSwiftPath = (currentDir as NSString).appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: packageSwiftPath) {
            let (swiftOut, _, swiftCode) = await cliRunner.execute(command: "swift test || true", workingDirectory: currentDir)
            if !swiftOut.isEmpty { report += "--- SWIFT TEST ---\n\(swiftOut)\n" }
            if swiftCode != 0 { allPassed = false }
        }

        report += "\nVERDICT: \(allPassed ? "✅ ALL CHECKS PASSED" : "⚠️ ISSUES DETECTED")\n"

        appendWorkLog(
            category: "execution_feedback",
            summary: allPassed ? "All codebase checks passed" : "Issues detected during test/lint execution",
            details: report
        )

        DispatchQueue.main.async {
            self.lastFeedbackOutput = report
            self.lastFeedbackPassed = allPassed
        }
        return (allPassed, report)
    }

    // MARK: - Durable Project Memory
    func durableMemory(action: String, content: String?) -> String {
        guard let currentDir = activeProjectDir else {
            return "No active project folder. Start a project first."
        }
        let memoryDir = (currentDir as NSString).appendingPathComponent(".agents/memory")
        let memoryFile = (memoryDir as NSString).appendingPathComponent("MEMORY.md")

        if action == "read" {
            if fileManager.fileExists(atPath: memoryFile) {
                return (try? String(contentsOfFile: memoryFile, encoding: .utf8)) ?? "(Empty memory file)"
            } else {
                return "No MEMORY.md found at \(memoryFile). You can create one with action='write'."
            }
        } else if action == "write" {
            guard let newContent = content else { return "Error: content required for write" }
            do {
                try fileManager.createDirectory(atPath: memoryDir, withIntermediateDirectories: true, attributes: nil)
                try newContent.write(toFile: memoryFile, atomically: true, encoding: .utf8)
                return "✅ Successfully updated .agents/memory/MEMORY.md (\(newContent.utf8.count) bytes)"
            } catch {
                return "Error writing memory: \(error.localizedDescription)"
            }
        } else if action == "append" {
            guard let appendText = content else { return "Error: content required for append" }
            let existing = (try? String(contentsOfFile: memoryFile, encoding: .utf8)) ?? "# Project Durable Memory\n\n"
            let updated = existing + "\n" + appendText
            do {
                try fileManager.createDirectory(atPath: memoryDir, withIntermediateDirectories: true, attributes: nil)
                try updated.write(toFile: memoryFile, atomically: true, encoding: .utf8)
                return "✅ Appended to .agents/memory/MEMORY.md"
            } catch {
                return "Error appending to memory: \(error.localizedDescription)"
            }
        }
        return "Unknown memory action: \(action). Use 'read', 'write', or 'append'."
    }
}

// MARK: - Work Logging (.agents/logs/ & runs/)
extension CodebaseHarnessService {
    func appendWorkLog(category: String, summary: String, details: String) {
        let baseDir = activeProjectDir ?? qwythosBaseDir
        let logsDir = (baseDir as NSString).appendingPathComponent(".agents/logs")
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let logFile = (logsDir as NSString).appendingPathComponent("\(today).md")

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = """

### [\(timestamp)] \(category.uppercased())
**Summary**: \(summary)
```
\(details)
```
"""
        do {
            try fileManager.createDirectory(atPath: logsDir, withIntermediateDirectories: true, attributes: nil)
            if fileManager.fileExists(atPath: logFile) {
                let existing = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
                try (existing + entry).write(toFile: logFile, atomically: true, encoding: .utf8)
            } else {
                let header = "# Offcoder Session Work Log — \(today)\n"
                try (header + entry).write(toFile: logFile, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Failed to append work log: \(error)")
        }
    }

    func appendConversationTranscript(messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }
        let baseDir = activeProjectDir ?? qwythosBaseDir
        let runsDir = (baseDir as NSString).appendingPathComponent(".agents/logs/conversations")
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let transcriptFile = (runsDir as NSString).appendingPathComponent("chat-\(today).jsonl")

        do {
            try fileManager.createDirectory(atPath: runsDir, withIntermediateDirectories: true, attributes: nil)
            var lines = ""
            for msg in messages {
                let payload: [String: Any] = [
                    "id": msg.id.uuidString,
                    "role": msg.role.rawValue,
                    "content": msg.content,
                    "timestamp": msg.timestamp.timeIntervalSince1970,
                    "tools": msg.toolCalls.map { ["name": $0.name, "args": $0.arguments, "output": $0.output ?? ""] }
                ]
                if let data = try? JSONSerialization.data(withJSONObject: payload),
                   let line = String(data: data, encoding: .utf8) {
                    lines += line + "\n"
                }
            }
            if let handle = FileHandle(forWritingAtPath: transcriptFile) {
                handle.seekToEndOfFile()
                if let d = lines.data(using: .utf8) { handle.write(d) }
                handle.closeFile()
            } else {
                try lines.write(toFile: transcriptFile, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Failed to write conversation log: \(error)")
        }
    }
}
