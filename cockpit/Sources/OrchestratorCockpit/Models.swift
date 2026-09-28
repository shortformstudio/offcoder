import Foundation

struct JournalItem: Identifiable {
    let id = UUID()
    let type: String
    let target: String
    let summary: String
}

struct LintDiagnosticItem: Identifiable, Hashable {
    let id = UUID()
    let line: Int
    let col: Int
    let severity: String
    let code: String
    let message: String
    let remediation: String
}

struct CandidateItem: Identifiable {
    let id = UUID()
    let file: String
    let worker: String
    let isValid: Bool
    var lintStatus: String = "CLEAN" // "CLEAN", "WARNING", "ERROR"
    var diagnostics: [LintDiagnosticItem] = []
    var rawCode: String? = nil
}

struct RepoItem: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case id = "repo_id"
        case defaultBranch = "default_branch"
    }

    init(id: String, name: String, defaultBranch: String) {
        self.id = id
        self.name = name
        self.defaultBranch = defaultBranch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let repoId = try container.decode(String.self, forKey: .id)
        self.id = repoId
        self.name = repoId.split(separator: "/").last.map(String.init) ?? repoId
        self.defaultBranch = try container.decodeIfPresent(String.self, forKey: .defaultBranch) ?? "main"
    }
}

struct ServerEnvelope: Decodable {
    let type: String
    let data: String?
    let entryType: String?
    let target: String?
    let summary: String?
    let file: String?
    let worker: String?
    let valid: Bool?
    let key: String?
    let state: String?
    let detail: String?
    let repoId: String?
    let level: MarqueeLevel?
    let text: String?
    let code: String?
    let ts: Int?
    let states: [MarqueeItem]?
    let repos: [RepoItem]?
    let battery: String?
    let pendingTasks: Int?
    let status: String?
    let targetFile: String?
    let targetWorker: String?
    let taskId: String?
    let sessionId: String?
    let reused: Bool?
    let files: Int?
    let presence: [String: Bool]?
    let visible: Bool?
}

struct ClientCommand: Encodable {
    let type: String
    var repoId: String? = nil
    var name: String? = nil
    var masterPlan: String? = nil
    var worker: String? = nil
    var visible: Bool? = nil
}

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

enum ToolCallStatus: String, Codable {
    case pending
    case executing
    case completed
    case failed
}

struct ToolCallItem: Identifiable, Codable {
    let id: String
    let name: String
    let arguments: String
    var output: String?
    var status: ToolCallStatus

    init(id: String = UUID().uuidString, name: String, arguments: String, output: String? = nil, status: ToolCallStatus = .pending) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.output = output
        self.status = status
    }
}

struct ContextMetrics: Equatable {
    var promptTokens: Int = 0
    var completionTokens: Int = 0
    var totalTokens: Int = 0
    var maxContextTokens: Int = 32768

    var percentage: Double {
        guard maxContextTokens > 0 else { return 0.0 }
        return min(100.0, (Double(totalTokens) / Double(maxContextTokens)) * 100.0)
    }

    var isWarning: Bool {
        percentage >= 60.0 && percentage < 85.0
    }

    var isCritical: Bool {
        percentage >= 85.0
    }
}

enum MessageFeedback: String, Codable {
    case thumbsUp = "UP"
    case thumbsDown = "DOWN"
}

enum AttachmentType: String, Codable {
    case file = "FILE"
    case folder = "FOLDER"
    case image = "IMAGE"
    case codeRef = "CODE_REF"
}

struct AttachedContextItem: Identifiable, Equatable {
    let id: UUID
    let type: AttachmentType
    let name: String
    let path: String
    let sizeBytes: Int
    let content: String

    init(id: UUID = UUID(), type: AttachmentType, name: String, path: String, sizeBytes: Int = 0, content: String = "") {
        self.id = id
        self.type = type
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.content = content
    }
}

struct PastedSnippetItem: Identifiable, Equatable {
    let id: UUID
    let snippet: String
    let lineCount: Int
    let charCount: Int

    init(id: UUID = UUID(), snippet: String, lineCount: Int, charCount: Int) {
        self.id = id
        self.snippet = snippet
        self.lineCount = lineCount
        self.charCount = charCount
    }
}


enum ChatMessageContentBlock: Identifiable {
    case text(id: String, content: String)
    case code(id: String, language: String, filename: String?, code: String)

    var id: String {
        switch self {
        case .text(let id, _): return id
        case .code(let id, _, _, _): return id
        }
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var content: String
    var thought: String?
    var processDetail: String?
    var toolCalls: [ToolCallItem]
    var timestamp: Date
    var feedback: MessageFeedback?
    var rawPrompt: String?
    var tokenCount: Int

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thought: String? = nil,
        processDetail: String? = nil,
        toolCalls: [ToolCallItem] = [],
        timestamp: Date = Date(),
        feedback: MessageFeedback? = nil,
        rawPrompt: String? = nil,
        tokenCount: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thought = thought
        self.processDetail = processDetail
        self.toolCalls = toolCalls
        self.timestamp = timestamp
        self.feedback = feedback
        self.rawPrompt = rawPrompt ?? (role == .user ? content : nil)
        self.tokenCount = tokenCount > 0 ? tokenCount : max(1, content.count / 4)
    }

    /// Parses markdown content into interleaved text segments and executable code blocks.
    func parseContentBlocks() -> [ChatMessageContentBlock] {
        guard !content.isEmpty else { return [] }

        var blocks: [ChatMessageContentBlock] = []
        let pattern = "```([a-zA-Z0-9_+\\-#]*)(?::([^\\n]+))?\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.text(id: UUID().uuidString, content: content)]
        }

        let nsString = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))

        var lastIndex = 0
        var blockIdx = 0

        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastIndex {
                let textChunk = nsString.substring(with: NSRange(location: lastIndex, length: matchRange.location - lastIndex))
                let trimmed = textChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(.text(id: "\(id.uuidString)-t-\(blockIdx)", content: textChunk))
                    blockIdx += 1
                }
            }

            var lang = ""
            if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                lang = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if lang.isEmpty { lang = "text" }

            var filename: String? = nil
            if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                let fn = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !fn.isEmpty { filename = fn }
            }

            var code = ""
            if match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound {
                code = nsString.substring(with: match.range(at: 3))
            }

            blocks.append(.code(id: "\(id.uuidString)-c-\(blockIdx)", language: lang, filename: filename, code: code))
            blockIdx += 1
            lastIndex = matchRange.location + matchRange.length
        }

        if lastIndex < nsString.length {
            let trailingText = nsString.substring(from: lastIndex)
            let trimmed = trailingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.text(id: "\(id.uuidString)-t-\(blockIdx)", content: trailingText))
            }
        }

        return blocks.isEmpty ? [.text(id: id.uuidString, content: content)] : blocks
    }
}

enum RevisionOrigin: String, Codable, CaseIterable {
    case userOriginal = "ORIGINAL"
    case localModel = "LOCAL_MODEL"
    case deepseekAudit = "DEEPSEEK_AUDIT"
    case kimiDesign = "KIMI_DESIGN"
    case geminiDesign = "GEMINI_SYNTHESIS"
    case cliOutput = "CLI_OUTPUT"
}

struct CodeRevision: Identifiable, Codable {
    let id: UUID
    let versionIndex: Int
    let filePath: String
    let origin: RevisionOrigin
    let code: String
    let diffFromPrevious: String
    let summary: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        versionIndex: Int,
        filePath: String,
        origin: RevisionOrigin,
        code: String,
        diffFromPrevious: String,
        summary: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.versionIndex = versionIndex
        self.filePath = filePath
        self.origin = origin
        self.code = code
        self.diffFromPrevious = diffFromPrevious
        self.summary = summary
        self.timestamp = timestamp
    }
}

struct WebReflectionState {
    var isActive: Bool = false
    var targetWorker: String = "DEEPSEEK_WEB"
    var promptSent: String = ""
    var streamingReply: String = ""
    var startedAt: Date = Date()
    var selectedProvider: String = "deepseek"
    var presence: [String: Bool] = [:]
    var browserVisible: Bool = false
}

