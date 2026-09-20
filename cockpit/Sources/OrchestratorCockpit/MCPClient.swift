import Foundation

/// Calls the repo's stdio MCP servers (journal, explore, heartbeat, mission).
/// Each call spawns the server, speaks JSON-RPC, and returns the tool text.
final class MCPClient {
    static let shared = MCPClient()

    private let repoRoot = "/Users/stevenjackson/Documents/DEVELOPMENT/WILD CARD/inference offload"
    private let queue = DispatchQueue(label: "offcoder.mcp.client", qos: .userInitiated)

    func call(server: String, tool: String, arguments: [String: Any] = [:], timeout: TimeInterval = 180) async -> String {
        let script = (repoRoot as NSString).appendingPathComponent("mcp-server/\(server)/index.js")
        guard FileManager.default.fileExists(atPath: script) else {
            return "Error: MCP server '\(server)' not found at \(script)"
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.run(script: script, tool: tool, arguments: arguments, timeout: timeout))
            }
        }
    }

    private static func run(script: String, tool: String, arguments: [String: Any], timeout: TimeInterval) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", script]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let callId = 3
        let messages: [[String: Any]] = [
            [
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [:],
                    "clientInfo": ["name": "offcoder-cockpit", "version": "2.0"],
                ],
            ],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            [
                "jsonrpc": "2.0", "id": callId, "method": "tools/call",
                "params": ["name": tool, "arguments": arguments],
            ],
        ]

        var payload = ""
        for message in messages {
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let line = String(data: data, encoding: .utf8) else { continue }
            payload += line + "\n"
        }

        do {
            try process.run()
        } catch {
            return "Error: failed to launch \(tool): \(error.localizedDescription)"
        }

        stdin.fileHandleForWriting.write(payload.data(using: .utf8) ?? Data())
        try? stdin.fileHandleForWriting.close()

        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let output = String(data: outputData, encoding: .utf8) ?? ""

        for line in output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (message["id"] as? Int) == callId else { continue }

            if let error = message["error"] as? [String: Any] {
                return "Error: \(error["message"] as? String ?? "unknown MCP error")"
            }
            guard let result = message["result"] as? [String: Any] else { continue }
            let content = result["content"] as? [[String: Any]] ?? []
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            let isError = result["isError"] as? Bool ?? false
            return isError ? "Error: \(text)" : text
        }

        let detail = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Error: no response from \(tool)\(detail.isEmpty ? "" : " — \(detail.suffix(300))")"
    }
}
