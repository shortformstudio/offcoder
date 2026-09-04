import SwiftUI

enum MarqueeLevel: String, Decodable {
    case idle, success, working, warning, alert

    var color: Color {
        switch self {
        case .idle, .success: return .green
        case .working, .warning: return .yellow
        case .alert: return .red
        }
    }

    var label: String {
        switch self {
        case .idle: return "IDLE"
        case .success: return "SUCCESS"
        case .working: return "WORKING"
        case .warning: return "WARNING"
        case .alert: return "ALERT"
        }
    }
}

struct MarqueeItem: Identifiable, Equatable, Decodable {
    var id = UUID()
    let level: MarqueeLevel
    let text: String
    let code: String
    let ts: Int

    init(level: MarqueeLevel, text: String, code: String, ts: Int) {
        self.level = level
        self.text = text
        self.code = code
        self.ts = ts
    }

    enum CodingKeys: String, CodingKey { case level, text, code, ts }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            level: try container.decode(MarqueeLevel.self, forKey: .level),
            text: try container.decode(String.self, forKey: .text),
            code: try container.decode(String.self, forKey: .code),
            ts: try container.decode(Int.self, forKey: .ts)
        )
    }
}

struct MarqueeScroller: View {
    let text: String
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { ctx, size in
                let resolvedText = ctx.resolve(
                    Text(text)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(color)
                )
                let metrics = resolvedText.measure(in: size)
                let speed: CGFloat = 26
                let period = max(metrics.width + 48, size.width + 1)
                let offset = CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Double(period))) * speed
                let origin = -offset
                let edge = CGPoint(x: origin, y: size.height / 2)
                let follow = CGPoint(x: origin + period, y: size.height / 2)
                ctx.draw(resolvedText, at: edge, anchor: .leading)
                if origin + metrics.width < size.width {
                    ctx.draw(resolvedText, at: follow, anchor: .leading)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .allowsHitTesting(false)
    }
}

struct MarqueeView: View {
    let item: MarqueeItem

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.level.color)
                .frame(width: 7, height: 7)
                .shadow(color: item.level.color.opacity(0.8), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.level.label)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(item.level.color)
                    Text(item.code)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray)
                }
                MarqueeScroller(text: item.text, color: item.level.color)
                    .frame(width: 300, height: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.trailing, item.level == .alert ? 34 : 0)
        .background(.ultraThinMaterial)
        .background(CockpitPalette.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.level.color.opacity(0.4), lineWidth: 1))
        .shadow(color: item.level.color.opacity(item.level == .alert ? 0.3 : 0.08), radius: 8)
    }
}

struct MarqueeDetailPanel: View {
    let history: [MarqueeItem]
    let faults: [BayFault]
    var onRecover: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STATUS DETAIL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close status details")
            }
            if faults.isEmpty {
                Text("no subsystem faults logged — telemetry nominal")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                ForEach(faults) { fault in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fault.code + " · " + fault.bayID)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                        Text(fault.stack.isEmpty ? fault.detail : fault.detail)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        Text(fault.stack)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            HStack {
                Button("Recover State") { onRecover() }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Reconnects the bridge and clears isolated bays")
                Spacer()
                ForEach(history.prefix(3)) { past in
                    Text(past.code)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(past.level.color.opacity(0.7))
                }
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(.ultraThinMaterial)
        .background(CockpitPalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
