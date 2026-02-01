import Foundation
import SwiftData

/// Represents an academic paper in the user's archive
@Model
final class Paper {
    // MARK: - Identity

    @Attribute(.unique) var id: UUID
    var title: String
    var authors: [String]

    // MARK: - Academic Metadata

    var abstract: String?
    var doi: String?
    var arxivId: String?
    var publishedDate: Date?
    var journal: String?
    var volume: String?
    var issue: String?
    var pages: String?
    var keywords: [String]

    // MARK: - File Data

    @Attribute(.externalStorage) var pdfData: Data
    @Attribute(.externalStorage) var thumbnailData: Data?
    var pageCount: Int
    var fileSize: Int64

    // MARK: - Organization

    @Relationship(deleteRule: .nullify, inverse: \Collection.papers)
    var collections: [Collection]

    var tags: [String]

    // MARK: - Annotations

    @Relationship(deleteRule: .cascade, inverse: \Annotation.paper)
    var annotations: [Annotation]

    // MARK: - Reading State

    var readingProgress: Double  // 0.0 to 1.0
    var currentPage: Int
    var lastOpenedDate: Date?
    var totalReadingTime: TimeInterval  // seconds

    // MARK: - Timestamps

    var importedDate: Date
    var modifiedDate: Date

    // MARK: - Custom Metadata

    var customMetadata: [String: String]

    // MARK: - Initialization

    init(
        title: String,
        authors: [String] = [],
        pdfData: Data,
        pageCount: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.authors = authors
        self.pdfData = pdfData
        self.pageCount = pageCount
        self.fileSize = Int64(pdfData.count)

        self.abstract = nil
        self.doi = nil
        self.arxivId = nil
        self.publishedDate = nil
        self.journal = nil
        self.volume = nil
        self.issue = nil
        self.pages = nil
        self.keywords = []
        self.thumbnailData = nil

        self.collections = []
        self.tags = []
        self.annotations = []

        self.readingProgress = 0.0
        self.currentPage = 0
        self.lastOpenedDate = nil
        self.totalReadingTime = 0

        self.importedDate = Date()
        self.modifiedDate = Date()
        self.customMetadata = [:]
    }
}

// MARK: - Computed Properties

extension Paper {
    var formattedAuthors: String {
        guard !authors.isEmpty else { return "Unknown Author" }
        if authors.count == 1 {
            return authors[0]
        } else if authors.count == 2 {
            return "\(authors[0]) and \(authors[1])"
        } else {
            return "\(authors[0]) et al."
        }
    }

    var citationKey: String {
        let firstAuthor = authors.first?.split(separator: " ").last ?? "unknown"
        let year = publishedDate.map { Calendar.current.component(.year, from: $0) } ?? 0
        return "\(firstAuthor)\(year)".lowercased()
    }

    var isRead: Bool {
        readingProgress >= 0.9
    }

    var hasAnnotations: Bool {
        !annotations.isEmpty
    }
}

// MARK: - Search Support

extension Paper {
    var searchableText: String {
        [
            title,
            authors.joined(separator: " "),
            abstract ?? "",
            keywords.joined(separator: " "),
            tags.joined(separator: " ")
        ].joined(separator: " ")
    }
}
