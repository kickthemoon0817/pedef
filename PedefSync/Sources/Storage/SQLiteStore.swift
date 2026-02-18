import Foundation
import SQLite
import SwiftProtobuf

/// Server-side SQLite storage for paper metadata, annotations, collections, and tags.
///
/// All dates are stored as ISO 8601 strings. Arrays/maps are stored as JSON TEXT.
/// Soft deletes set `is_deleted = true` and update `modified_date`.
/// Delta sync queries filter by `modified_date > sinceDate`.
final class SQLiteStore: @unchecked Sendable {
    let db: Connection
    private let dbLock = NSLock()

    // MARK: - Table Definitions

    static let papers = Table("papers")
    static let annotations = Table("annotations")
    static let collections = Table("collections")
    static let tags = Table("tags")

    // MARK: - Paper Columns

    static let pId = Expression<String>("id")
    static let pTitle = Expression<String>("title")
    static let pAuthors = Expression<String>("authors")                // JSON array
    static let pAbstract = Expression<String?>("abstract")
    static let pDoi = Expression<String?>("doi")
    static let pArxivId = Expression<String?>("arxiv_id")
    static let pPublishedDate = Expression<String?>("published_date")
    static let pJournal = Expression<String?>("journal")
    static let pVolume = Expression<String?>("volume")
    static let pIssue = Expression<String?>("issue")
    static let pPages = Expression<String?>("pages")
    static let pKeywords = Expression<String>("keywords")              // JSON array
    static let pPageCount = Expression<Int>("page_count")
    static let pFileSize = Expression<Int64>("file_size")
    static let pThumbnailData = Expression<SQLite.Blob?>("thumbnail_data")
    static let pReadingProgress = Expression<Double>("reading_progress")
    static let pCurrentPage = Expression<Int>("current_page")
    static let pLastOpenedDate = Expression<String?>("last_opened_date")
    static let pTotalReadingTime = Expression<Double>("total_reading_time")
    static let pImportedDate = Expression<String>("imported_date")
    static let pModifiedDate = Expression<String>("modified_date")
    static let pCustomMetadata = Expression<String>("custom_metadata") // JSON object
    static let pTags = Expression<String>("tags")                      // JSON array
    static let pTagIds = Expression<String>("tag_ids")                 // JSON array
    static let pCollectionIds = Expression<String>("collection_ids")   // JSON array
    static let pIsDeleted = Expression<Bool>("is_deleted")

    // MARK: - Annotation Columns

    static let aId = Expression<String>("id")
    static let aPaperId = Expression<String>("paper_id")
    static let aType = Expression<Int>("type")
    static let aColorHex = Expression<String?>("color_hex")
    static let aPageIndex = Expression<Int>("page_index")
    static let aBoundsX = Expression<Double>("bounds_x")
    static let aBoundsY = Expression<Double>("bounds_y")
    static let aBoundsW = Expression<Double>("bounds_width")
    static let aBoundsH = Expression<Double>("bounds_height")
    static let aSelectedText = Expression<String?>("selected_text")
    static let aNoteContent = Expression<String?>("note_content")
    static let aDrawingData = Expression<SQLite.Blob?>("drawing_data")
    static let aTags = Expression<String>("tags")                      // JSON array
    static let aCreatedDate = Expression<String>("created_date")
    static let aModifiedDate = Expression<String>("modified_date")
    static let aIsDeleted = Expression<Bool>("is_deleted")

    // MARK: - Collection Columns

    static let cId = Expression<String>("id")
    static let cName = Expression<String>("name")
    static let cType = Expression<Int>("type")
    static let cColorHex = Expression<String?>("color_hex")
    static let cIconName = Expression<String?>("icon_name")
    static let cParentId = Expression<String?>("parent_id")
    static let cPaperIds = Expression<String>("paper_ids")             // JSON array
    static let cSmartRulesData = Expression<SQLite.Blob?>("smart_rules_data")
    static let cNotes = Expression<String?>("notes")
    static let cSortOrder = Expression<Int>("sort_order")
    static let cCreatedDate = Expression<String>("created_date")
    static let cModifiedDate = Expression<String>("modified_date")
    static let cIsDeleted = Expression<Bool>("is_deleted")

    // MARK: - Tag Columns

    static let tId = Expression<String>("id")
    static let tName = Expression<String>("name")
    static let tColorHex = Expression<String?>("color_hex")
    static let tUsageCount = Expression<Int>("usage_count")
    static let tCreatedDate = Expression<String>("created_date")
    static let tModifiedDate = Expression<String>("modified_date")
    static let tPaperIds = Expression<String>("paper_ids")             // JSON array
    static let tIsDeleted = Expression<Bool>("is_deleted")

    // MARK: - Date Formatter

    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Initialization

    /// Opens (or creates) the database at `path` and ensures all tables exist.
    init(path: String) throws {
        self.db = try Connection(path)
        db.busyTimeout = 5
        try createTables()
    }

    /// In-memory database for testing.
    init() throws {
        self.db = try Connection(.inMemory)
        db.busyTimeout = 5
        try createTables()
    }

    // MARK: - Schema

    private func createTables() throws {
        try db.run(Self.papers.create(ifNotExists: true) { t in
            t.column(Self.pId, primaryKey: true)
            t.column(Self.pTitle)
            t.column(Self.pAuthors, defaultValue: "[]")
            t.column(Self.pAbstract)
            t.column(Self.pDoi)
            t.column(Self.pArxivId)
            t.column(Self.pPublishedDate)
            t.column(Self.pJournal)
            t.column(Self.pVolume)
            t.column(Self.pIssue)
            t.column(Self.pPages)
            t.column(Self.pKeywords, defaultValue: "[]")
            t.column(Self.pPageCount, defaultValue: 0)
            t.column(Self.pFileSize, defaultValue: 0)
            t.column(Self.pThumbnailData)
            t.column(Self.pReadingProgress, defaultValue: 0.0)
            t.column(Self.pCurrentPage, defaultValue: 0)
            t.column(Self.pLastOpenedDate)
            t.column(Self.pTotalReadingTime, defaultValue: 0.0)
            t.column(Self.pImportedDate)
            t.column(Self.pModifiedDate)
            t.column(Self.pCustomMetadata, defaultValue: "{}")
            t.column(Self.pTags, defaultValue: "[]")
            t.column(Self.pTagIds, defaultValue: "[]")
            t.column(Self.pCollectionIds, defaultValue: "[]")
            t.column(Self.pIsDeleted, defaultValue: false)
        })
        try db.run(Self.papers.createIndex(Self.pModifiedDate, ifNotExists: true))

        try db.run(Self.annotations.create(ifNotExists: true) { t in
            t.column(Self.aId, primaryKey: true)
            t.column(Self.aPaperId)
            t.column(Self.aType, defaultValue: 0)
            t.column(Self.aColorHex)
            t.column(Self.aPageIndex, defaultValue: 0)
            t.column(Self.aBoundsX, defaultValue: 0.0)
            t.column(Self.aBoundsY, defaultValue: 0.0)
            t.column(Self.aBoundsW, defaultValue: 0.0)
            t.column(Self.aBoundsH, defaultValue: 0.0)
            t.column(Self.aSelectedText)
            t.column(Self.aNoteContent)
            t.column(Self.aDrawingData)
            t.column(Self.aTags, defaultValue: "[]")
            t.column(Self.aCreatedDate)
            t.column(Self.aModifiedDate)
            t.column(Self.aIsDeleted, defaultValue: false)
            // Foreign key constraint: annotations.paper_id -> papers.id
            t.foreignKey(Self.aPaperId, references: Self.papers, Self.pId, delete: .cascade)
        })
        try db.run(Self.annotations.createIndex(Self.aModifiedDate, ifNotExists: true))
        try db.run(Self.annotations.createIndex(Self.aPaperId, ifNotExists: true))

        try db.run(Self.collections.create(ifNotExists: true) { t in
            t.column(Self.cId, primaryKey: true)
            t.column(Self.cName)
            t.column(Self.cType, defaultValue: 0)
            t.column(Self.cColorHex)
            t.column(Self.cIconName)
            t.column(Self.cParentId)
            t.column(Self.cPaperIds, defaultValue: "[]")
            t.column(Self.cSmartRulesData)
            t.column(Self.cNotes)
            t.column(Self.cSortOrder, defaultValue: 0)
            t.column(Self.cCreatedDate)
            t.column(Self.cModifiedDate)
            t.column(Self.cIsDeleted, defaultValue: false)
        })
        try db.run(Self.collections.createIndex(Self.cModifiedDate, ifNotExists: true))

        try db.run(Self.tags.create(ifNotExists: true) { t in
            t.column(Self.tId, primaryKey: true)
            t.column(Self.tName)
            t.column(Self.tColorHex)
            t.column(Self.tUsageCount, defaultValue: 0)
            t.column(Self.tCreatedDate)
            t.column(Self.tModifiedDate)
            t.column(Self.tPaperIds, defaultValue: "[]")
            t.column(Self.tIsDeleted, defaultValue: false)
        })
        try db.run(Self.tags.createIndex(Self.tModifiedDate, ifNotExists: true))
    }
}

// MARK: - JSON & Timestamp Helpers

extension SQLiteStore {

    static func encodeJSONArray(_ arr: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    static func decodeJSONArray(_ str: String) -> [String] {
        guard let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return arr
    }

    static func encodeJSONMap(_ map: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: map),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    static func decodeJSONMap(_ str: String) -> [String: String] {
        guard let data = str.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return map
    }

    static func timestampToString(_ ts: Google_Protobuf_Timestamp) -> String {
        iso8601.string(from: ts.date)
    }

    static func stringToTimestamp(_ str: String) -> Google_Protobuf_Timestamp? {
        guard let date = iso8601.date(from: str) else { return nil }
        return Google_Protobuf_Timestamp(date: date)
    }

    static func optionalTimestampToString(_ ts: Google_Protobuf_Timestamp?, has: Bool) -> String? {
        guard has, let ts = ts else { return nil }
        return timestampToString(ts)
    }
}


// MARK: - Paper CRUD

extension SQLiteStore {

    func upsertPaper(_ p: Pedef_PaperMetadata) throws {
        guard !p.id.isEmpty else { throw StorageError.invalidID }
        let thumb: SQLite.Blob? = p.thumbnailData.isEmpty ? nil : SQLite.Blob(bytes: [UInt8](p.thumbnailData))
        dbLock.lock()
        defer { dbLock.unlock() }
        try db.run(Self.papers.insert(or: .replace,
            Self.pId <- p.id,
            Self.pTitle <- p.title,
            Self.pAuthors <- Self.encodeJSONArray(p.authors),
            Self.pAbstract <- (p.abstract.isEmpty ? nil : p.abstract),
            Self.pDoi <- (p.doi.isEmpty ? nil : p.doi),
            Self.pArxivId <- (p.arxivID.isEmpty ? nil : p.arxivID),
            Self.pPublishedDate <- Self.optionalTimestampToString(p.publishedDate, has: p.hasPublishedDate),
            Self.pJournal <- (p.journal.isEmpty ? nil : p.journal),
            Self.pVolume <- (p.volume.isEmpty ? nil : p.volume),
            Self.pIssue <- (p.issue.isEmpty ? nil : p.issue),
            Self.pPages <- (p.pages.isEmpty ? nil : p.pages),
            Self.pKeywords <- Self.encodeJSONArray(p.keywords),
            Self.pPageCount <- Int(p.pageCount),
            Self.pFileSize <- p.fileSize,
            Self.pThumbnailData <- thumb,
            Self.pReadingProgress <- p.readingProgress,
            Self.pCurrentPage <- Int(p.currentPage),
            Self.pLastOpenedDate <- Self.optionalTimestampToString(p.lastOpenedDate, has: p.hasLastOpenedDate),
            Self.pTotalReadingTime <- p.totalReadingTime,
            Self.pImportedDate <- (p.hasImportedDate ? Self.timestampToString(p.importedDate) : Self.iso8601.string(from: Date())),
            Self.pModifiedDate <- (p.hasModifiedDate ? Self.timestampToString(p.modifiedDate) : Self.iso8601.string(from: Date())),
            Self.pCustomMetadata <- Self.encodeJSONMap(p.customMetadata),
            Self.pTags <- Self.encodeJSONArray(p.tags),
            Self.pTagIds <- Self.encodeJSONArray(p.tagIds),
            Self.pCollectionIds <- Self.encodeJSONArray(p.collectionIds),
            Self.pIsDeleted <- p.isDeleted
        ))
    }

    func getPaper(id: String) throws -> Pedef_PaperMetadata? {
        guard !id.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let row = try db.pluck(Self.papers.filter(Self.pId == id)) else { return nil }
        return paperFromRow(row)
    }

    func listPapers(includeDeleted: Bool = false) throws -> [Pedef_PaperMetadata] {
        dbLock.lock()
        defer { dbLock.unlock() }
        let query = includeDeleted ? Self.papers : Self.papers.filter(Self.pIsDeleted == false)
        return try db.prepare(query).map { paperFromRow($0) }
    }

    func deletePaper(id: String, hard: Bool = false) throws {
        guard !id.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        if hard {
            try db.run(Self.papers.filter(Self.pId == id).delete())
        } else {
            let now = Self.iso8601.string(from: Date())
            try db.run(Self.papers.filter(Self.pId == id).update(
                Self.pIsDeleted <- true,
                Self.pModifiedDate <- now
            ))
        }
    }

    func papersModifiedSince(_ sinceDate: String) throws -> [Pedef_PaperMetadata] {
        dbLock.lock()
        defer { dbLock.unlock() }
        return try db.prepare(Self.papers.filter(Self.pModifiedDate > sinceDate)).map { paperFromRow($0) }
    }

    private func paperFromRow(_ row: Row) -> Pedef_PaperMetadata {
        var p = Pedef_PaperMetadata()
        p.id = row[Self.pId]
        p.title = row[Self.pTitle]
        p.authors = Self.decodeJSONArray(row[Self.pAuthors])
        p.abstract = row[Self.pAbstract] ?? ""
        p.doi = row[Self.pDoi] ?? ""
        p.arxivID = row[Self.pArxivId] ?? ""
        if let str = row[Self.pPublishedDate], let ts = Self.stringToTimestamp(str) {
            p.publishedDate = ts
        }
        p.journal = row[Self.pJournal] ?? ""
        p.volume = row[Self.pVolume] ?? ""
        p.issue = row[Self.pIssue] ?? ""
        p.pages = row[Self.pPages] ?? ""
        p.keywords = Self.decodeJSONArray(row[Self.pKeywords])
        p.pageCount = Int32(row[Self.pPageCount])
        p.fileSize = row[Self.pFileSize]
        if let blob = row[Self.pThumbnailData] {
            p.thumbnailData = Data(blob.bytes)
        }
        p.readingProgress = row[Self.pReadingProgress]
        p.currentPage = Int32(row[Self.pCurrentPage])
        if let str = row[Self.pLastOpenedDate], let ts = Self.stringToTimestamp(str) {
            p.lastOpenedDate = ts
        }
        p.totalReadingTime = row[Self.pTotalReadingTime]
        // Safe unwrap with fallback to current date
        if let ts = Self.stringToTimestamp(row[Self.pImportedDate]) {
            p.importedDate = ts
        } else {
            p.importedDate = Google_Protobuf_Timestamp(date: Date())
        }
        if let ts = Self.stringToTimestamp(row[Self.pModifiedDate]) {
            p.modifiedDate = ts
        } else {
            p.modifiedDate = Google_Protobuf_Timestamp(date: Date())
        }
        p.customMetadata = Self.decodeJSONMap(row[Self.pCustomMetadata])
        p.tags = Self.decodeJSONArray(row[Self.pTags])
        p.tagIds = Self.decodeJSONArray(row[Self.pTagIds])
        p.collectionIds = Self.decodeJSONArray(row[Self.pCollectionIds])
        p.isDeleted = row[Self.pIsDeleted]
        return p
    }
}

// MARK: - Annotation CRUD

extension SQLiteStore {

    func upsertAnnotation(_ a: Pedef_AnnotationDTO) throws {
        guard !a.id.isEmpty else { throw StorageError.invalidID }
        guard !a.paperID.isEmpty else { throw StorageError.invalidID }
        let drawing: SQLite.Blob? = a.drawingData.isEmpty ? nil : SQLite.Blob(bytes: [UInt8](a.drawingData))
        dbLock.lock()
        defer { dbLock.unlock() }
        try db.run(Self.annotations.insert(or: .replace,
            Self.aId <- a.id,
            Self.aPaperId <- a.paperID,
            Self.aType <- a.type.rawValue,
            Self.aColorHex <- (a.colorHex.isEmpty ? nil : a.colorHex),
            Self.aPageIndex <- Int(a.pageIndex),
            Self.aBoundsX <- a.bounds.x,
            Self.aBoundsY <- a.bounds.y,
            Self.aBoundsW <- a.bounds.width,
            Self.aBoundsH <- a.bounds.height,
            Self.aSelectedText <- (a.selectedText.isEmpty ? nil : a.selectedText),
            Self.aNoteContent <- (a.noteContent.isEmpty ? nil : a.noteContent),
            Self.aDrawingData <- drawing,
            Self.aTags <- Self.encodeJSONArray(a.tags),
            Self.aCreatedDate <- (a.hasCreatedDate ? Self.timestampToString(a.createdDate) : Self.iso8601.string(from: Date())),
            Self.aModifiedDate <- (a.hasModifiedDate ? Self.timestampToString(a.modifiedDate) : Self.iso8601.string(from: Date())),
            Self.aIsDeleted <- a.isDeleted
        ))
    }

    func getAnnotation(id: String) throws -> Pedef_AnnotationDTO? {
        guard !id.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let row = try db.pluck(Self.annotations.filter(Self.aId == id)) else { return nil }
        return annotationFromRow(row)
    }

    func getAnnotationsForPaper(paperId: String, includeDeleted: Bool = false) throws -> [Pedef_AnnotationDTO] {
        guard !paperId.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        var query = Self.annotations.filter(Self.aPaperId == paperId)
        if !includeDeleted { query = query.filter(Self.aIsDeleted == false) }
        return try db.prepare(query).map { annotationFromRow($0) }
    }

    func deleteAnnotation(id: String, hard: Bool = false) throws {
        guard !id.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        if hard {
            try db.run(Self.annotations.filter(Self.aId == id).delete())
        } else {
            let now = Self.iso8601.string(from: Date())
            try db.run(Self.annotations.filter(Self.aId == id).update(
                Self.aIsDeleted <- true,
                Self.aModifiedDate <- now
            ))
        }
    }

    func annotationsModifiedSince(_ sinceDate: String) throws -> [Pedef_AnnotationDTO] {
        dbLock.lock()
        defer { dbLock.unlock() }
        return try db.prepare(Self.annotations.filter(Self.aModifiedDate > sinceDate)).map { annotationFromRow($0) }
    }

    private func annotationFromRow(_ row: Row) -> Pedef_AnnotationDTO {
        var a = Pedef_AnnotationDTO()
        a.id = row[Self.aId]
        a.paperID = row[Self.aPaperId]
        a.type = Pedef_AnnotationType(rawValue: row[Self.aType]) ?? .unspecified
        a.colorHex = row[Self.aColorHex] ?? ""
        a.pageIndex = Int32(row[Self.aPageIndex])
        var rect = Pedef_Rect()
        rect.x = row[Self.aBoundsX]
        rect.y = row[Self.aBoundsY]
        rect.width = row[Self.aBoundsW]
        rect.height = row[Self.aBoundsH]
        a.bounds = rect
        a.selectedText = row[Self.aSelectedText] ?? ""
        a.noteContent = row[Self.aNoteContent] ?? ""
        if let blob = row[Self.aDrawingData] {
            a.drawingData = Data(blob.bytes)
        }
        a.tags = Self.decodeJSONArray(row[Self.aTags])
        if let ts = Self.stringToTimestamp(row[Self.aCreatedDate]) {
            a.createdDate = ts
        }
        if let ts = Self.stringToTimestamp(row[Self.aModifiedDate]) {
            a.modifiedDate = ts
        }
        a.isDeleted = row[Self.aIsDeleted]
        return a
    }
}

// MARK: - Collection CRUD

extension SQLiteStore {

    func upsertCollection(_ c: Pedef_CollectionDTO) throws {
        guard !c.id.isEmpty else { throw StorageError.invalidID }
        let rules: SQLite.Blob? = c.smartRulesData.isEmpty ? nil : SQLite.Blob(bytes: [UInt8](c.smartRulesData))
        dbLock.lock()
        defer { dbLock.unlock() }
        try db.run(Self.collections.insert(or: .replace,
            Self.cId <- c.id,
            Self.cName <- c.name,
            Self.cType <- c.type.rawValue,
            Self.cColorHex <- (c.colorHex.isEmpty ? nil : c.colorHex),
            Self.cIconName <- (c.iconName.isEmpty ? nil : c.iconName),
            Self.cParentId <- (c.parentID.isEmpty ? nil : c.parentID),
            Self.cPaperIds <- Self.encodeJSONArray(c.paperIds),
            Self.cSmartRulesData <- rules,
            Self.cNotes <- (c.notes.isEmpty ? nil : c.notes),
            Self.cSortOrder <- Int(c.sortOrder),
            Self.cCreatedDate <- (c.hasCreatedDate ? Self.timestampToString(c.createdDate) : Self.iso8601.string(from: Date())),
            Self.cModifiedDate <- (c.hasModifiedDate ? Self.timestampToString(c.modifiedDate) : Self.iso8601.string(from: Date())),
            Self.cIsDeleted <- c.isDeleted
        ))
    }

    func getCollection(id: String) throws -> Pedef_CollectionDTO? {
        guard !id.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let row = try db.pluck(Self.collections.filter(Self.cId == id)) else { return nil }
        return collectionFromRow(row)
    }

    func listCollections(includeDeleted: Bool = false) throws -> [Pedef_CollectionDTO] {
        dbLock.lock()
        defer { dbLock.unlock() }
        let query = includeDeleted ? Self.collections : Self.collections.filter(Self.cIsDeleted == false)
        return try db.prepare(query).map { collectionFromRow($0) }
    }

    func deleteCollection(id: String, hard: Bool = false) throws {
        guard !id.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        if hard {
            try db.run(Self.collections.filter(Self.cId == id).delete())
        } else {
            let now = Self.iso8601.string(from: Date())
            try db.run(Self.collections.filter(Self.cId == id).update(
                Self.cIsDeleted <- true,
                Self.cModifiedDate <- now
            ))
        }
    }

    func collectionsModifiedSince(_ sinceDate: String) throws -> [Pedef_CollectionDTO] {
        dbLock.lock()
        defer { dbLock.unlock() }
        return try db.prepare(Self.collections.filter(Self.cModifiedDate > sinceDate)).map { collectionFromRow($0) }
    }

    private func collectionFromRow(_ row: Row) -> Pedef_CollectionDTO {
        var c = Pedef_CollectionDTO()
        c.id = row[Self.cId]
        c.name = row[Self.cName]
        c.type = Pedef_CollectionType(rawValue: row[Self.cType]) ?? .unspecified
        c.colorHex = row[Self.cColorHex] ?? ""
        c.iconName = row[Self.cIconName] ?? ""
        c.parentID = row[Self.cParentId] ?? ""
        c.paperIds = Self.decodeJSONArray(row[Self.cPaperIds])
        if let blob = row[Self.cSmartRulesData] {
            c.smartRulesData = Data(blob.bytes)
        }
        c.notes = row[Self.cNotes] ?? ""
        c.sortOrder = Int32(row[Self.cSortOrder])
        if let ts = Self.stringToTimestamp(row[Self.cCreatedDate]) {
            c.createdDate = ts
        }
        if let ts = Self.stringToTimestamp(row[Self.cModifiedDate]) {
            c.modifiedDate = ts
        }
        c.isDeleted = row[Self.cIsDeleted]
        return c
    }
}

// MARK: - Tag CRUD

extension SQLiteStore {

    func upsertTag(_ t: Pedef_TagDTO) throws {
        guard !t.id.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        try db.run(Self.tags.insert(or: .replace,
            Self.tId <- t.id,
            Self.tName <- t.name,
            Self.tColorHex <- (t.colorHex.isEmpty ? nil : t.colorHex),
            Self.tUsageCount <- Int(t.usageCount),
            Self.tCreatedDate <- (t.hasCreatedDate ? Self.timestampToString(t.createdDate) : Self.iso8601.string(from: Date())),
            Self.tModifiedDate <- Self.iso8601.string(from: Date()),
            Self.tPaperIds <- Self.encodeJSONArray(t.paperIds),
            Self.tIsDeleted <- t.isDeleted
        ))
    }

    func getTag(id: String) throws -> Pedef_TagDTO? {
        guard !id.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let row = try db.pluck(Self.tags.filter(Self.tId == id)) else { return nil }
        return tagFromRow(row)
    }

    func listTags(includeDeleted: Bool = false) throws -> [Pedef_TagDTO] {
        dbLock.lock()
        defer { dbLock.unlock() }
        let query = includeDeleted ? Self.tags : Self.tags.filter(Self.tIsDeleted == false)
        return try db.prepare(query).map { tagFromRow($0) }
    }

    func deleteTag(id: String, hard: Bool = false) throws {
        guard !id.isEmpty else { throw StorageError.invalidID }
        dbLock.lock()
        defer { dbLock.unlock() }
        if hard {
            try db.run(Self.tags.filter(Self.tId == id).delete())
        } else {
            let now = Self.iso8601.string(from: Date())
            try db.run(Self.tags.filter(Self.tId == id).update(
                Self.tIsDeleted <- true,
                Self.tModifiedDate <- now
            ))
        }
    }

    func tagsModifiedSince(_ sinceDate: String) throws -> [Pedef_TagDTO] {
        dbLock.lock()
        defer { dbLock.unlock() }
        return try db.prepare(Self.tags.filter(Self.tModifiedDate > sinceDate)).map { tagFromRow($0) }
    }

    private func tagFromRow(_ row: Row) -> Pedef_TagDTO {
        var t = Pedef_TagDTO()
        t.id = row[Self.tId]
        t.name = row[Self.tName]
        t.colorHex = row[Self.tColorHex] ?? ""
        t.usageCount = Int32(row[Self.tUsageCount])
        if let ts = Self.stringToTimestamp(row[Self.tCreatedDate]) {
            t.createdDate = ts
        }
        t.paperIds = Self.decodeJSONArray(row[Self.tPaperIds])
        t.isDeleted = row[Self.tIsDeleted]
        return t
    }
}

// MARK: - Purge

extension SQLiteStore {

    /// Hard-delete all soft-deleted records older than `beforeDate` (ISO 8601).
    func purgeDeletedBefore(date: String) throws {
        dbLock.lock()
        defer { dbLock.unlock() }
        try db.run(Self.papers.filter(Self.pIsDeleted == true && Self.pModifiedDate < date).delete())
        try db.run(Self.annotations.filter(Self.aIsDeleted == true && Self.aModifiedDate < date).delete())
        try db.run(Self.collections.filter(Self.cIsDeleted == true && Self.cModifiedDate < date).delete())
        try db.run(Self.tags.filter(Self.tIsDeleted == true && Self.tModifiedDate < date).delete())
    }
}

// MARK: - Error Types

enum StorageError: Error {
    case invalidID
}
