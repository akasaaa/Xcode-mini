// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XcodeMini",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "XcodeMini",
            path: "Sources/XcodeMini",
            linkerSettings: [
                .linkedFramework("ScriptingBridge")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
