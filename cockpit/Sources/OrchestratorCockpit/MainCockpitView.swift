import SwiftUI

struct OrchestratorMainCockpit: View {
    @StateObject private var vm = OrchestratorViewModel()
    @ObservedObject private var harness = CodebaseHarnessService.shared

    @State private var selectedDrawerTab = 0
    @State private var selectedBayTab = 1
    @State private var sideInspectorTab = 0 // 0 = Viewport/Inspector, 1 = System Log
    @State private var expandedStagingCandidateId: UUID? = nil
    @State private var isArtifactsDrawerOpen = false
    @State private var isSkillsDrawerOpen = false
    @State private var isModelSettingsDrawerOpen = false
    @State private var showTotemProfileModal = false
    @State private var workspaceDir: String = ""

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CockpitPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                GeometryReader { geo in
                    let bp = CockpitLayout.breakpoint(for: geo.size.width)
                    ZStack {
                        bentoContent(for: bp, size: geo.size)
                            .id(harness.activeProjectDir ?? "root")
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                )
                            )
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.9), value: harness.activeProjectDir)
                    .padding(10)
                }
            }

            // Skills + Memory Drawer (slides from left)
            if isSkillsDrawerOpen {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { isSkillsDrawerOpen = false } }

                HStack(spacing: 0) {
                    SkillsMemoryDrawerView(isOpen: $isSkillsDrawerOpen, vm: vm)
                        .frame(width: 300)
                        .transition(.move(edge: .leading))
                    Spacer()
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSkillsDrawerOpen)
            }

            // llama.cpp Model Settings Drawer (slides from right)
            if isModelSettingsDrawerOpen {
                ModelSettingsDrawerView(isOpen: $isModelSettingsDrawerOpen, vm: vm)
                    .transition(.move(edge: .trailing))
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $vm.showFreshProjectSheet) {
            FreshProjectModalView(vm: vm)
        }
        .sheet(isPresented: $vm.showSettingsModal) {
            SettingsModalView()
        }
        .sheet(isPresented: $showTotemProfileModal) {
            TotemProfileModalView(vm: vm)
        }
        .task {
            vm.connect()
            vm.pingModelEndpoint()
            dispatchHarnessRefresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                vm.fetchRepos()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                vm.requestBrowserStatus()
            }
        }
        .background {
            Button("") { vm.isViewportPaused.toggle() }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
            Button("") {
                if let repo = vm.selectedRepo { vm.pullRepository(repo) }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .opacity(0)
            Button("") { vm.showFreshProjectSheet = true }
                .keyboardShortcut("n", modifiers: [.command])
                .opacity(0)

            // Speculative Ghost Scrubber Shortcuts (Cmd + [ / Cmd + ])
            Button("") { SpeculativeDiffGhostManager.shared.scrubBackward() }
                .keyboardShortcut("[", modifiers: [.command])
                .opacity(0)
            Button("") { SpeculativeDiffGhostManager.shared.scrubForward() }
                .keyboardShortcut("]", modifiers: [.command])
                .opacity(0)
        }
        .sheet(isPresented: $vm.isConsensusArenaOpen) {
            ConsensusArenaView(onAdoptCode: { code in
                vm.chatInputText = code
            })
        }
    }

    @ViewBuilder
    private func bentoContent(for bp: CockpitLayout.Breakpoint, size: CGSize) -> some View {
        switch bp {
        case .bento4:
            HStack(spacing: 10) {
                bayLeftExplorer.frame(width: 240)
                ChatConsoleView(vm: vm).frame(maxWidth: .infinity)
                baySideInspector.frame(width: 330)
            }
        case .drawer3:
            HStack(spacing: 10) {
                bayLeftExplorer.frame(width: 220)
                ChatConsoleView(vm: vm).frame(maxWidth: .infinity)
                baySideInspector.frame(width: 300)
            }
        case .grid2x2:
            VStack(spacing: 10) {
                ChatConsoleView(vm: vm).frame(maxHeight: .infinity)
                HStack(spacing: 10) {
                    bayLeftExplorer.frame(maxWidth: .infinity)
                    baySideInspector.frame(maxWidth: .infinity)
                }
                .frame(height: 280)
            }
        case .singleBay:
            VStack(spacing: 8) {
                Picker("", selection: $selectedBayTab) {
                    Text("CHAT").tag(0)
                    Text("FILES").tag(1)
                    Text("LOGS").tag(2)
                }
                .pickerStyle(.segmented)
                switch selectedBayTab {
                case 0: ChatConsoleView(vm: vm).frame(maxWidth: .infinity, maxHeight: .infinity)
                case 1: bayLeftExplorer.frame(maxWidth: .infinity, maxHeight: .infinity)
                default: SystemLogView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var bayLeftExplorer: some View {
        FailSafeBay(bayID: "explorer") {
            VStack(spacing: 8) {
                projectConversationPanel
                WorkspaceRegisterView(harness: harness)

                // "off coder" title — bottom-left below bucket
                HStack {
                    Text("off coder")
                        .font(CockpitFonts.ultraThin(size: 11))
                        .foregroundColor(.white)
                        .cyanGlow(radius: 5)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
            .padding(4)
        }
    }

    /// Lists every offcoder project/conversation workspace. Clicking one slides
    /// that workspace in from the left, replacing the current workspace.
    private var projectConversationPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("conversations")
                    .font(CockpitFonts.ultraThin(size: 9))
                    .foregroundColor(.white)
                    .cyanGlow(radius: 5, opacity: 0.45)
                Spacer()
                Text("\(harness.projects.count)")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if harness.projects.isEmpty {
                Text("no projects yet — begin anew to start one")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(harness.projects) { project in
                            let isActive = harness.activeProjectDir == project.path
                            Button(action: {
                                withAnimation {
                                    harness.setProjectDir(project.path)
                                }
                                vm.clearChat()
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(isActive ? Color.cyan : Color.white.opacity(0.25))
                                        .frame(width: 6, height: 6)
                                    Text(project.name)
                                        .font(CockpitFonts.mono(size: 8, weight: isActive ? .semibold : .regular))
                                        .foregroundColor(isActive ? .white : .white.opacity(0.7))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 2)
                                    Text(project.modified, style: .date)
                                        .font(CockpitFonts.mono(size: 6))
                                        .foregroundColor(.gray.opacity(0.8))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(isActive ? Color.white.opacity(0.08) : Color.clear)
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isActive ? Color.cyan.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help(project.path)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 190)
            }
        }
        .background(Color.black.opacity(0.30))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var baySideInspector: some View {
        FailSafeBay(bayID: "system_inspector") {
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    // Top Inspector Tab Switcher
                    HStack(spacing: 4) {
                        Button(action: { sideInspectorTab = 0 }) {
                            HStack(spacing: 3) {
                                Image(systemName: "safari")
                                    .font(.system(size: 8))
                                Text("VIEWPORT")
                                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                            }
                            .foregroundColor(sideInspectorTab == 0 ? .cyan : .gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(sideInspectorTab == 0 ? Color.cyan.opacity(0.15) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)

                        Button(action: { sideInspectorTab = 1 }) {
                            HStack(spacing: 3) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 8))
                                Text("SYSTEM LOG")
                                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                            }
                            .foregroundColor(sideInspectorTab == 1 ? .white : .gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(sideInspectorTab == 1 ? Color.white.opacity(0.12) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.45))

                    Divider().background(Color.white.opacity(0.08))

                    if sideInspectorTab == 0 {
                        ProductionSimulatorView(onGroundingCaptured: { payload in
                            vm.appendVisualDebugPayload(payload)
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        SystemLogView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                // Artifacts Drawer — slide-out from right edge with arrow tab
                artifactsDrawerOverlay
            }
            .background(CockpitPalette.bayBackground)
            .frostyBento()
        }
    }

    private var artifactsDrawerOverlay: some View {
        HStack(spacing: 0) {
            // Arrow tab — always visible on right edge
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isArtifactsDrawerOpen.toggle()
                }
            }) {
                VStack(spacing: 4) {
                    Image(systemName: isArtifactsDrawerOpen ? "chevron.right" : "chevron.left")
                        .font(CockpitFonts.regular(size: 7))
                        .foregroundColor(.white.opacity(0.6))
                    Text("artifacts")
                        .font(CockpitFonts.ultraThin(size: 6))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(width: 20, height: 60)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            if isArtifactsDrawerOpen {
                ArtifactsView()
                    .frame(width: 260)
                    .background(Color.black.opacity(0.88))
                    .background(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(Color.white.opacity(0.08)),
                        alignment: .leading
                    )
                    .transition(.move(edge: .trailing))
            }
        }
    }

    private var bayFeedback: some View {
        FailSafeBay(bayID: "feedback") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("FEEDBACK")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                    Spacer()
                    Circle()
                        .fill(harness.lastFeedbackPassed ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                }

                if harness.lastFeedbackOutput.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "checkmark.seal")
                            .font(CockpitFonts.regular(size: 20))
                            .foregroundColor(.gray.opacity(0.3))
                        Text("No test runs yet.")
                            .font(CockpitFonts.mono(size: 9))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(harness.lastFeedbackOutput)
                            .font(CockpitFonts.mono(size: 9))
                            .foregroundColor(harness.lastFeedbackPassed ? .green.opacity(0.9) : .orange.opacity(0.9))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                }
            }
            .padding(8)
        }
    }

    private func dispatchHarnessRefresh() {
        harness.refreshProjects()
        harness.refreshDeliverables()
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Spacing for macOS traffic lights (close, minimize, zoom) with native window dragging
            WindowDragArea()
                .frame(width: 70, height: 32)

            // Top-Left Settings Control Module
            topLeftControlModule

            // Draggable center area
            WindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Minimal action cluster: settings + upload only
            headerActionCluster

            // Right header area: fully draggable
            WindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 38)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(CockpitPalette.header)
    }

    private var topLeftControlModule: some View {
        HStack(spacing: 6) {
            // Totem Persona Control Bar (click to manage/switch/create totems)
            totemPersonaControlBar

            // Skills + Memory button (opens left drawer)
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isSkillsDrawerOpen.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(CockpitFonts.regular(size: 8))
                    Text("skills")
                        .font(CockpitFonts.ultraThin(size: 8))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSkillsDrawerOpen ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSkillsDrawerOpen ? Color.cyan.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Skills & MCP Memory Center")
        }
    }

    private var totemPersonaControlBar: some View {
        Menu {
            ForEach(TotemPortListenerService.shared.totems) { totem in
                Button(action: {
                    TotemPortListenerService.shared.selectTotem(totem)
                    vm.setEndpoint(url: totem.host, model: totem.modelIdentifier)
                }) {
                    HStack {
                        if totem.id == TotemPortListenerService.shared.activeTotem.id {
                            Text("✓ \(totem.name) (Port \(totem.port))")
                        } else {
                            Text("\(totem.name) (Port \(totem.port))")
                        }
                    }
                }
            }
            Divider()
            Button("📂 Open \(TotemPortListenerService.shared.activeTotem.name) Memory Folder") {
                TotemPortListenerService.shared.openLocalRecordsFolder(storageFolder: TotemPortListenerService.shared.activeTotem.storageFolder)
            }
            Button("🧙 Manage Totem Personas & Knowledge Graphs...") {
                showTotemProfileModal = true
            }
            Button("⚙️ All Cockpit Settings...") {
                vm.showSettingsModal = true
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                    .overlay(Circle().stroke(Color.green.opacity(0.6), lineWidth: 1).scaleEffect(1.4))

                Text(TotemPortListenerService.shared.activeTotem.name)
                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                    .foregroundColor(.white)

                Text(":\(TotemPortListenerService.shared.activeTotem.port)")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.cyan)

                Image(systemName: "chevron.down")
                    .font(CockpitFonts.regular(size: 6))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
    }



    private var headerActionCluster: some View {
        HStack(spacing: 8) {
            // Settings Icon: Opens settings modal
            Button(action: { vm.showSettingsModal = true }) {
                Image(systemName: "gearshape")
                    .font(CockpitFonts.medium(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 28, height: 26)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Settings & Inference Configuration")

            // llama.cpp Model Settings Drawer button (far right)
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isModelSettingsDrawerOpen.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(CockpitFonts.regular(size: 8))
                    Text("llama.cpp")
                        .font(CockpitFonts.ultraThin(size: 8))
                }
                .foregroundColor(isModelSettingsDrawerOpen ? .black : .white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isModelSettingsDrawerOpen ? Color.cyan : Color.white.opacity(0.04))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isModelSettingsDrawerOpen ? Color.cyan : Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("llama.cpp Model & LAN Inference Settings")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func chooseAndUploadWorkspaceFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    harness.recordDeliverable(relativePath: url.lastPathComponent, status: "uploaded", content: content)
                    _ = harness.writeFile(path: url.lastPathComponent, content: content)
                }
            }
        }
    }

    private var bayStaging: some View {
        FailSafeBay(bayID: "staging") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ZERO-LATENCY STAGING RING")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(vm.stagingCandidates.count) items")
                        .font(CockpitFonts.mono(size: 8))
                        .foregroundColor(.gray.opacity(0.6))
                }

                if vm.stagingCandidates.isEmpty {
                    Text("No mutations detected.")
                        .font(CockpitFonts.mono(size: 10))
                        .foregroundColor(MoonpondTheme.neonCyan.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(vm.stagingCandidates) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: item.isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(item.isValid ? MoonpondTheme.neonCyan : .orange)
                                    .shadow(color: item.isValid ? MoonpondTheme.neonCyan.opacity(0.8) : .orange.opacity(0.8), radius: 3)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.file)
                                        .font(CockpitFonts.mono(size: 10, weight: .bold))
                                        .foregroundColor(item.isValid ? .white : .orange)
                                    Text("WORKER: \(item.worker)")
                                        .font(CockpitFonts.mono(size: 8))
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                // Pre-Commit Linter Status Badge
                                Text(item.lintStatus.uppercased())
                                    .font(CockpitFonts.mono(size: 7, weight: .bold))
                                    .foregroundColor(linterBadgeColor(item.lintStatus))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(linterBadgeColor(item.lintStatus).opacity(0.12))
                                    .cornerRadius(3)

                                // Ghost Speculation Trigger
                                Button(action: {
                                    if let code = item.rawCode, !code.isEmpty {
                                        SpeculativeDiffGhostManager.shared.pushSpeculativeCandidate(
                                            code: code,
                                            summary: "Staging candidate: \(item.file)"
                                        )
                                    }
                                }) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8))
                                        .foregroundColor(.cyan)
                                        .padding(3)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(3)
                                }
                                .buttonStyle(.plain)
                                .help("View Speculative Ghost Diff")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25)) {
                                    if expandedStagingCandidateId == item.id {
                                        expandedStagingCandidateId = nil
                                    } else {
                                        expandedStagingCandidateId = item.id
                                    }
                                }
                            }

                            // Expandable Remediation Diagnostics
                            if expandedStagingCandidateId == item.id, !item.diagnostics.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(item.diagnostics) { diag in
                                        HStack(alignment: .top, spacing: 4) {
                                            Circle().fill(diag.severity == "error" ? Color.red : Color.orange).frame(width: 4, height: 4).offset(y: 4)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text("L\(diag.line):\(diag.col) [\(diag.code)] \(diag.message)")
                                                    .font(CockpitFonts.mono(size: 8, weight: .semibold))
                                                    .foregroundColor(diag.severity == "error" ? .red : .orange)
                                                if !diag.remediation.isEmpty {
                                                    Text("Remediation: \(diag.remediation)")
                                                        .font(CockpitFonts.mono(size: 7))
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(8)
            .background(Color.black.opacity(0.4))
        }
    }

    private var bayJournal: some View {
        FailSafeBay(bayID: "journal") {
            VStack(alignment: .leading, spacing: 6) {
                Text("JOURNAL")
                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                    .foregroundColor(.gray)

                if vm.journalEntries.isEmpty {
                    Text("Empty")
                        .font(CockpitFonts.mono(size: 10))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(vm.journalEntries) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.type)
                                    .font(CockpitFonts.mono(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(3)
                                Text(item.target)
                                    .font(CockpitFonts.mono(size: 9, weight: .semibold))
                            }
                            Text(item.summary)
                                .font(CockpitFonts.mono(size: 10))
                                .foregroundColor(.gray)
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(8)
        }
    }

    private var bayViewport: some View {
        FailSafeBay(bayID: "viewport") {
            ViewportView(
                frame: vm.currentScreenFrame,
                isPaused: vm.isViewportPaused
            )
        }
    }

    private func linterBadgeColor(_ status: String) -> Color {
        switch status.uppercased() {
        case "ERROR": return .red
        case "WARNING": return .orange
        case "CLEAN": return .green
        default: return .cyan
        }
    }
}
