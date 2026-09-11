import SwiftUI

struct SettingsModalView: View {
    @ObservedObject private var totemService = TotemPortListenerService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0 // 0 = Totems & Port, 1 = Inference Parameters
    @State private var editingTotem: TotemProfile = TotemProfile.default
    @State private var editingTotemPort: String = "8080"
    @State private var showSavedToast: Bool = false
    @State private var isCreatingNewTotem: Bool = false
    @State private var newTotemName: String = ""
    @State private var newTotemPort: String = "8080"
    @State private var newTotemHost: String = "http://192.168.1.80:8080/v1"
    @State private var newTotemModel: String = "qwythos/qwythos"
    @State private var newTotemFilter: TotemFilterType = .syntaxRegex

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(CockpitFonts.regular(size: 13))
                        .foregroundColor(.cyan)
                    Text("SETTINGS & INFERENCE CONTROL")
                        .font(CockpitFonts.mono(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(CockpitFonts.bold(size: 11))
                        .foregroundColor(.gray)
                        .padding(6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.6))

            Divider().background(Color.white.opacity(0.08))

            // Navigation Tabs
            HStack(spacing: 12) {
                tabButton("Totem Management", tag: 0, icon: "cpu")
                tabButton("Inference Parameters (llama.cpp)", tag: 1, icon: "slider.horizontal.3")
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.3))

            Divider().background(Color.white.opacity(0.06))

            // Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if selectedTab == 0 {
                        totemManagementView
                    } else {
                        inferenceParametersView
                    }
                }
                .padding(20)
            }

            Divider().background(Color.white.opacity(0.08))

            // Footer Action Bar
            HStack {
                if selectedTab == 1 {
                    Button("Reset to Defaults") {
                        resetParametersToDefaults()
                    }
                    .font(CockpitFonts.mono(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(.gray)
                }

                Spacer()

                Button("Done") {
                    if let p = Int(editingTotemPort) {
                        editingTotem.port = p
                    }
                    totemService.saveTotem(editingTotem)
                    dismiss()
                }
                .font(CockpitFonts.mono(size: 11, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.cyan)
                .cornerRadius(6)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.6))
        }
        .frame(width: 680, height: 620)
        .background(CockpitPalette.background)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .onAppear {
            selectTotemForEdit(totemService.activeTotem)
        }
    }

    private func selectTotemForEdit(_ totem: TotemProfile) {
        editingTotem = totem
        editingTotemPort = String(totem.port)
    }

    private func tabButton(_ title: String, tag: Int, icon: String) -> some View {
        Button(action: { selectedTab = tag }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(CockpitFonts.regular(size: 10))
                Text(title)
                    .font(CockpitFonts.mono(size: 10, weight: selectedTab == tag ? .bold : .medium))
            }
            .foregroundColor(selectedTab == tag ? .cyan : .gray)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selectedTab == tag ? Color.cyan.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Totem Management View
    private var totemManagementView: some View {
        VStack(alignment: .leading, spacing: 16) {
            totemHeaderExplanation
            registeredTotemsList
            editTotemDetailsCard
            createNewTotemSection
        }
    }

    private var totemHeaderExplanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TOTEM PROFILES & PORT LISTENERS")
                .font(CockpitFonts.mono(size: 11, weight: .bold))
                .foregroundColor(.white)
            Text("Each Totem is logically bound to an API port listener. Click any totem below to edit its name, port, host, and memory settings, or open its memory folder.")
                .font(CockpitFonts.mono(size: 10))
                .foregroundColor(.gray)
        }
    }

    private var registeredTotemsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REGISTERED TOTEMS (CLICK TO SELECT & EDIT)")
                .font(CockpitFonts.mono(size: 9, weight: .bold))
                .foregroundColor(.gray)

            ForEach(totemService.totems) { totem in
                TotemRowItemView(
                    totem: totem,
                    isActive: totem.id == totemService.activeTotem.id,
                    isEditing: totem.id == editingTotem.id,
                    onSelect: { selectTotemForEdit(totem) },
                    onOpenFolder: { totemService.openLocalRecordsFolder(port: totem.port) },
                    onActivate: {
                        totemService.selectTotem(totem)
                        selectTotemForEdit(totem)
                    },
                    onDelete: (totemService.totems.count > 1 && totem.name != "Qwythos") ? {
                        totemService.deleteTotem(id: totem.id)
                        selectTotemForEdit(totemService.activeTotem)
                    } : nil
                )
            }
        }
    }

    private var editTotemDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            editTotemHeaderRow
            editTotemFieldsRow1
            editTotemFieldsRow2
            editTotemFilterRow
            totemMemoryFolderBox
        }
        .padding(12)
        .background(Color.black.opacity(0.35))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var editTotemHeaderRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.2.square")
                    .font(CockpitFonts.regular(size: 11))
                    .foregroundColor(.cyan)
                Text("EDIT TOTEM DETAILS: \(editingTotem.name.uppercased())")
                    .font(CockpitFonts.mono(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            if showSavedToast {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.green)
                    Text("Saved!")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .cornerRadius(4)
            }
        }
    }

    private var editTotemFieldsRow1: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Totem Name")
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.gray)
                TextField("Totem Name", text: $editingTotem.name)
                    .textFieldStyle(.plain)
                    .font(CockpitFonts.mono(size: 10))
                    .padding(7)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Port (API Port & 'local records - [port]')")
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.gray)
                TextField("8080", text: $editingTotemPort)
                    .textFieldStyle(.plain)
                    .font(CockpitFonts.mono(size: 10))
                    .padding(7)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
        }
    }

    private var editTotemFieldsRow2: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Host Endpoint (/v1)")
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.gray)
                TextField("http://192.168.1.80:8080/v1", text: $editingTotem.host)
                    .textFieldStyle(.plain)
                    .font(CockpitFonts.mono(size: 10))
                    .padding(7)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model Identifier")
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.gray)
                TextField("model/id", text: $editingTotem.modelIdentifier)
                    .textFieldStyle(.plain)
                    .font(CockpitFonts.mono(size: 10))
                    .padding(7)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
        }
    }

    private var editTotemFilterRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Modular Memory Filter")
                .font(CockpitFonts.mono(size: 9))
                .foregroundColor(.gray)
            Menu {
                ForEach(TotemFilterType.allCases) { filter in
                    Button(filter.rawValue) {
                        editingTotem.defaultFilter = filter
                    }
                }
            } label: {
                HStack {
                    Text(editingTotem.defaultFilter.rawValue)
                        .font(CockpitFonts.mono(size: 10))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(CockpitFonts.regular(size: 8))
                        .foregroundColor(.gray)
                }
                .padding(7)
                .background(Color.black.opacity(0.5))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var totemMemoryFolderBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "externaldrive.badge.person.crop")
                    .font(CockpitFonts.regular(size: 10))
                    .foregroundColor(.cyan)
                Text("TOTEM DURABLE MEMORY")
                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                    .foregroundColor(.cyan)
                Spacer()
                Text("local records - \(editingTotemPort)")
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.gray)
            }

            Text("This is the exact memory directory Qwythos (local model) inspects and assimilates when booting up through totem port \(editingTotemPort). It contains MEMORY.md, raw transaction logs, and synthesized biodynamic knowledge.")
                .font(CockpitFonts.mono(size: 9))
                .foregroundColor(.white.opacity(0.75))
                .lineSpacing(2)

            HStack(spacing: 10) {
                Button(action: {
                    if let p = Int(editingTotemPort) {
                        editingTotem.port = p
                    }
                    totemService.saveTotem(editingTotem)
                    totemService.openLocalRecordsFolder(port: editingTotem.port)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(CockpitFonts.regular(size: 10))
                        Text("Open Memory Folder in Finder")
                            .font(CockpitFonts.mono(size: 10, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.cyan)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    if let p = Int(editingTotemPort) {
                        editingTotem.port = p
                    }
                    totemService.saveTotem(editingTotem)
                    withAnimation {
                        showSavedToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            showSavedToast = false
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(CockpitFonts.regular(size: 9))
                        Text("Save Details")
                            .font(CockpitFonts.mono(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                if editingTotem.id != totemService.activeTotem.id {
                    Button(action: {
                        if let p = Int(editingTotemPort) {
                            editingTotem.port = p
                        }
                        totemService.saveTotem(editingTotem)
                        totemService.selectTotem(editingTotem)
                    }) {
                        Text("Activate Totem")
                            .font(CockpitFonts.mono(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.45))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
    }

    private var createNewTotemSection: some View {
        Group {
            if isCreatingNewTotem {
                createNewTotemForm
            } else {
                Button(action: { isCreatingNewTotem = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Add New Totem")
                    }
                    .font(CockpitFonts.mono(size: 10, weight: .medium))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var createNewTotemForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEW TOTEM CONFIGURATION")
                .font(CockpitFonts.mono(size: 10, weight: .bold))
                .foregroundColor(.cyan)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Totem Name")
                        .font(CockpitFonts.mono(size: 9))
                        .foregroundColor(.gray)
                    TextField("e.g. Athena", text: $newTotemName)
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 10))
                        .padding(7)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(CockpitFonts.mono(size: 9))
                        .foregroundColor(.gray)
                    TextField("8080", text: $newTotemPort)
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 10))
                        .padding(7)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Host Endpoint")
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.gray)
                TextField("http://192.168.1.80:8080/v1", text: $newTotemHost)
                    .textFieldStyle(.plain)
                    .font(CockpitFonts.mono(size: 10))
                    .padding(7)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model Identifier")
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.gray)
                TextField("model/id", text: $newTotemModel)
                    .textFieldStyle(.plain)
                    .font(CockpitFonts.mono(size: 10))
                    .padding(7)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }

            HStack {
                Button("Cancel") {
                    isCreatingNewTotem = false
                }
                .font(CockpitFonts.mono(size: 10))
                .buttonStyle(.plain)
                .foregroundColor(.gray)

                Spacer()

                Button("Create Totem") {
                    let portInt = Int(newTotemPort) ?? 8080
                    let newProfile = TotemProfile(
                        id: "totem-\(UUID().uuidString.prefix(6))",
                        name: newTotemName.isEmpty ? "Totem-\(portInt)" : newTotemName,
                        port: portInt,
                        host: newTotemHost.isEmpty ? "http://127.0.0.1:\(portInt)/v1" : newTotemHost,
                        modelIdentifier: newTotemModel.isEmpty ? "default-model" : newTotemModel,
                        defaultFilter: newTotemFilter,
                        reasoningLevel: "High",
                        temperature: 0.7,
                        topP: 0.9,
                        topK: 40,
                        minP: 0.05,
                        repeatPenalty: 1.1,
                        presencePenalty: 0.0,
                        frequencyPenalty: 0.0,
                        contextLength: 32768,
                        seed: -1
                    )
                    totemService.saveTotem(newProfile)
                    totemService.selectTotem(newProfile)
                    selectTotemForEdit(newProfile)
                    isCreatingNewTotem = false
                }
                .font(CockpitFonts.mono(size: 10, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.cyan)
                .cornerRadius(5)
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.4))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Inference Parameters View (llama.cpp)
    private var inferenceParametersView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Level of Reasoning
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LEVEL OF REASONING")
                        .font(CockpitFonts.mono(size: 10, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(editingTotem.reasoningLevel)
                        .font(CockpitFonts.mono(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                }

                Picker("", selection: $editingTotem.reasoningLevel) {
                    Text("Low").tag("Low")
                    Text("Medium").tag("Medium")
                    Text("High").tag("High")
                    Text("Maximum").tag("Maximum")
                }
                .pickerStyle(.segmented)

                Text("Controls the internal chain-of-thought depth, reflection iterations, and self-audit rigor before tool execution.")
                    .font(CockpitFonts.mono(size: 9))
                    .foregroundColor(.gray)
            }
            .padding(12)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))

            // llama.cpp Core Hyperparameters
            VStack(alignment: .leading, spacing: 14) {
                Text("LLAMA.CPP INFERENCE HYPERPARAMETERS")
                    .font(CockpitFonts.mono(size: 10, weight: .bold))
                    .foregroundColor(.white)

                // Temperature
                sliderRow(
                    label: "temperature",
                    description: "Controls randomness in token sampling (0.0 = deterministic, 1.0+ = creative)",
                    value: $editingTotem.temperature,
                    inRange: 0.0...2.0,
                    step: 0.05,
                    format: "%.2f"
                )

                // Top-P
                sliderRow(
                    label: "top_p (nucleus sampling)",
                    description: "Limits cumulative probability pool of candidate tokens",
                    value: $editingTotem.topP,
                    inRange: 0.0...1.0,
                    step: 0.05,
                    format: "%.2f"
                )

                // Min-P
                sliderRow(
                    label: "min_p",
                    description: "Minimum probability threshold relative to most likely token",
                    value: $editingTotem.minP,
                    inRange: 0.0...1.0,
                    step: 0.01,
                    format: "%.2f"
                )

                // Top-K
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("top_k")
                            .font(CockpitFonts.mono(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        Text("Caps number of top logits considered")
                            .font(CockpitFonts.mono(size: 8))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Stepper("\(editingTotem.topK)", value: $editingTotem.topK, in: 1...200)
                        .font(CockpitFonts.mono(size: 10))
                }
                .padding(.vertical, 4)

                Divider().background(Color.white.opacity(0.06))

                // Repeat Penalty
                sliderRow(
                    label: "repeat_penalty",
                    description: "Penalizes recently generated tokens to curb repetitive loops",
                    value: $editingTotem.repeatPenalty,
                    inRange: 1.0...2.0,
                    step: 0.05,
                    format: "%.2f"
                )

                // Presence Penalty
                sliderRow(
                    label: "presence_penalty",
                    description: "Encourages introducing new vocabulary and concepts (-2.0 to 2.0)",
                    value: $editingTotem.presencePenalty,
                    inRange: -2.0...2.0,
                    step: 0.1,
                    format: "%.1f"
                )

                // Frequency Penalty
                sliderRow(
                    label: "frequency_penalty",
                    description: "Penalizes tokens proportionally based on frequency (-2.0 to 2.0)",
                    value: $editingTotem.frequencyPenalty,
                    inRange: -2.0...2.0,
                    step: 0.1,
                    format: "%.1f"
                )

                Divider().background(Color.white.opacity(0.06))

                // Context Length (n_ctx)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("n_ctx (Context Window Length)")
                            .font(CockpitFonts.mono(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        Text("Max tokens allocated for prompt, working memory, and completion")
                            .font(CockpitFonts.mono(size: 8))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Picker("", selection: $editingTotem.contextLength) {
                        Text("4,096").tag(4096)
                        Text("8,192").tag(8192)
                        Text("16,384").tag(16384)
                        Text("32,768").tag(32768)
                        Text("65,536").tag(65536)
                        Text("131,072").tag(131072)
                    }
                    .frame(width: 120)
                }
                .padding(.vertical, 4)

                // Seed
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("seed (RNG Seed)")
                            .font(CockpitFonts.mono(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        Text("Set -1 for pseudo-random execution, or fixed integer for reproducibility")
                            .font(CockpitFonts.mono(size: 8))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    TextField("-1", value: $editingTotem.seed, formatter: NumberFormatter())
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 10))
                        .frame(width: 70)
                        .padding(5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .padding(.vertical, 4)
            }
            .padding(12)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func sliderRow(label: String, description: String, value: Binding<Double>, inRange: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(CockpitFonts.mono(size: 10, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(CockpitFonts.mono(size: 10, weight: .bold))
                    .foregroundColor(.cyan)
            }
            Text(description)
                .font(CockpitFonts.mono(size: 8))
                .foregroundColor(.gray)
            Slider(value: value, in: inRange, step: step)
                .accentColor(.cyan)
        }
        .padding(.vertical, 2)
    }

    private func resetParametersToDefaults() {
        editingTotem.reasoningLevel = "High"
        editingTotem.temperature = 0.7
        editingTotem.topP = 0.9
        editingTotem.topK = 40
        editingTotem.minP = 0.05
        editingTotem.repeatPenalty = 1.1
        editingTotem.presencePenalty = 0.0
        editingTotem.frequencyPenalty = 0.0
        editingTotem.contextLength = 32768
        editingTotem.seed = -1
    }
}

struct TotemRowItemView: View {
    let totem: TotemProfile
    let isActive: Bool
    let isEditing: Bool
    let onSelect: () -> Void
    let onOpenFolder: () -> Void
    let onActivate: () -> Void
    let onDelete: (() -> Void)?

    private var rowBgColor: Color {
        if isEditing {
            return Color.cyan.opacity(0.12)
        } else if isActive {
            return Color.white.opacity(0.05)
        } else {
            return Color.white.opacity(0.02)
        }
    }

    private var rowBorderColor: Color {
        if isEditing {
            return Color.cyan.opacity(0.5)
        } else if isActive {
            return Color.green.opacity(0.3)
        } else {
            return Color.white.opacity(0.06)
        }
    }

    private var rowBorderWidth: CGFloat {
        isEditing ? 1.5 : 1.0
    }

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator
            infoColumn
            Spacer()
            actionsCluster
        }
        .padding(10)
        .background(rowBgColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorderColor, lineWidth: rowBorderWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var statusIndicator: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray.opacity(0.4))
            .frame(width: 8, height: 8)
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(totem.name)
                    .font(CockpitFonts.mono(size: 11, weight: .bold))
                    .foregroundColor(.white)
                if isActive {
                    Text("ACTIVE")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(3)
                }
                if isEditing {
                    Text("EDITING")
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.cyan.opacity(0.15))
                        .cornerRadius(3)
                }
            }
            Text("Port \(totem.port) • \(totem.host) • \(totem.modelIdentifier)")
                .font(CockpitFonts.mono(size: 9))
                .foregroundColor(.gray)
        }
    }

    private var actionsCluster: some View {
        HStack(spacing: 8) {
            Button(action: onOpenFolder) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(CockpitFonts.regular(size: 9))
                    Text("Memory Folder")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.12))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Open local records - \(totem.port) in Finder")

            if !isActive {
                Button("Activate", action: onActivate)
                    .font(CockpitFonts.mono(size: 9, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
                    .buttonStyle(.plain)
            }

            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(CockpitFonts.regular(size: 10))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete Totem")
            }
        }
    }
}

