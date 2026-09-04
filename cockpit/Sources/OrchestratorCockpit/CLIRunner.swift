import Foundation

final class CLIRunner {
    static let shared = CLIRunner()

    func execute(
        command: String,
        workingDirectory: String? = nil,
        timeoutSeconds: Double = 60.0
    ) async -> (stdout: String, stderr: String, exitCode: Int32) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]

                if let workingDirectory, FileManager.default.fileExists(atPath: workingDirectory) {
                    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
                }

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                var stdoutData = Data()
                var stderrData = Data()

                let group = DispatchGroup()
                group.enter()
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        group.leave()
                    } else {
                        stdoutData.append(data)
                    }
                }

                group.enter()
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        group.leave()
                    } else {
                        stderrData.append(data)
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    _ = group.wait(timeout: .now() + 2.0)

                    let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.resume(returning: (stdout: stdoutStr, stderr: stderrStr, exitCode: process.terminationStatus))
                } catch {
                    continuation.resume(returning: (stdout: "", stderr: "Failed to run command: \(error.localizedDescription)", exitCode: -1))
                }
            }
        }
    }
}
