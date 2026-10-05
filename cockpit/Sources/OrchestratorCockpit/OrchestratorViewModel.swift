import SwiftUI
import AppKit
import Combine

final class OrchestratorViewModel: ObservableObject {
    static let shared = OrchestratorViewModel()

    @Published var githubRepos: [RepoItem] = []
    @Published var selectedRepo: String?
    @Published var chatInputText: String = ""
    @Published var journalEntries: [JournalItem] = []
    @Published var currentScreenFrame: NSImage?
    @Published var stagingCandidates: [CandidateItem] = []
    @Published var showFreshProjectSheet = false
    @Published var cdpState = "IDLE"
    @Published var connectionState = "CONNECTING"
    @Published var marquee: MarqueeItem?
    @Published var marqueeHistory: [MarqueeItem] = []
    @Published var marqueeDetailsOpen = false

    let fault = FaultRegistry.shared

    private var socket: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?
    private let framePool = DispatchQueue(label: "orch.framePool", qos: .utility)
    private var frameInFlight = false

    @Published var isViewportPaused = false

    enum ModelConnectionStatus {
        case connected
        case connecting
        case offline
    }

    @Published var modelStatus: ModelConnectionStatus = .connecting
    @Published var localModelEndpoint: String = BuildConfig.defaultEndpoint
    @Published var activeModelName: String = BuildConfig.defaultModel
    @Published var connectionLabel: String = BuildConfig.defaultModelName
    @Published var modelPingLatencyMs: Int = -1
    @Published var chatMessages: [ChatMessage] = []
    @Published var conversationName: String = "Conversation"
    @Published var isGenerating: Bool = false
    @Published var webReflection: WebReflectionState = WebReflectionState()
    @Published var isPullingRepo: Bool = false
    @Published var registeredRepoNotice: String? = nil
    @Published var activeChainOfThought: String = ""
    @Published var isThoughtOverlayVisible: Bool = false
    @Published var isThoughtOverlayCollapsed: Bool = false
    @Published var showSettingsModal: Bool = false
    @Published var showFloatingDiffWindow: Bool = false
    @Published var isReasoning: Bool = false
    @Published var currentProcessState: String = "IDLE"
    @Published var currentProcessDetail: String = "Standby"

    // Modern Chat & Real-Time Context Mechanics
    @Published var contextMetrics: ContextMetrics = ContextMetrics()
    @Published var attachedItems: [AttachedContextItem] = []
    @Published var pastedSnippets: [PastedSnippetItem] = []
    @Published var isContextSelectorOpen: Bool = false
    @Published var isCommandMenuOpen: Bool = false
    @Published var isConsensusArenaOpen: Bool = false
    @Published var activeGenerationTask: Task<Void, Never>? = nil

    // Mini-widget (collapsed supervisor) state
    @Published var isMiniWidgetActive: Bool = false

    func minimizeToMiniWidget() {
        isMiniWidgetActive = true
        NotificationCenter.default.post(name: .offcoderMinimizeToMini, object: self)
    }

    func restoreFromMiniWidget() {
        isMiniWidgetActive = false
        NotificationCenter.default.post(name: .offcoderRestoreFromMini, object: self)
    }

    // Per-prompt reasoning modulation, controlled from the input bar.
    // off = direct answer, no visible thought · low = brief hidden thought · max = full step-by-step.
    @Published var reasoningEffort: ReasoningEffort = .low

    func reasoningHint() -> String {
        switch reasoningEffort {
        case .off:
            return "REASONING BUDGET: none. Answer directly from what you already know. Do not emit internal reasoning, <think> blocks, or chain-of-thought text. Do not call any tools for greetings or small talk — just reply."
        case .low:
            return "REASONING BUDGET: minimal. Keep any internal deliberation to a sentence or two and keep it hidden. Match the scale of your reply to the request: greetings and small talk get a brief warm reply with no tool calls and no memory traversal."
        case .max:
            return "REASONING BUDGET: full. Think step by step, verify with tools, compilers, and tests where relevant, and show your work in the reasoning channel."
        }
    }

    func handleLargePastedText(_ text: String) {
        let lines = text.components(separatedBy: .newlines).count
        let snippet = PastedSnippetItem(snippet: text, lineCount: lines, charCount: text.count)
        pastedSnippets.append(snippet)
    }

    func removePastedSnippet(id: UUID) {
        pastedSnippets.removeAll(where: { $0.id == id })
    }

    func appendVisualDebugPayload(_ payload: VisualGroundingPayload) {
        let snippet = """
\n[VISUAL GROUNDING CONTEXT]
Target: `\(payload.selector)` (Tag: \(payload.tagName))
Bounds: [x: \(Int(payload.bounds.origin.x)), y: \(Int(payload.bounds.origin.y)), w: \(Int(payload.bounds.width)), h: \(Int(payload.bounds.height))]
Text: "\(payload.innerText)"
Please inspect and debug this rendered component.
"""
        self.chatInputText += snippet
    }

    private let localModelClient = LocalModelClient.shared
    private let versionManager = CodeVersionManager.shared
    private let harness = CodebaseHarnessService.shared

    func connect(host: String = "127.0.0.1", port: Int = 7171) {
        socket?.cancel()
        reconnectTask?.cancel()
        connectionState = "CONNECTING"
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://\(host):\(port)")!)
        socket = task
        task.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        guard let socket else { return }
        socket.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handle(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handle(data)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure(let error):
                self.connectionState = "OFFLINE"
                self.fault.record(
                    bayID: "bridge",
                    code: "socket_lost",
                    detail: "websocket dropped: \(error.localizedDescription)",
                    stack: ""
                )
                self.reconnectTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    await MainActor.run { self.connect() }
                }
            }
        }
    }

    private func handle(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(ServerEnvelope.self, from: data) else {
            fault.record(bayID: "bridge", code: "decode_failed", detail: "unreadable server frame", stack: "")
            return
        }
        DispatchQueue.main.async {
            switch envelope.type {
            case "screencast_frame":
                self.acceptFrame(envelope.data)
            case "marquee":
                if let level = envelope.level, let text = envelope.text, let code = envelope.code, let ts = envelope.ts {
                    let item = MarqueeItem(level: level, text: text, code: code, ts: ts)
                    self.marquee = item
                    var history = self.marqueeHistory
                    history.insert(item, at: 0)
                    if history.count > 6 { history.removeLast() }
                    self.marqueeHistory = history
                }
            case "marquee_state":
                if let states = envelope.states {
                    self.marqueeHistory = states
                    if let first = states.first {
                        self.marquee = first
                    }
                }
            case "org_repos":
                if let repos = envelope.repos {
                    self.githubRepos = repos
                    if self.selectedRepo == nil, let first = repos.first {
                        self.selectedRepo = first.id
                    }
                }
            case "repo_registered":
                self.isPullingRepo = false
                if let repoId = envelope.repoId {
                    let count = envelope.files ?? 0
                    self.registeredRepoNotice = "Indexed \(count) AST files"
                    structLogBridge("repo_registered", "\(repoId) indexed (\(count) files)")
                    self.fetchRepos()
                }
            case "error":
                self.isPullingRepo = false
                if let detail = envelope.detail {
                    self.registeredRepoNotice = "Error: \(detail)"
                    structLogBridge("error", detail)
                }
            case "plan_queued":
                if let taskId = envelope.taskId {
                    let flag = (envelope.reused == true) ? "reused" : "created"
                    structLogBridge("plan_queued", "task \(taskId) \(flag)")
                }
            case "journal":
                let item = JournalItem(
                    type: envelope.entryType ?? "NOTE",
                    target: envelope.target ?? "",
                    summary: envelope.summary ?? ""
                )
                var entries = self.journalEntries
                entries.insert(item, at: 0)
                if entries.count > 80 { entries.removeLast() }
                self.journalEntries = entries
            case "status":
                if envelope.key == "cdp" { self.cdpState = envelope.state ?? "IDLE" }
                if envelope.key == "ipc" { self.connectionState = envelope.state ?? "ONLINE" }
            case "telemetry":
                structLogBridge("telemetry", "battery \(envelope.battery ?? "ac") · \(envelope.pendingTasks ?? 0) pending")
            case "browsers_status":
                if let presence = envelope.presence {
                    self.webReflection.presence = presence
                }
                if let visible = envelope.visible {
                    self.webReflection.browserVisible = visible
                }
            case "browser_visibility_result":
                if let visible = envelope.visible {
                    self.webReflection.browserVisible = visible
                }
            case "screencast_targeted":
                if let worker = envelope.worker {
                    self.webReflection.targetWorker = worker
                }
            case "login_tab_opened":
                structLogBridge("login_tab", "opened \(envelope.worker ?? "unknown") login tab")
            case "task_event":
                if let worker = envelope.targetWorker, let file = envelope.targetFile {
                    let item = CandidateItem(
                        file: file,
                        worker: worker,
                        isValid: (envelope.status == "STAGED" || envelope.status == "VERIFIED")
                    )
                    var candidates = self.stagingCandidates
                    candidates.insert(item, at: 0)
                    if candidates.count > 60 { candidates.removeLast() }
                    self.stagingCandidates = candidates
                }
            default:
                break
            }
        }
    }

    private func acceptFrame(_ base64: String?) {
        guard !isViewportPaused, let base64, !frameInFlight, base64.count < 700_000 else { return }
        frameInFlight = true
        framePool.async { [weak self] in
            defer { self?.frameInFlight = false }
            autoreleasepool {
                guard let data = Data(base64Encoded: base64) else { return }
                
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: false,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 960
                ]
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    return
                }
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                DispatchQueue.main.async {
                    self?.currentScreenFrame = image
                }
            }
        }
    }

    func recover() {
        marqueeDetailsOpen = false
        fault.recoverAll()
        fault.recoverBay("bridge")
        connect()
        fetchRepos()
        let item = MarqueeItem(
            level: .success,
            text: "state recovered — all systems nominal",
            code: "recovered",
            ts: Int(Date().timeIntervalSince1970)
        )
        marquee = item
        marqueeHistory.insert(item, at: 0)
    }

    private func send(_ command: ClientCommand) {
        guard let socket, let payload = try? JSONEncoder().encode(command) else { return }
        socket.send(.data(payload)) { _ in }
    }

    func fetchRepos(org: String = BuildConfig.org) {
        send(ClientCommand(type: "org_repos"))
    }

    func setMirrorProvider(_ provider: String) {
        webReflection.selectedProvider = provider
        send(ClientCommand(type: "screencast_target", worker: provider))
    }

    func openLoginTab(_ provider: String) {
        send(ClientCommand(type: "open_login_tab", worker: provider))
    }

    func requestBrowserStatus() {
        send(ClientCommand(type: "browsers_status"))
    }

    func setBrowserMirrorVisibility(_ visible: Bool) {
        webReflection.browserVisible = visible
        send(ClientCommand(type: "browser_visibility", visible: visible))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.requestBrowserStatus()
        }
    }

    func pullRepository(_ repoId: String) {
        isPullingRepo = true
        registeredRepoNotice = nil
        send(ClientCommand(type: "pull_repo", repoId: repoId))
    }

    func createFreshProject(name: String, masterPlan: String) {
        harness.startProject(name: name, masterPlan: masterPlan)
        send(ClientCommand(type: "fresh_project", name: name, masterPlan: masterPlan))
    }

    func setEndpoint(url: String, model: String) {
        localModelEndpoint = url
        activeModelName = model
        if let components = URLComponents(string: url), let host = components.host {
            let portStr = components.port != nil ? ":\(components.port!)" : ""
            if host == "127.0.0.1" || host == "localhost" {
                if components.port == 8000 {
                    connectionLabel = "LOCAL DISPATCHER (8000)"
                } else if components.port == 11434 {
                    connectionLabel = "LOCAL OLLAMA (11434)"
                } else if components.port == 1234 {
                    connectionLabel = "LOCAL LM STUDIO (1234)"
                } else {
                    connectionLabel = "LOCAL LLAMA.CPP (\(host)\(portStr))"
                }
            } else if host.lowercased().contains("lockfort") {
                connectionLabel = "QWYTHOS · LOCKFORT (\(host)\(portStr))"
            } else {
                connectionLabel = "LAN HOST (\(host)\(portStr))"
            }
        } else {
            connectionLabel = "LOCAL MODEL (8080)"
        }
        pingModelEndpoint()
    }

    func pingModelEndpoint(attempts: Int = 2) {
        modelStatus = .connecting
        let start = Date()
        let resolved = LocalModelClient.resolveEndpointString(localModelEndpoint)
        let clean = resolved.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Try /models or /v1/models or /health
        let probeUrlStr = clean.hasSuffix("/v1") ? "\(clean)/models" : "\(clean)/health"
        guard let url = URL(string: probeUrlStr) else {
            modelStatus = .offline
            modelPingLatencyMs = -1
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8.0
        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                    self.modelStatus = .connected
                    self.modelPingLatencyMs = Int(Date().timeIntervalSince(start) * 1000)
                } else if error == nil {
                    self.modelStatus = .connected
                    self.modelPingLatencyMs = Int(Date().timeIntervalSince(start) * 1000)
                } else {
                    if attempts > 1 {
                        structLogBridge("model_ping_retry", "\(url.host ?? ""):\(url.port ?? 0) attempt failed: \(error?.localizedDescription ?? "unknown") — retrying once")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.pingModelEndpoint(attempts: attempts - 1)
                        }
                        return
                    }
                    structLogBridge("model_ping_offline", "\(url.host ?? ""):\(url.port ?? 0) unreachable: \(error?.localizedDescription ?? "unknown")")
                    self.modelStatus = .offline
                    self.modelPingLatencyMs = -1
                }
            }
        }.resume()
    }

    @Published var isCompressing: Bool = false

    func clearChat() {
        if !chatMessages.isEmpty {
            harness.appendConversationTranscript(messages: chatMessages)
        }
        chatMessages.removeAll()
        activeChainOfThought = ""
        isThoughtOverlayVisible = false
        attachedItems.removeAll()
        recalculateContextTokens()
    }

    func updateContextMetrics(promptTokens: Int, completionTokens: Int) {
        let totem = TotemPortListenerService.shared.activeTotem
        let maxTokens = totem.nCtx > 0 ? totem.nCtx : 32768
        contextMetrics.promptTokens = promptTokens
        contextMetrics.completionTokens = completionTokens
        contextMetrics.totalTokens = promptTokens + completionTokens
        contextMetrics.maxContextTokens = maxTokens
    }

    func recalculateContextTokens() {
        let totem = TotemPortListenerService.shared.activeTotem
        let maxTokens = totem.nCtx > 0 ? totem.nCtx : 32768
        let promptChars = chatMessages.reduce(0) { $0 + $1.content.count }
        let p = max(32, promptChars / 4 + 250)
        contextMetrics.promptTokens = p
        contextMetrics.completionTokens = 0
        contextMetrics.totalTokens = p
        contextMetrics.maxContextTokens = maxTokens
    }

    func stopGeneration() {
        guard isGenerating else { return }
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        isGenerating = false
        isReasoning = false
        isThoughtOverlayVisible = false
        currentProcessState = "IDLE"
        currentProcessDetail = "Generation halted"
    }

    func editPrompt(for message: ChatMessage) {
        chatInputText = message.rawPrompt ?? message.content
    }

    func regenerateLastResponse() {
        guard !isGenerating else { return }
        if let lastAssistantIdx = chatMessages.lastIndex(where: { $0.role == .assistant }) {
            if let lastUserIdx = chatMessages[..<lastAssistantIdx].lastIndex(where: { $0.role == .user }) {
                let prompt = chatMessages[lastUserIdx].content
                chatMessages.remove(at: lastAssistantIdx)
                chatMessages.remove(at: lastUserIdx)
                sendChatMessage(prompt: prompt)
            }
        }
    }

    func setFeedback(for messageId: UUID, rating: MessageFeedback) {
        if let idx = chatMessages.firstIndex(where: { $0.id == messageId }) {
            chatMessages[idx].feedback = (chatMessages[idx].feedback == rating) ? nil : rating
        }
    }

    func attachFiles(urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    attachFolder(url: url)
                } else {
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    let item = AttachedContextItem(type: .file, name: url.lastPathComponent, path: url.path, sizeBytes: size, content: content)
                    attachedItems.append(item)
                }
            }
        }
    }

    func attachFolder(url: URL) {
        let item = AttachedContextItem(type: .folder, name: url.lastPathComponent, path: url.path, sizeBytes: 0, content: "Folder directory: \(url.path)")
        attachedItems.append(item)
    }

    func removeAttachment(id: UUID) {
        attachedItems.removeAll(where: { $0.id == id })
    }

    /// Stages a screenshot file into the current conversation, ready to send.
    /// The user can add text or more attachments, then press enter to send.
    func attachScreenshot(url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let item = AttachedContextItem(
            type: .image,
            name: url.lastPathComponent,
            path: url.path,
            sizeBytes: size,
            content: "[Screenshot Attached: \(url.path)]"
        )
        attachedItems.append(item)
    }

    func compressContext() {
        guard !chatMessages.isEmpty, !isGenerating, !isCompressing else { return }
        isCompressing = true

        let snapshot = chatMessages
        // 1. Always record literal verbose transcript before compressing
        harness.appendConversationTranscript(messages: snapshot)

        Task {
            do {
                let compressedSummary = try await localModelClient.compressConversation(
                    endpoint: localModelEndpoint,
                    model: activeModelName,
                    messages: snapshot
                )

                await MainActor.run {
                    // Replace chat history with semantically compressed anchor
                    let compressedMsg = ChatMessage(
                        role: .assistant,
                        content: "📦 **Semantic Context Compression (by Qwythos)**:\n\n\(compressedSummary)\n\n*(Full verbose conversation saved to `.agents/logs/conversations/`)*"
                    )
                    self.chatMessages = [compressedMsg]
                    self.harness.appendWorkLog(
                        category: "semantic_compression",
                        summary: "Compressed \(snapshot.count) turns into semantic executive briefing",
                        details: compressedSummary
                    )
                    self.isCompressing = false
                }
            } catch {
                await MainActor.run {
                    // If model call fails, provide structured local fallback compression
                    let fallbackSummary = "### Compressed Context Summary (\(snapshot.count) turns)\n" +
                        snapshot.map { "- [\($0.role.rawValue.uppercased())]: \($0.content.prefix(120))..." }.joined(separator: "\n")
                    let fallbackMsg = ChatMessage(
                        role: .assistant,
                        content: "📦 **Locally Distilled Context**:\n\n\(fallbackSummary)\n\n*(Full verbose log saved to `.agents/logs/`)*"
                    )
                    self.chatMessages = [fallbackMsg]
                    self.isCompressing = false
                }
            }
        }
    }

    func sendChatMessage(prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle quick commands: /clear, /compress
        if trimmed == "/clear" {
            clearChat()
            return
        }
        if trimmed == "/compress" {
            compressContext()
            return
        }

        var resolvedPrompt = prompt
        if !pastedSnippets.isEmpty {
            for snippet in pastedSnippets {
                if resolvedPrompt.contains("[pasted text]") {
                    if let range = resolvedPrompt.range(of: "[pasted text]") {
                        resolvedPrompt.replaceSubrange(range, with: snippet.snippet)
                    }
                } else {
                    resolvedPrompt += "\n\n```\n\(snippet.snippet)\n```"
                }
            }
            pastedSnippets.removeAll()
        }

        var fullPrompt = resolvedPrompt
        if !attachedItems.isEmpty {
            var contextBlock = "\n\n--- ATTACHED CONTEXT ---\n"
            for item in attachedItems {
                contextBlock += "[\(item.type.rawValue): \(item.name)]\n"
                if !item.content.isEmpty {
                    contextBlock += "```\n\(item.content.prefix(3000))\n```\n"
                }
            }
            fullPrompt += contextBlock
            attachedItems.removeAll()
        }

        let userMsg = ChatMessage(role: .user, content: fullPrompt, rawPrompt: prompt)
        chatMessages.append(userMsg)
        TotemPortListenerService.shared.recordConversationTurn(role: "user", text: fullPrompt, toolCalls: [])

        let assistantId = UUID()
        let assistantMsg = ChatMessage(id: assistantId, role: .assistant, content: "")
        chatMessages.append(assistantMsg)

        // Handle slash command: /remember <query>, /remember assert <fact>, /remember log <query>
        if trimmed.hasPrefix("/remember") {
            let remainder = trimmed.dropFirst(9).trimmingCharacters(in: .whitespacesAndNewlines)
            isGenerating = true
            currentProcessState = "TRAVERSING_MEMORY"
            currentProcessDetail = "Traversing Totem knowledge graph..."

            activeGenerationTask = Task {
                let toolOutput: String
                if remainder.hasPrefix("assert ") {
                    let fact = String(remainder.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                    toolOutput = await MCPClient.shared.call(server: "remember", tool: "remember_assert", arguments: ["content": fact, "domain": "arch"])
                } else if remainder.hasPrefix("log") {
                    let query = String(remainder.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    toolOutput = await MCPClient.shared.call(server: "remember", tool: "remember_convo_log", arguments: ["query": query, "limit": 10])
                } else {
                    let q = remainder.isEmpty ? "architecture invariants" : remainder
                    toolOutput = await MCPClient.shared.call(server: "remember", tool: "remember", arguments: ["query": q, "limit": 6])
                }

                let finalOutput = toolOutput
                await MainActor.run {
                    if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                        self.chatMessages[idx].content = finalOutput
                    }
                    TotemPortListenerService.shared.recordConversationTurn(role: "assistant", text: finalOutput, toolCalls: [])
                    self.isGenerating = false
                    self.currentProcessState = "IDLE"
                    self.currentProcessDetail = "Standby"
                    self.activeGenerationTask = nil
                    self.recalculateContextTokens()
                }
            }
            return
        }

        // Handle slash command: /consensus <prompt> or /arena <prompt>
        if trimmed.hasPrefix("/consensus") || trimmed.hasPrefix("/arena") {
            let prefixLen = trimmed.hasPrefix("/consensus") ? 10 : 6
            let promptText = String(trimmed.dropFirst(prefixLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            let actualPrompt = promptText.isEmpty ? "Review architectural implementation and optimize performance" : promptText

            var contextCode = ""
            if let lastCodeMsg = self.chatMessages.last(where: { $0.content.contains("```") })?.content {
                let parts = lastCodeMsg.components(separatedBy: "```")
                if parts.count >= 3 {
                    contextCode = parts[1]
                }
            }

            self.isConsensusArenaOpen = true
            Task {
                await ConsensusEngineService.shared.runConsensus(prompt: actualPrompt, baseCode: contextCode.isEmpty ? nil : contextCode)
            }
            return
        }

        // Handle slash command: /deepseek <prompt> or /handoff <prompt>
        if trimmed.hasPrefix("/deepseek") || trimmed.hasPrefix("/handoff") {
            let prefixLen = trimmed.hasPrefix("/deepseek") ? 9 : 8
            let promptText = String(trimmed.dropFirst(prefixLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            let actualPrompt = promptText.isEmpty ? "Review and optimize active workspace code" : promptText

            isGenerating = true
            currentProcessState = "OFFLOADING_TO_DEEPSEEK"
            currentProcessDetail = "Handing off prompt + code to DeepSeek..."

            activeGenerationTask = Task {
                var contextCode = ""
                if let lastCodeMsg = self.chatMessages.last(where: { $0.content.contains("```") })?.content {
                    let parts = lastCodeMsg.components(separatedBy: "```")
                    if parts.count >= 3 {
                        contextCode = parts[1]
                    }
                }

                await MainActor.run {
                    if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                        self.chatMessages[idx].content = "⏳ **Handing off to DeepSeek...**\n`\(actualPrompt)`"
                    }
                }

                let (deepSeekCode, deepSeekExplanation, error) = await DeepSeekHandoffService.shared.executeHandoff(
                    prompt: actualPrompt,
                    code: contextCode
                ) { status in
                    DispatchQueue.main.async {
                        self.currentProcessDetail = status
                    }
                }

                let errNotice = error != nil ? "\n> [!NOTE]\n> \(error!)\n" : ""
                let deepSeekBlock = """
### 🚀 DeepSeek Output
\(errNotice)
```
\(deepSeekCode)
```

\(deepSeekExplanation)
"""

                await MainActor.run {
                    if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                        self.chatMessages[idx].content = deepSeekBlock
                    }
                    TotemPortListenerService.shared.recordConversationTurn(role: "assistant", text: deepSeekBlock, toolCalls: [])
                }

                // Immediately trigger Local Model Review
                let reviewId = UUID()
                await MainActor.run {
                    self.currentProcessState = "LOCAL_MODEL_REVIEWING"
                    self.currentProcessDetail = "Local model reviewing DeepSeek proposal..."
                    let reviewMsg = ChatMessage(id: reviewId, role: .assistant, content: "🔍 **Local Model Review:**\n")
                    self.chatMessages.append(reviewMsg)
                }

                let reviewPrompt = """
[DEEPSEEK PROPOSAL RECEIVED]
User Goal: "\(actualPrompt)"

DeepSeek produced the following code:
```
\(deepSeekCode)
```
DeepSeek Explanation:
\(deepSeekExplanation)

---
[INSTRUCTION FOR LOCAL MODEL]
Please perform a rigorous review of DeepSeek's proposal:
1. Verify correctness, edge cases, and architectural compatibility with our codebase.
2. Check for potential regressions, bugs, or performance issues.
3. Provide your authoritative review, final verdict, and any recommended code changes.
"""

                let reviewUserMsg = ChatMessage(role: .user, content: reviewPrompt)
                let messagesForReview = self.chatMessages.filter { $0.id != reviewId } + [reviewUserMsg]

                do {
                    let (finalReview, _) = try await self.localModelClient.sendChat(
                        endpoint: self.localModelEndpoint,
                        model: self.activeModelName,
                        messages: messagesForReview,
                        onDelta: { delta in
                            DispatchQueue.main.async {
                                if let idx = self.chatMessages.firstIndex(where: { $0.id == reviewId }) {
                                    self.chatMessages[idx].content += delta
                                }
                            }
                        },
                        onThoughtDelta: { thoughtChunk in
                            DispatchQueue.main.async {
                                self.activeChainOfThought += thoughtChunk
                            }
                        },
                        onProcessUpdate: { state, detail in
                            DispatchQueue.main.async {
                                self.currentProcessState = state
                                self.currentProcessDetail = detail
                            }
                        },
                        onToolCall: { toolItem in
                            DispatchQueue.main.async {
                                if let idx = self.chatMessages.firstIndex(where: { $0.id == reviewId }) {
                                    self.chatMessages[idx].toolCalls.append(toolItem)
                                }
                            }
                        },
                        onReflectionUpdate: nil,
                        onTokenUpdate: { p, c in
                            DispatchQueue.main.async {
                                self.updateContextMetrics(promptTokens: p, completionTokens: c)
                            }
                        }
                    )
                    await MainActor.run {
                        TotemPortListenerService.shared.recordConversationTurn(role: "assistant", text: finalReview, toolCalls: [])
                        self.isGenerating = false
                        self.currentProcessState = "IDLE"
                        self.currentProcessDetail = "Standby"
                        self.activeGenerationTask = nil
                        self.recalculateContextTokens()
                    }
                } catch {
                    await MainActor.run {
                        if let idx = self.chatMessages.firstIndex(where: { $0.id == reviewId }) {
                            self.chatMessages[idx].content += "\n\n⚠️ Local review error: \(error.localizedDescription)"
                        }
                        self.isGenerating = false
                        self.currentProcessState = "IDLE"
                        self.currentProcessDetail = "Standby"
                        self.activeGenerationTask = nil
                        self.recalculateContextTokens()
                    }
                }
            }
            return
        }

        isGenerating = true
        isReasoning = reasoningEffort != .off
        activeChainOfThought = ""
        isThoughtOverlayVisible = reasoningEffort != .off
        isThoughtOverlayCollapsed = false
        currentProcessState = "THINKING"
        currentProcessDetail = "thinking..."

        activeGenerationTask = Task {
            do {
                let (finalContent, finalThought) = try await localModelClient.sendChat(
                    endpoint: localModelEndpoint,
                    model: activeModelName,
                    messages: chatMessages.filter { $0.id != assistantId },
                    reasoningHint: reasoningHint(),
                    onDelta: { [weak self] delta in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                                self.chatMessages[idx].content += delta
                            }
                        }
                    },
                    onThoughtDelta: { [weak self] thoughtChunk in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            guard self.reasoningEffort != .off else { return }
                            self.activeChainOfThought += thoughtChunk
                            self.isReasoning = true
                            self.isThoughtOverlayVisible = true
                        }
                    },
                    onProcessUpdate: { [weak self] state, detail in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.currentProcessState = state
                            self.currentProcessDetail = detail
                            if state == "SYNTHESIZING_RESPONSE" || state == "EXECUTING_TOOL" || state == "IDLE" {
                                self.isReasoning = false
                            }
                        }
                    },
                    onToolCall: { [weak self] toolItem in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                                if let tcIdx = self.chatMessages[idx].toolCalls.firstIndex(where: { $0.id == toolItem.id }) {
                                    self.chatMessages[idx].toolCalls[tcIdx] = toolItem
                                } else {
                                    self.chatMessages[idx].toolCalls.append(toolItem)
                                }
                            }
                        }
                    },
                    onReflectionUpdate: { [weak self] targetWorker, payload in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.webReflection.isActive = true
                            self.webReflection.targetWorker = targetWorker
                            if self.webReflection.promptSent.isEmpty || payload.contains("Audit") || payload.contains("Review") {
                                self.webReflection.promptSent = payload
                            } else {
                                self.webReflection.streamingReply = payload
                            }
                            self.webReflection.startedAt = Date()
                        }
                    },
                    onTokenUpdate: { [weak self] promptTokens, completionTokens in
                        DispatchQueue.main.async {
                            self?.updateContextMetrics(promptTokens: promptTokens, completionTokens: completionTokens)
                        }
                    }
                )

                await MainActor.run {
                    if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                        self.chatMessages[idx].thought = self.reasoningEffort == .off ? "" : (finalThought.isEmpty ? self.activeChainOfThought : finalThought)
                        self.chatMessages[idx].processDetail = self.currentProcessDetail
                        TotemPortListenerService.shared.recordConversationTurn(
                            role: "assistant",
                            text: finalContent,
                            toolCalls: self.chatMessages[idx].toolCalls
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                        if self.chatMessages[idx].content.isEmpty {
                            var hint = "Ensure local or LAN model server is running at \(self.localModelEndpoint)."
                            if let urle = error as? URLError, urle.code == .notConnectedToInternet,
                               self.localModelEndpoint.contains("192.168.") {
                                hint = "macOS blocked LAN access to \(self.localModelEndpoint) (Local Network permission). Launch via Offcoder.command in Terminal, or enable \"Offcoder\" in System Settings > Privacy & Security > Local Network."
                            }
                            self.chatMessages[idx].content = "⚠️ Error communicating with model endpoint: \(error.localizedDescription)\n\(hint)"
                        }
                    }
                }
            }
            await MainActor.run {
                self.isGenerating = false
                self.isReasoning = false
                self.isThoughtOverlayVisible = false
                self.activeChainOfThought = ""
                self.currentProcessState = "IDLE"
                self.currentProcessDetail = "Standby"
                self.activeGenerationTask = nil
                self.recalculateContextTokens()
            }
        }
    }
}

enum ReasoningEffort: String, CaseIterable, Identifiable {
    case off
    case low
    case max

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

func structLogBridge(_ code: String, _ msg: String) {
    let payload = ["domain": "cockpit", "level": "info", "code": code, "msg": msg]
    if let data = try? JSONSerialization.data(withJSONObject: payload),
       let line = String(data: data, encoding: .utf8) {
        NSLog("[cockpit] %@", line)
    }
}
