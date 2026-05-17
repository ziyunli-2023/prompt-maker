// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PromptMaker",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PromptMaker", targets: ["PromptMaker"]),
    ],
    targets: [
        .executableTarget(
            name: "PromptMaker"
        ),
    ]
)
