// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TikiTimeCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "TikiTimeCore", targets: ["TikiTimeCore"]),
    ],
    targets: [
        .target(name: "TikiTimeCore"),
        .testTarget(name: "TikiTimeCoreTests", dependencies: ["TikiTimeCore"]),
    ]
)
