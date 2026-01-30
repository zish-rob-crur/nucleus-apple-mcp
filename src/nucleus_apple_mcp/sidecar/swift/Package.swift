// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NucleusAppleSidecar",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "nucleus-apple-sidecar",
            targets: ["NucleusAppleSidecar"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.7.0")
    ],
    targets: [
        .executableTarget(
            name: "NucleusAppleSidecar",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Markdown", package: "swift-markdown")
            ]
        )
    ]
)
