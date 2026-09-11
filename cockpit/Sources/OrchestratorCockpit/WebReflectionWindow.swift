import SwiftUI

struct WebReflectionWindow: View {
    @ObservedObject var vm: OrchestratorViewModel
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Header: Only exact tool call indicator (e.g. "deep seek web", "Kimi") and window controls
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().stroke(Color.cyan.opacity(0.5), lineWidth: 2).scaleEffect(1.4)
                    )

                Text(vm.webReflection.targetWorker)
                    .font(CockpitFonts.mono(size: 10, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)

                Button(action: { vm.webReflection.isActive = false }) {
                    Image(systemName: "xmark")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))

            if isExpanded {
                VStack(spacing: 6) {
                    // CDP Screencast Stream
                    ZStack {
                        Color.black
                        if let frame = vm.currentScreenFrame {
                            Image(nsImage: frame)
                                .interpolation(.medium)
                                .resizable()
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        } else {
                            VStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("Awaiting Web Frame...")
                                    .font(CockpitFonts.mono(size: 9))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .frame(height: 150)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .padding(8)
            }
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.85))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 6)
    }
}
