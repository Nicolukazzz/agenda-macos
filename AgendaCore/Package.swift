// swift-tools-version: 6.2
import PackageDescription

// Pure logic for Agenda (no UI, no SwiftData) so it can be unit tested with `swift test`.
let package = Package(
    name: "AgendaCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AgendaCore", targets: ["AgendaCore"]),
    ],
    targets: [
        .target(name: "AgendaCore"),
        .testTarget(name: "AgendaCoreTests", dependencies: ["AgendaCore"]),
    ]
)
