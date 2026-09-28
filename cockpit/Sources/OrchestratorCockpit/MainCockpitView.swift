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
    @State private var leftBayWidth: CGFloat = 250
    @State private var rightBayWidth: CGFloat = 340
    @State private var conversationPanelHeight: CGFloat = 190

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
        case .bento4, .drawer3:
            HStack(spacing: 0) {
                bayLeftExplorer
                    .frame(width: leftBayWidth)

                BentoHorizontalSplitter(
                    width: $leftBayWidth,
                    minWidth: 160,
                    maxWidth: max(200, size.width * 0.45),
                    isLeading: true
                )

                ChatConsoleView(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                BentoHorizontalSplitter(
                    width: $rightBayWidth,
                    minWidth: 200,
                    maxWidth: max(250, size.width * 0.50),
                    isLeading: false
                )

                baySideInspector
                    .frame(width: rightBayWidth)
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
            VStack(spacing: 4) {
                projectConversationPanel
                    .frame(height: conversationPanelHeight)

                BentoVerticalSplitter(
                    height: $conversationPanelHeight,
                    minHeight: 90,
                    maxHeight: 350,
                    isTop: true
                )

                WorkspaceRegisterView(harness: harness)
                    .frame(maxHeight: .infinity)

                // Skills button at bottom left
                HStack(spacing: 8) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            isSkillsDrawerOpen.toggle()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "brain.head.profile")
                                .font(CockpitFonts.regular(size: 9))
                            Text("skills")
                                .font(CockpitFonts.mono(size: 9, weight: .bold))
                        }
                        .foregroundColor(isSkillsDrawerOpen ? .cyan : .white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(isSkillsDrawerOpen ? Color.cyan.opacity(0.18) : Color.white.opacity(0.06))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSkillsDrawerOpen ? Color.cyan.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Open Skills & Memory Center")

                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(vm.connectionState == "CONNECTED" ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(vm.connectionState)
                    .font(CockpitFonts.mono(size: 7, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.04))
            .cornerRadius(4)
        }
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

struct BentoHorizontalSplitter: View {
    @Binding var width: CGFloat
    var minWidth: CGFloat = 160
    var maxWidth: CGFloat = 600
    var isLeading: Bool = true // true: increases width when dragging right; false: increases width when dragging left
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isHovered || isDragging ? Color.cyan.opacity(0.35) : Color.white.opacity(0.04))
                .frame(width: 6)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(isHovered || isDragging ? Color.cyan : Color.white.opacity(0.20))
                .frame(width: 3, height: 26)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    let delta = isLeading ? value.translation.width : -value.translation.width
                    let target = width + delta
                    width = min(maxWidth, max(minWidth, target))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

struct BentoVerticalSplitter: View {
    @Binding var height: CGFloat
    var minHeight: CGFloat = 80
    var maxHeight: CGFloat = 500
    var isTop: Bool = true // true: increases height when dragging down; false: increases height when dragging up
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isHovered || isDragging ? Color.cyan.opacity(0.35) : Color.white.opacity(0.04))
                .frame(height: 6)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(isHovered || isDragging ? Color.cyan : Color.white.opacity(0.20))
                .frame(width: 26, height: 3)
        }
        .frame(height: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    let delta = isTop ? value.translation.height : -value.translation.height
                    let target = height + delta
                    height = min(maxHeight, max(minHeight, target))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}
