import Foundation

/// Fast dual-engine DeepSeek integration service.
/// Tries direct OpenAI-compatible API (https://api.deepseek.com/chat/completions) using DEEPSEEK_API_KEY.
/// Gracefully falls back to local consult bridge (scripts/consult_mcp.sh) or local dispatcher.
final class DeepSeekHandoffService {
    static let shared = DeepSeekHandoffService()

    private let directApiEndpoint = "https://api.deepseek.com/chat/completions"
    private let defaultModel = "deepseek-chat"

    private init() {}

    /// Executes a code handoff to DeepSeek with prompt and optional context code.
    /// Returns (code: String, explanation: String).
    func executeHandoff(
        prompt: String,
        code: String = "",
        language: String = "",
        onProgress: ((String) -> Void)? = nil
    ) async -> (code: String, explanation: String, error: String?) {
        let apiKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 1. Try Direct API if key is present
        if !apiKey.isEmpty {
            onProgress?("Contacting DeepSeek API (fast direct connection)...")
            let (directCode, directExplanation, directError) = await callDirectApi(
                apiKey: apiKey,
                prompt: prompt,
                code: code,
                language: language
            )
            if let directCode, !directCode.isEmpty {
                return (code: directCode, explanation: directExplanation ?? "", error: nil)
            }
            if let err = directError {
                onProgress?("Direct API returned: \(err). Falling back to consult bridge...")
            }
        }

        // 2. Fallback: Consult Bridge (scripts/consult_mcp.sh)
        onProgress?("Routing to Consult Bridge / Dispatcher...")
        let bridgeResult = await callConsultBridge(prompt: prompt, code: code)
        let extracted = extractCodeBlock(from: bridgeResult) ?? ""
        return (code: extracted.isEmpty ? bridgeResult : extracted, explanation: bridgeResult, error: nil)
    }

    // MARK: - Direct DeepSeek API
    private func callDirectApi(
        apiKey: String,
        prompt: String,
        code: String,
        language: String
    ) async -> (code: String?, explanation: String?, error: String?) {
        guard let url = URL(string: directApiEndpoint) else {
            return (nil, nil, "Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60.0

        var userMessage = prompt
        if !code.isEmpty {
            userMessage += "\n\n```\(language)\n\(code)\n```"
        }

        let body: [String: Any] = [
            "model": defaultModel,
            "messages": [
                [
                    "role": "system",
                    "content": "You are DeepSeek-Coder, an elite software engineer. When asked to write, refactor, or audit code, provide clean, production-ready code in standard markdown code blocks with clear explanations."
                ],
                [
                    "role": "user",
                    "content": userMessage
                ]
            ],
            "temperature": 0.2,
            "max_tokens": 8192
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return (nil, nil, "Failed to serialize JSON body")
        }
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (nil, nil, "Non-HTTP response")
            }

            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    let extracted = extractCodeBlock(from: content) ?? content
                    return (extracted, content, nil)
                }
                return (nil, nil, "Failed to parse DeepSeek response")
            } else {
                let errString = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                return (nil, nil, "HTTP \(http.statusCode): \(errString)")
            }
        } catch {
            return (nil, nil, error.localizedDescription)
        }
    }

    // MARK: - Consult Bridge Fallback
    private func callConsultBridge(prompt: String, code: String) async -> String {
        let consultPrompt = code.isEmpty
            ? prompt
            : "\(prompt)\n\nCode to work on:\n```\n\(code)\n```"

        let projectRoot = findProjectRoot()
        let scriptPath = "\(projectRoot)/scripts/consult_mcp.sh"

        let rpcPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "consult_deepseek",
                "arguments": [
                    "prompt": consultPrompt
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
            if let data = stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let content = result["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                return text
            }
            return stdout
        }

        // Final fallback: local dispatcher HTTP
        return await callDispatcher(prompt: consultPrompt)
    }

    private func callDispatcher(prompt: String) async -> String {
        guard let url = URL(string: "http://127.0.0.1:8000/v1/chat/completions") else {
            return "Dispatcher URL error"
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["messages": [["role": "user", "content": prompt]]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return "Failed to serialize" }
        req.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return text
            }
            return String(data: data, encoding: .utf8) ?? "Dispatcher error"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func extractCodeBlock(from text: String) -> String? {
        let pattern = "```(?:[a-zA-Z0-9_-]+)?\\s*\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        if let lastMatch = matches.last, lastMatch.numberOfRanges > 1 {
            return nsText.substring(with: lastMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func findProjectRoot() -> String {
        let current = FileManager.default.currentDirectoryPath
        if FileManager.default.fileExists(atPath: "\(current)/scripts/consult_mcp.sh") {
            return current
        }
        return "/Users/stevenjackson/Documents/DEVELOPMENT/WILD CARD/inference offload"
    }
}
