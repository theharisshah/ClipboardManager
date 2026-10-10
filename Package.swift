// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ClipboardManager",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "ClipboardManager", targets: ["ClipboardManager"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            dependencies: [],
            path: "ClipboardManager",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "ClipboardManagerTests",
            dependencies: ["ClipboardManager"],
            path: "Tests"
        )
    ]
)
