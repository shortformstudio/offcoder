import SwiftUI
import AppKit
import Combine

final class OrchestratorViewModel: ObservableObject {
    @Published var githubRepos: [RepoItem] = []
    @Published var selectedRepo: String?
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
    @Published var localModelEndpoint: String = "http://192.168.1.80:8080/v1"
    @Published var activeModelName: String = "qwythos/qwythos"
    @Published var connectionLabel: String = "LAN QWYTHOS (192.168.1.80:8080)"
    @Published var modelPingLatencyMs: Int = -1
    @Published var chatMessages: [ChatMessage] = []
    @Published var isGenerating: Bool = false
    @Published var webReflection: WebReflectionState = WebReflectionState()
    @Published var isPullingRepo: Bool = false
    @Published var registeredRepoNotice: String? = nil

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
            guard let data = Data(base64Encoded: base64) else { return }
            
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1280
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

    func fetchRepos(org: String = "shortformstudio") {
        send(ClientCommand(type: "org_repos"))
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
        if url.contains("192.168.1.80") || url.contains("lockfort.local") {
            connectionLabel = "LAN QWYTHOS (192.168.1.80:8080)"
        } else if url.contains("8000") {
            connectionLabel = "LOCAL DISPATCHER"
        } else if url.contains("11434") {
            connectionLabel = "LOCAL OLLAMA"
        } else if url.contains("1234") {
            connectionLabel = "LOCAL LM STUDIO"
        } else {
            connectionLabel = "CUSTOM LAN HOST"
        }
        pingModelEndpoint()
    }

    func pingModelEndpoint() {
        modelStatus = .connecting
        let start = Date()
        let clean = localModelEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Try /models or /v1/models or /health
        let probeUrlStr = clean.hasSuffix("/v1") ? "\(clean)/models" : "\(clean)/health"
        guard let url = URL(string: probeUrlStr) else {
            modelStatus = .offline
            modelPingLatencyMs = -1
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 3.0
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
        let userMsg = ChatMessage(role: .user, content: prompt)
        chatMessages.append(userMsg)

        let assistantId = UUID()
        let assistantMsg = ChatMessage(id: assistantId, role: .assistant, content: "")
        chatMessages.append(assistantMsg)
        isGenerating = true

        Task {
            do {
                _ = try await localModelClient.sendChat(
                    endpoint: localModelEndpoint,
                    model: activeModelName,
                    messages: chatMessages.filter { $0.id != assistantId },
                    onDelta: { [weak self] delta in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                                self.chatMessages[idx].content += delta
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
                    }
                )
            } catch {
                await MainActor.run {
                    if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantId }) {
                        if self.chatMessages[idx].content.isEmpty {
                            self.chatMessages[idx].content = "⚠️ Error communicating with model endpoint: \(error.localizedDescription)\nEnsure local or LAN model server is running at \(self.localModelEndpoint)."
                        }
                    }
                }
            }
            await MainActor.run {
                self.isGenerating = false
            }
        }
    }
}

func structLogBridge(_ code: String, _ msg: String) {
    let payload = ["domain": "cockpit", "level": "info", "code": code, "msg": msg]
    if let data = try? JSONSerialization.data(withJSONObject: payload),
       let line = String(data: data, encoding: .utf8) {
        NSLog("[cockpit] %@", line)
    }
}
