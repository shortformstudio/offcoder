import Foundation
import Combine

/// Lightweight request/reply client for daemon-side browser commands
/// (read / clear / type against the mirrored login browser).
final class BrowserEvalBridge {
    static let shared = BrowserEvalBridge()

    private var task: URLSessionWebSocketTask?
    private var pending: [UUID: CheckedContinuation<Result<String, Error>, Never>] = [:]
    private let lock = NSLock()

    func eval(action: String, text: String = "") async -> String {
        let requestId = UUID()
        let url = URL(string: "ws://127.0.0.1:7171")!
        if task == nil {
            let t = URLSession.shared.webSocketTask(with: URLRequest(url: url))
            task = t
            t.resume()
            receiverLoop(t)
        }

        let request: [String: Any] = [
            "type": "browser_eval",
            "action": action,
            "text": text,
            "requestId": requestId.uuidString
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request) else {
            return "Error: unable to encode browser_eval request"
        }

        let result: Result<String, Error> = await withCheckedContinuation { (continuation: CheckedContinuation<Result<String, Error>, Never>) in
            lock.lock()
            pending[requestId] = continuation
            lock.unlock()

            task?.send(.data(data), completionHandler: { (error: Error?) in
                if let error {
                    self.resolve(requestId, with: .failure(error))
                }
            })

            // 15s watchdog (kept as closure guard; single send resolution)
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                self.resolve(requestId, with: .failure(URLError(.timedOut)))
            }
        }
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            return "browser_eval error: \(error.localizedDescription)"
        }
    }

    private func resolve(_ requestId: UUID, with result: Result<String, Error>) {
        lock.lock()
        let continuation = pending.removeValue(forKey: requestId)
        lock.unlock()
        continuation?.resume(returning: result)
    }

    private func receiverLoop(_ socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .data(let data) = message,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = json["type"] as? String,
                   let requestIdString = json["requestId"] as? String,
                   let requestId = UUID(uuidString: requestIdString) {
                    let detail = json["detail"] as? String ?? ""
                    self.resolve(requestId, with: .success(detail))
                }
                if case .string(let text) = message {
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let requestIdString = json["requestId"] as? String,
                       let requestId = UUID(uuidString: requestIdString) {
                        let detail = json["detail"] as? String ?? ""
                        self.resolve(requestId, with: .success(detail))
                    }
                }
                self.receiverLoop(socket)
            case .failure(let error):
                self.task = nil
                self.pending = [:]
                structLogBridge("browser_eval", "bridge closed: \(error.localizedDescription)")
            }
        }
    }
}
