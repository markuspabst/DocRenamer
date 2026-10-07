// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DocRenamer",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DocRenamerCore"),
        .executableTarget(name: "docrenamer", dependencies: ["DocRenamerCore"]),
        .testTarget(name: "DocRenamerCoreTests", dependencies: ["DocRenamerCore"]),
    ]
)
