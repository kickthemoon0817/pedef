// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pedef",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
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

        // gRPC sync client dependencies
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .executableTarget(
            name: "Pedef",
            dependencies: [
                .product(name: "SwiftAnthropic", package: "SwiftAnthropic"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                "KeychainAccess",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
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
