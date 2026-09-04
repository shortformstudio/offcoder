import Foundation

struct JournalItem: Identifiable {
    let id = UUID()
    let type: String
    let target: String
    let summary: String
}

struct CandidateItem: Identifiable {
    let id = UUID()
    let file: String
    let worker: String
    let isValid: Bool
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
}

struct ClientCommand: Encodable {
    let type: String
    var repoId: String? = nil
    var name: String? = nil
    var masterPlan: String? = nil
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

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var content: String
    var toolCalls: [ToolCallItem]
    var timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, toolCalls: [ToolCallItem] = [], timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.timestamp = timestamp
    }
}

enum RevisionOrigin: String, Codable, CaseIterable {
    case userOriginal = "ORIGINAL"
    case localModel = "LOCAL_MODEL"
    case deepseekAudit = "DEEPSEEK_AUDIT"
    case kimiDesign = "KIMI_DESIGN"
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
}

