import SwiftUI

struct SystemLogView: View {
    @ObservedObject var simulator = ProductionSimulatorService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.cyan)
                    Text("SYSTEM LOG")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)

                    if simulator.isRunning {
                        HStack(spacing: 3) {
                            ProgressView().controlSize(.mini)
                            Text("RUNNING")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(3)
                    } else if let exitCode = simulator.lastExitCode {
                        Text(exitCode == 0 ? "EXIT 0" : "EXIT \(exitCode)")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                            .foregroundColor(exitCode == 0 ? .green : .red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background((exitCode == 0 ? Color.green : Color.red).opacity(0.15))
                            .cornerRadius(3)
                    }
                }

                Spacer()

                Button(action: {
                    simulator.executeRun()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(CockpitFonts.regular(size: 8))
                        Text("Run")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(simulator.isRunning)
                .help("Run codebase build or script")

                Button(action: {
                    simulator.clearLogs()
                }) {
                    Image(systemName: "trash")
                        .font(CockpitFonts.regular(size: 8))
                        .foregroundColor(.gray)
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help("Clear System Log")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.6))

            Divider().background(Color.white.opacity(0.06))

            // Console Stream
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(simulator.logs) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timestamp, style: .time)
                                    .font(CockpitFonts.mono(size: 7))
                                    .foregroundColor(.gray.opacity(0.5))

                                Text(entry.source)
                                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                                    .foregroundColor(colorForSource(entry.source, level: entry.level))

                                Text(entry.message)
                                    .font(CockpitFonts.mono(size: 8))
                                    .foregroundColor(colorForLevel(entry.level))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(6)
                }
                .background(Color.black.opacity(0.75))
                .onChange(of: simulator.logs.count) { _ in
                    if let last = simulator.logs.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(height: 155)
        .background(Color.black.opacity(0.5))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.08)),
            alignment: .top
        )
    }

    private func colorForSource(_ source: String, level: String) -> Color {
        switch source {
        case "[QWYTHOS]": return .cyan
        case "[BUILD]": return .yellow
        case "[DONE]": return .green
        case "[FAIL]", "[ERR]": return .red
        case "[SIMULATOR]": return .mint
        default: return colorForLevel(level)
        }
    }

    private func colorForLevel(_ level: String) -> Color {
        switch level {
        case "error": return .red.opacity(0.9)
        case "warn": return .orange.opacity(0.9)
        case "success": return .green.opacity(0.9)
        default: return .white.opacity(0.8)
        }
    }
}
