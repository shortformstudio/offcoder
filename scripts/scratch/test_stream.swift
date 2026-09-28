import Foundation

class StreamParser {
    var accumulatedContent = ""
    var accumulatedThought = ""
    var isThinking = false
    var buffer = ""
    
    var onDelta: (String) -> Void
    var onThoughtDelta: (String) -> Void
    
    init(onDelta: @escaping (String) -> Void, onThoughtDelta: @escaping (String) -> Void) {
        self.onDelta = onDelta
        self.onThoughtDelta = onThoughtDelta
    }
    
    func processChunk(_ chunk: String) {
        buffer += chunk
        
        while !buffer.isEmpty {
            if !isThinking {
                if let r = buffer.range(of: "<think>") {
                    let pre = String(buffer[..<r.lowerBound])
                    if !pre.isEmpty {
                        accumulatedContent += pre
                        onDelta(pre)
                    }
                    isThinking = true
                    buffer.removeSubrange(..<r.upperBound)
                } else {
                    // Check if buffer ends with a partial "<think>"
                    if let lastLess = buffer.lastIndex(of: "<") {
                        let suffix = String(buffer[lastLess...])
                        if "<think>".hasPrefix(suffix) {
                            let pre = String(buffer[..<lastLess])
                            if !pre.isEmpty {
                                accumulatedContent += pre
                                onDelta(pre)
                            }
                            buffer = suffix
                            break
                        }
                    }
                    
                    accumulatedContent += buffer
                    onDelta(buffer)
                    buffer = ""
                }
            } else {
                if let r = buffer.range(of: "</think>") {
                    let thought = String(buffer[..<r.lowerBound])
                    if !thought.isEmpty {
                        accumulatedThought += thought
                        onThoughtDelta(thought)
                    }
                    isThinking = false
                    buffer.removeSubrange(..<r.upperBound)
                } else {
                    if let lastLess = buffer.lastIndex(of: "<") {
                        let suffix = String(buffer[lastLess...])
                        if "</think>".hasPrefix(suffix) {
                            let thought = String(buffer[..<lastLess])
                            if !thought.isEmpty {
                                accumulatedThought += thought
                                onThoughtDelta(thought)
                            }
                            buffer = suffix
                            break
                        }
                    }
                    
                    accumulatedThought += buffer
                    onThoughtDelta(buffer)
                    buffer = ""
                }
            }
        }
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
parser.processChunk("think> And this is the end.")
