import Foundation

let path = "cockpit/Sources/OrchestratorCockpit/LocalModelClient.swift"
var content = try! String(contentsOfFile: path, encoding: .utf8)

// 1. Inject StreamParser definition at the top of the file (or as a private class inside)
let streamParserCode = """
private class StreamParser {
    var accumulatedContent = ""
    var accumulatedThought = ""
    var accumulatedToolCalls = ""
    
    var state: State = .content
    var buffer = ""
    
    enum State { case content, thinking, toolCall }
    
    var onDelta: (String) -> Void
    var onThoughtDelta: (String) -> Void
    
    init(onDelta: @escaping (String) -> Void, onThoughtDelta: @escaping (String) -> Void) {
        self.onDelta = onDelta
        self.onThoughtDelta = onThoughtDelta
    }
    
    func processChunk(_ chunk: String) {
        buffer += chunk
        
        while !buffer.isEmpty {
            switch state {
            case .content:
                if let tRange = buffer.range(of: "<think>"), let tcRange = buffer.range(of: "<tool_call>") {
                    let firstRange = tRange.lowerBound < tcRange.lowerBound ? tRange : tcRange
                    transition(to: firstRange == tRange ? .thinking : .toolCall, range: firstRange, fullTag: firstRange == tRange ? "<think>" : "<tool_call>")
                } else if let tRange = buffer.range(of: "<think>") {
                    transition(to: .thinking, range: tRange, fullTag: "<think>")
                } else if let tcRange = buffer.range(of: "<tool_call>") {
                    transition(to: .toolCall, range: tcRange, fullTag: "<tool_call>")
                } else {
                    flushSafeContent()
                }
                
            case .thinking:
                if let r = buffer.range(of: "</think>") {
                    let thought = String(buffer[..<r.lowerBound])
                    if !thought.isEmpty {
                        accumulatedThought += thought
                        onThoughtDelta(thought)
                    }
                    state = .content
                    buffer.removeSubrange(..<r.upperBound)
                } else {
                    flushSafeThought()
                }
                
            case .toolCall:
                if let r = buffer.range(of: "</tool_call>") {
                    let tc = String(buffer[..<r.upperBound])
                    accumulatedToolCalls += "<tool_call>" + tc + "</tool_call>"
                    state = .content
                    buffer.removeSubrange(..<r.upperBound)
                } else {
                    // Just accumulate in buffer until we see </tool_call>
                    break
                }
            }
            
            if state == .toolCall && !buffer.contains("</tool_call>") { break }
            if state == .content && !buffer.contains("<think>") && !buffer.contains("<tool_call>") && !canFlushMore(buffer, tags: ["<think>", "<tool_call>"]) { break }
            if state == .thinking && !buffer.contains("</think>") && !canFlushMore(buffer, tags: ["</think>"]) { break }
        }
    }
    
    private func transition(to newState: State, range: Range<String.Index>, fullTag: String) {
        let pre = String(buffer[..<range.lowerBound])
        if !pre.isEmpty {
            accumulatedContent += pre
            onDelta(pre)
        }
        state = newState
        buffer.removeSubrange(..<range.upperBound)
    }
    
    private func canFlushMore(_ buf: String, tags: [String]) -> Bool {
        if let lastLess = buf.lastIndex(of: "<") {
            let suffix = String(buf[lastLess...])
            for tag in tags {
                if tag.hasPrefix(suffix) {
                    return false
                }
            }
        }
        return true
    }
    
    private func flushSafeContent() {
        if let lastLess = buffer.lastIndex(of: "<") {
            let suffix = String(buffer[lastLess...])
            if "<think>".hasPrefix(suffix) || "<tool_call>".hasPrefix(suffix) {
                let pre = String(buffer[..<lastLess])
                if !pre.isEmpty {
                    accumulatedContent += pre
                    onDelta(pre)
                }
                buffer = suffix
                return
            }
        }
        accumulatedContent += buffer
        onDelta(buffer)
        buffer = ""
    }
    
    private func flushSafeThought() {
        if let lastLess = buffer.lastIndex(of: "<") {
            let suffix = String(buffer[lastLess...])
            if "</think>".hasPrefix(suffix) {
                let pre = String(buffer[..<lastLess])
                if !pre.isEmpty {
                    accumulatedThought += pre
                    onThoughtDelta(pre)
                }
                buffer = suffix
                return
            }
        }
        accumulatedThought += buffer
        onThoughtDelta(buffer)
        buffer = ""
    }
}
"""

if !content.contains("class StreamParser") {
    // Insert just before `final class LocalModelClient`
    content = content.replacingOccurrences(of: "final class LocalModelClient {", with: streamParserCode + "\n\nfinal class LocalModelClient {")
}

// 2. Modify `sendChat` to inject directory map
let systemPromptInsertion = """
        // Build directory map
        let (lsStdout, _, _) = await cliRunner.execute(command: "ls -laR", workingDirectory: projectDir)
        let dirMap = lsStdout.isEmpty ? "Directory is empty or unreadable." : lsStdout.prefix(3000)

        // Build messages payload with injected version control and harness context
"""

content = content.replacingOccurrences(of: "// Build messages payload with injected version control and harness context", with: systemPromptInsertion)

let originalSystemContent = """
You are \\(BuildConfig.agentSystemName)
Operating Workspace: \\(projectDir)
"""

let newSystemContent = """
You are \\(BuildConfig.agentSystemName)
Operating Workspace: \\(projectDir)
Current Workspace Map (ls -laR):
```
\\(dirMap)
```
"""

content = content.replacingOccurrences(of: originalSystemContent, with: newSystemContent)

// 3. Update `streamCompletion` to use `StreamParser`
let oldStreamLogic = """
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
"""

let newStreamLogic = """
                        // Handle reasoning vs content vs tool_call routing via StreamParser
                        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                            // Native OpenAI-style reasoning
                            accumulatedThought += reasoning
                            onThoughtDelta?(reasoning)
                        }
                        if let content = delta["content"] as? String, !content.isEmpty {
                            // Route through our state machine to catch embedded <think> and <tool_call> tags
                            parser.processChunk(content)
                        }
"""
content = content.replacingOccurrences(of: oldStreamLogic, with: newStreamLogic)

// Instantiate `StreamParser` inside `streamCompletion`
let parserInstantiation = """
        var streamSucceeded = false
        
        let parser = StreamParser(onDelta: { onDelta($0) }, onThoughtDelta: { onThoughtDelta?($0) })
"""
content = content.replacingOccurrences(of: "var streamSucceeded = false", with: parserInstantiation)

// Append toolcalls to accumulated content so the regex fallback still works identically!
let postStreamAppend = """
            }
        } catch {
            streamSucceeded = false
        }
        
        // Sync StreamParser buffers back to the accumulated strings
        accumulatedContent += parser.accumulatedContent
        accumulatedThought += parser.accumulatedThought
        accumulatedContent += parser.accumulatedToolCalls
"""
content = content.replacingOccurrences(of: """
            }
        } catch {
            streamSucceeded = false
        }
""", with: postStreamAppend)

try! content.write(toFile: path, atomically: true, encoding: .utf8)
print("Updated LocalModelClient.swift")
