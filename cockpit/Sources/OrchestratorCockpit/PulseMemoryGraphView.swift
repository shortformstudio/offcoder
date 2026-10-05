import SwiftUI

enum PulseNodeType: String {
    case totem = "TOTEM"
    case mission = "MISSION"
    case fileBinding = "FILE"
    case fact = "FACT"

    var color: Color {
        switch self {
        case .totem: return .cyan
        case .mission: return .purple
        case .fileBinding: return .yellow
        case .fact: return .green
        }
    }

    var icon: String {
        switch self {
        case .totem: return "antenna.radiowaves.left.and.right"
        case .mission: return "target"
        case .fileBinding: return "doc.text.fill"
        case .fact: return "brain.head.profile"
        }
    }
}

struct PulseGraphNode: Identifiable {
    let id: String
    let label: String
    let type: PulseNodeType
    var x: CGFloat
    var y: CGFloat
    var salience: Double
    var isPinned: Bool
    var summary: String
}

struct PulseGraphEdge: Identifiable {
    let id = UUID()
    let sourceId: String
    let targetId: String
    let relationship: String
    let weight: Double
}

final class PulseMemoryGraphViewModel: ObservableObject {
    @Published var nodes: [PulseGraphNode] = []
    @Published var edges: [PulseGraphEdge] = []
    @Published var selectedNode: PulseGraphNode? = nil
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    init() {
        reloadGraph()
    }

    func reloadGraph() {
        let totem = TotemPortListenerService.shared.activeTotem
        let folder = totem.storageFolder
        let url = URL(fileURLWithPath: folder).appendingPathComponent("biodynamic")

        var loadedNodes: [PulseGraphNode] = []
        var loadedEdges: [PulseGraphEdge] = []

        // Root Totem Node
        loadedNodes.append(PulseGraphNode(
            id: "node_totem_\(totem.name)",
            label: totem.name,
            type: .totem,
            x: 0,
            y: 0,
            salience: 1.0,
            isPinned: true,
            summary: "Active Totem persona listening on port \(totem.port)."
        ))

        // Mission Node
        loadedNodes.append(PulseGraphNode(
            id: "node_mission_core",
            label: "Core Mission",
            type: .mission,
            x: 120,
            y: -80,
            salience: 0.95,
            isPinned: true,
            summary: "Long-horizon autonomous synthesis & zero-latency staging pipeline."
        ))

        loadedEdges.append(PulseGraphEdge(
            sourceId: "node_totem_\(totem.name)",
            targetId: "node_mission_core",
            relationship: "executes",
            weight: 1.0
        ))

        // Read biodynamic/graph_edges.json
        let edgesFile = url.appendingPathComponent("graph_edges.json")
        if let data = try? Data(contentsOf: edgesFile),
           let jsonArr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in jsonArr {
                if let src = item["source"] as? String,
                   let tgt = item["target"] as? String,
                   let rel = item["relationship"] as? String {
                    let weight = item["weight"] as? Double ?? 1.0

                    let srcId = "node_\(src.lowercased().replacingOccurrences(of: " ", with: "_"))"
                    let tgtId = "node_\(tgt.lowercased().replacingOccurrences(of: " ", with: "_"))"

                    if !loadedNodes.contains(where: { $0.id == srcId }) {
                        loadedNodes.append(PulseGraphNode(
                            id: srcId,
                            label: src,
                            type: .totem,
                            x: CGFloat.random(in: -150...150),
                            y: CGFloat.random(in: -150...150),
                            salience: 0.8,
                            isPinned: false,
                            summary: "Discovered knowledge source: \(src)"
                        ))
                    }
                    if !loadedNodes.contains(where: { $0.id == tgtId }) {
                        loadedNodes.append(PulseGraphNode(
                            id: tgtId,
                            label: tgt,
                            type: .mission,
                            x: CGFloat.random(in: -150...150),
                            y: CGFloat.random(in: -150...150),
                            salience: 0.8,
                            isPinned: false,
                            summary: "Discovered mission target: \(tgt)"
                        ))
                    }

                    loadedEdges.append(PulseGraphEdge(
                        sourceId: srcId,
                        targetId: tgtId,
                        relationship: rel,
                        weight: weight
                    ))
                }
            }
        }

        // Read biodynamic/working_knowledge.json
        let wkFile = url.appendingPathComponent("working_knowledge.json")
        if let data = try? Data(contentsOf: wkFile),
           let jsonArr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var angle: CGFloat = 0.0
            let radius: CGFloat = 160.0
            let step = (CGFloat.pi * 2) / max(1, CGFloat(jsonArr.count))

            for item in jsonArr.prefix(12) {
                let id = item["id"] as? String ?? UUID().uuidString
                let title = item["title"] as? String ?? "Knowledge Unit"
                let summary = item["semanticSummary"] as? String ?? ""
                let salience = item["salienceScore"] as? Double ?? 0.5
                let tags = item["tags"] as? [String] ?? []
                let isPinned = tags.contains("pinned")

                let nodeType: PulseNodeType = title.contains(".") ? .fileBinding : .fact

                let nodeX = cos(angle) * radius
                let nodeY = sin(angle) * radius
                angle += step

                let nodeId = "wk_\(id)"
                loadedNodes.append(PulseGraphNode(
                    id: nodeId,
                    label: title,
                    type: nodeType,
                    x: nodeX,
                    y: nodeY,
                    salience: salience,
                    isPinned: isPinned,
                    summary: summary
                ))

                loadedEdges.append(PulseGraphEdge(
                    sourceId: "node_mission_core",
                    targetId: nodeId,
                    relationship: "anchors",
                    weight: salience
                ))
            }
        }

        self.nodes = loadedNodes
        self.edges = loadedEdges
    }

    func togglePinNode(_ node: PulseGraphNode) {
        guard let idx = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        nodes[idx].isPinned.toggle()
        // Save back to working_knowledge.json or wisdom.json
        persistPinStatus(nodeId: node.id, isPinned: nodes[idx].isPinned)
    }

    func pruneNode(_ node: PulseGraphNode) {
        nodes.removeAll(where: { $0.id == node.id })
        edges.removeAll(where: { $0.sourceId == node.id || $0.targetId == node.id })
        if selectedNode?.id == node.id {
            selectedNode = nil
        }
    }

    private func persistPinStatus(nodeId: String, isPinned: Bool) {
        let totem = TotemPortListenerService.shared.activeTotem
        let file = URL(fileURLWithPath: totem.storageFolder)
            .appendingPathComponent("biodynamic")
            .appendingPathComponent("working_knowledge.json")

        guard let data = try? Data(contentsOf: file),
              var jsonArr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        let cleanId = nodeId.replacingOccurrences(of: "wk_", with: "")
        for i in 0..<jsonArr.count {
            if (jsonArr[i]["id"] as? String) == cleanId {
                var tags = jsonArr[i]["tags"] as? [String] ?? []
                if isPinned && !tags.contains("pinned") {
                    tags.append("pinned")
                } else if !isPinned {
                    tags.removeAll(where: { $0 == "pinned" })
                }
                jsonArr[i]["tags"] = tags
                break
            }
        }

        if let updated = try? JSONSerialization.data(withJSONObject: jsonArr, options: [.prettyPrinted]) {
            try? updated.write(to: file)
        }
    }
}

struct PulseMemoryGraphView: View {
    @StateObject private var vm = PulseMemoryGraphViewModel()
    @State private var dragCurrent: CGSize = .zero
    @State private var isPanning = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            graphHeader

            Divider().background(Color.white.opacity(0.1))

            // Canvas Area
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()

                GeometryReader { geo in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

                    ZStack {
                        // Render Edges
                        ForEach(vm.edges) { edge in
                            if let src = vm.nodes.first(where: { $0.id == edge.sourceId }),
                               let tgt = vm.nodes.first(where: { $0.id == edge.targetId }) {
                                edgeLine(from: src, to: tgt, rel: edge.relationship, weight: edge.weight, center: center)
                            }
                        }

                        // Render Nodes
                        ForEach(vm.nodes) { node in
                            nodeCircle(node: node, center: center)
                        }
                    }
                    .scaleEffect(vm.zoomScale)
                    .offset(x: vm.panOffset.width + dragCurrent.width, y: vm.panOffset.height + dragCurrent.height)
                    .gesture(
                        DragGesture()
                            .onChanged { val in
                                if !isPanning {
                                    isPanning = true
                                    WindowDragGate.suspend()
                                }
                                dragCurrent = val.translation
                            }
                            .onEnded { val in
                                isPanning = false
                                WindowDragGate.resume()
                                vm.panOffset.width += val.translation.width
                                vm.panOffset.height += val.translation.height
                                dragCurrent = .zero
                            }
                    )
                }

                // Selected Node Inspector Popover
                if let node = vm.selectedNode {
                    VStack {
                        Spacer()
                        selectedNodeCard(node)
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Subviews
    private var graphHeader: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(CockpitFonts.bold(size: 10))
                    .foregroundColor(.cyan)
                Text("PULSE MEMORY GRAPH")
                    .font(CockpitFonts.mono(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer()

            // Zoom Controls
            HStack(spacing: 4) {
                Button(action: { withAnimation { vm.zoomScale = max(0.5, vm.zoomScale - 0.2) } }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)

                Text("\(Int(vm.zoomScale * 100))%")
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.gray)

                Button(action: { withAnimation { vm.zoomScale = min(2.5, vm.zoomScale + 0.2) } }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation {
                        vm.zoomScale = 1.0
                        vm.panOffset = .zero
                        vm.reloadGraph()
                    }
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(CockpitFonts.regular(size: 8))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
                .help("Reset Canvas")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5))
    }

    private func edgeLine(from src: PulseGraphNode, to tgt: PulseGraphNode, rel: String, weight: Double, center: CGPoint) -> some View {
        let p1 = CGPoint(x: center.x + src.x, y: center.y + src.y)
        let p2 = CGPoint(x: center.x + tgt.x, y: center.y + tgt.y)

        return ZStack {
            Path { path in
                path.move(to: p1)
                path.addLine(to: p2)
            }
            .stroke(
                LinearGradient(
                    colors: [src.type.color.opacity(0.4), tgt.type.color.opacity(0.4)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: CGFloat(max(1.0, weight * 2.0)), lineCap: .round)
            )

            // Midpoint label
            Text(rel)
                .font(CockpitFonts.mono(size: 7))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.6))
                .cornerRadius(2)
                .position(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        }
    }

    private func nodeCircle(node: PulseGraphNode, center: CGPoint) -> some View {
        let pos = CGPoint(x: center.x + node.x, y: center.y + node.y)
        let isSelected = vm.selectedNode?.id == node.id

        return ZStack {
            // Pulse Halo
            Circle()
                .fill(node.type.color.opacity(isSelected ? 0.4 : 0.15))
                .frame(width: 38, height: 38)

            // Solid Core
            Circle()
                .fill(Color.black)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(node.type.color, lineWidth: isSelected ? 2 : 1))

            // Icon
            Image(systemName: node.type.icon)
                .font(.system(size: 10))
                .foregroundColor(node.type.color)

            // Pin badge
            if node.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.yellow)
                    .offset(x: 10, y: -10)
            }

            // Node Label
            Text(node.label)
                .font(CockpitFonts.mono(size: 8, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .offset(y: 20)
        }
        .position(pos)
        .onTapGesture {
            withAnimation(.spring(response: 0.25)) {
                vm.selectedNode = node
            }
        }
    }

    private func selectedNodeCard(_ node: PulseGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(node.type.color).frame(width: 6, height: 6)
                    Text(node.type.rawValue)
                        .font(CockpitFonts.mono(size: 8, weight: .bold))
                        .foregroundColor(node.type.color)
                    Text("• \(node.label)")
                        .font(CockpitFonts.mono(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                // Pin CTA
                Button(action: { vm.togglePinNode(node) }) {
                    HStack(spacing: 3) {
                        Image(systemName: node.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 8))
                        Text(node.isPinned ? "Pinned" : "Pin")
                            .font(CockpitFonts.mono(size: 8))
                    }
                    .foregroundColor(node.isPinned ? .yellow : .gray)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                // Prune CTA
                Button(action: { vm.pruneNode(node) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 8))
                        Text("Prune")
                            .font(CockpitFonts.mono(size: 8))
                    }
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button(action: { vm.selectedNode = nil }) {
                    Image(systemName: "xmark").font(.system(size: 8)).foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            if !node.summary.isEmpty {
                Text(node.summary)
                    .font(CockpitFonts.mono(size: 8))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(4)
            }

            HStack {
                Text("Salience: \(String(format: "%.2f", node.salience))")
                    .font(CockpitFonts.mono(size: 7))
                    .foregroundColor(.cyan)
                Spacer()
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.92))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(node.type.color.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 4)
    }
}
