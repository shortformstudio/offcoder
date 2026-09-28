import SwiftUI

struct LlamaSettingDoc {
    let title: String
    let flag: String
    let defaultValue: String
    let recommended: String
    let explanation: String
    let lanTip: String
}

struct ModelSettingsDrawerView: View {
    @Binding var isOpen: Bool
    @ObservedObject var vm: OrchestratorViewModel
    @ObservedObject private var totemService = TotemPortListenerService.shared

    @State private var editingTotem: TotemProfile = TotemProfile.default
    @State private var hoveredKey: String? = nil
    @State private var pingStatus: String? = nil
    @State private var isPinging: Bool = false
    @State private var activeTab: Int = 0 // 0 = Sampling & Penalties, 1 = Context & Hardware, 2 = LAN Server

    private let docs: [String: LlamaSettingDoc] = [
        "lan_host": LlamaSettingDoc(
            title: "LAN Host Endpoint",
            flag: "--host / endpoint URL",
            defaultValue: "http://127.0.0.1:8000",
            recommended: "LAN IP (e.g. 192.168.1.80:8080) or mDNS (.local)",
            explanation: "The network address of the dedicated llama.cpp or vLLM server on your local area network (LAN). Offcoder routes all inference traffic here over HTTP JSON-RPC/OpenAI API.",
            lanTip: "Using a wired 2.5GbE/10GbE or high-throughput Wi-Fi 6 LAN link minimizes token latency when streaming responses to your Mac."
        ),
        "lan_port": LlamaSettingDoc(
            title: "HTTP Port",
            flag: "--port",
            defaultValue: "8080",
            recommended: "8080 or 8000",
            explanation: "The TCP listening port of the llama.cpp server instance. Ensure firewall rules on the inference machine permit incoming connections on this port.",
            lanTip: "Port 8080 is the canonical llama.cpp server default; port 8000 is common for python dispatchers."
        ),
        "lan_model": LlamaSettingDoc(
            title: "Model Identifier",
            flag: "-m / --model / model alias",
            defaultValue: "qwythos/qwythos",
            recommended: "Matched to loaded GGUF file name or server alias",
            explanation: "Identifier passed in the 'model' field of chat completions. For llama.cpp, this can match the alias configured at server launch.",
            lanTip: "If your llama.cpp server serves multiple loaded slots, specify the precise model alias here."
        ),
        "temperature": LlamaSettingDoc(
            title: "Temperature",
            flag: "--temp",
            defaultValue: "0.70",
            recommended: "0.20 - 0.40 for coding; 0.70 - 0.90 for reasoning",
            explanation: "Controls the sharpness of the probability distribution over tokens. Lower values make output deterministic and conservative; higher values increase diversity.",
            lanTip: "For local code generation and compiler error fixes, keep temperature <= 0.4 to prevent hallucinated APIs."
        ),
        "top_p": LlamaSettingDoc(
            title: "Top-P (Nucleus Sampling)",
            flag: "--top-p",
            defaultValue: "0.90",
            recommended: "0.85 - 0.95",
            explanation: "Truncates the token pool to the smallest set whose cumulative probability exceeds P. Dynamically filters out low-probability tails.",
            lanTip: "Complementary with Min-P. When used together, Top-P acts as an outer guardrail while Min-P dynamically scales."
        ),
        "min_p": LlamaSettingDoc(
            title: "Min-P Sampling",
            flag: "--min-p",
            defaultValue: "0.05",
            recommended: "0.05 - 0.10",
            explanation: "Discards any token whose probability is less than min_p * (probability of top token). Highly effective at eliminating incoherent tokens without clipping valid synonyms.",
            lanTip: "Min-P is widely considered superior to Top-K in modern llama.cpp builds for maintainable agent code syntax."
        ),
        "top_k": LlamaSettingDoc(
            title: "Top-K Filtering",
            flag: "--top-k",
            defaultValue: "40",
            recommended: "40 - 80 (or 0 to disable)",
            explanation: "Keeps only the K highest-probability tokens at each generation step before applying other samplers.",
            lanTip: "Set to 0 if relying purely on Min-P and Top-P to prevent arbitrary token cutoff."
        ),
        "typical_p": LlamaSettingDoc(
            title: "Typical-P Sampling",
            flag: "--typical",
            defaultValue: "1.00 (disabled)",
            recommended: "0.90 - 0.95 when enabled",
            explanation: "Locally typical sampling selects tokens whose information content is close to the expected conditional entropy, optimizing for natural flow.",
            lanTip: "Useful for conversational brainstorming; leave at 1.0 (disabled) for strict syntax generation."
        ),
        "repeat_penalty": LlamaSettingDoc(
            title: "Repetition Penalty",
            flag: "--repeat-penalty",
            defaultValue: "1.10",
            recommended: "1.05 - 1.15",
            explanation: "Divides logit scores of tokens that have already appeared in the output context, discouraging repetitive loops.",
            lanTip: "Avoid values above 1.20 in coding models, as code naturally reuses variable names and function signatures."
        ),
        "repeat_last_n": LlamaSettingDoc(
            title: "Repeat Last N Window",
            flag: "--repeat-last-n",
            defaultValue: "64",
            recommended: "64 - 256",
            explanation: "The lookback distance (in tokens) over which repetition penalties are applied.",
            lanTip: "A 64-128 token window prevents immediate word loops while allowing the model to reuse identifiers later in a file."
        ),
        "presence_penalty": LlamaSettingDoc(
            title: "Presence Penalty",
            flag: "--presence-penalty",
            defaultValue: "0.00",
            recommended: "0.00 - 0.20",
            explanation: "Additive penalty applied once to any token that has already appeared, encouraging the introduction of fresh topics.",
            lanTip: "Keep at 0.0 for compiler loops to avoid forcing unnecessary synonyms for standard types."
        ),
        "frequency_penalty": LlamaSettingDoc(
            title: "Frequency Penalty",
            flag: "--frequency-penalty",
            defaultValue: "0.00",
            recommended: "0.00 - 0.20",
            explanation: "Additive penalty scaled by the exact count of times a token has appeared, heavily penalizing frequent words.",
            lanTip: "If an agent gets stuck outputting endless empty comments or spaces, raise this to 0.2."
        ),
        "dry_sampling": LlamaSettingDoc(
            title: "DRY (Don't Repeat Yourself) Sampler",
            flag: "--dry-multiplier / --dry-base",
            defaultValue: "0.0 (disabled)",
            recommended: "Multiplier: 0.8, Base: 1.75, Allowed: 2",
            explanation: "Novel n-gram repetition breaker in llama.cpp. Analyzes substring repetitions and exponentially suppresses repeated sequences without degrading vocabulary.",
            lanTip: "Greatly superior to standard repeat penalties for long chain-of-thought traces and multi-page code generation."
        ),
        "xtc_sampling": LlamaSettingDoc(
            title: "XTC (Exclude Top Choices)",
            flag: "--xtc-threshold / --xtc-probability",
            defaultValue: "0.0 (disabled)",
            recommended: "Threshold: 0.1, Probability: 0.5",
            explanation: "Removes the top choice token with probability P if its likelihood is below threshold, forcing exploration of creative alternatives.",
            lanTip: "Leave disabled (0.0) for pure software engineering where the top token is usually correct."
        ),
        "mirostat": LlamaSettingDoc(
            title: "Mirostat Adaptive Sampling",
            flag: "--mirostat 1 or 2",
            defaultValue: "0 (disabled)",
            recommended: "Mode 2, Tau: 5.0, Eta: 0.1",
            explanation: "Actively adjusts truncation dynamically at each step to maintain a constant target entropy (Tau) in the generated output.",
            lanTip: "Overrides temperature and Top-P when active. Ideal for long-form narrative coherence."
        ),
        "n_ctx": LlamaSettingDoc(
            title: "Context Window Length (n_ctx)",
            flag: "-c / --ctx-size",
            defaultValue: "32,768",
            recommended: "16,384 - 65,536 depending on GPU VRAM",
            explanation: "Maximum number of tokens allocated for the active prompt, system memory, tool outputs, and response.",
            lanTip: "On llama.cpp LAN servers, KV cache memory scales linearly with context length. Ensure server VRAM can hold n_ctx."
        ),
        "max_tokens": LlamaSettingDoc(
            title: "Max Generation Tokens (n_predict)",
            flag: "-n / --n-predict",
            defaultValue: "4,096",
            recommended: "2,048 - 8,192",
            explanation: "The upper limit of tokens generated by the model in a single assistant response turn.",
            lanTip: "Large code refactors need at least 4,096 tokens to emit complete files without truncation."
        ),
        "n_batch": LlamaSettingDoc(
            title: "Prompt Batch Size (n_batch)",
            flag: "-b / --batch-size",
            defaultValue: "512",
            recommended: "512 - 2048",
            explanation: "Logical batch size for evaluating prompt tokens. Higher values speed up initial prompt ingestion during large file reads.",
            lanTip: "Higher n_batch uses more compute buffer VRAM on the LAN host during prompt processing."
        ),
        "threads": LlamaSettingDoc(
            title: "CPU Threads",
            flag: "-t / --threads",
            defaultValue: "8",
            recommended: "Physical CPU cores (not hyperthreads) on LAN host",
            explanation: "Number of parallel worker threads used by llama.cpp for token generation when running partially or fully on CPU.",
            lanTip: "Setting threads higher than physical CPU cores causes thread contention and lowers tokens/sec."
        ),
        "flash_attn": LlamaSettingDoc(
            title: "Flash Attention",
            flag: "-fa / --flash-attn",
            defaultValue: "Enabled",
            recommended: "Enabled for Ampere (RTX 30xx+), Ada (40xx), Hopper, Apple Silicon",
            explanation: "Enables memory-efficient attention kernels, drastically cutting VRAM usage and accelerating context processing.",
            lanTip: "Enabling Flash Attention allows doubling the context window length without increasing VRAM consumption."
        ),
        "seed": LlamaSettingDoc(
            title: "RNG Seed",
            flag: "-s / --seed",
            defaultValue: "-1 (random)",
            recommended: "-1 for normal runs; fixed int for reproducible testing",
            explanation: "Random number generator seed. When set to a positive integer with temperature=0, outputs are strictly deterministic.",
            lanTip: "Useful when benchmarking prompt templates or verifying a bug report across LAN runs."
        ),
        "reasoning_level": LlamaSettingDoc(
            title: "Agent Reasoning Rigor",
            flag: "Internal agent directive",
            defaultValue: "High",
            recommended: "High or Maximum for complex coding tasks",
            explanation: "Determines the depth of the self-reflective chain-of-thought, compiler audit iterations, and tool validation loops before mutating files.",
            lanTip: "Pairs with deep reasoning models (e.g. DeepSeek-R1 / Qwen-2.5-Coder) to ensure exhaustive self-verification."
        )
    ]

    var body: some View {
        ZStack(alignment: .trailing) {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isOpen = false
                    }
                }

            // Drawer Sheet
            HStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    headerView
                    modelProfileSelectorBar
                    tabPickerView
                    contentScrollView
                    alwaysPresentExplainerDock
                    footerActionView
                }
                .frame(width: 440)
                .background(CockpitPalette.background)
                .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
                .overlay(Rectangle().frame(width: 1).foregroundColor(Color.white.opacity(0.1)), alignment: .leading)
                .shadow(color: Color.black.opacity(0.6), radius: 24, x: -10, y: 0)
            }
        }
        .onAppear {
            syncFromActiveTotem()
        }
    }

    private func syncFromActiveTotem() {
        self.editingTotem = totemService.activeTotem
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(CockpitFonts.bold(size: 11))
                .foregroundColor(.cyan)

            VStack(alignment: .leading, spacing: 1) {
                Text("LLAMA.CPP LAN SETTINGS")
                    .font(CockpitFonts.mono(size: 10, weight: .bold))
                    .foregroundColor(.white)
                Text("Configuring: \(totemService.activeTotem.name) (Port \(totemService.activePort))")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isOpen = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
                    .padding(5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.45))
        .border(Color.white.opacity(0.06), width: 1)
    }

    private var modelProfileSelectorBar: some View {
        HStack(spacing: 8) {
            Text("Model / Totem:")
                .font(CockpitFonts.mono(size: 8, weight: .bold))
                .foregroundColor(.cyan)

            Picker("", selection: Binding(
                get: { totemService.activeTotem.id },
                set: { newId in
                    if let target = totemService.totems.first(where: { $0.id == newId }) {
                        totemService.selectTotem(target)
                        self.editingTotem = target
                        vm.setEndpoint(url: "http://\(target.host):\(target.port)", model: target.modelId)
                        vm.recalculateContextTokens()
                    }
                }
            )) {
                ForEach(totemService.totems) { totem in
                    Text("\(totem.name) (\(totem.modelId))").tag(totem.id)
                }
            }
            .pickerStyle(.menu)

            Spacer()

            Text("Port :\(totemService.activePort)")
                .font(CockpitFonts.mono(size: 7))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Segmented Tab Picker
    private var tabPickerView: some View {
        HStack(spacing: 4) {
            tabButton("Sampling", tag: 0, icon: "waveform.path")
            tabButton("Advanced / DRY", tag: 1, icon: "shield.lefthalf.filled")
            tabButton("LAN & Hardware", tag: 2, icon: "network")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.25))
    }

    private func tabButton(_ title: String, tag: Int, icon: String) -> some View {
        Button(action: { activeTab = tag }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(title)
                    .font(CockpitFonts.mono(size: 8, weight: activeTab == tag ? .bold : .medium))
            }
            .foregroundColor(activeTab == tag ? .black : .white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(activeTab == tag ? Color.cyan : Color.white.opacity(0.04))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main Scrollable Content
    private var contentScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if activeTab == 0 {
                    samplingSection
                } else if activeTab == 1 {
                    advancedSamplersSection
                } else {
                    lanHardwareSection
                }
            }
            .padding(14)
        }
    }

    // MARK: - Tab 0: Core Sampling & Penalties
    private var samplingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Reasoning Level
            settingRowContainer(key: "reasoning_level") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Reasoning Depth")
                            .font(CockpitFonts.mono(size: 9, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text(editingTotem.reasoningLevel)
                            .font(CockpitFonts.mono(size: 9, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                    Picker("", selection: $editingTotem.reasoningLevel) {
                        Text("Low").tag("Low")
                        Text("Medium").tag("Medium")
                        Text("High").tag("High")
                        Text("Maximum").tag("Maximum")
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Temperature
            settingRowContainer(key: "temperature") {
                sliderControl(
                    title: "Temperature (--temp)",
                    value: $editingTotem.temperature,
                    range: 0.0...2.0,
                    step: 0.05,
                    format: "%.2f"
                )
            }

            // Min-P
            settingRowContainer(key: "min_p") {
                sliderControl(
                    title: "Min-P (--min-p)",
                    value: $editingTotem.minP,
                    range: 0.0...1.0,
                    step: 0.01,
                    format: "%.2f"
                )
            }

            // Top-P
            settingRowContainer(key: "top_p") {
                sliderControl(
                    title: "Top-P (--top-p)",
                    value: $editingTotem.topP,
                    range: 0.0...1.0,
                    step: 0.05,
                    format: "%.2f"
                )
            }

            // Top-K
            settingRowContainer(key: "top_k") {
                HStack {
                    Text("Top-K (--top-k)")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Stepper("\(editingTotem.topK)", value: $editingTotem.topK, in: 0...200)
                        .font(CockpitFonts.mono(size: 9))
                }
            }

            // Typical-P
            settingRowContainer(key: "typical_p") {
                sliderControl(
                    title: "Typical-P (--typical)",
                    value: $editingTotem.typicalP,
                    range: 0.1...1.0,
                    step: 0.05,
                    format: "%.2f"
                )
            }

            // Repeat Penalty
            settingRowContainer(key: "repeat_penalty") {
                sliderControl(
                    title: "Repeat Penalty (--repeat-penalty)",
                    value: $editingTotem.repeatPenalty,
                    range: 1.0...2.0,
                    step: 0.05,
                    format: "%.2f"
                )
            }

            // Repeat Last N
            settingRowContainer(key: "repeat_last_n") {
                HStack {
                    Text("Repeat Last N Window")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $editingTotem.repeatLastN) {
                        Text("32").tag(32)
                        Text("64").tag(64)
                        Text("128").tag(128)
                        Text("256").tag(256)
                        Text("512").tag(512)
                    }
                    .frame(width: 90)
                }
            }

            // Presence & Frequency Penalties
            settingRowContainer(key: "presence_penalty") {
                sliderControl(
                    title: "Presence Penalty",
                    value: $editingTotem.presencePenalty,
                    range: -2.0...2.0,
                    step: 0.1,
                    format: "%.1f"
                )
            }

            settingRowContainer(key: "frequency_penalty") {
                sliderControl(
                    title: "Frequency Penalty",
                    value: $editingTotem.frequencyPenalty,
                    range: -2.0...2.0,
                    step: 0.1,
                    format: "%.1f"
                )
            }
        }
    }

    // MARK: - Tab 1: Advanced Samplers (DRY, XTC, Mirostat)
    private var advancedSamplersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADVANCED ANTI-REPETITION (DRY)")
                .font(CockpitFonts.mono(size: 8, weight: .bold))
                .foregroundColor(.cyan)

            settingRowContainer(key: "dry_sampling") {
                VStack(spacing: 8) {
                    sliderControl(
                        title: "DRY Multiplier (0 = Off)",
                        value: $editingTotem.dryMultiplier,
                        range: 0.0...2.0,
                        step: 0.1,
                        format: "%.2f"
                    )
                    sliderControl(
                        title: "DRY Base",
                        value: $editingTotem.dryBase,
                        range: 1.0...3.0,
                        step: 0.05,
                        format: "%.2f"
                    )
                    HStack {
                        Text("DRY Allowed Length")
                            .font(CockpitFonts.mono(size: 9))
                            .foregroundColor(.gray)
                        Spacer()
                        Stepper("\(editingTotem.dryAllowedLength)", value: $editingTotem.dryAllowedLength, in: 1...10)
                            .font(CockpitFonts.mono(size: 9))
                    }
                }
            }

            Text("XTC SAMPLING")
                .font(CockpitFonts.mono(size: 8, weight: .bold))
                .foregroundColor(.cyan)
                .padding(.top, 4)

            settingRowContainer(key: "xtc_sampling") {
                VStack(spacing: 8) {
                    sliderControl(
                        title: "XTC Threshold (0 = Off)",
                        value: $editingTotem.xtcThreshold,
                        range: 0.0...1.0,
                        step: 0.05,
                        format: "%.2f"
                    )
                    sliderControl(
                        title: "XTC Probability",
                        value: $editingTotem.xtcProbability,
                        range: 0.0...1.0,
                        step: 0.05,
                        format: "%.2f"
                    )
                }
            }

            Text("MIROSTAT SAMPLING")
                .font(CockpitFonts.mono(size: 8, weight: .bold))
                .foregroundColor(.cyan)
                .padding(.top, 4)

            settingRowContainer(key: "mirostat") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Mirostat Mode")
                            .font(CockpitFonts.mono(size: 9, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $editingTotem.mirostat) {
                            Text("Disabled").tag(0)
                            Text("Mirostat 1").tag(1)
                            Text("Mirostat 2").tag(2)
                        }
                        .frame(width: 120)
                    }
                    if editingTotem.mirostat > 0 {
                        sliderControl(
                            title: "Mirostat Tau (Target Entropy)",
                            value: $editingTotem.mirostatTau,
                            range: 1.0...10.0,
                            step: 0.5,
                            format: "%.1f"
                        )
                        sliderControl(
                            title: "Mirostat Eta (Learning Rate)",
                            value: $editingTotem.mirostatEta,
                            range: 0.01...0.5,
                            step: 0.01,
                            format: "%.2f"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: LAN Host & Hardware Settings
    private var lanHardwareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOCAL AREA NETWORK (LAN) ENDPOINT")
                .font(CockpitFonts.mono(size: 8, weight: .bold))
                .foregroundColor(.cyan)

            settingRowContainer(key: "lan_host") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host URL / IP Address")
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray)
                    TextField("http://192.168.1.80:8080", text: $editingTotem.host)
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 9))
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }

            settingRowContainer(key: "lan_port") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Port Number")
                            .font(CockpitFonts.mono(size: 9, weight: .bold))
                            .foregroundColor(.white)
                        Text("Default: 8080")
                            .font(CockpitFonts.mono(size: 7))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    TextField("8080", value: $editingTotem.port, formatter: NumberFormatter())
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 9))
                        .frame(width: 70)
                        .padding(5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }

            settingRowContainer(key: "lan_model") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Identifier")
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray)
                    TextField("qwythos/qwythos", text: $editingTotem.modelIdentifier)
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 9))
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }

            // Ping Test Button
            HStack {
                Button(action: testLanConnection) {
                    HStack(spacing: 5) {
                        if isPinging {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                        }
                        Text(isPinging ? "Pinging LAN..." : "Test LAN Connection")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cyan)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(isPinging)

                if let pingStatus = pingStatus {
                    Text(pingStatus)
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(pingStatus.contains("OK") ? .green : .orange)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)

            Divider().background(Color.white.opacity(0.08))

            Text("COMPUTE & CONTEXT LIMITS")
                .font(CockpitFonts.mono(size: 8, weight: .bold))
                .foregroundColor(.cyan)

            // Context Window Length
            settingRowContainer(key: "n_ctx") {
                HStack {
                    Text("Context Window (n_ctx)")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $editingTotem.contextLength) {
                        Text("4,096").tag(4096)
                        Text("8,192").tag(8192)
                        Text("16,384").tag(16384)
                        Text("32,768").tag(32768)
                        Text("65,536").tag(65536)
                        Text("131,072").tag(131072)
                    }
                    .frame(width: 100)
                }
            }

            // Max Tokens
            settingRowContainer(key: "max_tokens") {
                HStack {
                    Text("Max Output (n_predict)")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $editingTotem.maxTokens) {
                        Text("1,024").tag(1024)
                        Text("2,048").tag(2048)
                        Text("4,096").tag(4096)
                        Text("8,192").tag(8192)
                        Text("16,384").tag(16384)
                    }
                    .frame(width: 100)
                }
            }

            // Batch Size
            settingRowContainer(key: "n_batch") {
                HStack {
                    Text("Prompt Batch (n_batch)")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $editingTotem.nBatch) {
                        Text("256").tag(256)
                        Text("512").tag(512)
                        Text("1024").tag(1024)
                        Text("2048").tag(2048)
                    }
                    .frame(width: 90)
                }
            }

            // Flash Attention
            settingRowContainer(key: "flash_attn") {
                Toggle(isOn: $editingTotem.flashAttn) {
                    Text("Flash Attention (--flash-attn)")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: .cyan))
            }

            // CPU Threads
            settingRowContainer(key: "threads") {
                HStack {
                    Text("CPU Threads (-t)")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Stepper("\(editingTotem.threads)", value: $editingTotem.threads, in: 1...64)
                        .font(CockpitFonts.mono(size: 9))
                }
            }

            // Seed
            settingRowContainer(key: "seed") {
                HStack {
                    Text("Seed (-1 for random)")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    TextField("-1", value: $editingTotem.seed, formatter: NumberFormatter())
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 9))
                        .frame(width: 70)
                        .padding(5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Reusable Setting Row Container with onHover
    private func settingRowContainer<Content: View>(key: String, @ViewBuilder content: () -> Content) -> some View {
        let isHovered = hoveredKey == key

        return VStack(alignment: .leading, spacing: 2) {
            content()
        }
        .padding(8)
        .background(isHovered ? Color.cyan.opacity(0.08) : Color.black.opacity(0.35))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovered ? Color.cyan.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .onHover { inside in
            if inside {
                hoveredKey = key
            } else if hoveredKey == key {
                hoveredKey = nil
            }
        }
    }

    // Helper Slider Control
    private func sliderControl(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.cyan)
            }
            Slider(value: value, in: range, step: step)
                .accentColor(.cyan)
        }
    }

    // MARK: - ALWAYS-PRESENT BOTTOM-LEFT EXPLAINER DOCK
    private var alwaysPresentExplainerDock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let key = hoveredKey, let doc = docs[key] {
                // Active Hover Explainer Box
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 5, height: 5)
                        .cyanGlow(radius: 4)

                    Text(doc.title.uppercased())
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(.cyan)

                    Spacer()

                    Text(doc.flag)
                        .font(CockpitFonts.code(size: 7))
                        .foregroundColor(.gray)
                }

                Text(doc.explanation)
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("Recommended:")
                        .font(CockpitFonts.mono(size: 7, weight: .bold))
                        .foregroundColor(.yellow.opacity(0.85))
                    Text(doc.recommended)
                        .font(CockpitFonts.mono(size: 7))
                        .foregroundColor(.gray)
                }

                if !doc.lanTip.isEmpty {
                    Text("💡 \(doc.lanTip)")
                        .font(CockpitFonts.mono(size: 6))
                        .foregroundColor(.cyan.opacity(0.8))
                        .lineLimit(2)
                }
            } else {
                // Default Standby Explainer Box
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.cyan.opacity(0.7))

                    Text("LLAMA.CPP PARAMETER EXPLAINER")
                        .font(CockpitFonts.mono(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }

                Text("Hover your cursor over any setting row above to inspect its underlying sampling mechanics, recommended values, and impact on local LAN inference.")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 88)
        .background(Color.black.opacity(0.65))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.cyan.opacity(0.2)), alignment: .top)
        .animation(.easeInOut(duration: 0.15), value: hoveredKey)
    }

    // MARK: - Footer Actions
    private var footerActionView: some View {
        HStack(spacing: 8) {
            Button("Reset Defaults") {
                resetDefaults()
            }
            .font(CockpitFonts.mono(size: 8, weight: .medium))
            .foregroundColor(.gray)
            .buttonStyle(.plain)

            Spacer()

            Button(action: applyAndSave) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                    Text("Apply & Save")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.cyan)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.4))
    }

    private func resetDefaults() {
        editingTotem.temperature = 0.70
        editingTotem.topP = 0.90
        editingTotem.minP = 0.05
        editingTotem.topK = 40
        editingTotem.typicalP = 1.00
        editingTotem.repeatPenalty = 1.10
        editingTotem.repeatLastN = 64
        editingTotem.presencePenalty = 0.00
        editingTotem.frequencyPenalty = 0.00
        editingTotem.dryMultiplier = 0.0
        editingTotem.xtcThreshold = 0.0
        editingTotem.mirostat = 0
        editingTotem.contextLength = 32768
        editingTotem.maxTokens = 4096
        editingTotem.flashAttn = true
        editingTotem.threads = 8
        editingTotem.seed = -1
    }

    private func applyAndSave() {
        totemService.saveTotem(editingTotem)
        vm.setEndpoint(url: editingTotem.host, model: editingTotem.modelIdentifier)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isOpen = false
        }
    }

    private func testLanConnection() {
        isPinging = true
        pingStatus = nil
        let host = editingTotem.host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let testUrl = host.hasSuffix("/v1") ? "\(host)/models" : "\(host)/v1/models"

        guard let url = URL(string: testUrl) else {
            isPinging = false
            pingStatus = "Invalid URL"
            return
        }

        let start = Date()
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0

        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                self.isPinging = false
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    self.pingStatus = "OK (\(ms)ms)"
                } else if let error = error {
                    self.pingStatus = "Fail: \(error.localizedDescription.prefix(20))"
                } else {
                    self.pingStatus = "Pinged (\(ms)ms)"
                }
            }
        }.resume()
    }
}
