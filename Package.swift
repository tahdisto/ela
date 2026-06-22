// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ela",
    platforms: [.macOS(.v15)],   // built and run on macOS 26+
    targets: [
        .target(
            name: "GreekAccent",
            path: "engine/Sources/GreekAccent"
        ),
        .executableTarget(
            name: "accent",                       // CLI + accuracy harness
            dependencies: ["GreekAccent"],
            path: "engine/Sources/accent"
        ),
        .executableTarget(
            name: "ela",                          // menu-bar app
            dependencies: ["GreekAccent"],
            path: "app/Sources/ela"
        ),
    ]
)
