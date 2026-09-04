import SwiftUI
import Foundation
import AppKit
import Combine

struct BayFault: Identifiable, Equatable {
    let id = UUID()
    let bayID: String
    let code: String
    let detail: String
    let stack: String
    let at: Date

    static func == (lhs: BayFault, rhs: BayFault) -> Bool {
        lhs.bayID == rhs.bayID && lhs.code == rhs.code && lhs.detail == rhs.detail
    }
}

final class FaultRegistry: ObservableObject {
    static let shared = FaultRegistry()

    @Published private(set) var bailedBays: Set<String> = []
    @Published private(set) var faults: [BayFault] = []
    @Published private(set) var isValid: Bool = false

    private init() {}

    func record(bayID: String, code: String, detail: String, stack: String = "") {
        let fault = BayFault(bayID: bayID, code: code, detail: detail, stack: stack, at: Date())
        if faults.contains(fault) { return }
        faults.insert(fault, at: 0)
        if faults.count > 6 { faults.removeLast() }
        bailedBays.insert(bayID)
        structLog(bayID: bayID, code: code, detail: detail, stack: stack)
    }

    private func structLog(bayID: String, code: String, detail: String, stack: String) {
        var payload: [String: String] = [
            "domain": "cockpit",
            "level": "error",
            "code": code,
            "msg": detail,
            "bay": bayID,
        ]
        if !stack.isEmpty { payload["stack"] = stack }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8) else { return }
        NSLog("[cockpit] %@", line)
    }

    func recoverBay(_ bayID: String) {
        bailedBays.remove(bayID)
    }

    func recoverAll() {
        bailedBays = []
        faults = []
    }

    func isBailed(_ bayID: String) -> Bool {
        bailedBays.contains(bayID)
    }

    func installUncaughtHandler() {
        NSSetUncaughtExceptionHandler { exception in
            FaultRegistry.shared.record(
                bayID: "global",
                code: "uncaught_exception",
                detail: exception.name.rawValue,
                stack: exception.reason ?? ""
            )
        }
    }
}

struct FailSafeBay<Content: View>: View {
    @ObservedObject var fault: FaultRegistry
    let bayID: String
    @ViewBuilder let content: () -> Content

    init(fault: FaultRegistry = .shared, bayID: String, @ViewBuilder content: @escaping () -> Content) {
        self.fault = fault
        self.bayID = bayID
        self.content = content
    }

    var body: some View {
        if fault.isBailed(bayID) {
            BayFallbackView(bayID: bayID) {
                fault.recoverBay(bayID)
            }
        } else {
            content()
        }
    }
}

struct BayFallbackView: View {
    let bayID: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.brakesignal")
                .font(.system(size: 20))
                .foregroundColor(.red.opacity(0.8))
            Text("BAY ISOLATED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            Text(bayID)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.red)
            Text("details logged to console · status marquee updated")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.gray)
            Button("Retry Bay") { onRetry() }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.25), lineWidth: 1))
        .allowsHitTesting(true)
    }
}
