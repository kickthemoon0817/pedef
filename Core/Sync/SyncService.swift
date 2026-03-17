import Foundation
import SwiftData

// MARK: - Sync State

/// Observable state of the sync engine, suitable for driving UI.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
@MainActor
@Observable
final class SyncState {
    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var lastError: String?
    var pendingChangeCount: Int = 0
    var progress: String = ""
}

// MARK: - Sync Error

enum SyncError: LocalizedError {
    case notConfigured
    case alreadySyncing
    case pullFailed(underlying: any Error)
    case pushFailed(underlying: any Error)
    case mergeFailed(underlying: any Error)
    case pdfTransferFailed(paperID: UUID, underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Sync server is not configured."
        case .alreadySyncing: return "A sync operation is already in progress."
        case .pullFailed(let e): return "Pull failed: \(e.localizedDescription)"
        case .pushFailed(let e): return "Push failed: \(e.localizedDescription)"
        case .mergeFailed(let e): return "Merge failed: \(e.localizedDescription)"
        case .pdfTransferFailed(let id, let e):
            return "PDF transfer failed for \(id): \(e.localizedDescription)"
        }
    }
}

// MARK: - SyncService

/// High-level sync orchestrator: pull → merge → push.
///
/// Manages the lifecycle of `SyncNetworkClient`, delegates change detection
/// to `ChangeTracker`, and uses `DTOMapper` for model conversion.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
@MainActor
final class SyncService {

    let state = SyncState()
    let changeTracker = ChangeTracker()

    private var networkClient: SyncNetworkClient?
    private var autoSyncTask: Task<Void, Never>?

    // MARK: - Configuration

    func configure(with config: SyncServerConfig) throws {
        networkClient?.close()
        networkClient = try SyncNetworkClient(config: config)
        state.lastError = nil
    }

    func disconnect() {
        stopAutoSync()
        networkClient?.close()
        networkClient = nil
    }

    // MARK: - Auto-Sync

    func startAutoSync(interval: TimeInterval = 300, modelContext: ModelContext) {
        stopAutoSync()
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                do {
                    try await self?.sync(modelContext: modelContext)
                } catch {
                    // Auto-sync errors are recorded in state, not thrown
                }
            }
        }
    }

    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    // MARK: - Full Sync (Pull → Merge → Push)

    func sync(modelContext: ModelContext) async throws {
        guard let client = networkClient else { throw SyncError.notConfigured }
        guard !state.isSyncing else { throw SyncError.alreadySyncing }

        state.isSyncing = true
        state.lastError = nil
        state.progress = "Starting sync..."
        defer { state.isSyncing = false }

        do {
            // 1. Pull remote changes
            state.progress = "Pulling remote changes..."
            let pullResponse = try await client.pull(since: changeTracker.lastSyncTimestamp)

            // 2. Merge remote into local
            state.progress = "Merging changes..."
            try mergeRemoteChanges(pullResponse, modelContext: modelContext)

            // 3. Gather local changes and push
            state.progress = "Pushing local changes..."
            let snapshot = try changeTracker.gatherChanges(modelContext: modelContext)

            if !snapshot.isEmpty {
                let pushRequest = buildPushRequest(from: snapshot)
                let pushResponse = try await client.push(pushRequest)

                if !pushResponse.success {
                    let conflictSummary = pushResponse.conflicts
                        .map { "\($0.entityType)/\($0.entityID): \($0.resolution)" }
                        .joined(separator: "; ")
                    state.lastError = "Push conflicts: \(conflictSummary)"
                }

                // 4. Upload PDFs for new/changed papers
                state.progress = "Syncing PDFs..."
                for paper in snapshot.papers where !paper.pdfData.isEmpty {
                    do {
                        _ = try await client.uploadPDF(paperID: paper.id, data: paper.pdfData)
                    } catch {
                        state.lastError = "PDF upload failed for \(paper.title): \(error.localizedDescription)"
                    }
                }
            }

            // 5. Update sync timestamp and save
            let serverTime = DTOMapper.fromTimestamp(pullResponse.serverTimestamp)
            changeTracker.setLastSyncTimestamp(serverTime)
            state.lastSyncDate = serverTime
            state.progress = "Sync complete"

            try changeTracker.pruneOldDeletions(before: serverTime, modelContext: modelContext)
            try modelContext.save()

        } catch let error as SyncError {
            state.lastError = error.localizedDescription
            throw error
        } catch {
            state.lastError = error.localizedDescription
            throw SyncError.pullFailed(underlying: error)
        }
    }

    // MARK: - Merge Remote Changes

    private func mergeRemoteChanges(
        _ response: Pedef_PullResponse,
        modelContext: ModelContext
    ) throws {
        // Merge papers
        for dto in response.papers {
            guard let uuid = UUID(uuidString: dto.id) else { continue }
            let predicate = #Predicate<Paper> { $0.id == uuid }
            let descriptor = FetchDescriptor<Paper>(predicate: predicate)
            if let existing = try modelContext.fetch(descriptor).first {
                let serverDate = DTOMapper.fromTimestamp(dto.modifiedDate)
                if serverDate > existing.modifiedDate {
                    DTOMapper.updatePaper(existing, from: dto)
                }
            } else {
                let paper = DTOMapper.makePaper(from: dto)
                modelContext.insert(paper)
            }
        }

        // Merge annotations
        for dto in response.annotations {
            guard let uuid = UUID(uuidString: dto.id) else { continue }
            let predicate = #Predicate<Annotation> { $0.id == uuid }
            let descriptor = FetchDescriptor<Annotation>(predicate: predicate)
            if let existing = try modelContext.fetch(descriptor).first {
                let serverDate = DTOMapper.fromTimestamp(dto.modifiedDate)
                if serverDate > existing.modifiedDate {
                    DTOMapper.updateAnnotation(existing, from: dto)
                }
            } else {
                let annotation = DTOMapper.makeAnnotation(from: dto)
                if let paperUUID = UUID(uuidString: dto.paperID) {
                    let paperPred = #Predicate<Paper> { $0.id == paperUUID }
                    let paperDesc = FetchDescriptor<Paper>(predicate: paperPred)
                    annotation.paper = try modelContext.fetch(paperDesc).first
                }
                modelContext.insert(annotation)
            }
        }

        // Merge collections
        for dto in response.collections {
            guard let uuid = UUID(uuidString: dto.id) else { continue }
            let predicate = #Predicate<Collection> { $0.id == uuid }
            let descriptor = FetchDescriptor<Collection>(predicate: predicate)
            if let existing = try modelContext.fetch(descriptor).first {
                let serverDate = DTOMapper.fromTimestamp(dto.modifiedDate)
                if serverDate > existing.modifiedDate {
                    DTOMapper.updateCollection(existing, from: dto)
                }
            } else {
                let collection = DTOMapper.makeCollection(from: dto)
                modelContext.insert(collection)
            }
        }

        // Merge tags
        for dto in response.tags {
            guard let uuid = UUID(uuidString: dto.id) else { continue }
            let predicate = #Predicate<Tag> { $0.id == uuid }
            let descriptor = FetchDescriptor<Tag>(predicate: predicate)
            if let existing = try modelContext.fetch(descriptor).first {
                let serverDate = DTOMapper.fromTimestamp(dto.createdDate)
                if serverDate > existing.createdDate {
                    DTOMapper.updateTag(existing, from: dto)
                }
            } else {
                let tag = DTOMapper.makeTag(from: dto)
                modelContext.insert(tag)
            }
        }

        // Process deletions
        try applyDeletions(response.deletions, modelContext: modelContext)
    }

    // MARK: - Build Push Request

    private func buildPushRequest(from snapshot: ChangeSnapshot) -> Pedef_PushRequest {
        var request = Pedef_PushRequest()
        request.papers = snapshot.papers.map { DTOMapper.toProto($0) }
        request.annotations = snapshot.annotations.map { DTOMapper.toProto($0) }
        request.collections = snapshot.collections.map { DTOMapper.toProto($0) }
        request.tags = snapshot.tags.map { DTOMapper.toProto($0) }

        var deletions = Pedef_Deletions()
        deletions.paperIds = snapshot.deletedPaperIDs.map(\.uuidString)
        deletions.annotationIds = snapshot.deletedAnnotationIDs.map(\.uuidString)
        deletions.collectionIds = snapshot.deletedCollectionIDs.map(\.uuidString)
        deletions.tagIds = snapshot.deletedTagIDs.map(\.uuidString)
        request.deletions = deletions

        return request
    }

    // MARK: - Apply Deletions

    private func applyDeletions(
        _ deletions: Pedef_Deletions,
        modelContext: ModelContext
    ) throws {
        for idStr in deletions.paperIds {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            let predicate = #Predicate<Paper> { $0.id == uuid }
            let descriptor = FetchDescriptor<Paper>(predicate: predicate)
            if let paper = try modelContext.fetch(descriptor).first {
                modelContext.delete(paper)
            }
        }

        for idStr in deletions.annotationIds {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            let predicate = #Predicate<Annotation> { $0.id == uuid }
            let descriptor = FetchDescriptor<Annotation>(predicate: predicate)
            if let annotation = try modelContext.fetch(descriptor).first {
                modelContext.delete(annotation)
            }
        }

        for idStr in deletions.collectionIds {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            let predicate = #Predicate<Collection> { $0.id == uuid }
            let descriptor = FetchDescriptor<Collection>(predicate: predicate)
            if let collection = try modelContext.fetch(descriptor).first {
                modelContext.delete(collection)
            }
        }

        for idStr in deletions.tagIds {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            let predicate = #Predicate<Tag> { $0.id == uuid }
            let descriptor = FetchDescriptor<Tag>(predicate: predicate)
            if let tag = try modelContext.fetch(descriptor).first {
                modelContext.delete(tag)
            }
        }
    }

    // MARK: - Download Missing PDFs

    /// Downloads PDFs for papers that were pulled from the server but lack local data.
    func downloadMissingPDFs(modelContext: ModelContext) async throws {
        guard let client = networkClient else { throw SyncError.notConfigured }

        let predicate = #Predicate<Paper> { $0.fileSize > 0 }
        let descriptor = FetchDescriptor<Paper>(predicate: predicate)
        let papers = try modelContext.fetch(descriptor)

        for paper in papers where paper.pdfData.isEmpty {
            do {
                let data = try await client.downloadPDF(paperID: paper.id)
                paper.pdfData = data
                paper.fileSize = Int64(data.count)
            } catch {
                state.lastError = "PDF download failed for \(paper.title): \(error.localizedDescription)"
            }
        }

        try modelContext.save()
    }
}

