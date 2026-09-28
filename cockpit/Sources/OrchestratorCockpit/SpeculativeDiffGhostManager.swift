import Foundation
import Combine
import SwiftUI

enum GhostLineType: String, Equatable {
    case unchanged
    case addition
    case deletion
}

struct GhostLine: Identifiable, Equatable {
    let id = UUID()
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let type: GhostLineType
    let content: String
}

final class SpeculativeDiffGhostManager: ObservableObject {
    static let shared = SpeculativeDiffGhostManager()

    @Published var isGhostActive: Bool = false
    @Published var activeFilePath: String = "active_buffer.py"
    @Published var baselineCode: String = ""
    @Published var speculativeChain: [CodeRevision] = []
    @Published var activeScrubIndex: Int = 0
    @Published var ghostLines: [GhostLine] = []
    @Published var additionsCount: Int = 0
    @Published var deletionsCount: Int = 0

    private init() {}

    var activeRevision: CodeRevision? {
        guard !speculativeChain.isEmpty, activeScrubIndex >= 0, activeScrubIndex < speculativeChain.count else {
            return nil
        }
        return speculativeChain[activeScrubIndex]
    }

    /// Initializes a speculative ghosting session against a baseline file buffer
    func startSession(filePath: String, baseline: String) {
        self.activeFilePath = filePath
        self.baselineCode = baseline
        self.speculativeChain = [
            CodeRevision(
                versionIndex: 0,
                filePath: filePath,
                origin: .userOriginal,
                code: baseline,
                diffFromPrevious: "(Baseline)",
                summary: "Baseline Buffer",
                timestamp: Date()
            )
        ]
        self.activeScrubIndex = 0
        self.isGhostActive = true
        computeGhostLines(newCode: baseline)
    }

    /// Ingests a new speculative code variation from a plan decomposition or streaming worker
    func pushSpeculativeCandidate(code: String, summary: String, origin: RevisionOrigin = .localModel) {
        if !isGhostActive {
            startSession(filePath: activeFilePath, baseline: CodeVersionManager.shared.latestRevision?.code ?? "")
        }

        let nextIdx = speculativeChain.count
        let prevCode = speculativeChain.last?.code ?? baselineCode
        let diff = CodeVersionManager.shared.generateDiff(oldCode: prevCode, newCode: code, oldIndex: nextIdx - 1, newIndex: nextIdx)

        let rev = CodeRevision(
            versionIndex: nextIdx,
            filePath: activeFilePath,
            origin: origin,
            code: code,
            diffFromPrevious: diff,
            summary: summary,
            timestamp: Date()
        )

        speculativeChain.append(rev)
        activeScrubIndex = speculativeChain.count - 1
        computeGhostLines(newCode: code)
    }

    /// Scrub backward across proposed speculative variations (Cmd + [)
    func scrubBackward() {
        guard isGhostActive, activeScrubIndex > 0 else { return }
        activeScrubIndex -= 1
        if let current = activeRevision {
            computeGhostLines(newCode: current.code)
        }
    }

    /// Scrub forward across proposed speculative variations (Cmd + ])
    func scrubForward() {
        guard isGhostActive, activeScrubIndex < speculativeChain.count - 1 else { return }
        activeScrubIndex += 1
        if let current = activeRevision {
            computeGhostLines(newCode: current.code)
        }
    }

    /// Instant rollback to a specific revision index
    func rollback(to index: Int) {
        guard isGhostActive, index >= 0, index < speculativeChain.count else { return }
        activeScrubIndex = index
        if let rev = activeRevision {
            computeGhostLines(newCode: rev.code)
        }
    }

    /// Accepts the currently scrubbed ghost candidate and stages it into the permanent version manager
    func acceptCurrentGhost() -> CodeRevision? {
        guard isGhostActive, let rev = activeRevision else { return nil }
        let committed = CodeVersionManager.shared.commitRevision(
            filePath: rev.filePath,
            code: rev.code,
            origin: rev.origin,
            summary: "Accepted Ghost: \(rev.summary)"
        )
        isGhostActive = false
        return committed
    }

    /// Discards speculative ghost edits and resets to baseline
    func discardGhost() {
        isGhostActive = false
        speculativeChain.removeAll()
        activeScrubIndex = 0
        ghostLines.removeAll()
    }

    /// Computes inline diff lines for ghost visualization
    private func computeGhostLines(newCode: String) {
        let baseLines = baselineCode.components(separatedBy: .newlines)
        let newLines = newCode.components(separatedBy: .newlines)

        var lines: [GhostLine] = []
        var adds = 0
        var dels = 0

        // Fast diff generator with line pairing
        var i = 0
        var j = 0
        var oldLineNum = 1
        var newLineNum = 1

        while i < baseLines.count || j < newLines.count {
            if i < baseLines.count && j < newLines.count && baseLines[i] == newLines[j] {
                lines.append(GhostLine(
                    oldLineNumber: oldLineNum,
                    newLineNumber: newLineNum,
                    type: .unchanged,
                    content: baseLines[i]
                ))
                i += 1
                j += 1
                oldLineNum += 1
                newLineNum += 1
            } else if j < newLines.count && (i >= baseLines.count || !baseLines.contains(newLines[j])) {
                lines.append(GhostLine(
                    oldLineNumber: nil,
                    newLineNumber: newLineNum,
                    type: .addition,
                    content: newLines[j]
                ))
                j += 1
                newLineNum += 1
                adds += 1
            } else if i < baseLines.count {
                lines.append(GhostLine(
                    oldLineNumber: oldLineNum,
                    newLineNumber: nil,
                    type: .deletion,
                    content: baseLines[i]
                ))
                i += 1
                oldLineNum += 1
                dels += 1
            } else {
                j += 1
            }
        }

        self.ghostLines = lines
        self.additionsCount = adds
        self.deletionsCount = dels
    }
}
