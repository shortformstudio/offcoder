import SwiftUI

struct SkillEntry: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let isActive: Bool
}

// Ensure repoRootPath exists as requested
extension CodebaseHarnessService {
    var repoRootPath: String {
        return activeProjectDir ?? qwythosBaseDir
    }
}

struct SkillsMemoryDrawerView: View {
    @Binding var isOpen: Bool
    @ObservedObject var totemService = TotemPortListenerService.shared
    @State private var selectedTab: Int = 0 // 0 = Skills, 1 = Totem Memory
    @State private var expandedTotemIds: Set<String> = []
    
    static let defaultSkills: [SkillEntry] = [
        SkillEntry(name: "/consult", description: "Inference offload architecture & multi-agent scaffolding (DeepSeek/Kimi)", isActive: true),
        SkillEntry(name: "codebase-memory", description: "Knowledge graph of codebase structure", isActive: true),
        SkillEntry(name: "web-search", description: "Search the web for documentation and references", isActive: true),
        SkillEntry(name: "file-operations", description: "Read, write, and manage project files", isActive: true),
        SkillEntry(name: "terminal", description: "Execute shell commands and scripts", isActive: true),
        SkillEntry(name: "browser-devtools", description: "Chrome DevTools for debugging web apps", isActive: false),
        SkillEntry(name: "git-operations", description: "Version control and repository management", isActive: true),
    ]

    static let defaultMCPServers: [SkillEntry] = [
        SkillEntry(name: "codebase-memory-mcp", description: "Graph-based code indexing and search", isActive: true),
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if isOpen {
                    Color.black.opacity(0.001)
                        .onTapGesture {
                            withAnimation(.spring()) { isOpen = false }
                        }
                    
                    drawerView
                        .frame(width: 300, height: geometry.size.height)
                        .transition(.move(edge: .leading))
                        .zIndex(1)
                }
            }
        }
    }
    
    private var drawerView: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            Rectangle().fill(Material.ultraThin).ignoresSafeArea()
            
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    headerView
                    tabSwitcherView
                    
                    if selectedTab == 0 {
                        skillsTabView
                    } else {
                        memoryTabView
                    }
                    
                    Spacer()
                }
                
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("skills & memory")
                .font(CockpitFonts.ultraThin(size: 11))
                .foregroundColor(.white)
                .shadow(color: .cyan, radius: 4, x: 0, y: 0)
            
            Spacer()
            
            Button(action: {
                withAnimation(.spring()) { isOpen = false }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
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
                Text("SKILLS")
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
    }
    
    private var memoryTabView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(totemService.totems) { totem in
                    totemAccordionView(totem)
                    Divider().background(Color.white.opacity(0.1))
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
        let stats = memoryStats(for: totem.port)
        
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
                    .foregroundColor(stats.memoryExists ? .gray : .red)
            }
            
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.yellow)
                    .font(.system(size: 10))
                Text("biodynamic/")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.white)
                Spacer()
                Text("\(stats.bioCount) files")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
            }
            
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.yellow)
                    .font(.system(size: 10))
                Text("raw/")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.white)
                Spacer()
                Text("\(stats.rawCount) files")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.gray)
            }
            
            Button(action: {
                // Since this isn't defined directly on the service, we might need a workaround 
                // if it's missing, but the prompt says to call `totemService.openLocalRecordsFolder(port: totem.port)`
                // Assuming it exists.
                totemService.openLocalRecordsFolder(port: totem.port)
            }) {
                HStack {
                    Image(systemName: "folder.badge.gearshape")
                    Text("Open in Finder")
                }
                .font(CockpitFonts.mono(size: 7, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.cyan)
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 4)
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }
    
    private func memoryStats(for port: Int) -> (memoryExists: Bool, bioCount: Int, rawCount: Int) {
        let base = (CodebaseHarnessService.shared.repoRootPath as NSString).appendingPathComponent("local records - \(port)")
        let fm = FileManager.default
        let memExists = fm.fileExists(atPath: (base as NSString).appendingPathComponent("MEMORY.md"))
        let bioPath = (base as NSString).appendingPathComponent("biodynamic")
        let bioCount = (try? fm.contentsOfDirectory(atPath: bioPath))?.filter { $0.hasSuffix(".md") }.count ?? 0
        let rawPath = (base as NSString).appendingPathComponent("raw")
        let rawCount = (try? fm.contentsOfDirectory(atPath: rawPath))?.count ?? 0
        return (memExists, bioCount, rawCount)
    }
    
}
