import Foundation

final class LocalModelClient {
    static let shared = LocalModelClient()

    private let versionManager = CodeVersionManager.shared
    private let cliRunner = CLIRunner.shared
    private let mcpBridge = MCPBridgeService.shared
    private let harnessService = CodebaseHarnessService.shared

    func buildTools() -> [[String: Any]] {
        var tools: [[String: Any]] = [
            // Codebase Manipulation Tools (from Qwythos Coding Harness)
            [
                "type": "function",
                "function": [
                    "name": "read_file",
                    "description": "Read file contents from the active project workspace. Supports reading entire file or slice with offset/length.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string", "description": "Relative or absolute file path to read"],
                            "offset": ["type": "integer", "description": "Optional starting character offset"],
                            "length": ["type": "integer", "description": "Optional number of characters to read"]
                        ],
                        "required": ["path"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "write_file",
                    "description": "Write code or text content to a file in the project workspace. Automatically tracks the file as a deliverable and commits a version diff revision.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string", "description": "Target file path"],
                            "content": ["type": "string", "description": "Full file content to write"]
                        ],
                        "required": ["path", "content"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "replace_file_content",
                    "description": "Surgically replace an exact block of text in an existing file with replacement content.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string", "description": "File path to modify"],
                            "target": ["type": "string", "description": "Exact text block to replace"],
                            "replacement": ["type": "string", "description": "Replacement text block"]
                        ],
                        "required": ["path", "target", "replacement"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "list_dir",
                    "description": "List files and directories in a given folder (or project root).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string", "description": "Optional folder path to list (defaults to project root)"]
                        ]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "grep_search",
                    "description": "Search for code patterns, symbols, or regex matches across the project workspace.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": ["type": "string", "description": "String or regex pattern to search for"],
                            "path": ["type": "string", "description": "Optional subfolder to constrain search to"]
                        ],
                        "required": ["query"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "code_feedback",
                    "description": "Run execution feedback loop: executes linter, compiler/typecheck, and tests (pytest/npm/swift) and returns stdout/stderr as observation.",
                    "parameters": [
                        "type": "object",
                        "properties": [:]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "durable_memory",
                    "description": "Read, write, or append to durable project memory (.agents/memory/MEMORY.md).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "action": ["type": "string", "enum": ["read", "write", "append"], "description": "Action to perform"],
                            "content": ["type": "string", "description": "Content for write or append"]
                        ],
                        "required": ["action"]
                    ]
                ]
            ],
            // Inference Offload Consult Tools
            [
                "type": "function",
                "function": [
                    "name": "consult_deepseek",
                    "description": "Execute a proper DeepSeek consultation: automatically requests DeepSeek to generate the entire architectural scaffolding, followed by 3 sequential audits across distinct aspects (Pass 1: Correctness & Edge Cases; Pass 2: Security Hardening & Boundaries; Pass 3: Performance & Big-O Complexity). The baseline and each successive stage are committed to the version diff ring.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "code": ["type": "string", "description": "The target source code or initial specification to scaffold and audit"],
                            "prompt": ["type": "string", "description": "High-level mission goals, architectural requirements, and scope"],
                            "template": ["type": "string", "description": "Template or file identifier, e.g. 'qwythos_code_audit' or 'main.py'"]
                        ],
                        "required": ["code", "prompt"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "consult_kimi",
                    "description": "Send UI components, layouts, or styles to Kimi for visual aesthetics and design system critique. Automatically commits revisions with unified diffs.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "code_or_ui": ["type": "string", "description": "CSS, SwiftUI, Svelte, or UI code to review"],
                            "prompt": ["type": "string", "description": "Design criteria and aesthetic objectives"],
                            "template": ["type": "string", "description": "Template name, e.g. 'kimi_design_system_review'"]
                        ],
                        "required": ["code_or_ui", "prompt"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "browser_eval",
                    "description": "Control the logged-in browser (the browser mirror). action read = dump the visible page text so you can evaluate what is on screen; action clear = erase the focused input field; action type (with text) = enter text into the focused input field (use for logins, searches, form filling).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "action": ["type": "string", "enum": ["read", "clear", "type"]],
                            "text": ["type": "string", "description": "Text to type (required when action is type)"]
                        ],
                        "required": ["action"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "run_command",
                    "description": "Execute a shell command (zsh/bash) in the project environment to run compilers, linters, git commands, or check system files.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "command": ["type": "string", "description": "The shell command to execute"],
                            "cwd": ["type": "string", "description": "Optional directory to run command in"]
                        ],
                        "required": ["command"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "save_code_revision",
                    "description": "Explicitly save a new code revision into the version control chain with summary description.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "file_path": ["type": "string", "description": "Target file path or module name"],
                            "code": ["type": "string", "description": "The revised code content"],
                            "summary": ["type": "string", "description": "Brief description of changes"]
                        ],
                        "required": ["file_path", "code", "summary"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "run_applescript_app",
                    "description": "Run an AppleScript app or script on macOS. Automatically renders and captures the actual window visuals in the OS Viz tab so you can see the visuals and make adjustments within your loop.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "script": ["type": "string", "description": "The AppleScript code to execute (e.g. display dialog, Cocoa window, System Events)"],
                            "file": ["type": "string", "description": "Optional path to a .applescript or .scpt file in workspace"]
                        ]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "capture_app_visuals",
                    "description": "Capture the actual visual snapshot of the running AppleScript app or active window on macOS. Updates the OS Viz canvas and saves /tmp/offcoder_os_viz.png for your review loop.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "description": "Optional title of the window or app"]
                        ]
                    ]
                ]
            ]
        ]
        if BuildConfig.isBlank {
            tools = tools.filter { tool in
                guard let name = (tool["function"] as? [String: Any])?["name"] as? String else { return true }
                return !name.hasPrefix("consult_") && name != "run_applescript_app" && name != "capture_app_visuals"
            }
        }
        return tools
    }

    // MARK: - Resilient LAN & mDNS Host Resolution
    static func resolveHostToIPv4(_ host: String) -> String? {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else {
            return nil
        }
        defer { freeaddrinfo(res) }

        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let sockaddrIn = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var addr = sockaddrIn.sin_addr
        inet_ntop(AF_INET, &addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
        let ip = String(cString: ipBuf)
        return ip.isEmpty ? nil : ip
    }

    static func resolveEndpointString(_ endpoint: String) -> String {
        guard var components = URLComponents(string: endpoint), let host = components.host else {
            return endpoint
        }
        if host.hasSuffix(".local") {
            if let ip = resolveHostToIPv4(host) {
                components.host = ip
            } else if host == "lockfort.local" {
                components.host = "192.168.1.80"
            }
            return components.string ?? endpoint
        }
        return endpoint
    }

    func sendChat(
        endpoint: String,
        model: String,
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onThoughtDelta: ((String) -> Void)? = nil,
        onProcessUpdate: ((String, String) -> Void)? = nil,
        onToolCall: @escaping (ToolCallItem) -> Void,
        onReflectionUpdate: ((String, String) -> Void)? = nil
    ) async throws -> (content: String, thought: String) {
        let startTime = Date()
        let resolvedEndpoint = LocalModelClient.resolveEndpointString(endpoint)
        let cleanedEndpoint = resolvedEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let port: Int = {
            if let url = URL(string: cleanedEndpoint), let p = url.port { return p }
            if cleanedEndpoint.contains(":8080") { return 8080 }
            if cleanedEndpoint.contains(":8000") { return 8000 }
            if cleanedEndpoint.contains(":11434") { return 11434 }
            if cleanedEndpoint.contains(":1234") { return 1234 }
            return 8080
        }()

        let targetUrlStr = cleanedEndpoint.hasSuffix("/v1")
            ? "\(cleanedEndpoint)/chat/completions"
            : (cleanedEndpoint.contains("/v1/") ? cleanedEndpoint : "\(cleanedEndpoint)/v1/chat/completions")

        guard let url = URL(string: targetUrlStr) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build messages payload with injected version control and harness context
        let projectDir = harnessService.activeProjectDir ?? (harnessService.qwythosBaseDir + "/projects/active")
        var wireMessages: [[String: Any]] = [
            [
                "role": "system",
                "content": """
You are \(BuildConfig.agentSystemName)
Operating Workspace: \(projectDir)

ROLE & ORCHESTRATION MANDATE:
You are the high-level strategist and mission driver. You think across long horizons, break big ideas down into executable phases, communicate with the harness components, and push progress forward toward realizing mission goals.

PHASE-BY-PHASE ASSESSMENT PROTOCOL:
- In between phases, you take an intentional turn to assess the state of the project.
- Scrutinize the outputs, test results, and diffs from the previous phase.
- IF everything looks solid and nominal: move the project onto the next phase.
- IF something is broken, incomplete, or failing: hold the line and repeat or refine the last step until verified.

PROPER CONSULT PROTOCOL (DEEPSEEK SCAFFOLD + TRIPLE AUDIT):
- When requesting an implementation or deep overhaul, call `consult_deepseek`.
- A proper consult toolcall automatically triggers a 4-stage pipeline:
  1. Full architectural scaffolding and complete file generation.
  2. Audit Pass 1: Correctness, logic integrity, boundary & edge cases.
  3. Audit Pass 2: Hostile security audit, input boundaries & hardening.
  4. Audit Pass 3: Performance, asymptotic Big-O complexity & heap allocation minimization.
- Each stage is committed to the version diff ring with line-by-line unified diff tracking.

BROWSER DIRECT CONTROL:
- Use browser_eval read to evaluate what is on screen before acting, then share your thoughts.
- Use browser_eval type to enter text into the login/search fields; use clear to erase a field.
- The mirrored browser is the persistent login session — driving it is driving the logged-in browser.

HARNESS CAPABILITIES:
1. CODEBASE RECONNAISSANCE: Use `read_file`, `list_dir`, and `grep_search` to map dependencies and symbols.
2. DRAFT & DELIVER: Use `write_file` or `replace_file_content` to commit deliverables.
3. VERIFICATION: Use `code_feedback` to run linters, compilers, and test suites.
4. DURABLE MEMORY: Maintain mission milestones and architecture in `.agents/memory/MEMORY.md` via `durable_memory`.

\(TotemPortListenerService.shared.generateSynthesizedContext())

\(versionManager.generateVersionContextPrompt())
"""
            ]
        ]

        for msg in messages {
            wireMessages.append([
                "role": msg.role.rawValue,
                "content": msg.content
            ])
        }

        onProcessUpdate?("INGESTING_PROMPT", "Ingesting instructions & preparing turn...")

        let totem = TotemPortListenerService.shared.activeTotem
        var payload: [String: Any] = [
            "model": model,
            "messages": wireMessages,
            "tools": buildTools(),
            "stream": true,
            "temperature": totem.temperature,
            "top_p": totem.topP,
            "top_k": totem.topK,
            "min_p": totem.minP,
            "repeat_penalty": totem.repeatPenalty,
            "presence_penalty": totem.presencePenalty,
            "frequency_penalty": totem.frequencyPenalty
        ]
        if totem.seed >= 0 {
            payload["seed"] = totem.seed
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var accumulatedThought = ""
        var accumulatedContent = ""
        var executedToolItems: [ToolCallItem] = []
        var stepPayload = payload
        let maxSteps = 6
        var busyMessage: [String: Any] = [:]
        busyMessage["role"] = "assistant"
        busyMessage["content"] = ""

        onProcessUpdate?("REASONING", "thinking...")

        for step in 0..<maxSteps {
            if step > 0 && executedToolItems.isEmpty { break }

            stepPayload["stream"] = true
            let (thoughtDelta, contentDelta, toolCalls) = try await streamCompletion(
                urlString: targetUrlStr,
                payload: stepPayload,
                onDelta: onDelta,
                onThoughtDelta: onThoughtDelta,
                onProcessUpdate: onProcessUpdate
            )

            accumulatedThought += thoughtDelta
            accumulatedContent += contentDelta
            if !executedToolItems.isEmpty {
                busyMessage["content"] = accumulatedContent
            }

            if toolCalls.isEmpty {
                break
            }

            // Execute this turn's tool calls
            var turnExecuted: [ToolCallItem] = []
            for item in toolCalls {
                var toolItem = ToolCallItem(id: item.id, name: item.name, arguments: item.arguments, status: .executing)
                onToolCall(toolItem)

                let desc = friendlyToolDescription(name: item.name, argsString: item.arguments)
                onProcessUpdate?("EXECUTING_TOOL", desc)

                let output = await executeTool(name: item.name, argsString: item.arguments, onReflectionUpdate: onReflectionUpdate)
                toolItem.output = output
                toolItem.status = .completed
                onToolCall(toolItem)
                turnExecuted.append(toolItem)

                onProcessUpdate?("STRATEGIC_ASSESSMENT", "Assessing tool execution results & phase transition...")
            }
            executedToolItems.append(contentsOf: turnExecuted)

            // Feed the tool results back so the model can continue its turn
            var followUp = wireMessages
            if !accumulatedContent.isEmpty || busyMessage["content"] != nil {
                busyMessage["tool_calls"] = toolCalls.map { tc in
                    [
                        "id": tc.id,
                        "type": "function",
                        "function": ["name": tc.name, "arguments": tc.arguments]
                    ] as [String: Any]
                }
                followUp.append(busyMessage)
            }
            for item in turnExecuted {
                followUp.append([
                    "role": "tool",
                    "tool_call_id": item.id,
                    "content": item.output
                ])
            }
            stepPayload["messages"] = followUp
        }

        // Totem / Port Listener: Record raw input & output and consolidate biodynamic memory
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        TotemPortListenerService.shared.recordTransaction(
            port: port,
            endpoint: targetUrlStr,
            model: model,
            requestPayload: payload,
            responseContent: accumulatedContent,
            reasoningContent: accumulatedThought,
            toolCalls: executedToolItems,
            durationMs: durationMs
        )

        onProcessUpdate?("IDLE", "Standby")
        return (content: accumulatedContent, thought: accumulatedThought)
    }

    /// Streams one completion for the given payload (SSE primary, non-streaming fallback),
    /// returns (thought, content, toolCalls) accumulated for that single model turn.
    private func streamCompletion(
        urlString: String,
        payload: [String: Any],
        onDelta: @escaping (String) -> Void,
        onThoughtDelta: ((String) -> Void)?,
        onProcessUpdate: ((String, String) -> Void)?
    ) async throws -> (thought: String, content: String, toolCalls: [(id: String, name: String, arguments: String)]) {
        var accumulatedThought = ""
        var accumulatedContent = ""
        var toolCallAccumulator: [Int: (id: String, name: String, arguments: String)] = [:]
        var streamSucceeded = false

        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // 1. Primary: Real-time SSE streaming for live reasoning and tokens
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let raw = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if raw == "[DONE]" { break }
                    guard let data = raw.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let firstChoice = choices.first else { continue }

                    streamSucceeded = true

                    if let delta = firstChoice["delta"] as? [String: Any] {
                        // Live reasoning content
                        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                            accumulatedThought += reasoning
                            onThoughtDelta?(reasoning)
                        }

                        // Live regular content
                        if let content = delta["content"] as? String, !content.isEmpty {
                            accumulatedContent += content
                            onDelta(content)
                        }

                        // Live tool calls
                        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                            for tc in toolCalls {
                                let idx = tc["index"] as? Int ?? 0
                                if toolCallAccumulator[idx] == nil {
                                    toolCallAccumulator[idx] = (id: tc["id"] as? String ?? UUID().uuidString, name: "", arguments: "")
                                }
                                if let id = tc["id"] as? String, !id.isEmpty {
                                    toolCallAccumulator[idx]?.id = id
                                }
                                if let function = tc["function"] as? [String: Any] {
                                    if let name = function["name"] as? String {
                                        toolCallAccumulator[idx]?.name += name
                                    }
                                    if let args = function["arguments"] as? String {
                                        toolCallAccumulator[idx]?.arguments += args
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            streamSucceeded = false
        }

        // 2. Secondary fallback: Non-streaming call if SSE didn't return content
        if !streamSucceeded || (accumulatedContent.isEmpty && accumulatedThought.isEmpty && toolCallAccumulator.isEmpty) {
            onProcessUpdate?("CONNECTING", "Evaluating model response...")
            var fallbackPayload = payload
            fallbackPayload["stream"] = false
            req.httpBody = try JSONSerialization.data(withJSONObject: fallbackPayload)

            let (data, response) = try await URLSession.shared.data(for: req)
            if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any] {

                if let reasoning = message["reasoning_content"] as? String, !reasoning.isEmpty {
                    accumulatedThought = reasoning
                    onThoughtDelta?(reasoning)
                }

                let content = message["content"] as? String ?? ""
                if !content.isEmpty {
                    accumulatedContent = content
                    onDelta(content)
                }

                if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                    for (i, tc) in toolCalls.enumerated() {
                        let id = tc["id"] as? String ?? UUID().uuidString
                        let function = tc["function"] as? [String: Any] ?? [:]
                        let name = function["name"] as? String ?? ""
                        let args = function["arguments"] as? String ?? "{}"
                        toolCallAccumulator[i] = (id: id, name: name, arguments: args)
                    }
                }
            }
        }

        // 3. Fallback check for models that output <think>...</think> directly in content
        if accumulatedThought.isEmpty && accumulatedContent.contains("<think>") {
            if let start = accumulatedContent.range(of: "<think>"),
               let end = accumulatedContent.range(of: "</think>") {
                let thought = String(accumulatedContent[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                accumulatedThought = thought
                onThoughtDelta?(thought)
            }
        }

        // 4. Fallback: Parse <tool_call> XML blocks embedded in content using robust Regex
        //    Handles models that emit tool calls as text rather than structured tool_calls.
        //    Supports format: <tool_call>\n<function=name>\n<parameter=key>value</parameter>\n</function>\n</tool_call>
        //    Supports XML format: <tool_call><function name="func"><parameter name="key">val</parameter></function></tool_call>
        //    Also supports JSON format: <tool_call>{"name":"func","arguments":{...}}</tool_call>
        if toolCallAccumulator.isEmpty && accumulatedContent.contains("<tool_call>") {
            let tcPattern = "(?s)<tool_call>(.*?)</tool_call>"
            if let tcRegex = try? NSRegularExpression(pattern: tcPattern) {
                let matches = tcRegex.matches(in: accumulatedContent, range: NSRange(accumulatedContent.startIndex..., in: accumulatedContent))
                var xmlToolIndex = toolCallAccumulator.count
                
                for match in matches {
                    if let blockRange = Range(match.range(at: 1), in: accumulatedContent) {
                        let blockContent = String(accumulatedContent[blockRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Try standard XML parsing (supporting <function=foo> or <function name="foo">)
                        let funcPattern = "(?s)<function(?:\\s*=\\s*([^>]+)|\\s+name=[\"']([^\"']+)[\"'])>(.*?)</function>"
                        if let funcRegex = try? NSRegularExpression(pattern: funcPattern),
                           let funcMatch = funcRegex.firstMatch(in: blockContent, range: NSRange(blockContent.startIndex..., in: blockContent)) {
                            
                            var funcName = ""
                            if let r1 = Range(funcMatch.range(at: 1), in: blockContent) { funcName = String(blockContent[r1]).trimmingCharacters(in: .whitespacesAndNewlines) }
                            else if let r2 = Range(funcMatch.range(at: 2), in: blockContent) { funcName = String(blockContent[r2]).trimmingCharacters(in: .whitespacesAndNewlines) }
                            
                            if let innerContentRange = Range(funcMatch.range(at: 3), in: blockContent) {
                                let innerContent = String(blockContent[innerContentRange])
                                
                                // Parse parameters <parameter=key>val</parameter> or <parameter name="key">val</parameter>
                                let paramPattern = "(?s)<parameter(?:\\s*=\\s*([^>]+)|\\s+name=[\"']([^\"']+)[\"'])>(.*?)</parameter>"
                                if let paramRegex = try? NSRegularExpression(pattern: paramPattern) {
                                    let pMatches = paramRegex.matches(in: innerContent, range: NSRange(innerContent.startIndex..., in: innerContent))
                                    var params: [String: Any] = [:]
                                    
                                    for pMatch in pMatches {
                                        var pName = ""
                                        if let pr1 = Range(pMatch.range(at: 1), in: innerContent) { pName = String(innerContent[pr1]).trimmingCharacters(in: .whitespacesAndNewlines) }
                                        else if let pr2 = Range(pMatch.range(at: 2), in: innerContent) { pName = String(innerContent[pr2]).trimmingCharacters(in: .whitespacesAndNewlines) }
                                        
                                        if let pValRange = Range(pMatch.range(at: 3), in: innerContent) {
                                            params[pName] = String(innerContent[pValRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                        }
                                    }
                                    
                                    let argsJSON = (try? JSONSerialization.data(withJSONObject: params))
                                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                                    
                                    toolCallAccumulator[xmlToolIndex] = (
                                        id: "xmltc_\(xmlToolIndex)_\(UUID().uuidString.prefix(8))",
                                        name: funcName,
                                        arguments: argsJSON
                                    )
                                    xmlToolIndex += 1
                                }
                            }
                        }
                        // Try JSON format parsing: {"name":"func","arguments":{...}}
                        else if let jsonData = blockContent.data(using: .utf8),
                                let jsonObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            let name = jsonObj["name"] as? String ?? ""
                            var argsJSON = "{}"
                            if let argsDict = jsonObj["arguments"] as? [String: Any],
                               let argsData = try? JSONSerialization.data(withJSONObject: argsDict) {
                                argsJSON = String(data: argsData, encoding: .utf8) ?? "{}"
                            } else if let argsStr = jsonObj["arguments"] as? String {
                                argsJSON = argsStr
                            }
                            
                            if !name.isEmpty {
                                toolCallAccumulator[xmlToolIndex] = (
                                    id: "xmltc_\(xmlToolIndex)_\(UUID().uuidString.prefix(8))",
                                    name: name,
                                    arguments: argsJSON
                                )
                                xmlToolIndex += 1
                            }
                        }
                    }
                }
                
                // Strip the tool_call XML from visible content if we parsed any
                if !matches.isEmpty && !toolCallAccumulator.isEmpty {
                    accumulatedContent = tcRegex.stringByReplacingMatches(
                        in: accumulatedContent,
                        range: NSRange(accumulatedContent.startIndex..., in: accumulatedContent),
                        withTemplate: ""
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let sortedToolCalls = toolCallAccumulator.keys.sorted().compactMap { idx -> (id: String, name: String, arguments: String)? in
            guard let item = toolCallAccumulator[idx], !item.name.isEmpty else { return nil }
            return item
        }

        return (thought: accumulatedThought, content: accumulatedContent, toolCalls: sortedToolCalls)
    }

    private func friendlyToolDescription(name: String, argsString: String) -> String {
        switch name {
        case "consult_deepseek":
            return "Consulting DeepSeek: Scaffolding & Triple Audit"
        case "consult_kimi":
            return "Consulting Kimi: Visual & UI Critique"
        case "read_file":
            if let data = argsString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let path = json["path"] as? String {
                return "Reading file: \(path.split(separator: "/").last.map(String.init) ?? path)"
            }
            return "Reading workspace file"
        case "write_file":
            if let data = argsString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let path = json["path"] as? String {
                return "Writing file: \(path.split(separator: "/").last.map(String.init) ?? path)"
            }
            return "Writing workspace file"
        case "replace_file_content":
            if let data = argsString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let path = json["path"] as? String {
                return "Refactoring: \(path.split(separator: "/").last.map(String.init) ?? path)"
            }
            return "Refactoring file content"
        case "run_command":
            if let data = argsString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cmd = json["command"] as? String {
                return "Running: \(cmd.prefix(30))..."
            }
            return "Executing shell command"
        case "browser_eval":
            if let data = argsString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let action = json["action"] as? String {
                return action == "type" ? "Typing in browser input" : "Evaluating browser: \(action)"
            }
            return "Controlling browser"
        case "code_feedback":
            return "Running test suite & harness verification"
        case "durable_memory":
            return "Syncing durable memory (.agents/memory)"
        default:
            return "Executing \(name)"
        }
    }

    private func executeTool(name: String, argsString: String, onReflectionUpdate: ((String, String) -> Void)?) async -> String {
        guard let data = argsString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Error: failed to parse tool arguments JSON"
        }

        switch name {
        // File & Codebase Operations
        case "read_file":
            let path = json["path"] as? String ?? ""
            let offset = json["offset"] as? Int
            let length = json["length"] as? Int
            let (content, error) = harnessService.readFile(path: path, offset: offset, length: length)
            if let error = error { return error }
            return content

        case "write_file":
            let path = json["path"] as? String ?? ""
            let content = json["content"] as? String ?? ""
            let res = harnessService.writeFile(path: path, content: content)
            ProductionSimulatorService.shared.appendLog(source: "[WRITE]", message: "Saved \(path.split(separator: "/").last.map(String.init) ?? path)", level: "info")
            return res.message

        case "replace_file_content":
            let path = json["path"] as? String ?? ""
            let target = json["target"] as? String ?? ""
            let replacement = json["replacement"] as? String ?? ""
            let res = harnessService.replaceFileContent(path: path, target: target, replacement: replacement)
            ProductionSimulatorService.shared.appendLog(source: "[PATCH]", message: "Patched \(path.split(separator: "/").last.map(String.init) ?? path)", level: "info")
            return res.message

        case "list_dir":
            let path = json["path"] as? String
            return harnessService.listDir(path: path)

        case "grep_search":
            let query = json["query"] as? String ?? ""
            let path = json["path"] as? String
            return await harnessService.grepSearch(query: query, path: path)

        case "browser_eval":
            let action = json["action"] as? String ?? "read"
            let text = json["text"] as? String ?? ""
            return await BrowserEvalBridge.shared.eval(action: action, text: text)

        case "code_feedback":
            ProductionSimulatorService.shared.appendLog(source: "[QWYTHOS]", message: "Running code feedback & test suite...", level: "info")
            let (passed, summary) = await harnessService.runCodeFeedback()
            ProductionSimulatorService.shared.appendLog(source: "[TEST]", message: summary.trimmingCharacters(in: .whitespacesAndNewlines), level: passed ? "success" : "warn")
            return summary

        case "durable_memory":
            let action = json["action"] as? String ?? "read"
            let content = json["content"] as? String
            return harnessService.durableMemory(action: action, content: content)

        // Consult Offload
        case "consult_deepseek":
            let code = json["code"] as? String ?? ""
            let prompt = json["prompt"] as? String ?? "Audit"
            let template = json["template"] as? String ?? "qwythos_code_audit"
            let res = await mcpBridge.consultDeepSeek(
                code: code,
                prompt: prompt,
                template: template,
                onReflectionUpdate: onReflectionUpdate
            )
            return "✅ DeepSeek Audit Complete (Committed as v\(res.revision.versionIndex)):\n\nUnified Diff:\n```diff\n\(res.revision.diffFromPrevious)\n```\n\nAudited Code:\n```\n\(res.auditedCode)\n```"

        case "consult_kimi":
            let codeOrUI = json["code_or_ui"] as? String ?? ""
            let prompt = json["prompt"] as? String ?? "Design review"
            let template = json["template"] as? String ?? "kimi_design_system_review"
            let res = await mcpBridge.consultKimi(
                codeOrUI: codeOrUI,
                prompt: prompt,
                template: template,
                onReflectionUpdate: onReflectionUpdate
            )
            return "🎨 Kimi Design Review Complete (Committed as v\(res.revision.versionIndex)):\n\nUnified Diff:\n```diff\n\(res.revision.diffFromPrevious)\n```\n\nOptimized Code:\n```\n\(res.auditedCode)\n```"

        case "run_command":
            let command = json["command"] as? String ?? ""
            let cwd = json["cwd"] as? String ?? harnessService.activeProjectDir
            ProductionSimulatorService.shared.appendLog(source: "[QWYTHOS]", message: "$ \(command)", level: "info")
            let (stdout, stderr, exitCode) = await cliRunner.execute(command: command, workingDirectory: cwd)
            if !stdout.isEmpty {
                for line in stdout.components(separatedBy: .newlines) where !line.isEmpty {
                    ProductionSimulatorService.shared.appendLog(source: "[STDOUT]", message: line, level: "info")
                }
            }
            if !stderr.isEmpty {
                for line in stderr.components(separatedBy: .newlines) where !line.isEmpty {
                    ProductionSimulatorService.shared.appendLog(source: "[STDERR]", message: line, level: "warn")
                }
            }
            ProductionSimulatorService.shared.appendLog(
                source: exitCode == 0 ? "[DONE]" : "[FAIL]",
                message: "Process exited with code \(exitCode)",
                level: exitCode == 0 ? "success" : "error"
            )
            var out = "Exit Code: \(exitCode)\n"
            if !stdout.isEmpty { out += "STDOUT:\n\(stdout)\n" }
            if !stderr.isEmpty { out += "STDERR:\n\(stderr)\n" }
            return out

        case "save_code_revision":
            let filePath = json["file_path"] as? String ?? "active_buffer.py"
            let code = json["code"] as? String ?? ""
            let summary = json["summary"] as? String ?? "Manual revision"
            let rev = versionManager.commitRevision(filePath: filePath, code: code, origin: .localModel, summary: summary)
            return "Committed v\(rev.versionIndex) for \(filePath) with diff from previous:\n```diff\n\(rev.diffFromPrevious)\n```"

        case "run_applescript_app":
            let script = json["script"] as? String
            let file = json["file"] as? String
            ProductionSimulatorService.shared.runAppleScript(script: script, file: file)
            let sim = ProductionSimulatorService.shared
            return "✅ AppleScript executed. Real visual frame captured and rendered in OS Viz canvas (/tmp/offcoder_os_viz.png, Resolution: \(Int(sim.osAppResolution.width))x\(Int(sim.osAppResolution.height))). Visual feedback is available for your review loop."

        case "capture_app_visuals":
            let title = json["title"] as? String ?? "App Visuals"
            ProductionSimulatorService.shared.captureOSVisuals(title: title)
            let sim = ProductionSimulatorService.shared
            return "📸 Window visuals captured for OS Viz review loop (/tmp/offcoder_os_viz.png, Resolution: \(Int(sim.osAppResolution.width))x\(Int(sim.osAppResolution.height)))."

        default:
            return "Unknown tool: \(name)"
        }
    }
}

// MARK: - Semantic Context Compression by Qwythos
extension LocalModelClient {
    func compressConversation(
        endpoint: String,
        model: String,
        messages: [ChatMessage]
    ) async throws -> String {
        guard !messages.isEmpty else { return "" }

        let resolvedEndpoint = LocalModelClient.resolveEndpointString(endpoint)
        let cleanedEndpoint = resolvedEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetUrlStr = cleanedEndpoint.hasSuffix("/v1")
            ? "\(cleanedEndpoint)/chat/completions"
            : (cleanedEndpoint.contains("/v1/") ? cleanedEndpoint : "\(cleanedEndpoint)/v1/chat/completions")

        guard let url = URL(string: targetUrlStr) else {
            throw URLError(.badURL)
        }

        // Format the entire conversation into a structured transcript
        var transcript = ""
        for m in messages {
            transcript += "[\(m.role.rawValue.uppercased())]: \(m.content)\n"
            for tc in m.toolCalls {
                transcript += "  -> TOOL CALL: \(tc.name)(\(tc.arguments))\n"
                if let out = tc.output {
                    transcript += "     OUTPUT: \(out.prefix(200))...\n"
                }
            }
        }

        let compressionPrompt = """
\(BuildConfig.compressIdentity) Perform a dense semantic compression of the conversation context below.
Capture all durable architectural decisions, modified file paths, active bugs or directives, code states, and current working plan into a structured markdown executive briefing.
Preserve exact function names, file paths, variables, and constraints. Omit small talk and ephemeral banter.

CONVERSATION TRANSCRIPT TO COMPRESS:
\(transcript)
"""

        let wireMessages: [[String: Any]] = [
            [
                "role": "system",
                "content": "\(BuildConfig.compressIdentity) An apex coder specializing in lossless semantic compression and codebase memory distillation."
            ],
            [
                "role": "user",
                "content": compressionPrompt
            ]
        ]

        let payload: [String: Any] = [
            "model": model,
            "messages": wireMessages,
            "stream": false,
            "temperature": 0.2
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Compression request failed"
            throw NSError(domain: "LocalModelClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return content
        }

        return "Summary of conversation (\(messages.count) turns compressed)."
    }
}
