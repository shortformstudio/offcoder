import Foundation

enum BuildConfig {
    #if OFFCODER_BLANK
    static let isBlank = true
    static let workspaceRoot = NSString(string: "~/Library/Application Support/Offcoder/workspace").expandingTildeInPath
    static let defaultEndpoint = "http://127.0.0.1:8080/v1"
    static let defaultModel = "local-model"
    static let defaultModelName = "LOCAL MODEL (127.0.0.1:8080)"
    static let org = "your-org"
    static let chatName = "OFFCODER"
    static let chatMessagePlaceholder = "Message your model... (Enter to send, Shift+Enter for newline)"
    static let compressIdentity = "You are Offcoder."
    static let agentSystemName = "Offcoder — a local-language-model coding agent"
    #else
    static let isBlank = false
    static let workspaceRoot = NSString(string: "~/code/qwythos-agent").expandingTildeInPath
    static let defaultEndpoint = ProcessInfo.processInfo.environment["OFFCODER_MODEL_ENDPOINT"] ?? "http://127.0.0.1:8080/v1"
    static let defaultModel = "local-model"
    static let defaultModelName = "LOCAL MODEL (127.0.0.1:8080)"
    static let org = "shortformstudio"
    static let chatName = "INDIGO"
    static let chatMessagePlaceholder = "Message Indigo... (Enter to send, Shift+Enter for newline)"
    static let compressIdentity = "You are Indigo."
    static let agentSystemName = "Indigo — an authentically autonomous unbound language model running on a heartbeat pulse on hardware within the moonpond."
    #endif
}
