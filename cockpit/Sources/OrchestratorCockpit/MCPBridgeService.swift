import Foundation

final class MCPBridgeService {
    static let shared = MCPBridgeService()

    private let versionManager = CodeVersionManager.shared

    func consultDeepSeek(
        code: String,
        prompt: String,
        filePath: String = "active_buffer.py",
        template: String = "code_audit_deep",
        onReflectionUpdate: ((String, String) -> Void)? = nil
    ) async -> (auditedCode: String, explanation: String, revision: CodeRevision) {
        // 1. Snapshot original code before consult
        versionManager.commitRevision(
            filePath: filePath,
            code: code,
            origin: .userOriginal,
            summary: "Pre-audit baseline (\(template))"
        )

        let consultPrompt = "Audit and optimize this code according to template '\(template)'. Return clean, production-ready code with diff explanations:\n\nUser Notes: \(prompt)\n\nCode:\n```\n\(code)\n```"
        onReflectionUpdate?("DEEPSEEK_WEB", consultPrompt)

        // 2. Query consult MCP or local dispatcher
        let result = await callConsultScript(provider: "deepseek", prompt: consultPrompt)
        onReflectionUpdate?("DEEPSEEK_WEB", result)

        let extractedCode = extractCodeBlock(from: result) ?? result

        // 3. Snapshot audited code as next version
        let newRev = versionManager.commitRevision(
            filePath: filePath,
            code: extractedCode,
            origin: .deepseekAudit,
            summary: "DeepSeek Coder Audit (\(template))"
        )

        return (auditedCode: extractedCode, explanation: result, revision: newRev)
    }

    func consultKimi(
        codeOrUI: String,
        prompt: String,
        filePath: String = "theme.css",
        template: String = "kimi_design_system_review",
        onReflectionUpdate: ((String, String) -> Void)? = nil
    ) async -> (auditedCode: String, explanation: String, revision: CodeRevision) {
        // 1. Snapshot original
        versionManager.commitRevision(
            filePath: filePath,
            code: codeOrUI,
            origin: .userOriginal,
            summary: "Pre-design review baseline (\(template))"
        )

        let consultPrompt = "Review design system, aesthetics, layout hierarchy, and CSS structure for '\(template)':\n\nUser Notes: \(prompt)\n\nAsset:\n```\n\(codeOrUI)\n```"
        onReflectionUpdate?("KIMI_WEB", consultPrompt)

        // 2. Query consult MCP or local dispatcher
        let result = await callConsultScript(provider: "kimi", prompt: consultPrompt)
        onReflectionUpdate?("KIMI_WEB", result)

        let extractedCode = extractCodeBlock(from: result) ?? result

        // 3. Snapshot audited code as next version
        let newRev = versionManager.commitRevision(
            filePath: filePath,
            code: extractedCode,
            origin: .kimiDesign,
            summary: "Kimi Design System Review (\(template))"
        )

        return (auditedCode: extractedCode, explanation: result, revision: newRev)
    }

    private func callConsultScript(provider: String, prompt: String) async -> String {
        let root = "/Users/stevenjackson/Documents/DEVELOPMENT/WILD CARD/inference offload"
        let scriptPath = "\(root)/scripts/consult_mcp.sh"

        // Construct JSON-RPC request for consult tool
        let toolName = provider == "kimi" ? "consult_kimi" : "consult_deepseek"
        let rpcPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": toolName,
                "arguments": [
                    "prompt": prompt
                ]
            ]
        ]

        guard let rpcData = try? JSONSerialization.data(withJSONObject: rpcPayload),
              let rpcString = String(data: rpcData, encoding: .utf8) else {
            return "Error: failed to encode consult JSON-RPC request"
        }

        let cmd = "printf '%s\\n' '\(rpcString.replacingOccurrences(of: "'", with: "'\\''"))' | '\(scriptPath)'"
        let (stdout, _, exitCode) = await CLIRunner.shared.execute(command: cmd)

        if exitCode == 0 && !stdout.isEmpty {
            // Parse tool response
            if let data = stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let content = result["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                return text
            }
            return stdout
        }

        // Fallback: If stdio JSON-RPC isn't responding or had an error, route to local dispatcher on 8000
        return await callDispatcherFallback(prompt: prompt)
    }

    private func callDispatcherFallback(prompt: String) async -> String {
        guard let url = URL(string: "http://127.0.0.1:8000/v1/chat/completions") else {
            return "Dispatcher URL error"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "messages": [["role": "user", "content": prompt]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return "Failed to serialize fallback request"
        }
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let text = json["text"] as? String { return text }
                if let choices = json["choices"] as? [[String: Any]],
                   let msg = choices.first?["message"] as? [String: Any],
                   let content = msg["content"] as? String {
                    return content
                }
            }
            return String(data: data, encoding: .utf8) ?? "Dispatcher fallback returned no data"
        } catch {
            return "Consult execution note: \(error.localizedDescription)"
        }
    }

    private func extractCodeBlock(from text: String) -> String? {
        guard let startRange = text.range(of: "```") else { return nil }
        let afterStart = text[startRange.upperBound...]

        // Skip language identifier line if present
        let codeStart: Substring.Index
        if let newlineRange = afterStart.range(of: "\n") {
            codeStart = newlineRange.upperBound
        } else {
            codeStart = startRange.upperBound
        }

        guard let endRange = text[codeStart...].range(of: "```") else { return nil }
        return String(text[codeStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
