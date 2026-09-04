import SwiftUI

struct OrchestratorMainCockpit: View {
    @StateObject private var vm = OrchestratorViewModel()
    @ObservedObject private var harness = CodebaseHarnessService.shared

    @State private var selectedDrawerTab = 0
    @State private var selectedBayTab = 1
    @State private var selectedLeftTab = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CockpitPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                GeometryReader { geo in
                    let bp = CockpitLayout.breakpoint(for: geo.size.width)
                    bentoContent(for: bp, size: geo.size)
                        .padding(10)
                }
            }

            // Floating Web Reflection Window (pops up anytime web model is queried)
            if vm.webReflection.isActive {
                WebReflectionWindow(vm: vm)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .padding(.trailing, 16)
                    .padding(.bottom, 36)
                    .zIndex(10)
            }

            marqueeOverlay
                .padding(12)
        }
        .sheet(isPresented: $vm.showFreshProjectSheet) {
            FreshProjectModalView(vm: vm)
        }
        .task {
            vm.connect()
            vm.pingModelEndpoint()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                vm.fetchRepos()
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
        }
    }

    @ViewBuilder
    private func bentoContent(for bp: CockpitLayout.Breakpoint, size: CGSize) -> some View {
        switch bp {
        case .bento4:
            HStack(spacing: 10) {
                bayLeftExplorer.frame(width: 250)
                ChatConsoleView(vm: vm).frame(maxWidth: .infinity)
                baySideInspector.frame(width: 360)
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
                .frame(height: 260)
            }
        case .singleBay:
            VStack(spacing: 8) {
                Picker("", selection: $selectedBayTab) {
                    Text("CHAT").tag(0)
                    Text("DIFFS").tag(1)
                    Text("FILES").tag(2)
                    Text("STREAM").tag(3)
                }
                .pickerStyle(.segmented)
                switch selectedBayTab {
                case 0: ChatConsoleView(vm: vm).frame(maxWidth: .infinity, maxHeight: .infinity)
                case 1: CodeVersionDiffView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case 2: bayLeftExplorer.frame(maxWidth: .infinity, maxHeight: .infinity)
                default: bayViewport.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var bayLeftExplorer: some View {
        FailSafeBay(bayID: "explorer") {
            VStack(spacing: 6) {
                Picker("", selection: $selectedLeftTab) {
                    Text("ARTIFACTS").tag(0)
                    Text("REPOS").tag(1)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

                if selectedLeftTab == 0 {
                    ArtifactsView()
                } else {
                    bayRepos
                }
            }
            .padding(4)
        }
    }

    private var baySideInspector: some View {
        VStack(spacing: 6) {
            Picker("", selection: $selectedDrawerTab) {
                Text("DIFFS").tag(0)
                Text("FEEDBACK").tag(1)
                Text("STAGING").tag(2)
                Text("JOURNAL").tag(3)
                Text("STREAM").tag(4)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            switch selectedDrawerTab {
            case 0:
                CodeVersionDiffView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case 1:
                bayFeedback
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case 2:
                bayStaging
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case 3:
                bayJournal
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                bayViewport
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var bayFeedback: some View {
        FailSafeBay(bayID: "feedback") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("FEEDBACK")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
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
                            .font(.system(size: 20))
                            .foregroundColor(.gray.opacity(0.3))
                        Text("No test runs yet.")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(harness.lastFeedbackOutput)
                            .font(.system(size: 9, design: .monospaced))
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

    private var marqueeOverlay: some View {
        ZStack(alignment: .bottomLeading) {
            if vm.marqueeDetailsOpen {
                MarqueeDetailPanel(
                    history: vm.marqueeHistory,
                    faults: vm.fault.faults,
                    onRecover: { vm.recover() },
                    onDismiss: { vm.marqueeDetailsOpen = false }
                )
                .allowsHitTesting(true)
            } else if let item = vm.marquee {
                MarqueeView(item: item)
                    .allowsHitTesting(false)
                if item.level == .alert {
                    Button {
                        vm.marqueeDetailsOpen = true
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                            .frame(width: 20, height: 20)
                            .background(Color.red.opacity(0.18))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Problem details")
                    .allowsHitTesting(true)
                    .padding(.leading, 348)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 8, height: 8)
                Text("OFFCODER")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                Text("•")
                    .foregroundColor(.white.opacity(0.2))
                Text(harness.activeProjectName ?? "No Project Active")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(harness.activeProjectName == nil ? .gray.opacity(0.6) : .cyan)
            }

            Divider().frame(height: 14).background(Color.white.opacity(0.1))

            ModelConnectionBar(vm: vm)

            Spacer()

            // Web Reflection Toggle
            Button(action: { withAnimation { vm.webReflection.isActive.toggle() } }) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(vm.webReflection.isActive ? Color.red : Color.gray)
                        .frame(width: 6, height: 6)
                    Text("Reflection")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(vm.webReflection.isActive ? .cyan : .gray)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(vm.webReflection.isActive ? Color.cyan.opacity(0.15) : Color.white.opacity(0.04))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: { vm.showFreshProjectSheet = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                    Text("New")
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(CockpitPalette.header)
    }

    private var bayRepos: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REPOSITORIES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)

            List(vm.githubRepos) { repo in
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue.opacity(0.7))
                    Text(repo.name)
                        .font(.system(size: 11, design: .monospaced))
                }
                .contentShape(Rectangle())
                .onTapGesture { vm.selectedRepo = repo.id }
                .listRowBackground(
                    vm.selectedRepo == repo.id
                        ? Color.white.opacity(0.06)
                        : Color.clear
                )
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if let notice = vm.registeredRepoNotice {
                Text(notice)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(notice.contains("Error") ? .red : .green)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }

            Button(action: {
                if let repo = vm.selectedRepo {
                    vm.pullRepository(repo)
                }
            }) {
                HStack(spacing: 6) {
                    if vm.isPullingRepo {
                        ProgressView().controlSize(.mini)
                        Text("Loading...")
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("Load into Context")
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(vm.selectedRepo == nil || vm.isPullingRepo ? Color.gray.opacity(0.2) : Color.blue.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(vm.selectedRepo == nil || vm.isPullingRepo)
        }
        .padding(4)
    }

    private var bayStaging: some View {
        FailSafeBay(bayID: "staging") {
            VStack(alignment: .leading, spacing: 6) {
                Text("STAGING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)

                if vm.stagingCandidates.isEmpty {
                    Text("No candidates")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(vm.stagingCandidates) { item in
                        HStack {
                            Image(systemName: item.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(item.isValid ? .green : .orange)
                            VStack(alignment: .leading) {
                                Text(item.file)
                                    .font(.system(size: 11, design: .monospaced))
                                Text(item.worker)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(8)
        }
    }

    private var bayJournal: some View {
        FailSafeBay(bayID: "journal") {
            VStack(alignment: .leading, spacing: 6) {
                Text("JOURNAL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)

                if vm.journalEntries.isEmpty {
                    Text("Empty")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(vm.journalEntries) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.type)
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(3)
                                Text(item.target)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            }
                            Text(item.summary)
                                .font(.system(size: 10, design: .monospaced))
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
}
