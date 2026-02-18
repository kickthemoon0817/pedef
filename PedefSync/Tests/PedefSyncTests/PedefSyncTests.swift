import Foundation
import Testing

@testable import PedefSync

// MARK: - SQLiteStore Tests

@Suite("SQLiteStore — Paper CRUD")
struct SQLiteStorePaperTests {
    let store: SQLiteStore

    init() throws {
        store = try SQLiteStore()  // in-memory
    }

    @Test("Upsert and get paper")
    func upsertAndGet() throws {
        var paper = Pedef_PaperMetadata()
        paper.id = "p1"
        paper.title = "Test Paper"
        paper.authors = ["Alice", "Bob"]
        paper.abstract = "Abstract text"
        paper.doi = "10.1234/test"
        paper.readingProgress = 0.5
        paper.modifiedDate = .init(date: Date())

        try store.upsertPaper(paper)
        let fetched = try store.getPaper(id: "p1")
        #expect(fetched != nil)
        #expect(fetched?.title == "Test Paper")
        #expect(fetched?.authors == ["Alice", "Bob"])
        #expect(fetched?.abstract == "Abstract text")
        #expect(fetched?.doi == "10.1234/test")
        #expect(fetched?.readingProgress == 0.5)
    }

    @Test("List papers excludes deleted by default")
    func listExcludesDeleted() throws {
        var p1 = Pedef_PaperMetadata()
        p1.id = "p1"; p1.title = "Active"
        p1.modifiedDate = .init(date: Date())
        try store.upsertPaper(p1)

        var p2 = Pedef_PaperMetadata()
        p2.id = "p2"; p2.title = "ToDelete"
        p2.modifiedDate = .init(date: Date())
        try store.upsertPaper(p2)
        try store.deletePaper(id: "p2")  // soft delete

        let active = try store.listPapers(includeDeleted: false)
        #expect(active.count == 1)
        #expect(active[0].id == "p1")

        let all = try store.listPapers(includeDeleted: true)
        #expect(all.count == 2)
    }

    @Test("Delta sync returns papers modified after timestamp")
    func papersModifiedSince() throws {
        let old = "2020-01-01T00:00:00.000Z"
        var p1 = Pedef_PaperMetadata()
        p1.id = "p1"; p1.title = "Paper 1"
        p1.modifiedDate = .init(date: Date())
        try store.upsertPaper(p1)

        let results = try store.papersModifiedSince(old)
        #expect(results.count == 1)
        #expect(results[0].id == "p1")

        // Future timestamp should return nothing
        let future = "2099-01-01T00:00:00.000Z"
        let empty = try store.papersModifiedSince(future)
        #expect(empty.isEmpty)
    }

    @Test("Hard delete removes paper permanently")
    func hardDelete() throws {
        var p = Pedef_PaperMetadata()
        p.id = "p-hard"; p.title = "To Hard Delete"
        p.modifiedDate = .init(date: Date())
        try store.upsertPaper(p)

        try store.deletePaper(id: "p-hard", hard: true)
        let fetched = try store.getPaper(id: "p-hard")
        #expect(fetched == nil)
    }

    @Test("Get nonexistent paper returns nil")
    func getNonexistent() throws {
        let result = try store.getPaper(id: "nonexistent")
        #expect(result == nil)
    }

    @Test("Upsert updates existing paper")
    func upsertUpdate() throws {
        var p = Pedef_PaperMetadata()
        p.id = "p-update"; p.title = "Original"
        p.modifiedDate = .init(date: Date())
        try store.upsertPaper(p)

        p.title = "Updated"
        try store.upsertPaper(p)

        let fetched = try store.getPaper(id: "p-update")
        #expect(fetched?.title == "Updated")
    }
}

@Suite("SQLiteStore — Annotation CRUD")
struct SQLiteStoreAnnotationTests {
    let store: SQLiteStore

    init() throws {
        store = try SQLiteStore()
    }

    @Test("Upsert and get annotation")
    func upsertAndGet() throws {
        var a = Pedef_AnnotationDTO()
        a.id = "a1"
        a.paperID = "p1"
        a.type = .highlight
        a.selectedText = "Highlighted text"
        a.colorHex = "#FFFF00"
        a.pageIndex = 5
        a.modifiedDate = .init(date: Date())

        try store.upsertAnnotation(a)
        let fetched = try store.getAnnotation(id: "a1")
        #expect(fetched != nil)
        #expect(fetched?.paperID == "p1")
        #expect(fetched?.type == .highlight)
        #expect(fetched?.selectedText == "Highlighted text")
        #expect(fetched?.pageIndex == 5)
    }

    @Test("Get annotations for paper")
    func getForPaper() throws {
        var a1 = Pedef_AnnotationDTO()
        a1.id = "a1"; a1.paperID = "p1"; a1.type = .highlight
        a1.modifiedDate = .init(date: Date())
        try store.upsertAnnotation(a1)

        var a2 = Pedef_AnnotationDTO()
        a2.id = "a2"; a2.paperID = "p1"; a2.type = .textNote
        a2.modifiedDate = .init(date: Date())
        try store.upsertAnnotation(a2)

        var a3 = Pedef_AnnotationDTO()
        a3.id = "a3"; a3.paperID = "p2"; a3.type = .bookmark
        a3.modifiedDate = .init(date: Date())
        try store.upsertAnnotation(a3)

        let forP1 = try store.getAnnotationsForPaper(paperId: "p1")
        #expect(forP1.count == 2)

        let forP2 = try store.getAnnotationsForPaper(paperId: "p2")
        #expect(forP2.count == 1)
    }

    @Test("Soft delete annotation")
    func softDelete() throws {
        var a = Pedef_AnnotationDTO()
        a.id = "a-del"; a.paperID = "p1"; a.type = .textNote
        a.modifiedDate = .init(date: Date())
        try store.upsertAnnotation(a)

        try store.deleteAnnotation(id: "a-del")
        let active = try store.getAnnotationsForPaper(paperId: "p1", includeDeleted: false)
        #expect(active.isEmpty)

        let all = try store.getAnnotationsForPaper(paperId: "p1", includeDeleted: true)
        #expect(all.count == 1)
        #expect(all[0].isDeleted == true)
    }
}


@Suite("SQLiteStore — Collection CRUD")
struct SQLiteStoreCollectionTests {
    let store: SQLiteStore

    init() throws {
        store = try SQLiteStore()
    }

    @Test("Upsert and get collection")
    func upsertAndGet() throws {
        var c = Pedef_CollectionDTO()
        c.id = "c1"
        c.name = "My Collection"
        c.type = .folder
        c.paperIds = ["p1", "p2"]
        c.modifiedDate = .init(date: Date())

        try store.upsertCollection(c)
        let fetched = try store.getCollection(id: "c1")
        #expect(fetched != nil)
        #expect(fetched?.name == "My Collection")
        #expect(fetched?.type == .folder)
        #expect(fetched?.paperIds == ["p1", "p2"])
    }

    @Test("List and soft delete collections")
    func listAndDelete() throws {
        var c1 = Pedef_CollectionDTO()
        c1.id = "c1"; c1.name = "Active"
        c1.modifiedDate = .init(date: Date())
        try store.upsertCollection(c1)

        var c2 = Pedef_CollectionDTO()
        c2.id = "c2"; c2.name = "ToDelete"
        c2.modifiedDate = .init(date: Date())
        try store.upsertCollection(c2)

        try store.deleteCollection(id: "c2")
        let active = try store.listCollections(includeDeleted: false)
        #expect(active.count == 1)
        #expect(active[0].id == "c1")
    }
}

@Suite("SQLiteStore — Tag CRUD")
struct SQLiteStoreTagTests {
    let store: SQLiteStore

    init() throws {
        store = try SQLiteStore()
    }

    @Test("Upsert and get tag")
    func upsertAndGet() throws {
        var t = Pedef_TagDTO()
        t.id = "t1"
        t.name = "machine-learning"
        t.colorHex = "#FF0000"

        try store.upsertTag(t)
        let fetched = try store.getTag(id: "t1")
        #expect(fetched != nil)
        #expect(fetched?.name == "machine-learning")
        #expect(fetched?.colorHex == "#FF0000")
    }

    @Test("List and soft delete tags")
    func listAndDelete() throws {
        var t1 = Pedef_TagDTO()
        t1.id = "t1"; t1.name = "tag1"
        try store.upsertTag(t1)

        var t2 = Pedef_TagDTO()
        t2.id = "t2"; t2.name = "tag2"
        try store.upsertTag(t2)

        try store.deleteTag(id: "t2")
        let active = try store.listTags(includeDeleted: false)
        #expect(active.count == 1)
    }
}

@Suite("SQLiteStore — Purge")
struct SQLiteStorePurgeTests {
    let store: SQLiteStore

    init() throws {
        store = try SQLiteStore()
    }

    @Test("Purge removes soft-deleted entities before cutoff")
    func purge() throws {
        var p = Pedef_PaperMetadata()
        p.id = "p-purge"; p.title = "Purge Me"
        p.modifiedDate = .init(date: Date())
        try store.upsertPaper(p)
        try store.deletePaper(id: "p-purge")

        // Purge with future cutoff — should remove the soft-deleted paper
        try store.purgeDeletedBefore(date: "2099-01-01T00:00:00.000Z")

        let all = try store.listPapers(includeDeleted: true)
        #expect(all.isEmpty)
    }
}

// MARK: - FileStore Tests

@Suite("FileStore — PDF Operations")
struct FileStoreTests {
    let fileStore: FileStore
    let tempDir: String

    init() throws {
        tempDir = NSTemporaryDirectory() + "pedef-test-\(UUID().uuidString)"
        fileStore = try FileStore(directory: tempDir)
    }

    @Test("Save and read PDF")
    func saveAndRead() throws {
        let data = Data("Hello PDF".utf8)
        try fileStore.savePDF(paperID: "p1", data: data)

        let read = fileStore.readPDF(paperID: "p1")
        #expect(read == data)
    }

    @Test("PDF exists check")
    func pdfExists() throws {
        #expect(fileStore.pdfExists(paperID: "nonexistent") == false)

        let data = Data("test".utf8)
        try fileStore.savePDF(paperID: "p1", data: data)
        #expect(fileStore.pdfExists(paperID: "p1") == true)
    }

    @Test("Delete PDF")
    func deletePDF() throws {
        let data = Data("delete me".utf8)
        try fileStore.savePDF(paperID: "p1", data: data)
        #expect(fileStore.pdfExists(paperID: "p1") == true)

        let deleted = fileStore.deletePDF(paperID: "p1")
        #expect(deleted == true)
        #expect(fileStore.pdfExists(paperID: "p1") == false)
    }

    @Test("PDF file size")
    func pdfFileSize() throws {
        let data = Data(repeating: 0x42, count: 1024)
        try fileStore.savePDF(paperID: "p1", data: data)

        let size = fileStore.pdfFileSize(paperID: "p1")
        #expect(size == 1024)
    }

    @Test("SHA-256 hash")
    func sha256() {
        let data = Data("Hello".utf8)
        let hash = FileStore.sha256Hex(data)
        // Known SHA-256 for "Hello"
        #expect(hash == "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969")
    }

    @Test("Path traversal protection")
    func pathTraversal() {
        #expect(throws: FileStoreError.self) {
            try fileStore.savePDF(paperID: "../escape", data: Data())
        }
        #expect(throws: FileStoreError.self) {
            try fileStore.savePDF(paperID: "sub/dir", data: Data())
        }
        #expect(throws: FileStoreError.self) {
            try fileStore.savePDF(paperID: "", data: Data())
        }
    }
}

// MARK: - Service Tests

import GRPCCore

/// Helper to create a ServerContext for testing.
func makeTestContext(method: String = "TestMethod") -> ServerContext {
    let descriptor = ServiceDescriptor(fullyQualifiedService: "pedef.TestService")
    return ServerContext(
        descriptor: MethodDescriptor(service: descriptor, method: method),
        remotePeer: "ipv4:127.0.0.1:0",
        localPeer: "ipv4:127.0.0.1:50051",
        cancellation: .init()
    )
}

@Suite("SyncServiceImpl")
struct SyncServiceTests {
    let store: SQLiteStore
    let service: SyncServiceImpl

    init() throws {
        store = try SQLiteStore()
        service = SyncServiceImpl(store: store)
    }

    @Test("Status returns server info")
    func status() async throws {
        let ctx = makeTestContext(method: "Status")
        let resp = try await service.status(request: Pedef_StatusRequest(), context: ctx)
        #expect(resp.serverVersion == "0.1.0")
        #expect(resp.paperCount == 0)
        #expect(resp.annotationCount == 0)
    }

    @Test("Pull full sync returns all entities")
    func pullFull() async throws {
        // Insert test data
        var p = Pedef_PaperMetadata()
        p.id = "p1"; p.title = "Paper 1"
        p.modifiedDate = .init(date: Date())
        try store.upsertPaper(p)

        var a = Pedef_AnnotationDTO()
        a.id = "a1"; a.paperID = "p1"; a.type = .highlight
        a.modifiedDate = .init(date: Date())
        try store.upsertAnnotation(a)

        // Pull without since timestamp = full sync
        let req = Pedef_PullRequest()
        let ctx = makeTestContext(method: "Pull")
        let resp = try await service.pull(request: req, context: ctx)

        #expect(resp.papers.count == 1)
        #expect(resp.annotations.count == 1)
        #expect(resp.hasServerTimestamp)
    }

    @Test("Pull delta sync filters by timestamp")
    func pullDelta() async throws {
        var p = Pedef_PaperMetadata()
        p.id = "p1"; p.title = "Paper 1"
        p.modifiedDate = .init(date: Date())
        try store.upsertPaper(p)

        // Pull with future timestamp should return nothing
        var req = Pedef_PullRequest()
        req.since = .init(date: Date(timeIntervalSinceNow: 3600))
        let ctx = makeTestContext(method: "Pull")
        let resp = try await service.pull(request: req, context: ctx)

        #expect(resp.papers.isEmpty)
    }

    @Test("Push upserts entities")
    func pushUpsert() async throws {
        var p = Pedef_PaperMetadata()
        p.id = "p-push"; p.title = "Pushed Paper"
        p.modifiedDate = .init(date: Date())

        var req = Pedef_PushRequest()
        req.papers = [p]
        let ctx = makeTestContext(method: "Push")
        let resp = try await service.push(request: req, context: ctx)

        #expect(resp.success == true)
        #expect(resp.conflicts.isEmpty)

        let fetched = try store.getPaper(id: "p-push")
        #expect(fetched?.title == "Pushed Paper")
    }

    @Test("Push detects conflict when server is newer")
    func pushConflict() async throws {
        // Insert a paper with a recent timestamp
        var serverPaper = Pedef_PaperMetadata()
        serverPaper.id = "p-conflict"
        serverPaper.title = "Server Version"
        serverPaper.modifiedDate = .init(date: Date())
        try store.upsertPaper(serverPaper)

        // Push an older version
        var clientPaper = Pedef_PaperMetadata()
        clientPaper.id = "p-conflict"
        clientPaper.title = "Client Version (older)"
        clientPaper.modifiedDate = .init(date: Date(timeIntervalSinceNow: -3600))

        var req = Pedef_PushRequest()
        req.papers = [clientPaper]
        let ctx = makeTestContext(method: "Push")
        let resp = try await service.push(request: req, context: ctx)

        #expect(resp.success == false)
        #expect(resp.conflicts.count == 1)
        #expect(resp.conflicts[0].entityType == "paper")
        #expect(resp.conflicts[0].resolution == "server_wins")

        // Server paper should be unchanged
        let fetched = try store.getPaper(id: "p-conflict")
        #expect(fetched?.title == "Server Version")
    }

    @Test("Push processes deletions")
    func pushDeletions() async throws {
        var p = Pedef_PaperMetadata()
        p.id = "p-del"; p.title = "To Delete"
        p.modifiedDate = .init(date: Date())
        try store.upsertPaper(p)

        var req = Pedef_PushRequest()
        var dels = Pedef_Deletions()
        dels.paperIds = ["p-del"]
        req.deletions = dels

        let ctx = makeTestContext(method: "Push")
        let resp = try await service.push(request: req, context: ctx)
        #expect(resp.success == true)

        // Paper should be soft-deleted
        let active = try store.listPapers(includeDeleted: false)
        #expect(active.isEmpty)
    }
}

@Suite("PaperServiceImpl")
struct PaperServiceTests {
    let store: SQLiteStore
    let fileStore: FileStore
    let service: PaperServiceImpl

    init() throws {
        store = try SQLiteStore()
        let tempDir = NSTemporaryDirectory() + "pedef-paper-test-\(UUID().uuidString)"
        fileStore = try FileStore(directory: tempDir)
        service = PaperServiceImpl(store: store, fileStore: fileStore)
    }

    @Test("GetPaper returns paper")
    func getPaper() async throws {
        var p = Pedef_PaperMetadata()
        p.id = "p1"; p.title = "Test Paper"
        p.modifiedDate = .init(date: Date())
        try store.upsertPaper(p)

        var req = Pedef_GetPaperRequest()
        req.paperID = "p1"
        let ctx = makeTestContext()
        let resp = try await service.getPaper(request: req, context: ctx)
        #expect(resp.paper.title == "Test Paper")
    }

    @Test("GetPaper with empty ID throws invalidArgument")
    func getPaperEmptyID() async throws {
        let req = Pedef_GetPaperRequest()
        let ctx = makeTestContext()
        await #expect(throws: RPCError.self) {
            try await service.getPaper(request: req, context: ctx)
        }
    }

    @Test("GetPaper not found throws notFound")
    func getPaperNotFound() async throws {
        var req = Pedef_GetPaperRequest()
        req.paperID = "nonexistent"
        let ctx = makeTestContext()
        await #expect(throws: RPCError.self) {
            try await service.getPaper(request: req, context: ctx)
        }
    }

    @Test("ListPapers with offset and limit")
    func listPapers() async throws {
        for i in 0..<5 {
            var p = Pedef_PaperMetadata()
            p.id = "p\(i)"; p.title = "Paper \(i)"
            p.modifiedDate = .init(date: Date())
            try store.upsertPaper(p)
        }

        var req = Pedef_ListPapersRequest()
        req.offset = 1
        req.limit = 2
        let ctx = makeTestContext()
        let resp = try await service.listPapers(request: req, context: ctx)
        #expect(resp.papers.count == 2)
        #expect(resp.totalCount == 5)
    }

    @Test("UpsertPaper creates new paper")
    func upsertCreate() async throws {
        var p = Pedef_PaperMetadata()
        p.id = "p-new"; p.title = "New Paper"
        p.modifiedDate = .init(date: Date())

        var req = Pedef_UpsertPaperRequest()
        req.paper = p
        let ctx = makeTestContext()
        let resp = try await service.upsertPaper(request: req, context: ctx)
        #expect(resp.created == true)
        #expect(resp.paper.title == "New Paper")
    }

    @Test("DeletePaper soft deletes")
    func deletePaperSoft() async throws {
        var p = Pedef_PaperMetadata()
        p.id = "p-del"; p.title = "Delete Me"
        p.modifiedDate = .init(date: Date())
        try store.upsertPaper(p)

        var req = Pedef_DeletePaperRequest()
        req.paperID = "p-del"
        req.hardDelete = false
        let ctx = makeTestContext()
        let resp = try await service.deletePaper(request: req, context: ctx)
        #expect(resp.success == true)

        // Should still exist as soft-deleted
        let all = try store.listPapers(includeDeleted: true)
        #expect(all.count == 1)
        #expect(all[0].isDeleted == true)
    }

    @Test("DeletePaper hard deletes with PDF cleanup")
    func deletePaperHard() async throws {
        var p = Pedef_PaperMetadata()
        p.id = "p-hard"; p.title = "Hard Delete"
        p.modifiedDate = .init(date: Date())
        try store.upsertPaper(p)

        // Save a PDF too
        try fileStore.savePDF(paperID: "p-hard", data: Data("pdf data".utf8))
        #expect(fileStore.pdfExists(paperID: "p-hard") == true)

        var req = Pedef_DeletePaperRequest()
        req.paperID = "p-hard"
        req.hardDelete = true
        let ctx = makeTestContext()
        let resp = try await service.deletePaper(request: req, context: ctx)
        #expect(resp.success == true)

        // Both DB record and PDF file should be gone
        let fetched = try store.getPaper(id: "p-hard")
        #expect(fetched == nil)
        #expect(fileStore.pdfExists(paperID: "p-hard") == false)
    }
}