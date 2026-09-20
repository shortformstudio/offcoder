import Foundation
import Combine

/// Assembles the user's mission (state.db), totem memory (local records), and
/// indexing cache into one compact context block. The block is pre-appended to
/// every agent system prompt so each turn starts warm.
final class PreloadContextService: ObservableObject {
    static let shared = PreloadContextService()

    @Published private(set) var context: String = ""
    @Published private(set) var lastBuiltAt: Date? = nil
    @Published private(set) var isBuilding: Bool = false

    let offcoderHome: String
    let preloadDir: String
    let contextPath: String

    private let fileManager = FileManager.default
    private let stateDBPath = NSString(string: "~/.local_orchestrator/state.db").expandingTildeInPath
    private let projectRoot = "/Users/stevenjackson/Documents/DEVELOPMENT/WILD CARD/inference offload"
    private let workspacesRoot = BuildConfig.workspaceRoot

    private let buildQueue = DispatchQueue(label: "offcoder.preload.build", qos: .utility)
    private var hasBuilt = false

    private init() {
        offcoderHome = NSString(string: "~/.offcoder").expandingTildeInPath
        preloadDir = (offcoderHome as NSString).appendingPathComponent("preload")
        contextPath = (preloadDir as NSString).appendingPathComponent("context.md")
        try? fileManager.createDirectory(atPath: preloadDir, withIntermediateDirectories: true)
        if let existing = try? String(contentsOfFile: contextPath, encoding: .utf8), !existing.isEmpty {
            context = existing
            hasBuilt = true
        }
    }

    /// Builds once per process, then returns the cached block.
    func ensureLoaded() async -> String {
        if hasBuilt && !context.isEmpty { return context }
        return await rebuild()
    }

    func rebuild(totemPort: Int? = nil) async -> String {
        let port = TotemPortListenerService.shared.activePort
        return await withCheckedContinuation { continuation in
            buildQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: "")
                    return
                }
                let assembled = self.assemble(totemPort: port)
                try? assembled.write(toFile: self.contextPath, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    self.context = assembled
                    self.lastBuiltAt = Date()
                    self.isBuilding = false
                    self.hasBuilt = true
                    continuation.resume(returning: assembled)
                }
            }
        }
    }

    // MARK: - Assembly

    private func assemble(totemPort: Int) -> String {
        let recordsDir = (projectRoot as NSString).appendingPathComponent("local records - \(totemPort)")
        var sections: [String] = []

        sections.append("""
        # OFFCODER PRELOADED CONTEXT — mission, memory, index
        Generated: \(Self.isoFormatter.string(from: Date())) | Host: \(Host.current().localizedName ?? "local") | Totem: totem-\(totemPort)
        State DB: \(stateDBPath)
        Totem records: \(recordsDir)
        """)

        sections.append(contentsOf: stateSections())
        sections.append(workspaceSection())
        sections.append(totemMemorySection(recordsDir: recordsDir, totemPort: totemPort))

        return sections.joined(separator: "\n\n") + "\n"
    }

    private func stateSections() -> [String] {
        guard fileManager.fileExists(atPath: stateDBPath) else {
            return ["## 1. MISSION STATE\nstate.db not found at \(stateDBPath)"]
        }
        var sections: [String] = []

        let queue = sqliteJSON("SELECT task_id, target_worker, operation_mode, target_file, status, prompt_payload, created_at FROM task_queue ORDER BY created_at DESC LIMIT 20;")
        if queue.isEmpty {
            sections.append("## 1. MISSION QUEUE (task_queue)\n- empty")
        } else {
            let lines = queue.map { row -> String in
                var project = ""
                if let payload = row["prompt_payload"] as? String,
                   let data = payload.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    project = json["projectName"] as? String ?? ""
                }
                let label = project.isEmpty ? string(row["target_file"]) : "\(project) → \(string(row["target_file"]))"
                return "- [\(string(row["status"]))] \(string(row["operation_mode"])) · \(string(row["target_worker"])) · \(label) (created \(epoch(row["created_at"])))"
            }
            sections.append("## 1. MISSION QUEUE (task_queue)\n" + lines.joined(separator: "\n"))
        }

        let journal = sqliteJSON("SELECT entry_type, target_module, summary, created_at FROM session_journal ORDER BY journal_id DESC LIMIT 15;")
        if journal.isEmpty {
            sections.append("## 2. SESSION JOURNAL (recent)\n- empty")
        } else {
            let lines = journal.map { row in
                "- \(epoch(row["created_at"])) [\(string(row["entry_type"]))] \(string(row["target_module"])): \(string(row["summary"]))"
            }
            sections.append("## 2. SESSION JOURNAL (recent)\n" + lines.joined(separator: "\n"))
        }

        let repos = sqliteJSON("SELECT repo_id, local_path, default_branch, last_synced FROM repo_registry;")
        let indexedTotal = sqliteJSON("SELECT COUNT(*) AS n FROM context_nodes;").first.flatMap { int($0["n"]) } ?? 0
        if repos.isEmpty {
            sections.append("## 3. REPOSITORY INDEX (cache)\n- no repositories indexed yet\n- total indexed context nodes: \(indexedTotal)")
        } else {
            let lines = repos.map { row -> String in
                let repoId = string(row["repo_id"])
                let nodes = sqliteJSON("SELECT COUNT(*) AS n FROM context_nodes WHERE repo_id = '\(repoId.replacingOccurrences(of: "'", with: "''"))';").first.flatMap { int($0["n"]) } ?? 0
                return "- \(repoId) @ \(string(row["local_path"])) (branch \(string(row["default_branch"]))) · indexed nodes: \(nodes) · last synced \(epoch(row["last_synced"]))"
            }
            sections.append("## 3. REPOSITORY INDEX (cache)\n" + lines.joined(separator: "\n") + "\n- total indexed context nodes: \(indexedTotal)")
        }

        return sections
    }

    private func workspaceSection() -> String {
        let projectsDir = (workspacesRoot as NSString).appendingPathComponent("projects")
        var lines: [String] = []
        if let entries = try? fileManager.contentsOfDirectory(atPath: projectsDir) {
            for entry in entries.sorted() {
                var isDir: ObjCBool = false
                let full = (projectsDir as NSString).appendingPathComponent(entry)
                guard fileManager.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
                var count = 0
                if let enumerator = fileManager.enumerator(atPath: full) {
                    for case let item as String in enumerator where !item.hasPrefix(".") {
                        count += 1
                    }
                }
                lines.append("- \(entry) (\(count) files) → \(full)")
            }
        }
        if lines.isEmpty && fileManager.fileExists(atPath: workspacesRoot) {
            lines.append("- workspace root: \(workspacesRoot)")
        }
        return "## 4. WORKSPACES ON DISK\n" + (lines.isEmpty ? "- none found" : lines.joined(separator: "\n"))
    }

    private func totemMemorySection(recordsDir: String, totemPort: Int) -> String {
        let bioDir = (recordsDir as NSString).appendingPathComponent("biodynamic")
        let memoryPath = (recordsDir as NSString).appendingPathComponent("MEMORY.md")
        let memory = (try? String(contentsOfFile: memoryPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clipped = String(memory.prefix(6000))

        var counts: [String] = []
        if let factsData = try? String(contentsOfFile: (bioDir as NSString).appendingPathComponent("facts.jsonl"), encoding: .utf8) {
            counts.append("facts: \(factsData.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count)")
        }
        for (label, file) in [("working_knowledge", "working_knowledge.json"), ("wisdom", "wisdom.json"), ("legacy", "legacy.json")] {
            let path = (bioDir as NSString).appendingPathComponent(file)
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let list = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                counts.append("\(label): \(list.count)")
            }
        }

        var section = "## 5. TOTEM MEMORY LEDGER (port \(totemPort))\n\(clipped.isEmpty ? "(empty)" : clipped)\n\nLedger counts: \(counts.isEmpty ? "no biodynamic ledger yet" : counts.joined(separator: " | "))"

        let factsPath = (bioDir as NSString).appendingPathComponent("facts.jsonl")
        if let factsData = try? String(contentsOfFile: factsPath, encoding: .utf8) {
            let recent = factsData.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(25)
            var factLines: [String] = []
            for line in recent {
                guard let data = line.data(using: .utf8),
                      let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let domain = row["domain"] as? String ?? "?"
                let content = String((row["content"] as? String ?? "").prefix(180))
                factLines.append("- [\(domain)] \(content)")
            }
            if !factLines.isEmpty {
                section += "\n\n## 6. RECENT VERIFIED FACTS\n" + factLines.joined(separator: "\n")
            }
        }
        return section
    }

    // MARK: - Helpers

    private func sqliteJSON(_ query: String) -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", stateDBPath, query]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows
    }

    private func string(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    private func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private func epoch(_ value: Any?) -> String {
        guard let seconds = value.flatMap({ double($0) }) else { return "unknown" }
        return Self.isoFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private func double(_ value: Any) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
