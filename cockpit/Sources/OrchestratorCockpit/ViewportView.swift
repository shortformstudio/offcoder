import SwiftUI

struct ViewportView: View {
    let frame: NSImage?
    var isPaused: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
            if let frame {
                Image(nsImage: frame)
                    .interpolation(.medium)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Awaiting Browser Automation Frame...")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            if isPaused {
                ZStack {
                    Color.black.opacity(0.4)
                    HStack(spacing: 6) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12))
                        Text("STREAM PAUSED (SPACE)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live CDP Browser Viewport Stream")
    }
}
