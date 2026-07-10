// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ObjCBridgeKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ObjCBridgeKit", targets: ["ObjCBridgeKit"])
    ],
    targets: [
        .target(
            name: "ObjCBridgeKit"
        ),
        .testTarget(
            name: "ObjCBridgeKitTests",
            dependencies: ["ObjCBridgeKit"]
        )
    ]
)
