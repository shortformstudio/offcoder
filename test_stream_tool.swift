import Foundation

class StreamParser {
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
                    accumulatedToolCalls += "<tool_call>" + tc
                    state = .content
                    buffer.removeSubrange(..<r.upperBound)
                } else {
                    // Just accumulate in buffer until we see </tool_call>
                    break
                }
            }
            
            // If buffer didn't change (waiting for tag completion), break
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

let parser = StreamParser(
    onDelta: { print("CONTENT: \($0)") },
    onThoughtDelta: { print("THOUGHT: \($0)") }
)

parser.processChunk("Hello! ")
parser.processChunk("<thi")
parser.processChunk("nk>This is my ")
parser.processChunk("thought process.</")
parser.processChunk("think> And here is a tool call: <tool_")
parser.processChunk("call><func=foo></tool_call> Done.")

print("\nFinal Tool Calls Buffer: \(parser.accumulatedToolCalls)")
