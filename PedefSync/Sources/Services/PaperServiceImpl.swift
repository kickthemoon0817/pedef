import Foundation
import GRPCCore

/// Implementation of the gRPC PaperService for paper CRUD and PDF binary transfer.
///
/// Unary RPCs delegate to SQLiteStore. PDF upload/download use streaming
/// with 64KB chunks and SHA-256 integrity verification.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct PaperServiceImpl: Pedef_PaperService.SimpleServiceProtocol {
    let store: SQLiteStore
    let fileStore: FileStore

    /// 64 KB chunk size for PDF streaming
    private static let chunkSize = 64 * 1024

    init(store: SQLiteStore, fileStore: FileStore) {
        self.store = store
        self.fileStore = fileStore
    }

    // MARK: - GetPaper

    func getPaper(
        request: Pedef_GetPaperRequest,
        context: ServerContext
    ) async throws -> Pedef_GetPaperResponse {
        guard !request.paperID.isEmpty else {
            throw RPCError(code: .invalidArgument, message: "paper_id is required")
        }
        guard let paper = try store.getPaper(id: request.paperID) else {
            throw RPCError(code: .notFound, message: "Paper not found: \(request.paperID)")
        }
        var response = Pedef_GetPaperResponse()
        response.paper = paper
        return response
    }

    // MARK: - ListPapers

    func listPapers(
        request: Pedef_ListPapersRequest,
        context: ServerContext
    ) async throws -> Pedef_ListPapersResponse {
        let allPapers = try store.listPapers(includeDeleted: false)
        var papers = allPapers

        // Apply offset/limit if provided
        if request.offset > 0 {
            papers = Array(papers.dropFirst(Int(request.offset)))
        }
        if request.limit > 0 {
            papers = Array(papers.prefix(Int(request.limit)))
        }

        var response = Pedef_ListPapersResponse()
        response.papers = papers
        response.totalCount = Int32(allPapers.count)
        return response
    }

    // MARK: - UpsertPaper

    func upsertPaper(
        request: Pedef_UpsertPaperRequest,
        context: ServerContext
    ) async throws -> Pedef_UpsertPaperResponse {
        guard request.hasPaper else {
            throw RPCError(code: .invalidArgument, message: "paper is required")
        }
        let paper = request.paper
        guard !paper.id.isEmpty else {
            throw RPCError(code: .invalidArgument, message: "paper.id is required")
        }

        let existing = try store.getPaper(id: paper.id)
        try store.upsertPaper(paper)

        var response = Pedef_UpsertPaperResponse()
        response.created = (existing == nil)
        response.paper = paper
        return response
    }

    // MARK: - DeletePaper

    func deletePaper(
        request: Pedef_DeletePaperRequest,
        context: ServerContext
    ) async throws -> Pedef_DeletePaperResponse {
        guard !request.paperID.isEmpty else {
            throw RPCError(code: .invalidArgument, message: "paper_id is required")
        }

        try store.deletePaper(id: request.paperID, hard: request.hardDelete)

        // If hard delete, also remove the PDF file
        if request.hardDelete {
            fileStore.deletePDF(paperID: request.paperID)
        }

        var response = Pedef_DeletePaperResponse()
        response.success = true
        return response
    }

    // MARK: - UploadPDF (Client Streaming)

    func uploadPDF(
        request: RPCAsyncSequence<Pedef_UploadPDFRequest, any Error>,
        context: ServerContext
    ) async throws -> Pedef_UploadPDFResponse {
        var paperID: String?
        var expectedHash: String?
        var accumulatedData = Data()

        for try await message in request {
            switch message.payload {
            case .metadata(let meta):
                guard !meta.paperID.isEmpty else {
                    throw RPCError(code: .invalidArgument, message: "paper_id is required in metadata")
                }
                paperID = meta.paperID
                expectedHash = meta.sha256Hash.isEmpty ? nil : meta.sha256Hash
                if meta.totalSize > 0 {
                    accumulatedData.reserveCapacity(Int(meta.totalSize))
                }
            case .chunkData(let chunk):
                guard paperID != nil else {
                    throw RPCError(
                        code: .invalidArgument,
                        message: "First message must contain metadata"
                    )
                }
                accumulatedData.append(chunk)
            case nil:
                throw RPCError(code: .invalidArgument, message: "Empty upload message")
            }
        }

        guard let id = paperID else {
            throw RPCError(code: .invalidArgument, message: "No metadata received in upload stream")
        }

        // Verify integrity if hash was provided
        let computedHash = FileStore.sha256Hex(accumulatedData)
        if let expected = expectedHash, computedHash != expected {
            throw RPCError(
                code: .dataLoss,
                message: "SHA-256 mismatch: expected \(expected), got \(computedHash)"
            )
        }

        // Save to filesystem
        try fileStore.savePDF(paperID: id, data: accumulatedData)

        var response = Pedef_UploadPDFResponse()
        response.success = true
        response.bytesReceived = Int64(accumulatedData.count)
        response.sha256Hash = computedHash
        return response
    }

    // MARK: - DownloadPDF (Server Streaming)

    func downloadPDF(
        request: Pedef_DownloadPDFRequest,
        response: RPCWriter<Pedef_DownloadPDFResponse>,
        context: ServerContext
    ) async throws {
        guard !request.paperID.isEmpty else {
            throw RPCError(code: .invalidArgument, message: "paper_id is required")
        }

        guard let pdfData = fileStore.readPDF(paperID: request.paperID) else {
            throw RPCError(code: .notFound, message: "PDF not found for paper: \(request.paperID)")
        }

        // Send metadata first
        let hash = FileStore.sha256Hex(pdfData)
        var metaMsg = Pedef_DownloadPDFResponse()
        var meta = Pedef_DownloadPDFMetadata()
        meta.paperID = request.paperID
        meta.totalSize = Int64(pdfData.count)
        meta.sha256Hash = hash
        metaMsg.metadata = meta
        try await response.write(metaMsg)

        // Stream PDF in 64KB chunks
        var offset = 0
        while offset < pdfData.count {
            let end = min(offset + Self.chunkSize, pdfData.count)
            let chunk = pdfData[offset..<end]

            var chunkMsg = Pedef_DownloadPDFResponse()
            chunkMsg.chunkData = Data(chunk)
            try await response.write(chunkMsg)

            offset = end
        }
    }
}
