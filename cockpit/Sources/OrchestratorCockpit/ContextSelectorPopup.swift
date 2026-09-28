import SwiftUI

struct ContextSelectorPopup: View {
    @ObservedObject var harness = CodebaseHarnessService.shared
    var onSelect: (String) -> Void
    var onClose: () -> Void

    @State private var filterQuery: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header & Search
            HStack(spacing: 6) {
                Image(systemName: "at")
                    .font(CockpitFonts.regular(size: 11))
                    .foregroundColor(.cyan)

                TextField("Reference file, doc, or symbol...", text: $filterQuery)
                    .font(CockpitFonts.mono(size: 10))
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(CockpitFonts.regular(size: 9))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))

            Divider().background(Color.white.opacity(0.08))

            // File items list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if filteredDeliverables.isEmpty {
                        Text("No matching files found")
                            .font(CockpitFonts.mono(size: 9))
                            .foregroundColor(.gray)
                            .padding(10)
                    } else {
                        ForEach(filteredDeliverables) { item in
                            Button(action: {
                                onSelect("@\(item.path)")
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: iconForFile(item.path))
                                        .font(CockpitFonts.regular(size: 9))
                                        .foregroundColor(.cyan.opacity(0.8))

                                    Text(item.path)
                                        .font(CockpitFonts.mono(size: 10))
                                        .foregroundColor(.white.opacity(0.9))

                                    Spacer()

                                    Text(item.status.uppercased())
                                        .font(CockpitFonts.mono(size: 7, weight: .bold))
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 180)
        }
        .frame(width: 340)
        .background(Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.96))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 10, y: 5)
    }

    private var filteredDeliverables: [DeliverableItem] {
        if filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return harness.deliverables
        }
        return harness.deliverables.filter { $0.path.localizedCaseInsensitiveContains(filterQuery) }
    }

    private func iconForFile(_ path: String) -> String {
        if path.hasSuffix(".py") { return "curlybraces" }
        if path.hasSuffix(".swift") { return "swift" }
        if path.hasSuffix(".ts") || path.hasSuffix(".js") { return "doc.plaintext" }
        if path.hasSuffix(".md") { return "text.book.closed" }
        if path.hasSuffix(".json") { return "curlybraces" }
        return "doc.text"
    }
}
