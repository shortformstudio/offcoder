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
        // 0. Initial baseline snapshot
        versionManager.commitRevision(
            filePath: filePath,
            code: code,
            origin: .userOriginal,
            summary: "Pre-consult baseline: \(filePath)"
        )

        var currentCode = code
        var explanations: [String] = []

        // Stage 1: Entire Scaffolding Generation
        let scaffoldPrompt = """
[STAGE 1/4: FULL ARCHITECTURAL SCAFFOLDING]
Goal: Generate the complete, end-to-end scaffolding and implementation for \(filePath).
Objective / Mission: \(prompt)
Requirements:
- Provide entire complete file implementation, full classes, methods, error handling, and signatures.
- Do NOT leave placeholders or TODOs.
- Return the full source code in a markdown code block.

Current Context / Existing Code:
```
\(currentCode)
```
"""
        onReflectionUpdate?("DEEPSEEK_WEB", scaffoldPrompt)
        let scaffoldResult = await callConsultScript(provider: "deepseek", prompt: scaffoldPrompt)
        onReflectionUpdate?("DEEPSEEK_WEB", scaffoldResult)
        if let extracted = extractCodeBlock(from: scaffoldResult), !extracted.isEmpty {
            currentCode = extracted
        }
        explanations.append("### Stage 1: Complete Scaffolding\n" + scaffoldResult)
        let scaffoldRev = versionManager.commitRevision(
            filePath: filePath,
            code: currentCode,
            origin: .deepseekAudit,
            summary: "DeepSeek Stage 1: Full Scaffolding (\(filePath))"
        )

        // Stage 2: Audit Pass 1 — Correctness, Edge Cases & Logic Robustness
        let audit1Prompt = """
[STAGE 2/4: AUDIT PASS 1 — CORRECTNESS & EDGE CASES]
Review the newly scaffolded implementation for \(filePath).
Specific Focus:
- Correctness, boundary conditions, race conditions, edge cases, type integrity, and error recovery paths.
- Return the improved, fully audited code in a markdown code block.

Code to audit:
```
\(currentCode)
```
"""
        onReflectionUpdate?("DEEPSEEK_WEB", audit1Prompt)
        let audit1Result = await callConsultScript(provider: "deepseek", prompt: audit1Prompt)
        onReflectionUpdate?("DEEPSEEK_WEB", audit1Result)
        if let extracted = extractCodeBlock(from: audit1Result), !extracted.isEmpty {
            currentCode = extracted
        }
        explanations.append("### Stage 2: Audit Pass 1 (Correctness & Edge Cases)\n" + audit1Result)
        let audit1Rev = versionManager.commitRevision(
            filePath: filePath,
            code: currentCode,
            origin: .deepseekAudit,
            summary: "DeepSeek Stage 2: Audit 1 - Correctness & Edge Cases"
        )

        // Stage 3: Audit Pass 2 — Security Hardening, Injection & Defense-in-Depth
        let audit2Prompt = """
[STAGE 3/4: AUDIT PASS 2 — SECURITY HARDENING]
Review the code for \(filePath) from a hostile security perspective (OWASP Top 10, sanitization, defensive boundaries, state leakage, resource exhaustion).
Specific Focus:
- Eliminate any vulnerabilities, validate all inputs, and secure resource lifecycle.
- Return the hardened, production-ready code in a markdown code block.

Code to audit:
```
\(currentCode)
```
"""
        onReflectionUpdate?("DEEPSEEK_WEB", audit2Prompt)
        let audit2Result = await callConsultScript(provider: "deepseek", prompt: audit2Prompt)
        onReflectionUpdate?("DEEPSEEK_WEB", audit2Result)
        if let extracted = extractCodeBlock(from: audit2Result), !extracted.isEmpty {
            currentCode = extracted
        }
        explanations.append("### Stage 3: Audit Pass 2 (Security Hardening)\n" + audit2Result)
        let audit2Rev = versionManager.commitRevision(
            filePath: filePath,
            code: currentCode,
            origin: .deepseekAudit,
            summary: "DeepSeek Stage 3: Audit 2 - Security Hardening"
        )

        // Stage 4: Audit Pass 3 — Performance, Big-O Complexity & Memory Footprint
        let audit3Prompt = """
[STAGE 4/4: AUDIT PASS 3 — PERFORMANCE & ALGORITHMIC OPTIMIZATION]
Review the code for \(filePath) for maximum efficiency.
Specific Focus:
- Algorithmic Big-O time and space complexity, redundant heap allocations, lock contention, caching, and stream throughput.
- Ensure 100% preservation of all correctness and security invariants established in prior passes.
- Return the final, battle-tested production code in a markdown code block.

Code to audit:
```
\(currentCode)
```
"""
        onReflectionUpdate?("DEEPSEEK_WEB", audit3Prompt)
        let audit3Result = await callConsultScript(provider: "deepseek", prompt: audit3Prompt)
        onReflectionUpdate?("DEEPSEEK_WEB", audit3Result)
        if let extracted = extractCodeBlock(from: audit3Result), !extracted.isEmpty {
            currentCode = extracted
        }
        explanations.append("### Stage 4: Audit Pass 3 (Performance & Asymptotic Optimization)\n" + audit3Result)
        let finalRev = versionManager.commitRevision(
            filePath: filePath,
            code: currentCode,
            origin: .deepseekAudit,
            summary: "DeepSeek Stage 4: Audit 3 - Performance & Complexity"
        )

        let compositeExplanation = explanations.joined(separator: "\n\n---\n\n")
        return (auditedCode: currentCode, explanation: compositeExplanation, revision: finalRev)
    }

    func consultKimi(
        codeOrUI: String,
        prompt: String,
        filePath: String = "theme.css",
        template: String = "kimi_design_system_review",
        onReflectionUpdate: ((String, String) -> Void)? = nil
    ) async -> (auditedCode: String, explanation: String, revision: CodeRevision) {
        // 1. Snapshot original
        if !codeOrUI.isEmpty {
            versionManager.commitRevision(
                filePath: filePath,
                code: codeOrUI,
                origin: .userOriginal,
                summary: "Pre-design review baseline (\(template))"
            )
        }

        let consultPrompt = codeOrUI.isEmpty 
            ? "Kimi Task:\n\n\(prompt)" 
            : "Review design system, aesthetics, layout hierarchy, and CSS structure for '\(template)':\n\nUser Notes: \(prompt)\n\nAsset:\n```\n\(codeOrUI)\n```"
        
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

    func consultGemini(
        code: String,
        prompt: String,
        filePath: String = "gemini_baseline.py",
        template: String = "gemini_multimodal_audit",
        onReflectionUpdate: ((String, String) -> Void)? = nil
    ) async -> (auditedCode: String, explanation: String, revision: CodeRevision) {
        if !code.isEmpty {
            versionManager.commitRevision(
                filePath: filePath,
                code: code,
                origin: .userOriginal,
                summary: "Pre-Gemini baseline (\(template))"
            )
        }

        let consultPrompt = code.isEmpty 
            ? "Gemini Task:\n\n\(prompt)" 
            : "Analyze the following context via Gemini capabilities (Multi-modal or advanced reasoning):\n\nUser Notes: \(prompt)\n\nAsset:\n```\n\(code)\n```"
            
        onReflectionUpdate?("GEMINI_WEB", consultPrompt)

        let result = await callConsultScript(provider: "gemini", prompt: consultPrompt)
        onReflectionUpdate?("GEMINI_WEB", result)

        let extractedCode = extractCodeBlock(from: result) ?? result

        let newRev = versionManager.commitRevision(
            filePath: filePath,
            code: extractedCode,
            origin: .geminiDesign,
            summary: "Gemini Synthesis (\(template))"
        )

        return (auditedCode: extractedCode, explanation: result, revision: newRev)
    }

    private func callConsultScript(provider: String, prompt: String) async -> String {
        let root = "/Users/stevenjackson/Documents/DEVELOPMENT/WILD CARD/inference offload" // consult bridge is separate; blank builds do not ship it
        let scriptPath = "\(root)/scripts/consult_mcp.sh"
        if BuildConfig.isBlank {
            return "Error: consult bridge not bundled in this build"
        }

        // Construct JSON-RPC request for consult tool
        let toolName: String
        switch provider {
        case "kimi": toolName = "consult_kimi"
        case "gemini": toolName = "consult_gemini"
        default: toolName = "consult_deepseek"
        }
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
