import SwiftUI

struct TotemProfileModalView: View {
    @ObservedObject var vm: OrchestratorViewModel
    @ObservedObject private var totemService = TotemPortListenerService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isCreating: Bool = false
    @State private var newName: String = ""
    @State private var newDescription: String = "Autonomous local coding agent persona"
    @State private var newSystemPrompt: String = "You are an authentic, high-agency autonomous local coding agent. You reason rigorously, inspect code before touching it, verify all mutations with compilers and tests, and maintain deep memory continuity across sessions."
    @State private var newPort: String = "8080"
    @State private var newHost: String = "http://127.0.0.1:8000"
    @State private var newModel: String = "qwythos/qwythos"
    @State private var newStorageFolder: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(CockpitFonts.bold(size: 13))
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTEM PERSONA PROFILES & MEMORY GRAPHS")
                        .font(CockpitFonts.mono(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("Each Totem persona owns a dedicated dual-tier knowledge graph (raw archival + compressed biodynamic)")
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(CockpitFonts.bold(size: 10))
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Profile List
                    Text("ACTIVE & REGISTERED TOTEMS")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.cyan)

                    ForEach(totemService.totems) { totem in
                        totemCardView(totem)
                    }

                    Divider().background(Color.white.opacity(0.06))

                    // Creation Form
                    if isCreating {
                        creationFormView
                    } else {
                        Button(action: { withAnimation { isCreating = true } }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                Text("Create New Totem Persona Profile")
                                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.cyan)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }

            Divider().background(Color.white.opacity(0.08))

            // Footer
            HStack {
                Button("Consolidate Memory Now") {
                    totemService.consolidateBiodynamicMemory()
                }
                .font(CockpitFonts.mono(size: 9))
                .foregroundColor(.cyan)
                .buttonStyle(.plain)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .font(CockpitFonts.mono(size: 10, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.9))
                .cornerRadius(5)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.6))
        }
        .frame(width: 720, height: 600)
        .background(CockpitPalette.background)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func totemCardView(_ totem: TotemProfile) -> some View {
        let isActive = totemService.activeTotem.id == totem.id

        return VStack(spacing: 12) {
            // 3D Spherical Orb
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                isActive ? Color.cyan.opacity(0.8) : Color.white.opacity(0.3),
                                isActive ? Color.cyan.opacity(0.2) : Color.white.opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        isActive ? Color.cyan.opacity(0.6) : Color.white.opacity(0.2),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: isActive ? Color.cyan.opacity(0.4) : Color.clear, radius: 12)

                // Neon lab video placeholder (looping animation)
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color.cyan.opacity(0.3),
                                Color.purple.opacity(0.2),
                                Color.blue.opacity(0.3),
                                Color.cyan.opacity(0.3)
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 80, height: 80)
                    .opacity(0.6)
                    .rotationEffect(.degrees(isActive ? 360 : 0))
                    .animation(
                        isActive ? Animation.linear(duration: 8).repeatForever(autoreverses: false) : .default,
                        value: isActive
                    )
            }
            .frame(height: 110)

            // Persona Name
            Text(totem.name)
                .font(CockpitFonts.mono(size: 11, weight: .bold))
                .foregroundColor(.white)

            // Diagonal Arrow Button
            HStack {
                Spacer()
                Button(action: {
                    totemService.selectTotem(totem)
                    vm.setEndpoint(url: totem.host, model: totem.modelIdentifier)
                }) {
                    Image(systemName: "arrow.up.right")
                        .font(CockpitFonts.regular(size: 12))
                        .foregroundColor(isActive ? .cyan : .white.opacity(0.6))
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open Totem Designer: \(totem.name)")
            }
        }
        .padding(12)
        .background(isActive ? Color.cyan.opacity(0.06) : Color.black.opacity(0.35))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.cyan.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var creationFormView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CREATE NEW TOTEM PERSONA")
                    .font(CockpitFonts.mono(size: 10, weight: .bold))
                    .foregroundColor(.cyan)
                Spacer()
                Button("Cancel") {
                    withAnimation { isCreating = false }
                }
                .font(CockpitFonts.mono(size: 8))
                .foregroundColor(.gray)
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Persona Name")
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray)
                    TextField("e.g. Architect, Pentester, CodeAuditor", text: $newName)
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 9))
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Listening Port")
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray)
                    TextField("8080", text: $newPort)
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 9))
                        .frame(width: 80)
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Persona Description (Role & Focus)")
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.gray)
                TextField("e.g. Deep systems engineering specialist and test loop driver", text: $newDescription)
                    .textFieldStyle(.plain)
                    .font(CockpitFonts.mono(size: 9))
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("System Prompt Directive")
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.gray)
                TextEditor(text: $newSystemPrompt)
                    .font(CockpitFonts.mono(size: 8))
                    .frame(height: 60)
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Host Endpoint URL")
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray)
                    TextField("http://127.0.0.1:8000", text: $newHost)
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 9))
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Model Name")
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray)
                    TextField("qwythos/qwythos", text: $newModel)
                        .textFieldStyle(.plain)
                        .font(CockpitFonts.mono(size: 9))
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }

            Button(action: createAndActivate) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                    Text("Instantiate Totem Persona & Scaffold Memory Graph")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.cyan)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color.black.opacity(0.45))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
    }

    private func createAndActivate() {
        let p = Int(newPort) ?? 8080
        let created = totemService.createTotemProfile(
            name: newName,
            personaDescription: newDescription,
            systemPrompt: newSystemPrompt,
            port: p,
            host: newHost,
            modelIdentifier: newModel,
            storageFolder: newStorageFolder.isEmpty ? nil : newStorageFolder
        )
        vm.setEndpoint(url: created.host, model: created.modelIdentifier)
        isCreating = false
        newName = ""
    }
}
