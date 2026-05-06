// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StreamDown",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        // Umbrella products
        .library(name: "StreamDown",        targets: ["StreamDownUI"]),
        .library(name: "StreamDownNative",  targets: ["StreamDownUIKit"]),
        // Individual targets
        .library(name: "StreamDownCore",    targets: ["StreamDownCore"]),
        .library(name: "StreamDownUI",      targets: ["StreamDownUI"]),
        .library(name: "StreamDownUIKit",   targets: ["StreamDownUIKit"]),
        .library(name: "StreamDownCode",    targets: ["StreamDownCode"]),
        .library(name: "StreamDownMath",    targets: ["StreamDownMath"]),
        .library(name: "StreamDownDiagram", targets: ["StreamDownDiagram"]),
        .library(name: "StreamDownCJK",     targets: ["StreamDownCJK"]),
    ],
    targets: [
        .target(
            name: "StreamDownCore",
            dependencies: [],
            path: "Sources/StreamDownCore"
        ),
        .target(
            name: "StreamDownUI",
            dependencies: ["StreamDownCore"],
            path: "Sources/StreamDownUI"
        ),
        .target(
            name: "StreamDownUIKit",
            dependencies: ["StreamDownCore"],
            path: "Sources/StreamDownUIKit"
        ),
        .target(
            name: "StreamDownCode",
            dependencies: ["StreamDownCore", "StreamDownUI", "StreamDownUIKit"],
            path: "Sources/StreamDownCode"
            // resources: [.process("Resources/grammars")] — restore when grammar files are added
        ),
        .target(
            name: "StreamDownMath",
            dependencies: ["StreamDownCore", "StreamDownUI", "StreamDownUIKit"],
            path: "Sources/StreamDownMath"
            // resources: [.process("Resources/katex")] — restore when KaTeX assets are bundled
        ),
        .target(
            name: "StreamDownDiagram",
            dependencies: ["StreamDownCore", "StreamDownUI", "StreamDownUIKit"],
            path: "Sources/StreamDownDiagram"
            // resources: [.process("Resources/mermaid")] — restore when Mermaid assets are bundled
        ),
        .target(
            name: "StreamDownCJK",
            dependencies: ["StreamDownCore"],
            path: "Sources/StreamDownCJK"
        ),
        .target(
            name: "StreamDownTestSupport",
            dependencies: ["StreamDownCore"],
            path: "Sources/StreamDownTestSupport"
        ),
        .testTarget(
            name: "StreamDownCoreTests",
            dependencies: ["StreamDownCore", "StreamDownTestSupport"],
            path: "Tests/StreamDownCoreTests"
        ),
        .testTarget(
            name: "StreamDownUITests",
            dependencies: ["StreamDownUI", "StreamDownUIKit"],
            path: "Tests/StreamDownUITests"
        ),
        .testTarget(
            name: "StreamDownSnapshotTests",
            dependencies: ["StreamDownUI", "StreamDownUIKit"],
            path: "Tests/StreamDownSnapshotTests"
        ),
    ]
)
