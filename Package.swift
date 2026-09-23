// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Elmers",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Elmers", targets: ["Elmers"])],
    targets: [
        .target(name: "ElmersCore"),
        .executableTarget(name: "Elmers", dependencies: ["ElmersCore"]),
        .executableTarget(name: "ElmersCoreChecks", dependencies: ["ElmersCore"], path: "Tests/ElmersCoreTests")
    ]
)
