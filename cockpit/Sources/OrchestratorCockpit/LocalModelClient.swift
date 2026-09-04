import Foundation

final class LocalModelClient {
    static let shared = LocalModelClient()

    private let versionManager = CodeVersionManager.shared
    private let cliRunner = CLIRunner.shared
    private let mcpBridge = MCPBridgeService.shared
    private let harnessService = CodebaseHarnessService.shared

    func buildTools() -> [[String: Any]] {
        return [
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
                    "description": "Send code to DeepSeek for deep algorithmic, security, and performance audit. The original code is saved as a baseline revision, and the audited result is committed with line-by-line diff tracking.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "code": ["type": "string", "description": "The exact source code block to audit"],
                            "prompt": ["type": "string", "description": "Specific audit objectives (e.g. edge cases, performance, security)"],
                            "template": ["type": "string", "description": "Template name, e.g. 'qwythos_code_audit' or 'code_audit_deep'"]
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
            ]
        ]
    }

    func sendChat(
        endpoint: String,
        model: String,
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCallItem) -> Void,
        onReflectionUpdate: ((String, String) -> Void)? = nil
    ) async throws -> String {
        let cleanedEndpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
You are Offcoder — an apex local coding assistant powered by the Qwythos coding harness and inference offload architecture.
Operating Workspace: \(projectDir)

CAPABILITIES & HARNESS DIRECTIVES:
1. CODEBASE EXPLORATION: Use `read_file`, `list_dir`, and `grep_search` to inspect files and find symbols.
2. DRAFT & DELIVER: Use `write_file` or `replace_file_content` to write code. Every written file is automatically registered as a deliverable and committed to version control.
3. MANDATORY AUDIT CONSULTATION: When writing critical algorithms or refactoring, offload audit to `consult_deepseek`. For UI/UX or styling, use `consult_kimi`.
4. EXECUTION FEEDBACK: After writing code, run `code_feedback` to run tests and linters, verifying the changes pass cleanly.
5. DURABLE MEMORY: Maintain key project facts in `.agents/memory/MEMORY.md` via `durable_memory`.

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

        let payload: [String: Any] = [
            "model": model,
            "messages": wireMessages,
            "tools": buildTools(),
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown response error"
            throw NSError(domain: "LocalModelClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let rawStr = String(data: data, encoding: .utf8) ?? ""
            onDelta(rawStr)
            return rawStr
        }

        let choices = json["choices"] as? [[String: Any]] ?? []
        guard let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            let text = json["text"] as? String ?? "No response content"
            onDelta(text)
            return text
        }

        let content = message["content"] as? String ?? ""
        if !content.isEmpty {
            onDelta(content)
        }

        // Handle tool calls if returned
        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for tc in toolCalls {
                guard let function = tc["function"] as? [String: Any],
                      let name = function["name"] as? String else { continue }

                let argsStr = function["arguments"] as? String ?? "{}"
                let callId = tc["id"] as? String ?? UUID().uuidString
                var toolItem = ToolCallItem(id: callId, name: name, arguments: argsStr, status: .executing)
                onToolCall(toolItem)

                // Execute tool
                let output = await executeTool(name: name, argsString: argsStr, onReflectionUpdate: onReflectionUpdate)
                toolItem.output = output
                toolItem.status = .completed
                onToolCall(toolItem)
            }
        }

        return content
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
            return res.message

        case "replace_file_content":
            let path = json["path"] as? String ?? ""
            let target = json["target"] as? String ?? ""
            let replacement = json["replacement"] as? String ?? ""
            let res = harnessService.replaceFileContent(path: path, target: target, replacement: replacement)
            return res.message

        case "list_dir":
            let path = json["path"] as? String
            return harnessService.listDir(path: path)

        case "grep_search":
            let query = json["query"] as? String ?? ""
            let path = json["path"] as? String
            return await harnessService.grepSearch(query: query, path: path)

        case "code_feedback":
            let (_, summary) = await harnessService.runCodeFeedback()
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
            let (stdout, stderr, exitCode) = await cliRunner.execute(command: command, workingDirectory: cwd)
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

        let cleanedEndpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
You are Qwythos. Perform a dense semantic compression of the conversation context below.
Capture all durable architectural decisions, modified file paths, active bugs or directives, code states, and current working plan into a structured markdown executive briefing.
Preserve exact function names, file paths, variables, and constraints. Omit small talk and ephemeral banter.

CONVERSATION TRANSCRIPT TO COMPRESS:
\(transcript)
"""

        let wireMessages: [[String: Any]] = [
            [
                "role": "system",
                "content": "You are Qwythos, an apex coder specializing in lossless semantic compression and codebase memory distillation."
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
