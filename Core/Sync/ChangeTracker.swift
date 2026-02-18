import Foundation
import SwiftData

// MARK: - Change Snapshot

/// A snapshot of all local entities modified since the last sync.
struct ChangeSnapshot: Sendable {
    let papers: [Paper]
    let annotations: [Annotation]
    let collections: [Collection]
    let tags: [Tag]

    /// IDs of entities deleted locally since last sync.
    let deletedPaperIDs: [UUID]
    let deletedAnnotationIDs: [UUID]
    let deletedCollectionIDs: [UUID]
    let deletedTagIDs: [UUID]

    var isEmpty: Bool {
        papers.isEmpty && annotations.isEmpty && collections.isEmpty && tags.isEmpty
            && deletedPaperIDs.isEmpty && deletedAnnotationIDs.isEmpty
            && deletedCollectionIDs.isEmpty && deletedTagIDs.isEmpty
    }
}

// MARK: - Deletion Record

/// Tracks entity deletions so they can be propagated to the server.
@Model
final class DeletionRecord {
    @Attribute(.unique) var id: UUID
    var entityType: String   // "paper", "annotation", "collection", "tag"
    var entityID: UUID
    var deletedDate: Date

    init(entityType: String, entityID: UUID) {
        self.id = UUID()
        self.entityType = entityType
        self.entityID = entityID
        self.deletedDate = Date()
    }
}

// MARK: - ChangeTracker

/// Detects local changes since last sync by comparing `modifiedDate` against the stored sync timestamp.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
final class ChangeTracker: Sendable {

    private static let lastSyncKey = "pedef_lastSyncTimestamp"

    // MARK: - Last Sync Timestamp

    /// The timestamp of the last successful sync, stored in UserDefaults.
    var lastSyncTimestamp: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date }
    }

    func setLastSyncTimestamp(_ date: Date) {
        UserDefaults.standard.set(date, forKey: Self.lastSyncKey)
    }

    func clearLastSyncTimestamp() {
        UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
    }

    // MARK: - Gather Changes

    /// Queries SwiftData for all entities modified after `lastSyncTimestamp`.
    @MainActor
    func gatherChanges(modelContext: ModelContext) throws -> ChangeSnapshot {
        let since = lastSyncTimestamp ?? Date.distantPast

        // Papers modified since last sync
        let paperPredicate = #Predicate<Paper> { $0.modifiedDate > since }
        let paperDescriptor = FetchDescriptor<Paper>(predicate: paperPredicate)
        let papers = try modelContext.fetch(paperDescriptor)

        // Annotations modified since last sync
        let annotationPredicate = #Predicate<Annotation> { $0.modifiedDate > since }
        let annotationDescriptor = FetchDescriptor<Annotation>(predicate: annotationPredicate)
        let annotations = try modelContext.fetch(annotationDescriptor)

        // Collections modified since last sync
        let collectionPredicate = #Predicate<Collection> { $0.modifiedDate > since }
        let collectionDescriptor = FetchDescriptor<Collection>(predicate: collectionPredicate)
        let collections = try modelContext.fetch(collectionDescriptor)

        // Tags — no modifiedDate, so on first sync send all; after that, use createdDate
        let tagPredicate = #Predicate<Tag> { $0.createdDate > since }
        let tagDescriptor = FetchDescriptor<Tag>(predicate: tagPredicate)
        let tags = try modelContext.fetch(tagDescriptor)

        // Deletion records
        let deletionPredicate = #Predicate<DeletionRecord> { $0.deletedDate > since }
        let deletionDescriptor = FetchDescriptor<DeletionRecord>(predicate: deletionPredicate)
        let deletions = try modelContext.fetch(deletionDescriptor)

        let deletedPaperIDs = deletions.filter { $0.entityType == "paper" }.map(\.entityID)
        let deletedAnnotationIDs = deletions.filter { $0.entityType == "annotation" }.map(\.entityID)
        let deletedCollectionIDs = deletions.filter { $0.entityType == "collection" }.map(\.entityID)
        let deletedTagIDs = deletions.filter { $0.entityType == "tag" }.map(\.entityID)

        return ChangeSnapshot(
            papers: papers,
            annotations: annotations,
            collections: collections,
            tags: tags,
            deletedPaperIDs: deletedPaperIDs,
            deletedAnnotationIDs: deletedAnnotationIDs,
            deletedCollectionIDs: deletedCollectionIDs,
            deletedTagIDs: deletedTagIDs
        )
    }

    // MARK: - Record Deletion

    /// Records a deletion so it can be pushed on next sync.
    @MainActor
    func recordDeletion(entityType: String, entityID: UUID, modelContext: ModelContext) {
        let record = DeletionRecord(entityType: entityType, entityID: entityID)
        modelContext.insert(record)
    }

    // MARK: - Cleanup

    /// Removes deletion records older than the given date (after successful sync).
    @MainActor
    func pruneOldDeletions(before date: Date, modelContext: ModelContext) throws {
        let predicate = #Predicate<DeletionRecord> { $0.deletedDate < date }
        let descriptor = FetchDescriptor<DeletionRecord>(predicate: predicate)
        let old = try modelContext.fetch(descriptor)
        for record in old {
            modelContext.delete(record)
        }
    }
}

