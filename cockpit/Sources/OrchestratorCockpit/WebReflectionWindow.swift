import SwiftUI

struct WebReflectionWindow: View {
    @ObservedObject var vm: OrchestratorViewModel
    @State private var selectedTab = 0 // 0 = Prompt, 1 = Reply
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("HEADLESS REFLECTION")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }

                Text("[\(vm.webReflection.targetWorker)]")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)

                Spacer()

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)

                Button(action: { vm.webReflection.isActive = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))

            if isExpanded {
                VStack(spacing: 8) {
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
                                Text("Awaiting Headless Browser Frame...")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .frame(height: 140)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))

                    // Dual Tab: Prompt Sent vs Live Reply
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $selectedTab) {
                            Text("PROMPT SENT").tag(0)
                            Text("STREAMING REPLY").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)

                        ScrollView {
                            Text(selectedTab == 0 ? vm.webReflection.promptSent : vm.webReflection.streamingReply)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(6)
                        }
                        .frame(height: 90)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.75))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 6)
    }
}
