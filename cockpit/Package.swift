// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OrchestratorCockpit",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OrchestratorCockpit",
            path: "Sources/OrchestratorCockpit"
        )
    ]
)
