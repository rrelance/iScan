// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ScanKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ScanKit", targets: ["ScanKit"]),
    ],
    targets: [
        .target(name: "ScanKit"),
        .testTarget(name: "ScanKitTests", dependencies: ["ScanKit"]),
    ]
)
