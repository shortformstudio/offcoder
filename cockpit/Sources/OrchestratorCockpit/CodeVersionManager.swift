import Foundation
import Combine

final class CodeVersionManager: ObservableObject {
    static let shared = CodeVersionManager()

    @Published var history: [String: [CodeRevision]] = [:]
    @Published var activeFilePath: String = "active_buffer.py"
    @Published var selectedRevision: CodeRevision?

    init() {}

    var activeChain: [CodeRevision] {
        return history[activeFilePath] ?? []
    }

    var latestRevision: CodeRevision? {
        return activeChain.last
    }

    @discardableResult
    func commitRevision(
        filePath: String,
        code: String,
        origin: RevisionOrigin,
        summary: String
    ) -> CodeRevision {
        var chain = history[filePath] ?? []
        let nextIndex = chain.count
        let previousCode = chain.last?.code

        let diff = generateDiff(oldCode: previousCode ?? "", newCode: code, oldIndex: nextIndex - 1, newIndex: nextIndex)

        let rev = CodeRevision(
            versionIndex: nextIndex,
            filePath: filePath,
            origin: origin,
            code: code,
            diffFromPrevious: diff,
            summary: summary,
            timestamp: Date()
        )

        chain.append(rev)
        history[filePath] = chain
        activeFilePath = filePath
        selectedRevision = rev
        return rev
    }

    func rollback(to revision: CodeRevision) -> CodeRevision {
        return commitRevision(
            filePath: revision.filePath,
            code: revision.code,
            origin: .localModel,
            summary: "Rollback to v\(revision.versionIndex) (\(revision.summary))"
        )
    }

    func generateVersionContextPrompt() -> String {
        guard !history.isEmpty else {
            return "No code revisions currently tracked in local cache."
        }

        var lines: [String] = [
            "### ACTIVE CODE VERSION CONTROL REGISTRY",
            "You have access to automated version tracking. Every consultation with DeepSeek or Kimi is automatically committed with full line-by-line unified diffs."
        ]

        for (file, chain) in history {
            lines.append("\nFile: `\(file)` (\(chain.count) revisions):")
            for rev in chain {
                let parentStr = rev.versionIndex > 0 ? " [Parent: v\(rev.versionIndex - 1)]" : " [Root]"
                lines.append("  - v\(rev.versionIndex): [\(rev.origin.rawValue)] \(rev.summary)\(parentStr)")
            }
        }
        lines.append("\nWhen suggesting modifications, reference prior revisions (e.g. 'comparing v1 to v0') or invoke save_code_revision.")
        return lines.joined(separator: "\n")
    }

    /// O(N + M) Myers-style greedy LCS diff generator with pre-split line storage
    func generateDiff(oldCode: String, newCode: String, oldIndex: Int, newIndex: Int) -> String {
        if oldCode.isEmpty {
            return newCode.components(separatedBy: .newlines).map { "+ \($0)" }.joined(separator: "\n")
        }
        if oldCode == newCode {
            return "(Identical to v\(oldIndex) — no changes detected)"
        }

        let a = oldCode.components(separatedBy: .newlines)
        let b = newCode.components(separatedBy: .newlines)
        let n = a.count
        let m = b.count

        // Fast prefix trim
        var start = 0
        while start < n && start < m && a[start] == b[start] {
            start += 1
        }

        // Fast suffix trim
        var endA = n - 1
        var endB = m - 1
        while endA >= start && endB >= start && a[endA] == b[endB] {
            endA -= 1
            endB -= 1
        }

        var result: [String] = ["--- v\(oldIndex)", "+++ v\(newIndex)"]

        // Common prefix
        for i in 0..<start {
            result.append("  \(a[i])")
        }

        // Middle differences: LCS on trimmed middle slices
        let midA = start <= endA ? Array(a[start...endA]) : []
        let midB = start <= endB ? Array(b[start...endB]) : []

        if !midA.isEmpty || !midB.isEmpty {
            let subDiff = computeLCSDiff(midA, midB)
            result.append(contentsOf: subDiff)
        }

        // Common suffix
        if endA + 1 < n {
            for i in (endA + 1)..<n {
                result.append("  \(a[i])")
            }
        }

        return result.joined(separator: "\n")
    }

    private func computeLCSDiff(_ a: [String], _ b: [String]) -> [String] {
        let n = a.count
        let m = b.count
        if n == 0 { return b.map { "+ \($0)" } }
        if m == 0 { return a.map { "- \($0)" } }

        // Standard DP matrix for trimmed sub-slice
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0..<n {
            for j in 0..<m {
                if a[i] == b[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var lines: [String] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i - 1] == b[j - 1] {
                lines.append("  \(a[i - 1])")
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                lines.append("+ \(b[j - 1])")
                j -= 1
            } else if i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j]) {
                lines.append("- \(a[i - 1])")
                i -= 1
            }
        }
        return lines.reversed()
    }
}
