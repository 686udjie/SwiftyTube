// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftyTube",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "SwiftyTube", type: .static, targets: ["SwiftyTube"])
    ],
    targets: [
        .target(name: "SwiftyTube", path: "SwiftyTube"),
        .testTarget(name: "SwiftyTubeTests", dependencies: ["SwiftyTube"])
    ]
)
