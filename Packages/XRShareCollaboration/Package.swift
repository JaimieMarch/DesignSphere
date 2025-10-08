// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XRShareCollaboration",
    platforms: [
        .iOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "XRShareCollaboration",
            targets: ["XRShareCollaboration"]
        )
    ],
    targets: [
        .target(
            name: "XRShareCollaboration",
            path: "Sources/XRShareCollaboration"
        )
    ]
)
