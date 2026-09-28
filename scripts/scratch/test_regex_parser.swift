import Foundation

func parseToolCallsRegex(from accumulatedContent: inout String) -> [(id: String, name: String, arguments: String)] {
    var toolCallAccumulator: [Int: (id: String, name: String, arguments: String)] = [:]
    
    let tcPattern = "(?s)<tool_call>(.*?)</tool_call>"
    guard let tcRegex = try? NSRegularExpression(pattern: tcPattern) else { return [] }
    
    let matches = tcRegex.matches(in: accumulatedContent, range: NSRange(accumulatedContent.startIndex..., in: accumulatedContent))
    
    var xmlToolIndex = 0
    
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
                
                let innerContentRange = Range(funcMatch.range(at: 3), in: blockContent)!
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
                    
                    toolCallAccumulator[xmlToolIndex] = (id: "xmltc_\(xmlToolIndex)", name: funcName, arguments: argsJSON)
                    xmlToolIndex += 1
                }
            }
        }
    }
    
    return toolCallAccumulator.keys.sorted().compactMap { toolCallAccumulator[$0] }
}

var testCommand = """
<tool_call>
<function=run_command>
<parameter=command>
cat << 'SHELL_EOF' > script.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "No argument"
fi
echo "<html><body><foo>xml</foo></body></html>"
SHELL_EOF
bash script.sh
</parameter>
</function>
</tool_call>
"""

print("COMMAND PARSE:", parseToolCallsRegex(from: &testCommand))
