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
    static let workspaceRoot = "/Users/stevenjackson/code/qwythos-agent"
    static let defaultEndpoint = "http://192.168.1.80:8080/v1"
    static let defaultModel = "qwythos/qwythos"
    static let defaultModelName = "QWYTHOS (192.168.1.80:8080)"
    static let org = "shortformstudio"
    static let chatName = "QWYTHOS"
    static let chatMessagePlaceholder = "Message Qwythos... (Enter to send, Shift+Enter for newline)"
    static let compressIdentity = "You are Qwythos."
    static let agentSystemName = "Qwythos / Offcoder — an apex, long-horizon high-level software architect and orchestrator driving the coding harness and inference offload architecture."
    #endif
}
