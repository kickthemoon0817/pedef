import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import CryptoKit

// MARK: - SyncNetworkError

/// Errors specific to the sync network layer.
enum SyncNetworkError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case serverError(String)
    case hashMismatch(expected: String, actual: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to sync server"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .serverError(let msg):
            return "Server error: \(msg)"
        case .hashMismatch(let expected, let actual):
            return "PDF hash mismatch: expected \(expected), got \(actual)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - SyncServerConfig

/// Configuration for connecting to the gRPC sync server.
struct SyncServerConfig: Sendable, Codable, Equatable {
    var host: String = "localhost"
    var port: Int = 50051
    var authToken: String = ""
    var useTLS: Bool = false
}

// MARK: - ServerStatus

/// Parsed server status response.
struct ServerStatus: Sendable {
    let serverVersion: String
    let paperCount: Int64
    let annotationCount: Int64
    let collectionCount: Int64
    let tagCount: Int64
    let storageBytesUsed: Int64
    let lastModified: Date?
}

// MARK: - SyncNetworkClient

/// High-level async client wrapping generated gRPC stubs for SyncService and PaperService.
///
/// Usage:
/// ```
/// let client = SyncNetworkClient(config: config)
/// try await client.connect()
/// let response = try await client.pull(since: lastSync)
/// client.disconnect()
/// ```
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class SyncNetworkClient: Sendable {

    private let config: SyncServerConfig
    private let grpcClient: GRPCClient<HTTP2ClientTransport.Posix>
    private let runTask: Task<Void, any Error>

    // MARK: - Lifecycle

    init(config: SyncServerConfig) throws {
        self.config = config

        let transport = try HTTP2ClientTransport.Posix(
            target: .dns(host: config.host, port: config.port),
            transportSecurity: config.useTLS ? .tls : .plaintext
        )
        self.grpcClient = GRPCClient(transport: transport)

        // gRPC client requires a background run loop for connection management
        let client = self.grpcClient
        self.runTask = Task {
            try await client.runConnections()
        }
    }

    func close() {
        self.grpcClient.beginGracefulShutdown()
        self.runTask.cancel()
    }

    // MARK: - Auth Metadata

    private var authMetadata: Metadata {
        if config.authToken.isEmpty {
            return [:]
        }
        return ["authorization": "Bearer \(config.authToken)"]
    }

    // MARK: - SyncService RPCs

    /// Pull changes from the server since the given timestamp.
    func pull(since: Date? = nil) async throws -> Pedef_PullResponse {
        let syncClient = Pedef_SyncService.Client(wrapping: grpcClient)
        var request = Pedef_PullRequest()
        if let since {
            request.since = DTOMapper.toTimestamp(since)
        }
        return try await syncClient.pull(request, metadata: authMetadata)
    }

    /// Push local changes to the server.
    func push(_ request: Pedef_PushRequest) async throws -> Pedef_PushResponse {
        let syncClient = Pedef_SyncService.Client(wrapping: grpcClient)
        return try await syncClient.push(request, metadata: authMetadata)
    }

    /// Get server status information.
    func status() async throws -> ServerStatus {
        let syncClient = Pedef_SyncService.Client(wrapping: grpcClient)
        let response = try await syncClient.status(Pedef_StatusRequest(), metadata: authMetadata)
        return ServerStatus(
            serverVersion: response.serverVersion,
            paperCount: response.paperCount,
            annotationCount: response.annotationCount,
            collectionCount: response.collectionCount,
            tagCount: response.tagCount,
            storageBytesUsed: response.storageBytesUsed,
            lastModified: response.hasLastModified ? DTOMapper.fromTimestamp(response.lastModified) : nil
        )
    }

    // MARK: - PaperService RPCs

    /// Upload a PDF to the server using client streaming (64KB chunks).
    func uploadPDF(paperID: UUID, data: Data) async throws -> Pedef_UploadPDFResponse {
        let paperClient = Pedef_PaperService.Client(wrapping: grpcClient)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let chunkSize = 64 * 1024

        return try await paperClient.uploadPDF(
            metadata: authMetadata,
            requestProducer: { writer in
            // First message: metadata
            var metaMsg = Pedef_UploadPDFRequest()
            var uploadMeta = Pedef_UploadPDFMetadata()
            uploadMeta.paperID = paperID.uuidString
            uploadMeta.totalSize = Int64(data.count)
            uploadMeta.sha256Hash = hash
            metaMsg.metadata = uploadMeta
            try await writer.write(metaMsg)

            // Subsequent messages: data chunks
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                var chunkMsg = Pedef_UploadPDFRequest()
                chunkMsg.chunkData = data[offset..<end]
                try await writer.write(chunkMsg)
                offset = end
            }
            }
        )
    }

    /// Download a PDF from the server using server streaming (64KB chunks).
    func downloadPDF(paperID: UUID) async throws -> Data {
        let paperClient = Pedef_PaperService.Client(wrapping: grpcClient)
        var request = Pedef_DownloadPDFRequest()
        request.paperID = paperID.uuidString

        return try await paperClient.downloadPDF(request, metadata: authMetadata, onResponse: { response in
            var pdfData = Data()
            var expectedHash = ""

            for try await part in response.messages {
                switch part.payload {
                case .metadata(let meta):
                    expectedHash = meta.sha256Hash
                    pdfData.reserveCapacity(Int(meta.totalSize))
                case .chunkData(let chunk):
                    pdfData.append(chunk)
                case nil:
                    break
                }
            }

            // Verify integrity
            if !expectedHash.isEmpty {
                let actualHash = SHA256.hash(data: pdfData).map { String(format: "%02x", $0) }.joined()
                guard actualHash == expectedHash else {
                    throw SyncNetworkError.hashMismatch(expected: expectedHash, actual: actualHash)
                }
            }

            return pdfData
        })
    }

    /// Upsert paper metadata on the server.
    func upsertPaper(_ metadata: Pedef_PaperMetadata) async throws -> Pedef_UpsertPaperResponse {
        let paperClient = Pedef_PaperService.Client(wrapping: grpcClient)
        var request = Pedef_UpsertPaperRequest()
        request.paper = metadata
        return try await paperClient.upsertPaper(request, metadata: authMetadata)
    }

    /// Get paper metadata from the server.
    func getPaper(id: UUID) async throws -> Pedef_PaperMetadata {
        let paperClient = Pedef_PaperService.Client(wrapping: grpcClient)
        var request = Pedef_GetPaperRequest()
        request.paperID = id.uuidString
        let response = try await paperClient.getPaper(request, metadata: authMetadata)
        return response.paper
    }

    /// List papers from the server with pagination.
    func listPapers(offset: Int = 0, limit: Int = 100) async throws -> (papers: [Pedef_PaperMetadata], totalCount: Int) {
        let paperClient = Pedef_PaperService.Client(wrapping: grpcClient)
        var request = Pedef_ListPapersRequest()
        request.offset = Int32(offset)
        request.limit = Int32(limit)
        let response = try await paperClient.listPapers(request, metadata: authMetadata)
        return (papers: response.papers, totalCount: Int(response.totalCount))
    }

    /// Delete a paper on the server.
    func deletePaper(id: UUID) async throws -> Pedef_DeletePaperResponse {
        let paperClient = Pedef_PaperService.Client(wrapping: grpcClient)
        var request = Pedef_DeletePaperRequest()
        request.paperID = id.uuidString
        return try await paperClient.deletePaper(request, metadata: authMetadata)
    }
}
