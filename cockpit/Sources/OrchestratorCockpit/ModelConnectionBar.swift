import SwiftUI

struct ModelConnectionBar: View {
    @ObservedObject var vm: OrchestratorViewModel
    @State private var showingSettingsSheet = false

    var body: some View {
        HStack(spacing: 8) {
            // Preset Dropdown
            Menu {
                Button("LAN Qwythos (192.168.1.80:8080)") {
                    vm.setEndpoint(url: "http://192.168.1.80:8080/v1", model: "qwythos/qwythos")
                }
                Button("Lockfort Qwythos (lockfort.local:8080)") {
                    vm.setEndpoint(url: "http://lockfort.local:8080/v1", model: "qwythos/qwythos")
                }
                Button("Local Dispatcher (127.0.0.1:8000)") {
                    vm.setEndpoint(url: "http://127.0.0.1:8000/v1", model: "deepseek-coder")
                }
                Button("Local Ollama (127.0.0.1:11434)") {
                    vm.setEndpoint(url: "http://127.0.0.1:11434/v1", model: "deepseek-coder:6.7b")
                }
                Button("Local LM Studio (127.0.0.1:1234)") {
                    vm.setEndpoint(url: "http://127.0.0.1:1234/v1", model: "local-model")
                }
                Divider()
                Button("Configure Custom LAN Host...") {
                    showingSettingsSheet = true
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(vm.connectionLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)

            // Endpoint & Model Readout
            HStack(spacing: 6) {
                Text(vm.localModelEndpoint)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
                Text("•")
                    .foregroundColor(.white.opacity(0.2))
                Text(vm.activeModelName)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 6)

            Spacer()

            // Latency / Ping Indicator
            if vm.modelPingLatencyMs >= 0 {
                HStack(spacing: 4) {
                    Text("\(vm.modelPingLatencyMs)ms")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(vm.modelPingLatencyMs < 100 ? .green : .yellow)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.04))
                .cornerRadius(4)
            }

            Button(action: { vm.pingModelEndpoint() }) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
            .help("Ping Model Endpoint")

            Button(action: { showingSettingsSheet = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help("Endpoint Settings")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.3))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .sheet(isPresented: $showingSettingsSheet) {
            endpointSettingsSheet
        }
    }

    private var statusColor: Color {
        switch vm.modelStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .offline: return .red
        }
    }

    private var endpointSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MODEL HOST CONFIGURATION")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text("Connect Offcoder to your local server or LAN inference node (Ollama, LM Studio, vLLM, llama.cpp).")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 6) {
                Text("API Endpoint (OpenAI-compatible /v1)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)
                TextField("http://192.168.1.50:8000/v1", text: $vm.localModelEndpoint)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model Name Identifier")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)
                TextField("qwythos/qwythos", text: $vm.activeModelName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }

            HStack {
                Button("Test Ping") {
                    vm.pingModelEndpoint()
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))

                Spacer()

                Button("Done") {
                    showingSettingsSheet = false
                    vm.setEndpoint(url: vm.localModelEndpoint, model: vm.activeModelName)
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(18)
        .frame(width: 440)
        .background(CockpitPalette.background)
    }
}
