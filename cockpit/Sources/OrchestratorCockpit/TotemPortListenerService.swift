import Foundation
import Combine
import AppKit

// MARK: - Modular Memory Filter Protocol & Types

enum TotemFilterType: String, CaseIterable, Identifiable, Codable {
    case syntaxRegex = "Syntax & Invariant Filter"
    case semanticHeuristic = "Semantic Heuristic Filter"
    case apiTransaction = "API Transaction Filter"
    case rawPassthrough = "Raw Passthrough Filter"
    case biodynamicAtlas = "Biodynamic Atlas Filter"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .syntaxRegex:
            return "Extracts explicit syntax rules, invariants, file paths, diff markers, and error patterns."
        case .semanticHeuristic:
            return "Extracts architectural decisions, user constraints, heuristics, and milestone solutions."
        case .apiTransaction:
            return "Extracts structured tool calls, function parameters, schemas, and execution deliverables."
        case .rawPassthrough:
            return "Unfiltered high-fidelity recording of all raw conversational and prompt interactions."
        case .biodynamicAtlas:
            return "Routes observations into the 4 whitepaper domains: Architecture, Operations, Heuristics, Domain."
        }
    }
}

// MARK: - Biodynamic Memory Data Models

struct TotemFact: Identifiable, Codable {
    let id: String
    var content: String
    var domain: String // "arch", "ops", "heuristics", "domain"
    var veracity: Double
    var timestamp: Double
    var tags: [String]

    init(id: String = "fact-\(UUID().uuidString.prefix(8))", content: String, domain: String = "arch", veracity: Double = 1.0, timestamp: Double = Date().timeIntervalSince1970, tags: [String] = []) {
        self.id = id
        self.content = content
        self.domain = domain
        self.veracity = veracity
        self.timestamp = timestamp
        self.tags = tags
    }
}

struct TotemWorkingKnowledge: Identifiable, Codable {
    let id: String
    var title: String
    var semanticSummary: String
    var domain: String
    var originSeed: String
    var journeyTrace: [String]
    var reinforcementCount: Int
    var salienceScore: Double
    var lastReinforcedAt: Double
    var associatedFactIds: [String]
    var tags: [String]

    init(
        id: String = "wk-\(UUID().uuidString.prefix(8))",
        title: String,
        semanticSummary: String,
        domain: String = "arch",
        originSeed: String = "",
        journeyTrace: [String] = [],
        reinforcementCount: Int = 1,
        salienceScore: Double = 1.0,
        lastReinforcedAt: Double = Date().timeIntervalSince1970,
        associatedFactIds: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.semanticSummary = semanticSummary
        self.domain = domain
        self.originSeed = originSeed
        self.journeyTrace = journeyTrace
        self.reinforcementCount = reinforcementCount
        self.salienceScore = salienceScore
        self.lastReinforcedAt = lastReinforcedAt
        self.associatedFactIds = associatedFactIds
        self.tags = tags
    }
}

struct TotemWisdomAphorism: Identifiable, Codable {
    let id: String
    var declaration: String
    var rationale: String
    var domain: String
    var sourceKnowledgeIds: [String]
    var relevantConversations: [String]
    var crystallizedAt: Double
    var confidence: Double

    init(
        id: String = "wis-\(UUID().uuidString.prefix(8))",
        declaration: String,
        rationale: String,
        domain: String = "arch",
        sourceKnowledgeIds: [String] = [],
        relevantConversations: [String] = [],
        crystallizedAt: Double = Date().timeIntervalSince1970,
        confidence: Double = 0.95
    ) {
        self.id = id
        self.declaration = declaration
        self.rationale = rationale
        self.domain = domain
        self.sourceKnowledgeIds = sourceKnowledgeIds
        self.relevantConversations = relevantConversations
        self.crystallizedAt = crystallizedAt
        self.confidence = confidence
    }
}

struct TotemLegacyDeclaration: Identifiable, Codable {
    let id: String
    var principle: String
    var domain: String
    var originAphorismId: String
    var enshrinedAt: Double
    var invariant: Bool

    init(
        id: String = "leg-\(UUID().uuidString.prefix(8))",
        principle: String,
        domain: String = "arch",
        originAphorismId: String = "",
        enshrinedAt: Double = Date().timeIntervalSince1970,
        invariant: Bool = true
    ) {
        self.id = id
        self.principle = principle
        self.domain = domain
        self.originAphorismId = originAphorismId
        self.enshrinedAt = enshrinedAt
        self.invariant = invariant
    }
}

struct TotemAtlasCategory: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let keywords: [String]
}

struct TotemProfile: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var port: Int
    var host: String
    var modelIdentifier: String
    var defaultFilter: TotemFilterType
    var reasoningLevel: String // "Low", "Medium", "High", "Maximum"
    var temperature: Double
    var topP: Double
    var topK: Int
    var minP: Double
    var repeatPenalty: Double
    var presencePenalty: Double
    var frequencyPenalty: Double
    var contextLength: Int
    var seed: Int

    static let `default` = TotemProfile(
        id: BuildConfig.isBlank ? "totem-local-8080" : "totem-qwythos-8080",
        name: BuildConfig.isBlank ? "Local Model" : "Qwythos",
        port: 8080,
        host: BuildConfig.defaultEndpoint,
        modelIdentifier: BuildConfig.defaultModel,
        defaultFilter: .syntaxRegex,
        reasoningLevel: "High",
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        minP: 0.05,
        repeatPenalty: 1.1,
        presencePenalty: 0.0,
        frequencyPenalty: 0.0,
        contextLength: 32768,
        seed: -1
    )
}

// MARK: - Totem Port Listener & Biodynamic Consolidator Service

final class TotemPortListenerService: ObservableObject {
    static let shared = TotemPortListenerService()

    @Published var totems: [TotemProfile] = [TotemProfile.default]
    @Published var activeTotem: TotemProfile = TotemProfile.default
    @Published var activePort: Int = 8080
    @Published var activeFilter: TotemFilterType = .syntaxRegex
    @Published var totalTransactionsRecorded: Int = 0
    @Published var factsCount: Int = 0
    @Published var workingKnowledgeCount: Int = 0
    @Published var wisdomCount: Int = 0
    @Published var legacyCount: Int = 0
    @Published var lastConsolidatedAt: Date? = nil
    @Published var isConsolidating: Bool = false
    @Published var lastConsoleLog: String = "Totem Port Listener initialized on port 8080."

    func selectTotem(_ totem: TotemProfile) {
        self.activeTotem = totem
        self.activePort = totem.port
        self.activeFilter = totem.defaultFilter
        loadPersistedMemory(port: totem.port)
        persistTotems()
    }

    func saveTotem(_ totem: TotemProfile) {
        if let idx = totems.firstIndex(where: { $0.id == totem.id }) {
            totems[idx] = totem
        } else {
            totems.append(totem)
        }
        if activeTotem.id == totem.id {
            self.activeTotem = totem
            self.activePort = totem.port
            self.activeFilter = totem.defaultFilter
            loadPersistedMemory(port: totem.port)
        }
        persistTotems()
    }

    func deleteTotem(id: String) {
        guard totems.count > 1 else { return } // Keep at least one
        totems.removeAll { $0.id == id }
        if activeTotem.id == id, let first = totems.first {
            selectTotem(first)
        }
        persistTotems()
    }

    // Storage persistence keys
    private let totemsStorageKey = "offcoder_totem_profiles_v1"
    private let activeTotemIdKey = "offcoder_active_totem_id_v1"

    func persistTotems() {
        if let data = try? JSONEncoder().encode(totems) {
            UserDefaults.standard.set(data, forKey: totemsStorageKey)
        }
        UserDefaults.standard.set(activeTotem.id, forKey: activeTotemIdKey)
    }

    private func loadTotemsFromStorage() {
        if let data = UserDefaults.standard.data(forKey: totemsStorageKey),
           let list = try? JSONDecoder().decode([TotemProfile].self, from: data),
           !list.isEmpty {
            self.totems = list
            let savedActiveId = UserDefaults.standard.string(forKey: activeTotemIdKey)
            if let saved = list.first(where: { $0.id == savedActiveId }) {
                self.activeTotem = saved
            } else if let first = list.first {
                self.activeTotem = first
            }
            self.activePort = self.activeTotem.port
            self.activeFilter = self.activeTotem.defaultFilter
        } else {
            self.totems = [TotemProfile.default]
            self.activeTotem = TotemProfile.default
            self.activePort = TotemProfile.default.port
            self.activeFilter = TotemProfile.default.defaultFilter
        }
    }

    // In-memory Biodynamic stores
    var facts: [TotemFact] = []
    var workingKnowledge: [TotemWorkingKnowledge] = []
    var wisdom: [TotemWisdomAphorism] = []
    var legacy: [TotemLegacyDeclaration] = []

    private let fileManager = FileManager.default
    private let halfLifeSeconds: Double = 86400.0 * 7.0 // 7-day half life
    private let decayLambda: Double = log(2.0) / (86400.0 * 7.0)
    private let reinforcementBeta: Double = 0.35

    private init() {
        loadTotemsFromStorage()
        loadPersistedMemory(port: activePort)
    }

    /// Computes path to 'local records - <port>' folder in workspace
    func getLocalRecordsDir(port: Int? = nil) -> String {
        let p = port ?? activePort
        let baseDir = "/Users/stevenjackson/Documents/DEVELOPMENT/WILD CARD/inference offload"
        return (baseDir as NSString).appendingPathComponent("local records - \(p)")
    }

    /// Record a full raw API transaction for the chosen port
    func recordTransaction(
        port: Int,
        endpoint: String,
        model: String,
        requestPayload: [String: Any],
        responseContent: String,
        reasoningContent: String,
        toolCalls: [ToolCallItem],
        durationMs: Int
    ) {
        self.activePort = port
        let recordsDir = getLocalRecordsDir(port: port)
        let rawDir = (recordsDir as NSString).appendingPathComponent("raw")

        do {
            try fileManager.createDirectory(atPath: rawDir, withIntermediateDirectories: true, attributes: nil)

            let timestamp = Date().timeIntervalSince1970
            let isoDate = ISO8601DateFormatter().string(from: Date())

            // 1. Full Raw Transaction Entry
            let entry: [String: Any] = [
                "transaction_id": UUID().uuidString,
                "timestamp": timestamp,
                "iso_date": isoDate,
                "port": port,
                "endpoint": endpoint,
                "model": model,
                "duration_ms": durationMs,
                "request": requestPayload,
                "response": [
                    "content": responseContent,
                    "reasoning_content": reasoningContent,
                    "tool_calls": toolCalls.map { [
                        "id": $0.id,
                        "name": $0.name,
                        "arguments": $0.arguments,
                        "output": $0.output ?? "",
                        "status": $0.status.rawValue
                    ]}
                ]
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: entry, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let jsonlPath = (rawDir as NSString).appendingPathComponent("raw_transactions.jsonl")
                if fileManager.fileExists(atPath: jsonlPath) {
                    if let handle = FileHandle(forWritingAtPath: jsonlPath) {
                        handle.seekToEndOfFile()
                        if let lineData = (jsonString + "\n").data(using: .utf8) {
                            handle.write(lineData)
                        }
                        try? handle.close()
                    }
                } else {
                    try? (jsonString + "\n").write(toFile: jsonlPath, atomically: true, encoding: .utf8)
                }
            }

            DispatchQueue.main.async {
                self.totalTransactionsRecorded += 1
                self.lastConsoleLog = "Recorded raw API transaction on port \(port) (\(durationMs)ms)"
            }

            // 2. Filter & Consolidate Memory
            applyModularFilter(
                request: requestPayload,
                response: responseContent,
                reasoning: reasoningContent,
                toolCalls: toolCalls
            )

            // 3. Save Biodynamic Memory state
            persistBiodynamicMemory(port: port)

        } catch {
            DispatchQueue.main.async {
                self.lastConsoleLog = "Error writing to local records - \(port): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Modular Filter System

    func applyModularFilter(
        request: [String: Any],
        response: String,
        reasoning: String,
        toolCalls: [ToolCallItem]
    ) {
        let userPrompt: String = {
            if let msgs = request["messages"] as? [[String: Any]],
               let lastUser = msgs.last(where: { ($0["role"] as? String) == "user" }) {
                return (lastUser["content"] as? String) ?? ""
            }
            return ""
        }()

        switch activeFilter {
        case .syntaxRegex:
            filterSyntaxRegex(userPrompt: userPrompt, response: response, reasoning: reasoning, toolCalls: toolCalls)
        case .semanticHeuristic:
            filterSemanticHeuristic(userPrompt: userPrompt, response: response, reasoning: reasoning)
        case .apiTransaction:
            filterApiTransactions(userPrompt: userPrompt, response: response, toolCalls: toolCalls)
        case .rawPassthrough:
            filterRawPassthrough(userPrompt: userPrompt, response: response, reasoning: reasoning)
        case .biodynamicAtlas:
            filterBiodynamicAtlas(userPrompt: userPrompt, response: response, reasoning: reasoning)
        }
    }

    private func filterSyntaxRegex(userPrompt: String, response: String, reasoning: String, toolCalls: [ToolCallItem]) {
        // Extract Invariants, Rules, Requirements
        let lines = (response + "\n" + reasoning).components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().starts(with: "invariant:") ||
               trimmed.lowercased().starts(with: "rule:") ||
               trimmed.lowercased().starts(with: "principle:") ||
               trimmed.lowercased().starts(with: "# architecture:") {
                let fact = TotemFact(content: trimmed, domain: "arch", tags: ["syntax_rule", "invariant"])
                facts.append(fact)
            }
        }

        // Record tool calls as operational facts
        for tc in toolCalls {
            let tcFact = TotemFact(
                content: "Executed tool \(tc.name) [Status: \(tc.status.rawValue)]",
                domain: "ops",
                tags: ["tool_execution", tc.name]
            )
            facts.append(tcFact)
        }

        // Synthesize Working Knowledge
        if !userPrompt.isEmpty && !response.isEmpty {
            let title = String(userPrompt.prefix(50))
            let summary = String(response.prefix(200))
            let wk = TotemWorkingKnowledge(
                title: title,
                semanticSummary: summary,
                domain: "arch",
                originSeed: userPrompt,
                journeyTrace: ["session_\(Int(Date().timeIntervalSince1970))"],
                tags: ["syntax_distilled"]
            )
            workingKnowledge.append(wk)
        }
    }

    private func filterSemanticHeuristic(userPrompt: String, response: String, reasoning: String) {
        if !userPrompt.isEmpty {
            let fact = TotemFact(content: "User Goal: \(userPrompt)", domain: "heuristics", tags: ["intent"])
            facts.append(fact)
        }
        if !reasoning.isEmpty {
            let wk = TotemWorkingKnowledge(
                title: "Heuristic: \(String(userPrompt.prefix(40)))",
                semanticSummary: String(reasoning.prefix(250)),
                domain: "heuristics",
                originSeed: userPrompt,
                journeyTrace: ["heuristic_turn"],
                tags: ["heuristic_trace"]
            )
            workingKnowledge.append(wk)
        }
    }

    private func filterApiTransactions(userPrompt: String, response: String, toolCalls: [ToolCallItem]) {
        for tc in toolCalls {
            let fact = TotemFact(
                content: "API Tool Call: \(tc.name) with args \(String(tc.arguments.prefix(100)))",
                domain: "ops",
                tags: ["api", tc.name]
            )
            facts.append(fact)
        }
        let wk = TotemWorkingKnowledge(
            title: "API Action Turn (\(toolCalls.count) tools)",
            semanticSummary: "Response snippet: \(String(response.prefix(180)))",
            domain: "ops",
            originSeed: userPrompt,
            tags: ["api_transaction"]
        )
        workingKnowledge.append(wk)
    }

    private func filterRawPassthrough(userPrompt: String, response: String, reasoning: String) {
        let fact = TotemFact(content: "Turn Input: \(userPrompt)", domain: "domain", tags: ["raw_in"])
        facts.append(fact)
        let wk = TotemWorkingKnowledge(
            title: "Raw Turn Observation",
            semanticSummary: "Model replied: \(String(response.prefix(200)))",
            domain: "domain",
            originSeed: userPrompt,
            tags: ["raw_observation"]
        )
        workingKnowledge.append(wk)
    }

    private func filterBiodynamicAtlas(userPrompt: String, response: String, reasoning: String) {
        let fullText = (userPrompt + " " + response + " " + reasoning).lowercased()
        let domain: String
        if fullText.contains("arch") || fullText.contains("module") || fullText.contains("pattern") {
            domain = "arch"
        } else if fullText.contains("cli") || fullText.contains("terminal") || fullText.contains("build") || fullText.contains("test") {
            domain = "ops"
        } else if fullText.contains("style") || fullText.contains("ui") || fullText.contains("preference") {
            domain = "heuristics"
        } else {
            domain = "domain"
        }

        let fact = TotemFact(content: String(response.prefix(150)), domain: domain, tags: ["atlas_routed"])
        facts.append(fact)

        let wk = TotemWorkingKnowledge(
            title: "Atlas [\(domain.uppercased())]: \(String(userPrompt.prefix(40)))",
            semanticSummary: String(reasoning.isEmpty ? response.prefix(180) : reasoning.prefix(180)),
            domain: domain,
            originSeed: userPrompt,
            tags: ["atlas", domain]
        )
        workingKnowledge.append(wk)
    }

    // MARK: - Biodynamic Consolidation Engine (Whitepaper Equations)

    func runConsolidation() {
        isConsolidating = true
        let now = Date().timeIntervalSince1970

        // 1. Update Neuromorphic Synaptic Salience S(t)
        for idx in 0..<workingKnowledge.count {
            let elapsed = max(0.0, now - workingKnowledge[idx].lastReinforcedAt)
            let decayFactor = exp(-decayLambda * elapsed)
            let reinforcementMultiplier = 1.0 + log(1.0 + reinforcementBeta * Double(workingKnowledge[idx].reinforcementCount))
            workingKnowledge[idx].salienceScore = max(0.01, min(10.0, workingKnowledge[idx].salienceScore * decayFactor * reinforcementMultiplier))
        }

        // 2. Evaluate Wisdom Crystallization Gate (Phi_Wisdom)
        // Rule: R >= 3 AND unique_sessions >= 2 AND summary.count >= 15
        for wk in workingKnowledge {
            let uniqueSessions = Set(wk.journeyTrace).count
            let isReady = wk.reinforcementCount >= 2 && wk.semanticSummary.count >= 15
            let alreadyCrystallized = wisdom.contains(where: { $0.sourceKnowledgeIds.contains(wk.id) })

            if isReady && !alreadyCrystallized {
                let aphorism = TotemWisdomAphorism(
                    declaration: "Principle: \(wk.title.trimmingCharacters(in: CharacterSet(charactersIn: "."))). \(String(wk.semanticSummary.prefix(120)))",
                    rationale: "Distilled across \(uniqueSessions) sessions with \(wk.reinforcementCount) reinforcements.",
                    domain: wk.domain,
                    sourceKnowledgeIds: [wk.id],
                    relevantConversations: wk.journeyTrace,
                    crystallizedAt: now,
                    confidence: 0.95
                )
                wisdom.append(aphorism)

                // 3. Evaluate Legacy Invariant Enshrinement Gate (Phi_Legacy)
                // Rule: unique_sessions >= 3 AND confidence >= 0.90
                if uniqueSessions >= 2 && aphorism.confidence >= 0.90 {
                    let alreadyEnshrined = legacy.contains(where: { $0.originAphorismId == aphorism.id })
                    if !alreadyEnshrined {
                        let legacyItem = TotemLegacyDeclaration(
                            principle: aphorism.declaration,
                            domain: aphorism.domain,
                            originAphorismId: aphorism.id,
                            enshrinedAt: now,
                            invariant: true
                        )
                        legacy.append(legacyItem)
                    }
                }
            }
        }

        persistBiodynamicMemory(port: activePort)

        DispatchQueue.main.async {
            self.lastConsolidatedAt = Date()
            self.factsCount = self.facts.count
            self.workingKnowledgeCount = self.workingKnowledge.count
            self.wisdomCount = self.wisdom.count
            self.legacyCount = self.legacy.count
            self.isConsolidating = false
            self.lastConsoleLog = "Biodynamic consolidation complete: \(self.wisdomCount) Wisdom, \(self.legacyCount) Legacy invariants."
        }
    }

    // MARK: - Persistence to 'local records - <port>'

    private func persistBiodynamicMemory(port: Int) {
        let recordsDir = getLocalRecordsDir(port: port)
        let bioDir = (recordsDir as NSString).appendingPathComponent("biodynamic")

        try? fileManager.createDirectory(atPath: bioDir, withIntermediateDirectories: true, attributes: nil)

        // 1. Facts JSONL
        let factsPath = (bioDir as NSString).appendingPathComponent("facts.jsonl")
        let factsContent = facts.compactMap { fact -> String? in
            guard let data = try? JSONEncoder().encode(fact),
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        }.joined(separator: "\n")
        try? factsContent.write(toFile: factsPath, atomically: true, encoding: .utf8)

        // 2. Working Knowledge JSON
        let wkPath = (bioDir as NSString).appendingPathComponent("working_knowledge.json")
        if let data = try? JSONEncoder().encode(workingKnowledge) {
            try? data.write(to: URL(fileURLWithPath: wkPath))
        }

        // 3. Wisdom JSON
        let wisPath = (bioDir as NSString).appendingPathComponent("wisdom.json")
        if let data = try? JSONEncoder().encode(wisdom) {
            try? data.write(to: URL(fileURLWithPath: wisPath))
        }

        // 4. Legacy JSON
        let legPath = (bioDir as NSString).appendingPathComponent("legacy.json")
        if let data = try? JSONEncoder().encode(legacy) {
            try? data.write(to: URL(fileURLWithPath: legPath))
        }

        // 5. Atlas Categorical Index
        let atlasPath = (bioDir as NSString).appendingPathComponent("atlas.json")
        let atlasCategories: [TotemAtlasCategory] = [
            TotemAtlasCategory(id: "arch", name: "Architecture & Systems", description: "Structural invariants & contracts", keywords: ["architecture", "module", "api", "database"]),
            TotemAtlasCategory(id: "ops", name: "Operations & Execution", description: "CLI, build pipelines, test suites", keywords: ["cli", "terminal", "build", "tooling"]),
            TotemAtlasCategory(id: "heuristics", name: "Cognitive Heuristics", description: "User preferences and ergonomics", keywords: ["preference", "style", "ui", "tone"]),
            TotemAtlasCategory(id: "domain", name: "Domain Knowledge", description: "Specialized algorithmic invariants", keywords: ["algorithm", "inference", "memory", "math"])
        ]
        if let data = try? JSONEncoder().encode(atlasCategories) {
            try? data.write(to: URL(fileURLWithPath: atlasPath))
        }

        // 6. Synthesized MEMORY.md (Whitepaper Section 4.2 Format)
        let memoryMdPath = (recordsDir as NSString).appendingPathComponent("MEMORY.md")
        let synthesizedPromptContext = generateSynthesizedContext()
        try? synthesizedPromptContext.write(toFile: memoryMdPath, atomically: true, encoding: .utf8)

        // Also duplicate to active project dir if present
        if let activeProjectDir = CodebaseHarnessService.shared.activeProjectDir {
            let projectLocalRecords = (activeProjectDir as NSString).appendingPathComponent("local records - \(port)")
            let projectMemMd = (projectLocalRecords as NSString).appendingPathComponent("MEMORY.md")
            try? fileManager.createDirectory(atPath: projectLocalRecords, withIntermediateDirectories: true, attributes: nil)
            try? synthesizedPromptContext.write(toFile: projectMemMd, atomically: true, encoding: .utf8)
        }
    }

    /// Generates high-density context according to Section 4.2 of the Totem Biodynamic Whitepaper
    func generateSynthesizedContext() -> String {
        var sections: [String] = []

        // Header
        sections.append("""
# Totem Biodynamic Memory Ledger (Port \(activePort))
**Last Consolidated**: \(ISO8601DateFormatter().string(from: Date()))
**Active Filter**: \(activeFilter.rawValue)
""")

        // 1. Top-Level Immutable Legacy Invariants
        if !legacy.isEmpty {
            let lines = legacy.map { "• \($0.principle)" }
            sections.append("### 🏛️ Totem Legacy Invariants:\n" + lines.joined(separator: "\n"))
        }

        // 2. Overriding Distilled Wisdom Principles
        if !wisdom.isEmpty {
            let lines = wisdom.prefix(5).map { "• \($0.declaration)\n  *(Rationale: \($0.rationale))*" }
            sections.append("### 📜 Distilled Wisdom Principles:\n" + lines.joined(separator: "\n"))
        }

        // 3. Active Working Knowledge (Ranked by Synaptic Salience)
        if !workingKnowledge.isEmpty {
            let sortedWk = workingKnowledge.sorted(by: { $0.salienceScore > $1.salienceScore }).prefix(4)
            let lines = sortedWk.map { "**[\($0.title)]** (Domain: \($0.domain), Salience: \(String(format: "%.2f", $0.salienceScore)))\n\($0.semanticSummary)" }
            sections.append("### 🧠 Active Working Knowledge & Relational Context:\n" + lines.joined(separator: "\n\n"))
        }

        // 4. Verified Facts
        if !facts.isEmpty {
            let recent = facts.suffix(6).map { "• [\($0.domain.uppercased())] \($0.content)" }
            sections.append("### 📌 Verified Ground Truth Facts:\n" + recent.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    /// Appends a project to Qwythos's pathname map: lands in the totem facts
    /// ledger (facts.jsonl) and the synthesized MEMORY.md prompt context.
    func recordProjectPathname(name: String, pathname: String, mediaBucket: String? = nil) {
        var content = "PROJECT PATHNAME MAP: \(name) = \(pathname)"
        if let mediaBucket {
            content += " | media bucket: \(mediaBucket)"
        }
        let fact = TotemFact(content: content, domain: "arch")
        facts.append(fact)
        persistBiodynamicMemory(port: activePort)

        DispatchQueue.main.async {
            self.factsCount = self.facts.count
            self.lastConsoleLog = "Project registered in pathname map: \(name) → \(pathname)"
        }
    }

    func loadPersistedMemory(port: Int? = nil) {
        let p = port ?? activePort
        let recordsDir = getLocalRecordsDir(port: p)
        let bioDir = (recordsDir as NSString).appendingPathComponent("biodynamic")

        facts.removeAll()
        workingKnowledge.removeAll()
        wisdom.removeAll()
        legacy.removeAll()

        // Load facts
        let factsPath = (bioDir as NSString).appendingPathComponent("facts.jsonl")
        if let data = try? String(contentsOfFile: factsPath, encoding: .utf8) {
            let lines = data.components(separatedBy: .newlines).filter { !$0.isEmpty }
            facts = lines.compactMap { line in
                guard let d = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(TotemFact.self, from: d)
            }
        }

        // Load working knowledge
        let wkPath = (bioDir as NSString).appendingPathComponent("working_knowledge.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: wkPath)),
           let list = try? JSONDecoder().decode([TotemWorkingKnowledge].self, from: data) {
            workingKnowledge = list
        }

        // Load wisdom
        let wisPath = (bioDir as NSString).appendingPathComponent("wisdom.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: wisPath)),
           let list = try? JSONDecoder().decode([TotemWisdomAphorism].self, from: data) {
            wisdom = list
        }

        // Load legacy
        let legPath = (bioDir as NSString).appendingPathComponent("legacy.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: legPath)),
           let list = try? JSONDecoder().decode([TotemLegacyDeclaration].self, from: data) {
            legacy = list
        }

        DispatchQueue.main.async {
            self.factsCount = self.facts.count
            self.workingKnowledgeCount = self.workingKnowledge.count
            self.wisdomCount = self.wisdom.count
            self.legacyCount = self.legacy.count
        }
    }

    /// Opens the memory folder ('local records - <port>') in macOS Finder and ensures MEMORY.md and directories exist
    func openLocalRecordsFolder(port: Int? = nil) {
        let p = port ?? activePort
        let path = getLocalRecordsDir(port: p)
        let bioDir = (path as NSString).appendingPathComponent("biodynamic")
        let rawDir = (path as NSString).appendingPathComponent("raw")

        try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(atPath: bioDir, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(atPath: rawDir, withIntermediateDirectories: true, attributes: nil)

        // Ensure MEMORY.md exists so Qwythos has immediate durable memory on boot through this totem port
        let memMdPath = (path as NSString).appendingPathComponent("MEMORY.md")
        if !fileManager.fileExists(atPath: memMdPath) {
            let initialContext = generateSynthesizedContext()
            try? initialContext.write(toFile: memMdPath, atomically: true, encoding: .utf8)
        }

        let folderUrl = URL(fileURLWithPath: path)
        if !NSWorkspace.shared.open(folderUrl) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        }

        DispatchQueue.main.async {
            self.lastConsoleLog = "Opened memory folder for port \(p) in Finder: local records - \(p)"
        }
    }
}
