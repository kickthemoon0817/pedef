import Foundation
import GRPCCore
import SwiftProtobuf

/// Implementation of the gRPC SyncService for delta synchronization.
///
/// - `pull`: Returns entities modified since a given timestamp (or all for full sync).
/// - `push`: Upserts entities using last-write-wins conflict resolution.
/// - `status`: Returns server health and entity counts.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct SyncServiceImpl: Pedef_SyncService.SimpleServiceProtocol {
    let store: SQLiteStore
    private let startTime: Date

    init(store: SQLiteStore) {
        self.store = store
        self.startTime = Date()
    }

    // MARK: - Pull

    func pull(
        request: Pedef_PullRequest,
        context: ServerContext
    ) async throws -> Pedef_PullResponse {
        var response = Pedef_PullResponse()

        if request.hasSince {
            let since = SQLiteStore.timestampToString(request.since)
            response.papers = try store.papersModifiedSince(since)
            response.annotations = try store.annotationsModifiedSince(since)
            response.collections = try store.collectionsModifiedSince(since)
            response.tags = try store.tagsModifiedSince(since)
        } else {
            // Full sync — return everything including soft-deleted
            response.papers = try store.listPapers(includeDeleted: true)
            // No listAnnotations; use epoch to get all via modifiedSince
            response.annotations = try store.annotationsModifiedSince("1970-01-01T00:00:00.000Z")
            response.collections = try store.listCollections(includeDeleted: true)
            response.tags = try store.listTags(includeDeleted: true)
        }

        // Populate deletions for quick client reference
        var deletions = Pedef_Deletions()
        deletions.paperIds = response.papers.filter(\.isDeleted).map(\.id)
        deletions.annotationIds = response.annotations.filter(\.isDeleted).map(\.id)
        deletions.collectionIds = response.collections.filter(\.isDeleted).map(\.id)
        deletions.tagIds = response.tags.filter(\.isDeleted).map(\.id)
        response.deletions = deletions

        response.serverTimestamp = Google_Protobuf_Timestamp(date: Date())
        return response
    }

    // MARK: - Push

    func push(
        request: Pedef_PushRequest,
        context: ServerContext
    ) async throws -> Pedef_PushResponse {
        var conflicts: [Pedef_ConflictDetail] = []
        var accepted = 0

        // Upsert papers (last-write-wins)
        for paper in request.papers {
            if let existing = try store.getPaper(id: paper.id),
               existing.hasModifiedDate, paper.hasModifiedDate,
               existing.modifiedDate.seconds > paper.modifiedDate.seconds
            {
                var conflict = Pedef_ConflictDetail()
                conflict.entityType = "paper"
                conflict.entityID = paper.id
                conflict.resolution = "server_wins"
                conflict.reason = "Server has newer version"
                conflicts.append(conflict)
            } else {
                try store.upsertPaper(paper)
                accepted += 1
            }
        }

        // Upsert annotations
        for annotation in request.annotations {
            if let existing = try store.getAnnotation(id: annotation.id),
               existing.hasModifiedDate, annotation.hasModifiedDate,
               existing.modifiedDate.seconds > annotation.modifiedDate.seconds
            {
                var conflict = Pedef_ConflictDetail()
                conflict.entityType = "annotation"
                conflict.entityID = annotation.id
                conflict.resolution = "server_wins"
                conflict.reason = "Server has newer version"
                conflicts.append(conflict)
            } else {
                try store.upsertAnnotation(annotation)
                accepted += 1
            }
        }

        // Upsert collections
        for collection in request.collections {
            if let existing = try store.getCollection(id: collection.id),
               existing.hasModifiedDate, collection.hasModifiedDate,
               existing.modifiedDate.seconds > collection.modifiedDate.seconds
            {
                var conflict = Pedef_ConflictDetail()
                conflict.entityType = "collection"
                conflict.entityID = collection.id
                conflict.resolution = "server_wins"
                conflict.reason = "Server has newer version"
                conflicts.append(conflict)
            } else {
                try store.upsertCollection(collection)
                accepted += 1
            }
        }

        // Upsert tags (no modified_date conflict check — tags are simpler)
        for tag in request.tags {
            try store.upsertTag(tag)
            accepted += 1
        }

        // Process deletions
        if request.hasDeletions {
            let d = request.deletions
            for id in d.paperIds { try store.deletePaper(id: id) }
            for id in d.annotationIds { try store.deleteAnnotation(id: id) }
            for id in d.collectionIds { try store.deleteCollection(id: id) }
            for id in d.tagIds { try store.deleteTag(id: id) }
        }

        var response = Pedef_PushResponse()
        response.success = conflicts.isEmpty
        response.conflicts = conflicts
        response.serverTimestamp = Google_Protobuf_Timestamp(date: Date())
        return response
    }

    // MARK: - Status

    func status(
        request: Pedef_StatusRequest,
        context: ServerContext
    ) async throws -> Pedef_StatusResponse {
        var response = Pedef_StatusResponse()
        response.serverVersion = "0.1.0"
        response.paperCount = Int64(try store.listPapers(includeDeleted: false).count)
        response.annotationCount = Int64(try store.annotationsModifiedSince("1970-01-01T00:00:00.000Z").count)
        response.collectionCount = Int64(try store.listCollections(includeDeleted: false).count)
        response.tagCount = Int64(try store.listTags(includeDeleted: false).count)
        response.lastModified = Google_Protobuf_Timestamp(date: Date())
        response.storageBytesUsed = 0  // TODO: compute from FileStore in future
        return response
    }
}

