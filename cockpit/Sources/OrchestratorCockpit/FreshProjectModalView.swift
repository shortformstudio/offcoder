import SwiftUI

struct FreshProjectModalView: View {
    @ObservedObject var vm: OrchestratorViewModel
    @Environment(\.dismiss) var dismiss
    @State private var projectName = ""
    @State private var masterPlanText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Project")
                .font(CockpitFonts.mono(size: 14, weight: .bold))
                .foregroundColor(.white)

            TextField("Project Name (e.g. mesh-router)", text: $projectName)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)

            Text("Specification / Goals:")
                .font(CockpitFonts.mono(size: 10))
                .foregroundColor(.gray)

            TextEditor(text: $masterPlanText)
                .font(CockpitFonts.mono(size: 11))
                .padding(4)
                .background(Color.black.opacity(0.3))
                .cornerRadius(6)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Spacer()
                Button("Begin") {
                    vm.createFreshProject(name: projectName, masterPlan: masterPlanText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 380)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    }
}
