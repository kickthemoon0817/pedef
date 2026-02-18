// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PedefSync",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        // gRPC Swift v2
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.0.0"),
        // Protobuf runtime
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        // SQLite
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "PedefSync",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "PedefSyncTests",
            dependencies: [
                "PedefSync",
            ],
            path: "Tests/PedefSyncTests"
        ),
    ]
)

