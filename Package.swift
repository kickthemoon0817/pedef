// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pedef",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Pedef", targets: ["Pedef"])
    ],
    dependencies: [
        // SwiftAnthropic - Claude API client for AI agent features
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic.git", from: "2.2.0"),

        // Markdown rendering for notes
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1"),

        // Keychain access for API key storage
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "Pedef",
            dependencies: [
                .product(name: "SwiftAnthropic", package: "SwiftAnthropic"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                "KeychainAccess",
            ],
            path: ".",
            exclude: ["Tests", "Claude.md", ".gitignore", ".build", "Resources", "scripts"],
            sources: ["App", "Core", "Features", "Shared"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "PedefTests",
            dependencies: ["Pedef"],
            path: "Tests"
        )
    ]
)
