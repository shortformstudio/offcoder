import SwiftUI

struct SkillEntry: Identifiable {
    let id: String
    let name: String
    let description: String
    let isActive: Bool
}

struct SkillsMemoryDrawerView: View {
    @Binding var isOpen: Bool
    @ObservedObject var vm: OrchestratorViewModel
    @State private var selectedTab = 0
    
    @ObservedObject var totemService = TotemPortListenerService.shared
    @State private var expandedTotemIds: Set<String> = []
    
    static let defaultSkills = [
        SkillEntry(id: "deepseek", name: "DeepSeek Consult", description: "Offloads reasoning logic to DeepSeek backend architecture audit.", isActive: true),
        SkillEntry(id: "kimi", name: "Kimi Design Audit", description: "UI/UX visual review with frontend aesthetics.", isActive: true),
        SkillEntry(id: "gemini", name: "Gemini Synthesizer", description: "Multi-modal vision and complex problem solving.", isActive: true),
        SkillEntry(id: "qwythos_native", name: "Qwythos Web Harness", description: "Local browser scraping and testing suite.", isActive: true)
    ]
    
    static let defaultMCPServers = [
        SkillEntry(id: "remember", name: "/remember (Memory Graph)", description: "Traverse Totem knowledge graph & relational edges with bounded context.", isActive: true),
        SkillEntry(id: "surf", name: "/surf (Stealth Web)", description: "Search DuckDuckGo/Bing and digest web sources directly in-process.", isActive: true),
        SkillEntry(id: "webaudit", name: "/webaudit (3-Pass DeepSeek)", description: "Autonomous 3-pass architectural audit and clone engine.", isActive: true),
        SkillEntry(id: "freeaudit", name: "/freeaudit (Free Tier Audit)", description: "Zero-cost code audit through DeepSeek Free Tier.", isActive: true),
        SkillEntry(id: "consult", name: "consult (Multi-Model)", description: "Inference offload to DeepSeek, Gemini, and Kimi.", isActive: true),
        SkillEntry(id: "journal", name: "journal (Milestone Log)", description: "Persist durable architectural decisions and milestones.", isActive: true),
        SkillEntry(id: "mission", name: "mission (Planner)", description: "Deconstruct multi-step goals into verifiable subtasks.", isActive: true),
        SkillEntry(id: "heartbeat", name: "heartbeat (Autonomous Task)", description: "Background pulse monitor and recurring agent watchdog.", isActive: true),
        SkillEntry(id: "explore", name: "explore (File System)", description: "Read, write, and diff files in the project workspace.", isActive: true)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            tabSwitcherView
            
            if selectedTab == 0 {
                skillsTabView
            } else {
                memoryTabView
            }
        }
        .background(Color.black.opacity(0.85).ignoresSafeArea())
        .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
        .border(Color.white.opacity(0.06), width: 1)
    }
    
    private var headerView: some View {
        HStack {
            Text("COMMAND CENTER")
                .font(CockpitFonts.mono(size: 9, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isOpen = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private var tabSwitcherView: some View {
        HStack(spacing: 8) {
            tabButton(title: "skills", index: 0)
            tabButton(title: "memory", index: 1)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }
    
    private func tabButton(title: String, index: Int) -> some View {
        Button(action: {
            selectedTab = index
        }) {
            Text(title)
                .font(CockpitFonts.regular(size: 8))
                .foregroundColor(selectedTab == index ? .white : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedTab == index ? Color.white.opacity(0.12) : Color.clear)
                .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var skillsTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("BUILT-IN SKILLS & COMMANDS")
                    .font(CockpitFonts.mono(size: 7, weight: .bold))
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                
                ForEach(Self.defaultSkills) { skill in
                    skillEntryView(skill)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 8)
                
                Text("MCP SERVERS")
                    .font(CockpitFonts.mono(size: 7, weight: .bold))
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                
                ForEach(Self.defaultMCPServers) { server in
                    skillEntryView(server)
                }
            }
            .padding(.bottom)
        }
    }
    
    private func skillEntryView(_ entry: SkillEntry) -> some View {
        Button(action: {
            // Preload hypertext into input box
            let insertion = "/\(entry.id) "
            if !vm.chatInputText.contains(insertion) {
                vm.chatInputText = insertion + vm.chatInputText
            }
            withAnimation(.spring()) {
                isOpen = false
            }
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(entry.isActive ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    
                    Text(entry.name)
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(.cyan)
                }
                
                Text(entry.description)
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
                    .padding(.leading, 14)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.02))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
    
    @State private var memoryViewMode: Int = 1 // 0 = List, 1 = Pulse Graph

    private var memoryTabView: some View {
        VStack(spacing: 0) {
            // View Mode Switcher
            HStack {
                HStack(spacing: 4) {
                    Button(action: { memoryViewMode = 0 }) {
                        Text("LIST")
                            .font(CockpitFonts.mono(size: 8, weight: .bold))
                            .foregroundColor(memoryViewMode == 0 ? .white : .gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(memoryViewMode == 0 ? Color.white.opacity(0.12) : Color.clear)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button(action: { memoryViewMode = 1 }) {
                        HStack(spacing: 3) {
                            Image(systemName: "circle.hexagongrid.fill")
                                .font(.system(size: 8))
                            Text("PULSE GRAPH")
                                .font(CockpitFonts.mono(size: 8, weight: .bold))
                        }
                        .foregroundColor(memoryViewMode == 1 ? .cyan : .gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(memoryViewMode == 1 ? Color.cyan.opacity(0.18) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .background(Color.black.opacity(0.4))
                .cornerRadius(6)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider().background(Color.white.opacity(0.08))

            if memoryViewMode == 1 {
                PulseMemoryGraphView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(totemService.totems) { totem in
                            totemAccordionView(totem)
                            Divider().background(Color.white.opacity(0.1))
                        }
                    }
                }
            }
        }
    }
    
    private func totemAccordionView(_ totem: TotemProfile) -> some View {
        let isExpanded = expandedTotemIds.contains(totem.id)
        let isActive = totemService.activeTotem.id == totem.id
        
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                if isExpanded {
                    expandedTotemIds.remove(totem.id)
                } else {
                    expandedTotemIds.insert(totem.id)
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                        .frame(width: 12)
                    
                    Text("\(totem.name) (\(totem.port))")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Circle()
                        .fill(isActive ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                totemMemoryDetails(for: totem)
            }
        }
    }
    
    private func totemMemoryDetails(for totem: TotemProfile) -> some View {
        let stats = memoryStats(for: totem)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.cyan)
                    .font(.system(size: 10))
                Text("MEMORY.md")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.white)
                Spacer()
                Text(stats.memoryExists ? "Exists" : "Missing")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(stats.memoryExists ? .green : .red)
            }

            HStack {
                Image(systemName: "network")
                    .foregroundColor(.purple)
                    .font(.system(size: 10))
                Text("biodynamic/ (Graph & Facts)")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.white)
                Spacer()
                Text("\(stats.bioCount) records")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
            }

            HStack {
                Image(systemName: "archivebox")
                    .foregroundColor(.yellow)
                    .font(.system(size: 10))
                Text("raw/ (Raw History)")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.white)
                Spacer()
                Text("\(stats.rawCount) turns")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
            }

            Button(action: {
                totemService.openLocalRecordsFolder(storageFolder: totem.storageFolder)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.gearshape")
                    Text("Open Memory Folder")
                }
                .font(CockpitFonts.mono(size: 7, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.cyan)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }

    private func memoryStats(for totem: TotemProfile) -> (memoryExists: Bool, bioCount: Int, rawCount: Int) {
        let base = totemService.getLocalRecordsDir(storageFolder: totem.storageFolder)
        let fm = FileManager.default
        let memExists = fm.fileExists(atPath: (base as NSString).appendingPathComponent("MEMORY.md"))

        let bioPath = (base as NSString).appendingPathComponent("biodynamic")
        let factsFile = (bioPath as NSString).appendingPathComponent("facts.jsonl")
        let factsCount: Int = {
            if let str = try? String(contentsOfFile: factsFile, encoding: .utf8) {
                return str.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            }
            return 0
        }()

        let rawPath = (base as NSString).appendingPathComponent("raw")
        let rawConvoFile = (rawPath as NSString).appendingPathComponent("raw_convo.jsonl")
        let rawCount: Int = {
            if let str = try? String(contentsOfFile: rawConvoFile, encoding: .utf8) {
                return str.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            }
            return 0
        }()

        return (memExists, factsCount, rawCount)
    }
}
