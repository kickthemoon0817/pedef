import Foundation
import SwiftData
import CryptoKit

/// Service for managing the paper archive - storage, retrieval, search, and organization
@MainActor
final class ArchiveService: ObservableObject {
    private var modelContext: ModelContext?

    init() {}

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Paper Import

    /// Import a paper from PDF data with automatic metadata extraction
    func importPaper(
        pdfData: Data,
        title: String? = nil,
        authors: [String]? = nil
    ) throws -> Paper {
        guard let modelContext else {
            throw ArchiveError.notConfigured
        }

        // Validate PDF
        guard PDFService.shared.isValidPDF(pdfData) else {
            throw ArchiveError.invalidPDF
        }

        // Check for duplicates
        let hash = computeHash(for: pdfData)
        if let existing = try? findPaperByHash(hash) {
            throw ArchiveError.duplicatePaper(title: existing.title, id: existing.id)
        }

        // Extract metadata
        let metadata = PDFService.shared.extractMetadata(from: pdfData)
        let documentInfo = PDFService.shared.getDocumentInfo(from: pdfData)

        // Determine title
        let paperTitle = title ?? metadata?.title ?? "Untitled Paper"

        // Create paper
        let paper = Paper(
            title: paperTitle,
            authors: authors ?? metadata?.authors ?? [],
            pdfData: pdfData,
            pageCount: documentInfo?.pageCount ?? 0
        )

        // Set additional metadata
        paper.abstract = metadata?.subject
        paper.keywords = metadata?.keywords ?? []
        paper.customMetadata["contentHash"] = hash

        // Generate thumbnail
        if let thumbnail = PDFService.shared.generateThumbnail(from: pdfData) {
            paper.thumbnailData = thumbnail
        }

        modelContext.insert(paper)
        return paper
    }

    /// Import a paper from a URL
    func importPaper(from url: URL) throws -> Paper {
        let data = try Data(contentsOf: url)
        let filename = url.deletingPathExtension().lastPathComponent
        return try importPaper(pdfData: data, title: filename)
    }

    // MARK: - Paper Retrieval

    /// Fetch all papers
    func fetchAllPapers() throws -> [Paper] {
        guard let modelContext else {
            throw ArchiveError.notConfigured
        }

        let descriptor = FetchDescriptor<Paper>(
            sortBy: [SortDescriptor(\Paper.importedDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch papers matching a predicate
    func fetchPapers(matching predicate: Predicate<Paper>) throws -> [Paper] {
        guard let modelContext else {
            throw ArchiveError.notConfigured
        }

        var descriptor = FetchDescriptor<Paper>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\Paper.importedDate, order: .reverse)]
        return try modelContext.fetch(descriptor)
    }

    /// Fetch recently read papers
    func fetchRecentlyReadPapers(limit: Int = 20) throws -> [Paper] {
        guard let modelContext else {
            throw ArchiveError.notConfigured
        }

        let cutoffDate = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days
        let predicate = #Predicate<Paper> { paper in
            paper.lastOpenedDate != nil && paper.lastOpenedDate! > cutoffDate
        }

        var descriptor = FetchDescriptor<Paper>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\Paper.lastOpenedDate, order: .reverse)]
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    /// Fetch favorite papers
    func fetchFavoritePapers() throws -> [Paper] {
        let predicate = #Predicate<Paper> { paper in
            paper.tags.contains("favorite")
        }
        return try fetchPapers(matching: predicate)
    }

    /// Fetch unread papers (reading list)
    func fetchReadingList() throws -> [Paper] {
        let predicate = #Predicate<Paper> { paper in
            paper.readingProgress < 0.9
        }
        return try fetchPapers(matching: predicate)
    }

    /// Get a paper by ID
    func getPaper(by id: UUID) throws -> Paper? {
        guard let context = modelContext else {
            throw ArchiveError.notConfigured
        }

        let predicate = #Predicate<Paper> { paper in
            paper.id == id
        }
        var descriptor = FetchDescriptor<Paper>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Search

    /// Full-text search across papers
    func search(query: String) throws -> [PaperSearchResult] {
        guard modelContext != nil else {
            throw ArchiveError.notConfigured
        }

        let allPapers = try fetchAllPapers()
        let queryLower = query.lowercased()

        var results: [PaperSearchResult] = []

        for paper in allPapers {
            var score: Double = 0
            var matchedFields: [String] = []

            // Check title
            if paper.title.lowercased().contains(queryLower) {
                score += 10
                matchedFields.append("title")
            }

            // Check authors
            if paper.authors.joined(separator: " ").lowercased().contains(queryLower) {
                score += 8
                matchedFields.append("authors")
            }

            // Check keywords
            if paper.keywords.joined(separator: " ").lowercased().contains(queryLower) {
                score += 6
                matchedFields.append("keywords")
            }

            // Check abstract
            if let abstract = paper.abstract, abstract.lowercased().contains(queryLower) {
                score += 4
                matchedFields.append("abstract")
            }

            // Check tags
            if paper.tagNames.joined(separator: " ").lowercased().contains(queryLower) {
                score += 3
                matchedFields.append("tags")
            }

            // Search within PDF content
            if !matchedFields.isEmpty || score == 0 {
                let pdfResults = PDFService.shared.search(query: query, in: paper.pdfData)
                if !pdfResults.isEmpty {
                    score += Double(min(pdfResults.count, 10)) * 0.5
                    matchedFields.append("content (\(pdfResults.count) matches)")
                }
            }

            if score > 0 {
                results.append(PaperSearchResult(
                    paper: paper,
                    score: score,
                    matchedFields: matchedFields
                ))
            }
        }

        // Sort by score descending
        return results.sorted { $0.score > $1.score }
    }

    /// Search by author name
    func searchByAuthor(_ authorName: String) throws -> [Paper] {
        let allPapers = try fetchAllPapers()
        let nameLower = authorName.lowercased()

        return allPapers.filter { paper in
            paper.authors.contains { $0.lowercased().contains(nameLower) }
        }
    }

    /// Search by keyword
    func searchByKeyword(_ keyword: String) throws -> [Paper] {
        let allPapers = try fetchAllPapers()
        let keywordLower = keyword.lowercased()

        return allPapers.filter { paper in
            paper.keywords.contains { $0.lowercased().contains(keywordLower) }
        }
    }

    // MARK: - Duplicate Detection

    /// Find potential duplicate papers
    func findDuplicates() throws -> [[Paper]] {
        let allPapers = try fetchAllPapers()
        var duplicateGroups: [[Paper]] = []
        var processedIds: Set<UUID> = []

        for paper in allPapers {
            guard !processedIds.contains(paper.id) else { continue }

            var duplicates = [paper]
            processedIds.insert(paper.id)

            for otherPaper in allPapers where otherPaper.id != paper.id && !processedIds.contains(otherPaper.id) {
                if isPotentialDuplicate(paper, otherPaper) {
                    duplicates.append(otherPaper)
                    processedIds.insert(otherPaper.id)
                }
            }

            if duplicates.count > 1 {
                duplicateGroups.append(duplicates)
            }
        }

        return duplicateGroups
    }

    /// Check if two papers are potential duplicates
    private func isPotentialDuplicate(_ paper1: Paper, _ paper2: Paper) -> Bool {
        // Check content hash first (fastest, most accurate)
        if let hash1 = paper1.customMetadata["contentHash"],
           let hash2 = paper2.customMetadata["contentHash"],
           hash1 == hash2 {
            return true
        }

        // Check file size (must be similar)
        let sizeDiff = abs(paper1.fileSize - paper2.fileSize)
        if sizeDiff > min(paper1.fileSize, paper2.fileSize) / 10 {
            return false
        }

        // Check title similarity
        let titleSimilarity = stringSimilarity(paper1.title, paper2.title)
        if titleSimilarity > 0.8 {
            return true
        }

        // Check authors
        if !paper1.authors.isEmpty && !paper2.authors.isEmpty {
            let commonAuthors = Set(paper1.authors.map { $0.lowercased() })
                .intersection(Set(paper2.authors.map { $0.lowercased() }))
            if commonAuthors.count >= min(paper1.authors.count, paper2.authors.count) {
                return titleSimilarity > 0.5
            }
        }

        return false
    }

    /// Compute string similarity (Jaccard index on words)
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let words1 = Set(s1.lowercased().split(separator: " ").map(String.init))
        let words2 = Set(s2.lowercased().split(separator: " ").map(String.init))

        guard !words1.isEmpty || !words2.isEmpty else { return 0 }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        return Double(intersection) / Double(union)
    }

    /// Merge duplicate papers (keep first, move annotations/collections from others)
    func mergeDuplicates(_ papers: [Paper]) throws -> Paper {
        guard let modelContext else {
            throw ArchiveError.notConfigured
        }

        guard papers.count >= 2 else {
            throw ArchiveError.insufficientPapersForMerge
        }

        let primary = papers[0]
        let others = Array(papers.dropFirst())

        for other in others {
            // Merge annotations
            for annotation in other.annotations {
                annotation.paper = primary
            }

            // Merge collections
            for collection in other.collections where !primary.collections.contains(where: { $0.id == collection.id }) {
                primary.collections.append(collection)
            }

            // Merge tags
            for tag in other.tagObjects where !primary.tagObjects.contains(where: { $0.id == tag.id }) {
                primary.tagObjects.append(tag)
            }

            // Merge legacy tags
            for tag in other.tags where !primary.tags.contains(tag) {
                primary.tags.append(tag)
            }

            // Merge keywords
            for keyword in other.keywords where !primary.keywords.contains(keyword) {
                primary.keywords.append(keyword)
            }

            // Use longer reading time
            primary.totalReadingTime = max(primary.totalReadingTime, other.totalReadingTime)

            // Use higher progress
            primary.readingProgress = max(primary.readingProgress, other.readingProgress)

            // Delete the duplicate
            modelContext.delete(other)
        }

        primary.modifiedDate = Date()
        return primary
    }

    // MARK: - Statistics

    /// Get archive statistics
    func getStatistics() throws -> ArchiveStatistics {
        let allPapers = try fetchAllPapers()

        let totalPapers = allPapers.count
        let totalAnnotations = allPapers.reduce(0) { $0 + $1.annotations.count }
        let totalReadingTime = allPapers.reduce(0.0) { $0 + $1.totalReadingTime }
        let readPapers = allPapers.filter { $0.isRead }.count
        let favoritePapers = allPapers.filter { $0.tags.contains("favorite") }.count

        // Total file size
        let totalSize = allPapers.reduce(Int64(0)) { $0 + $1.fileSize }

        // Unique authors
        let uniqueAuthors = Set(allPapers.flatMap { $0.authors }).count

        // Unique keywords
        let uniqueKeywords = Set(allPapers.flatMap { $0.keywords }).count

        return ArchiveStatistics(
            totalPapers: totalPapers,
            readPapers: readPapers,
            favoritePapers: favoritePapers,
            totalAnnotations: totalAnnotations,
            totalReadingTimeSeconds: totalReadingTime,
            totalFileSizeBytes: totalSize,
            uniqueAuthors: uniqueAuthors,
            uniqueKeywords: uniqueKeywords
        )
    }

    // MARK: - Helpers

    /// Compute a hash of the PDF content for duplicate detection
    private func computeHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Find a paper by its content hash
    private func findPaperByHash(_ hash: String) throws -> Paper? {
        let allPapers = try fetchAllPapers()
        return allPapers.first { $0.customMetadata["contentHash"] == hash }
    }
}

// MARK: - Supporting Types

struct PaperSearchResult {
    let paper: Paper
    let score: Double
    let matchedFields: [String]
}

struct ArchiveStatistics {
    let totalPapers: Int
    let readPapers: Int
    let favoritePapers: Int
    let totalAnnotations: Int
    let totalReadingTimeSeconds: TimeInterval
    let totalFileSizeBytes: Int64

    let uniqueAuthors: Int
    let uniqueKeywords: Int

    var formattedReadingTime: String {
        let hours = Int(totalReadingTimeSeconds / 3600)
        let minutes = Int((totalReadingTimeSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalFileSizeBytes)
    }

    var readingProgress: Double {
        guard totalPapers > 0 else { return 0 }
        return Double(readPapers) / Double(totalPapers)
    }
}

enum ArchiveError: LocalizedError {
    case notConfigured
    case invalidPDF
    case duplicatePaper(title: String, id: UUID)
    case insufficientPapersForMerge
    case paperNotFound

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Archive service not configured"
        case .invalidPDF:
            return "The file is not a valid PDF document"
        case .duplicatePaper(let title, _):
            return "This paper already exists in your library: \(title)"
        case .insufficientPapersForMerge:
            return "At least two papers are required to merge"
        case .paperNotFound:
            return "Paper not found in the archive"
        }
    }
}
