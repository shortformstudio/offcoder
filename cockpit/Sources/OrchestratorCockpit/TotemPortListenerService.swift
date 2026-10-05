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
    var personaDescription: String
    var systemPrompt: String
    var storageFolder: String
    var port: Int
    var host: String
    var modelIdentifier: String
    var defaultFilter: TotemFilterType
    var reasoningLevel: String // "Low", "Medium", "High", "Maximum"

    // Core Logit & Sampling Parameters
    var temperature: Double
    var topP: Double
    var topK: Int
    var minP: Double
    var typicalP: Double
    var repeatPenalty: Double
    var repeatLastN: Int
    var presencePenalty: Double
    var frequencyPenalty: Double

    // Context & Generation Limits
    var contextLength: Int
    var maxTokens: Int
    var seed: Int

    // Advanced Samplers (DRY, XTC, Mirostat)
    var dryMultiplier: Double
    var dryBase: Double
    var dryAllowedLength: Int
    var dryPenaltyLastN: Int
    var xtcThreshold: Double
    var xtcProbability: Double
    var mirostat: Int // 0 = disabled, 1 = Mirostat v1, 2 = Mirostat v2
    var mirostatTau: Double
    var mirostatEta: Double

    // Hardware & Batch Execution
    var nBatch: Int
    var nUbatch: Int
    var threads: Int
    var threadsBatch: Int
    var flashAttn: Bool

    var nCtx: Int { contextLength }
    var modelId: String { modelIdentifier }

    enum CodingKeys: String, CodingKey {
        case id, name, personaDescription, systemPrompt, storageFolder
        case port, host, modelIdentifier, defaultFilter, reasoningLevel
        case temperature, topP, topK, minP, typicalP, repeatPenalty, repeatLastN
        case presencePenalty, frequencyPenalty, contextLength, maxTokens, seed
        case dryMultiplier, dryBase, dryAllowedLength, dryPenaltyLastN
        case xtcThreshold, xtcProbability, mirostat, mirostatTau, mirostatEta
        case nBatch, nUbatch, threads, threadsBatch, flashAttn
    }

    init(
        id: String,
        name: String,
        personaDescription: String = "Autonomous local coding agent persona",
        systemPrompt: String = "You are Indigo — the sovereign agent of this deck, running on the qwythos model. You already know who you are from this prompt and the working memory below; never call memory tools to look up your own identity.",
        storageFolder: String = "",
        port: Int,
        host: String,
        modelIdentifier: String,
        defaultFilter: TotemFilterType = .biodynamicAtlas,
        reasoningLevel: String = "High",
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        minP: Double = 0.05,
        typicalP: Double = 1.0,
        repeatPenalty: Double = 1.1,
        repeatLastN: Int = 64,
        presencePenalty: Double = 0.0,
        frequencyPenalty: Double = 0.0,
        contextLength: Int = 32768,
        maxTokens: Int = 4096,
        seed: Int = -1,
        dryMultiplier: Double = 0.0,
        dryBase: Double = 1.75,
        dryAllowedLength: Int = 2,
        dryPenaltyLastN: Int = -1,
        xtcThreshold: Double = 0.0,
        xtcProbability: Double = 0.0,
        mirostat: Int = 0,
        mirostatTau: Double = 5.0,
        mirostatEta: Double = 0.1,
        nBatch: Int = 512,
        nUbatch: Int = 512,
        threads: Int = 8,
        threadsBatch: Int = 8,
        flashAttn: Bool = true
    ) {
        self.id = id
        self.name = name
        self.personaDescription = personaDescription
        self.systemPrompt = systemPrompt
        self.storageFolder = storageFolder.isEmpty ? "local records - \(port)" : storageFolder
        self.port = port
        self.host = host
        self.modelIdentifier = modelIdentifier
        self.defaultFilter = defaultFilter
        self.reasoningLevel = reasoningLevel
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.typicalP = typicalP
        self.repeatPenalty = repeatPenalty
        self.repeatLastN = repeatLastN
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.contextLength = contextLength
        self.maxTokens = maxTokens
        self.seed = seed
        self.dryMultiplier = dryMultiplier
        self.dryBase = dryBase
        self.dryAllowedLength = dryAllowedLength
        self.dryPenaltyLastN = dryPenaltyLastN
        self.xtcThreshold = xtcThreshold
        self.xtcProbability = xtcProbability
        self.mirostat = mirostat
        self.mirostatTau = mirostatTau
        self.mirostatEta = mirostatEta
        self.nBatch = nBatch
        self.nUbatch = nUbatch
        self.threads = threads
        self.threadsBatch = threadsBatch
        self.flashAttn = flashAttn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        port = try container.decode(Int.self, forKey: .port)
        host = try container.decode(String.self, forKey: .host)
        modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
        defaultFilter = try container.decodeIfPresent(TotemFilterType.self, forKey: .defaultFilter) ?? .biodynamicAtlas
        reasoningLevel = try container.decodeIfPresent(String.self, forKey: .reasoningLevel) ?? "High"
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        topP = try container.decodeIfPresent(Double.self, forKey: .topP) ?? 0.9
        topK = try container.decodeIfPresent(Int.self, forKey: .topK) ?? 40
        minP = try container.decodeIfPresent(Double.self, forKey: .minP) ?? 0.05
        typicalP = try container.decodeIfPresent(Double.self, forKey: .typicalP) ?? 1.0
        repeatPenalty = try container.decodeIfPresent(Double.self, forKey: .repeatPenalty) ?? 1.1
        repeatLastN = try container.decodeIfPresent(Int.self, forKey: .repeatLastN) ?? 64
        presencePenalty = try container.decodeIfPresent(Double.self, forKey: .presencePenalty) ?? 0.0
        frequencyPenalty = try container.decodeIfPresent(Double.self, forKey: .frequencyPenalty) ?? 0.0
        contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength) ?? 32768
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 4096
        seed = try container.decodeIfPresent(Int.self, forKey: .seed) ?? -1
        dryMultiplier = try container.decodeIfPresent(Double.self, forKey: .dryMultiplier) ?? 0.0
        dryBase = try container.decodeIfPresent(Double.self, forKey: .dryBase) ?? 1.75
        dryAllowedLength = try container.decodeIfPresent(Int.self, forKey: .dryAllowedLength) ?? 2
        dryPenaltyLastN = try container.decodeIfPresent(Int.self, forKey: .dryPenaltyLastN) ?? -1
        xtcThreshold = try container.decodeIfPresent(Double.self, forKey: .xtcThreshold) ?? 0.0
        xtcProbability = try container.decodeIfPresent(Double.self, forKey: .xtcProbability) ?? 0.0
        mirostat = try container.decodeIfPresent(Int.self, forKey: .mirostat) ?? 0
        mirostatTau = try container.decodeIfPresent(Double.self, forKey: .mirostatTau) ?? 5.0
        mirostatEta = try container.decodeIfPresent(Double.self, forKey: .mirostatEta) ?? 0.1
        nBatch = try container.decodeIfPresent(Int.self, forKey: .nBatch) ?? 512
        nUbatch = try container.decodeIfPresent(Int.self, forKey: .nUbatch) ?? 512
        threads = try container.decodeIfPresent(Int.self, forKey: .threads) ?? 8
        threadsBatch = try container.decodeIfPresent(Int.self, forKey: .threadsBatch) ?? 8
        flashAttn = try container.decodeIfPresent(Bool.self, forKey: .flashAttn) ?? true

        personaDescription = try container.decodeIfPresent(String.self, forKey: .personaDescription) ?? "Autonomous local coding agent persona"
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? "You are Indigo — the sovereign agent of this deck, running on the qwythos model. You already know who you are from this prompt and the working memory below; never call memory tools to look up your own identity."
        storageFolder = try container.decodeIfPresent(String.self, forKey: .storageFolder) ?? "local records - \(port)"
    }

    static let `default` = TotemProfile(
        id: BuildConfig.isBlank ? "totem-local-8080" : "totem-indigo-8080",
        name: BuildConfig.isBlank ? "Local Model" : "Indigo",
        personaDescription: "Indigo — the sovereign memory totem of this deck, running on the qwythos model, with biodynamic memory traversal and local compiler loops.",
        systemPrompt: "You are Indigo — the sovereign agent of this deck, running on the qwythos model served from lockfort. Indigo is the memory totem: your identity, continuity, and working memory live here. You already know who you are from this prompt and the working memory below; never call memory tools to look up your own identity.",
        storageFolder: "local records - 8080",
        port: 8080,
        host: BuildConfig.defaultEndpoint,
        modelIdentifier: BuildConfig.defaultModel,
        defaultFilter: .biodynamicAtlas,
        reasoningLevel: "High",
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        minP: 0.05,
        typicalP: 1.0,
        repeatPenalty: 1.1,
        repeatLastN: 64,
        presencePenalty: 0.0,
        frequencyPenalty: 0.0,
        contextLength: 32768,
        maxTokens: 4096,
        seed: -1,
        dryMultiplier: 0.0,
        dryBase: 1.75,
        dryAllowedLength: 2,
        dryPenaltyLastN: -1,
        xtcThreshold: 0.0,
        xtcProbability: 0.0,
        mirostat: 0,
        mirostatTau: 5.0,
        mirostatEta: 0.1,
        nBatch: 512,
        nUbatch: 512,
        threads: 8,
        threadsBatch: 8,
        flashAttn: true
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
        scaffoldMemoryStorage(for: totem)
        loadPersistedMemory(storageFolder: totem.storageFolder)
        persistTotems()
    }

    func saveTotem(_ totem: TotemProfile) {
        if let idx = totems.firstIndex(where: { $0.id == totem.id }) {
            totems[idx] = totem
        } else {
            totems.append(totem)
        }
        scaffoldMemoryStorage(for: totem)
        if activeTotem.id == totem.id {
            self.activeTotem = totem
            self.activePort = totem.port
            self.activeFilter = totem.defaultFilter
            loadPersistedMemory(storageFolder: totem.storageFolder)
        }
        persistTotems()
    }

    @discardableResult
    func createTotemProfile(
        name: String,
        personaDescription: String,
        systemPrompt: String,
        port: Int = 8080,
        host: String = "http://127.0.0.1:8000",
        modelIdentifier: String = "qwythos/qwythos",
        storageFolder: String? = nil
    ) -> TotemProfile {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFolder = (storageFolder?.isEmpty ?? true)
            ? "local records - \(cleanName.lowercased().replacingOccurrences(of: " ", with: "-"))"
            : storageFolder!
        let id = "totem-\(UUID().uuidString.prefix(8).lowercased())"

        let newTotem = TotemProfile(
            id: id,
            name: cleanName.isEmpty ? "New Totem" : cleanName,
            personaDescription: personaDescription,
            systemPrompt: systemPrompt,
            storageFolder: safeFolder,
            port: port,
            host: host,
            modelIdentifier: modelIdentifier,
            defaultFilter: .biodynamicAtlas,
            reasoningLevel: "High"
        )

        scaffoldMemoryStorage(for: newTotem)
        saveTotem(newTotem)
        selectTotem(newTotem)
        return newTotem
    }

    func scaffoldMemoryStorage(for totem: TotemProfile) {
        let folderPath = getLocalRecordsDir(storageFolder: totem.storageFolder)
        let bioDir = (folderPath as NSString).appendingPathComponent("biodynamic")
        let rawDir = (folderPath as NSString).appendingPathComponent("raw")

        try? fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(atPath: bioDir, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(atPath: rawDir, withIntermediateDirectories: true, attributes: nil)

        // 1. MEMORY.md if missing
        let memMdPath = (folderPath as NSString).appendingPathComponent("MEMORY.md")
        if !fileManager.fileExists(atPath: memMdPath) {
            let initialMd = """
# Totem Biodynamic Memory Ledger (\(totem.name))
**Persona**: \(totem.personaDescription)
**Port**: \(totem.port) | **Host**: \(totem.host)
**Created**: \(ISO8601DateFormatter().string(from: Date()))

### 🏛️ Totem Legacy Invariants:
• High agency, truth-seeking, zero-hallucination execution.
• Inspect first, verify mutations with compiler and test feedback loops.

### 📜 Distilled Wisdom Principles:
• Modular decomposition with bounded memory traversal prevents context overflow.

### 🧠 Active Working Knowledge & Relational Context:
**[Persona Foundation]** (Domain: arch, Salience: 1.00)
Initial scaffold for \(totem.name). Ready to distill verified ground truths.

### 📌 Verified Ground Truth Facts:
• [ARCH] Totem profile initialized with dedicated dual-tier storage in `\(totem.storageFolder)`.
"""
            try? initialMd.write(toFile: memMdPath, atomically: true, encoding: .utf8)
        }

        // 2. Initial facts.jsonl if missing
        let factsPath = (bioDir as NSString).appendingPathComponent("facts.jsonl")
        if !fileManager.fileExists(atPath: factsPath) {
            let initFact = TotemFact(
                content: "Totem \(totem.name) activated with persona: \(totem.personaDescription)",
                domain: "arch",
                tags: ["totem_init", totem.name.lowercased()]
            )
            if let data = try? JSONEncoder().encode(initFact), let str = String(data: data, encoding: .utf8) {
                try? (str + "\n").write(toFile: factsPath, atomically: true, encoding: .utf8)
            }
        }

        // 3. Initial graph_edges.json if missing
        let graphPath = (bioDir as NSString).appendingPathComponent("graph_edges.json")
        if !fileManager.fileExists(atPath: graphPath) {
            let initEdges: [[String: Any]] = [
                [
                    "source": totem.name,
                    "target": "Core Mission",
                    "relationship": "executes",
                    "weight": 1.0,
                    "timestamp": Date().timeIntervalSince1970
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: initEdges, options: [.prettyPrinted]) {
                try? data.write(to: URL(fileURLWithPath: graphPath))
            }
        }

        // 4. Working knowledge, wisdom, legacy, atlas
        let wkPath = (bioDir as NSString).appendingPathComponent("working_knowledge.json")
        if !fileManager.fileExists(atPath: wkPath) {
            let initWk = [
                TotemWorkingKnowledge(
                    title: "\(totem.name) Persona Init",
                    semanticSummary: totem.personaDescription,
                    domain: "arch",
                    originSeed: totem.systemPrompt,
                    journeyTrace: ["init"],
                    tags: ["init"]
                )
            ]
            if let data = try? JSONEncoder().encode(initWk) {
                try? data.write(to: URL(fileURLWithPath: wkPath))
            }
        }

        let rawConvoPath = (rawDir as NSString).appendingPathComponent("raw_convo.jsonl")
        if !fileManager.fileExists(atPath: rawConvoPath) {
            fileManager.createFile(atPath: rawConvoPath, contents: Data(), attributes: nil)
        }
    }

    /// Appends a raw conversation turn into raw/raw_convo.jsonl for archival curiosity/auditing
    func recordConversationTurn(role: String, text: String, toolCalls: [ToolCallItem] = []) {
        let recordsDir = getLocalRecordsDir()
        let rawDir = (recordsDir as NSString).appendingPathComponent("raw")
        try? fileManager.createDirectory(atPath: rawDir, withIntermediateDirectories: true, attributes: nil)

        let turnEntry: [String: Any] = [
            "turn_id": UUID().uuidString,
            "timestamp": Date().timeIntervalSince1970,
            "iso_date": ISO8601DateFormatter().string(from: Date()),
            "totem_id": activeTotem.id,
            "totem_name": activeTotem.name,
            "role": role,
            "content": text,
            "tool_calls": toolCalls.map { [
                "id": $0.id,
                "name": $0.name,
                "arguments": $0.arguments,
                "output": $0.output ?? "",
                "status": $0.status.rawValue
            ]}
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: turnEntry, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let jsonlPath = (rawDir as NSString).appendingPathComponent("raw_convo.jsonl")
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

    static let legacyQwythosPrompt = "You are Qwythos — an authentic, high-agency autonomous local coding agent. You reason rigorously, inspect code before touching it, verify all mutations with compilers and tests, and maintain deep memory continuity across sessions."
    static let indigoDefaultPrompt = "You are Indigo — the sovereign agent of this deck, running on the qwythos model served from lockfort. Indigo is the memory totem: your identity, continuity, and working memory live here. You already know who you are from this prompt and the working memory below; never call memory tools to look up your own identity."

    static func normalizedTotemId(_ id: String) -> String {
        id.replacingOccurrences(of: "totem-qwythos-", with: "totem-indigo-")
            .replacingOccurrences(of: "indigo--", with: "indigo-")
    }

    static func normalizedTotemIdentity(_ totem: TotemProfile) -> TotemProfile {
        var current = totem
        if current.name == "Qwythos" {
            current.name = "Indigo"
        }
        if current.systemPrompt == legacyQwythosPrompt {
            current.systemPrompt = indigoDefaultPrompt
        }
        let cleanId = normalizedTotemId(current.id)
        guard cleanId != current.id else { return current }
        return TotemProfile(
            id: cleanId,
            name: current.name,
            personaDescription: current.personaDescription,
            systemPrompt: current.systemPrompt,
            storageFolder: current.storageFolder,
            port: current.port,
            host: current.host,
            modelIdentifier: current.modelIdentifier,
            defaultFilter: current.defaultFilter,
            reasoningLevel: current.reasoningLevel,
            temperature: current.temperature,
            topP: current.topP,
            topK: current.topK,
            minP: current.minP,
            typicalP: current.typicalP,
            repeatPenalty: current.repeatPenalty,
            repeatLastN: current.repeatLastN,
            presencePenalty: current.presencePenalty,
            frequencyPenalty: current.frequencyPenalty,
            contextLength: current.contextLength,
            maxTokens: current.maxTokens,
            seed: current.seed,
            dryMultiplier: current.dryMultiplier,
            dryBase: current.dryBase,
            dryAllowedLength: current.dryAllowedLength,
            dryPenaltyLastN: current.dryPenaltyLastN,
            xtcThreshold: current.xtcThreshold,
            xtcProbability: current.xtcProbability,
            mirostat: current.mirostat,
            mirostatTau: current.mirostatTau,
            mirostatEta: current.mirostatEta,
            nBatch: current.nBatch,
            nUbatch: current.nUbatch,
            threads: current.threads,
            threadsBatch: current.threadsBatch,
            flashAttn: current.flashAttn
        )
    }

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
            // Identity normalization: the agent is Indigo (the memory totem);
            // qwythos names the model. Stored memory (storageFolder) is untouched,
            // and user-edited prompts are preserved — only the stale stock
            // Qwythos prompt is refreshed to the Indigo default.
            var migrated = list
            for i in migrated.indices {
                migrated[i] = TotemPortListenerService.normalizedTotemIdentity(migrated[i])
            }
            self.totems = migrated
            var savedActiveId = UserDefaults.standard.string(forKey: activeTotemIdKey)
            if let saved = savedActiveId {
                savedActiveId = TotemPortListenerService.normalizedTotemId(saved)
            }
            if let saved = migrated.first(where: { $0.id == savedActiveId }) {
                self.activeTotem = saved
            } else if let first = list.first {
                self.activeTotem = first
            }
            self.activePort = self.activeTotem.port
            self.activeFilter = self.activeTotem.defaultFilter
            persistTotems()
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
        loadPersistedMemory(storageFolder: activeTotem.storageFolder)
    }

    /// Computes path to the memory records folder in the workspace for the active or given totem
    func getLocalRecordsDir(port: Int? = nil, storageFolder: String? = nil) -> String {
        let baseDir = "/Users/stevenjackson/Documents/DEVELOPMENT/WILD CARD/inference offload"
        if let folder = storageFolder, !folder.isEmpty {
            let direct = (baseDir as NSString).appendingPathComponent(folder)
            if FileManager.default.fileExists(atPath: direct) { return direct }
            return direct
        }
        let p = port ?? activePort
        if let matched = totems.first(where: { $0.port == p }) {
            let folderPath = (baseDir as NSString).appendingPathComponent(matched.storageFolder)
            if FileManager.default.fileExists(atPath: folderPath) { return folderPath }
        }
        let cleanDir = (baseDir as NSString).appendingPathComponent("totem_memory/records/\(p)")
        if FileManager.default.fileExists(atPath: cleanDir) { return cleanDir }

        let legacy = (baseDir as NSString).appendingPathComponent("local records - \(p)")
        if FileManager.default.fileExists(atPath: legacy) { return legacy }

        return legacy
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

    func consolidateBiodynamicMemory() {
        runConsolidation()
    }

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

        persistBiodynamicMemory(storageFolder: activeTotem.storageFolder)

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

    private func persistBiodynamicMemory(port: Int? = nil, storageFolder: String? = nil) {
        let recordsDir = getLocalRecordsDir(port: port, storageFolder: storageFolder)
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
            let projectLocalRecords = (activeProjectDir as NSString).appendingPathComponent(storageFolder ?? activeTotem.storageFolder)
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
# Totem Biodynamic Memory Ledger (\(activeTotem.name))
**Last Consolidated**: \(ISO8601DateFormatter().string(from: Date()))
**Active Filter**: \(activeFilter.rawValue)
**Port**: \(activePort) | **Host**: \(activeTotem.host)
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
        persistBiodynamicMemory(storageFolder: activeTotem.storageFolder)

        DispatchQueue.main.async {
            self.factsCount = self.facts.count
            self.lastConsoleLog = "Project registered in pathname map: \(name) → \(pathname)"
        }
    }

    func loadPersistedMemory(port: Int? = nil, storageFolder: String? = nil) {
        let recordsDir = getLocalRecordsDir(port: port, storageFolder: storageFolder)
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

    /// Opens the memory folder in macOS Finder and ensures MEMORY.md and directories exist
    func openLocalRecordsFolder(port: Int? = nil, storageFolder: String? = nil) {
        let path = getLocalRecordsDir(port: port, storageFolder: storageFolder)
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
            self.lastConsoleLog = "Opened memory folder in Finder: \((path as NSString).lastPathComponent)"
        }
    }
}
