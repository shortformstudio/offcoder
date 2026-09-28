import SwiftUI

struct ViewportView: View {
    let frame: NSImage?
    var isPaused: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
                            .font(CockpitFonts.mono(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }

                if isPaused {
                    ZStack {
                        Color.black.opacity(0.4)
                        HStack(spacing: 6) {
                            Image(systemName: "pause.fill")
                                .font(CockpitFonts.regular(size: 12))
                            Text("STREAM PAUSED (SPACE)")
                                .font(CockpitFonts.mono(size: 10, weight: .bold))
                        }
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                    }
                }
            }
            
            // Philosophize Action
            Button(action: {
                print("[Philosophize] Triggered local model DOM analysis on current viewport")
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text("PHILOSOPHIZE")
                }
                .font(CockpitFonts.mono(size: 8, weight: .bold))
                .foregroundColor(MoonpondTheme.neonCyan)
                .padding(6)
                .background(Color.black.opacity(0.8))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(MoonpondTheme.neonCyan.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live CDP Browser Viewport Stream")
    }
}
