import Foundation

/// Boots the backing services directly from inside the app bundle, so clicking
/// the Offcoder icon opens the deck alone: no Terminal, no second app.
/// Services already listening are adopted; children started here are terminated
/// when the app exits.
final class ServiceBootstrap {
    static let shared = ServiceBootstrap()

    private let fileManager = FileManager.default
    private let logDir: String
    private let projectRoot = "/Users/stevenjackson/Documents/DEVELOPMENT/WILD CARD/inference offload"

    private var children: [Process] = []
    private var started = false

    private init() {
        logDir = NSString(string: "~/.offcoder/logs").expandingTildeInPath
        try? fileManager.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    }

    func bootBackingServices() {
        guard !started else { return }
        started = true
        guard fileManager.fileExists(atPath: projectRoot) else { return }

        if !isPortOpen(8000) {
            launchShell("cd \(quoted(projectRoot))/dispatcher && exec python3 -m uvicorn src.main:app --port 8000", logName: "dispatcher.log")
        }
        if !isPortOpen(7171) {
            let dist = (projectRoot as NSString).appendingPathComponent("daemon/dist/index.js")
            if fileManager.fileExists(atPath: dist) {
                launchShell("cd \(quoted(projectRoot))/daemon && exec node dist/index.js", logName: "daemon.log")
            } else {
                launchShell("cd \(quoted(projectRoot))/daemon && exec npm run dev", logName: "daemon.log")
            }
        }
        if !isPortOpen(9090) {
            launchShell("exec \(quoted(projectRoot))/scripts/launch_totem2.sh", logName: "totem-9090.log")
        }
        if !isProcessRunning(matching: "pulse_engine.py") {
            launchShell("exec /usr/bin/python3 \(quoted(projectRoot))/scripts/pulse_engine.py", logName: "pulse-engine.log")
        }
    }

    
    private func isProcessRunning(matching: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", matching]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    func shutdown() {
        for child in children where child.isRunning {
            child.terminate()
        }
        children.removeAll()
        started = false
    }

    // MARK: - Launching

    private func launchShell(_ command: String, logName: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let logPath = (logDir as NSString).appendingPathComponent(logName)
        fileManager.createFile(atPath: logPath, contents: nil)
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            process.standardOutput = handle
            process.standardError = handle
        }

        do {
            try process.run()
            children.append(process)
        } catch {
            NSLog("[offcoder] service launch failed: \(command) — \(error.localizedDescription)")
        }
    }

    // MARK: - Port probe

    private func isPortOpen(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
