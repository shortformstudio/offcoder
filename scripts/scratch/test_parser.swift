import Foundation

func parseToolCalls(from accumulatedContent: inout String) -> [(id: String, name: String, arguments: String)] {
    var toolCallAccumulator: [Int: (id: String, name: String, arguments: String)] = [:]
    
    if toolCallAccumulator.isEmpty && accumulatedContent.contains("<tool_call>") {
        var searchRange = accumulatedContent.startIndex..<accumulatedContent.endIndex
        var xmlToolIndex = toolCallAccumulator.count

        while let startRange = accumulatedContent.range(of: "<tool_call>", range: searchRange),
              let endRange = accumulatedContent.range(of: "</tool_call>", range: startRange.upperBound..<accumulatedContent.endIndex) {

            let blockContent = String(accumulatedContent[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if blockContent.contains("<function=") {
                if let funcStart = blockContent.range(of: "<function="),
                   let funcEnd = blockContent.range(of: ">", range: funcStart.upperBound..<blockContent.endIndex) {
                    let funcName = String(blockContent[funcStart.upperBound..<funcEnd.lowerBound])

                    var params: [String: Any] = [:]
                    var paramSearch = blockContent.startIndex..<blockContent.endIndex
                    while let pStart = blockContent.range(of: "<parameter=", range: paramSearch),
                          let pNameEnd = blockContent.range(of: ">", range: pStart.upperBound..<blockContent.endIndex) {
                        let paramName = String(blockContent[pStart.upperBound..<pNameEnd.lowerBound])
                        let closeTag = "</parameter>"
                        if let pClose = blockContent.range(of: closeTag, range: pNameEnd.upperBound..<blockContent.endIndex) {
                            let paramValue = String(blockContent[pNameEnd.upperBound..<pClose.lowerBound])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            params[paramName] = paramValue
                            paramSearch = pClose.upperBound..<blockContent.endIndex
                        } else {
                            break
                        }
                    }

                    let argsJSON = (try? JSONSerialization.data(withJSONObject: params))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

                    toolCallAccumulator[xmlToolIndex] = (
                        id: "xmltc_\(xmlToolIndex)_test",
                        name: funcName,
                        arguments: argsJSON
                    )
                    xmlToolIndex += 1
                }
            } else if let jsonData = blockContent.data(using: .utf8),
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
                        id: "xmltc_\(xmlToolIndex)_test",
                        name: name,
                        arguments: argsJSON
                    )
                    xmlToolIndex += 1
                }
            }
            searchRange = endRange.upperBound..<accumulatedContent.endIndex
        }
        
        var cleanedContent = accumulatedContent
        while let s = cleanedContent.range(of: "<tool_call>"),
              let e = cleanedContent.range(of: "</tool_call>", range: s.upperBound..<cleanedContent.endIndex) {
            cleanedContent.removeSubrange(s.lowerBound..<e.upperBound)
        }
        accumulatedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    return toolCallAccumulator.keys.sorted().compactMap { toolCallAccumulator[$0] }
}

var test1 = """
Some reasoning here.
<tool_call>
<function=list_dir>
<parameter=path>
/Users/stevenjackson/code/qwythos-agent/projects/hello/media
</parameter>
</function>
</tool_call>
"""
print("TEST 1:", parseToolCalls(from: &test1))
print("REMAINING 1:", test1)

var test2 = """
<tool_call>{"name": "grep_search", "arguments": {"query": "foo"}}</tool_call>
"""
print("TEST 2:", parseToolCalls(from: &test2))

var test3 = """
<tool_call>
<function=run_command>
<parameter=command>
ls -la | grep "foo"
echo "done"
</parameter>
<parameter=cwd>/tmp</parameter>
</function>
</tool_call>
"""
print("TEST 3:", parseToolCalls(from: &test3))

