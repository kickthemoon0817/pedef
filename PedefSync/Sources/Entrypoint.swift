import ArgumentParser
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf

/// PedefSync gRPC server — self-hosted on Mac Mini for cross-device sync.
///
/// Usage:
///   PedefSync --token <auth-token> [--hostname 0.0.0.0] [--port 50051] [--data-dir ./Storage]
///
/// Security: the `--token` flag is REQUIRED. Never hardcode tokens in source.
@main
struct PedefSyncServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "PedefSync gRPC server for cross-device paper synchronization."
    )

    @Option(name: .shortAndLong, help: "Hostname to listen on.")
    var hostname: String = "0.0.0.0"

    @Option(name: .shortAndLong, help: "Port to listen on.")
    var port: Int = 50051

    @Option(name: .long, help: "Bearer token for authentication. Required.")
    var token: String

    @Option(name: .long, help: "Directory for database and PDF storage.")
    var dataDir: String = "./Storage"

    func run() async throws {
        print("PedefSync server v0.1.0")
        print("  Hostname: \(hostname)")
        print("  Port:     \(port)")
        print("  Data dir: \(dataDir)")

        // Initialize storage
        let sqliteStore = try SQLiteStore(path: "\(dataDir)/pedef.db")
        let fileStore = try FileStore(directory: "\(dataDir)/pdfs")

        // Initialize services
        let syncService = SyncServiceImpl(store: sqliteStore)
        let paperService = PaperServiceImpl(store: sqliteStore, fileStore: fileStore)

        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .ipv4(host: hostname, port: port),
                transportSecurity: .plaintext
            ),
            services: [
                syncService,
                paperService,
            ],
            interceptors: [
                AuthInterceptor(expectedToken: token),
            ]
        )

        try await withThrowingDiscardingTaskGroup { group in
            group.addTask { try await server.serve() }
            if let address = try await server.listeningAddress {
                print("PedefSync gRPC server listening on \(address)")
            }
        }
    }
}

