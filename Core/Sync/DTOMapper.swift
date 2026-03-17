import Foundation
import SwiftProtobuf

// MARK: - DTOMapper

/// Bidirectional mapper between SwiftData models and protobuf DTOs used by the gRPC sync layer.
enum DTOMapper {

    // MARK: - Timestamp Helpers

    static func toTimestamp(_ date: Date) -> Google_Protobuf_Timestamp {
        return Google_Protobuf_Timestamp(date: date)
    }

    static func fromTimestamp(_ ts: Google_Protobuf_Timestamp) -> Date {
        return ts.date
    }

    // MARK: - AnnotationType Mapping

    static func toProto(_ type: AnnotationType) -> Pedef_AnnotationType {
        switch type {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        case .textNote: return .textNote
        case .stickyNote: return .stickyNote
        case .freehandDrawing: return .freehandDrawing
        case .shape: return .shape
        case .bookmark: return .bookmark
        }
    }

    static func fromProto(_ type: Pedef_AnnotationType) -> AnnotationType {
        switch type {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        case .textNote: return .textNote
        case .stickyNote: return .stickyNote
        case .freehandDrawing: return .freehandDrawing
        case .shape: return .shape
        case .bookmark: return .bookmark
        case .unspecified, .UNRECOGNIZED: return .highlight
        }
    }

    // MARK: - CollectionType Mapping

    static func toProto(_ type: CollectionType) -> Pedef_CollectionType {
        switch type {
        case .folder: return .folder
        case .smartFolder: return .smartFolder
        case .readingList: return .readingList
        case .favorites: return .favorites
        }
    }

    static func fromProto(_ type: Pedef_CollectionType) -> CollectionType {
        switch type {
        case .folder: return .folder
        case .smartFolder: return .smartFolder
        case .readingList: return .readingList
        case .favorites: return .favorites
        case .unspecified, .UNRECOGNIZED: return .folder
        }
    }

    // MARK: - Paper → Proto

    static func toProto(_ paper: Paper) -> Pedef_PaperMetadata {
        var dto = Pedef_PaperMetadata()
        dto.id = paper.id.uuidString
        dto.title = paper.title
        dto.authors = paper.authors
        dto.abstract = paper.abstract ?? ""
        dto.doi = paper.doi ?? ""
        dto.arxivID = paper.arxivId ?? ""
        if let date = paper.publishedDate {
            dto.publishedDate = toTimestamp(date)
        }
        dto.journal = paper.journal ?? ""
        dto.volume = paper.volume ?? ""
        dto.issue = paper.issue ?? ""
        dto.pages = paper.pages ?? ""
        dto.keywords = paper.keywords
        dto.pageCount = Int32(paper.pageCount)
        dto.fileSize = paper.fileSize
        dto.readingProgress = paper.readingProgress
        dto.currentPage = Int32(paper.currentPage)
        if let date = paper.lastOpenedDate {
            dto.lastOpenedDate = toTimestamp(date)
        }
        dto.totalReadingTime = paper.totalReadingTime
        dto.importedDate = toTimestamp(paper.importedDate)
        dto.modifiedDate = toTimestamp(paper.modifiedDate)
        dto.customMetadata = paper.customMetadata
        dto.tagIds = paper.tagObjects.map { $0.id.uuidString }
        dto.collectionIds = paper.collections.map { $0.id.uuidString }
        return dto
    }

    // MARK: - Proto → Paper (update existing)

    static func updatePaper(_ paper: Paper, from dto: Pedef_PaperMetadata) {
        paper.title = dto.title
        paper.authors = dto.authors
        paper.abstract = dto.abstract.isEmpty ? nil : dto.abstract
        paper.doi = dto.doi.isEmpty ? nil : dto.doi
        paper.arxivId = dto.arxivID.isEmpty ? nil : dto.arxivID
        paper.publishedDate = dto.hasPublishedDate ? fromTimestamp(dto.publishedDate) : nil
        paper.journal = dto.journal.isEmpty ? nil : dto.journal
        paper.volume = dto.volume.isEmpty ? nil : dto.volume
        paper.issue = dto.issue.isEmpty ? nil : dto.issue
        paper.pages = dto.pages.isEmpty ? nil : dto.pages
        paper.keywords = dto.keywords
        paper.pageCount = Int(dto.pageCount)
        paper.fileSize = dto.fileSize
        paper.readingProgress = dto.readingProgress
        paper.currentPage = Int(dto.currentPage)
        paper.lastOpenedDate = dto.hasLastOpenedDate ? fromTimestamp(dto.lastOpenedDate) : nil
        paper.totalReadingTime = dto.totalReadingTime
        paper.importedDate = fromTimestamp(dto.importedDate)
        paper.modifiedDate = fromTimestamp(dto.modifiedDate)
        paper.customMetadata = dto.customMetadata
    }

    /// Creates a new Paper from a protobuf DTO (for inserts).
    static func makePaper(from dto: Pedef_PaperMetadata) -> Paper {
        let paper = Paper(
            title: dto.title,
            authors: dto.authors,
            pdfData: Data(),
            pageCount: Int(dto.pageCount)
        )
        paper.id = UUID(uuidString: dto.id) ?? UUID()
        updatePaper(paper, from: dto)
        return paper
    }

    // MARK: - Annotation → Proto

    static func toProto(_ annotation: Annotation) -> Pedef_AnnotationDTO {
        var dto = Pedef_AnnotationDTO()
        dto.id = annotation.id.uuidString
        dto.paperID = annotation.paper?.id.uuidString ?? ""
        dto.type = toProto(annotation.type)
        dto.colorHex = annotation.colorHex
        dto.pageIndex = Int32(annotation.pageIndex)

        var rect = Pedef_Rect()
        rect.x = annotation.boundsX
        rect.y = annotation.boundsY
        rect.width = annotation.boundsWidth
        rect.height = annotation.boundsHeight
        dto.bounds = rect

        dto.selectedText = annotation.selectedText ?? ""
        dto.noteContent = annotation.noteContent ?? ""
        if let drawingData = annotation.drawingData {
            dto.drawingData = drawingData
        }
        dto.tags = annotation.tags
        dto.createdDate = toTimestamp(annotation.createdDate)
        dto.modifiedDate = toTimestamp(annotation.modifiedDate)
        return dto
    }

    // MARK: - Proto → Annotation (update existing)

    static func updateAnnotation(_ annotation: Annotation, from dto: Pedef_AnnotationDTO) {
        annotation.typeRawValue = fromProto(dto.type).rawValue
        annotation.colorHex = dto.colorHex
        annotation.pageIndex = Int(dto.pageIndex)
        annotation.boundsX = dto.bounds.x
        annotation.boundsY = dto.bounds.y
        annotation.boundsWidth = dto.bounds.width
        annotation.boundsHeight = dto.bounds.height
        annotation.selectedText = dto.selectedText.isEmpty ? nil : dto.selectedText
        annotation.noteContent = dto.noteContent.isEmpty ? nil : dto.noteContent
        annotation.drawingData = dto.drawingData.isEmpty ? nil : dto.drawingData
        annotation.tags = dto.tags
        annotation.createdDate = fromTimestamp(dto.createdDate)
        annotation.modifiedDate = fromTimestamp(dto.modifiedDate)
    }

    /// Creates a new Annotation from a protobuf DTO.
    static func makeAnnotation(from dto: Pedef_AnnotationDTO) -> Annotation {
        let annotation = Annotation(
            type: fromProto(dto.type),
            pageIndex: Int(dto.pageIndex),
            bounds: CGRect(
                x: dto.bounds.x,
                y: dto.bounds.y,
                width: dto.bounds.width,
                height: dto.bounds.height
            ),
            color: AnnotationColor(rawValue: dto.colorHex) ?? .yellow
        )
        annotation.id = UUID(uuidString: dto.id) ?? UUID()
        updateAnnotation(annotation, from: dto)
        return annotation
    }

    // MARK: - Collection → Proto

    static func toProto(_ collection: Collection) -> Pedef_CollectionDTO {
        var dto = Pedef_CollectionDTO()
        dto.id = collection.id.uuidString
        dto.name = collection.name
        dto.type = toProto(collection.type)
        dto.colorHex = collection.colorHex ?? ""
        dto.iconName = collection.iconName ?? ""
        dto.parentID = collection.parent?.id.uuidString ?? ""
        dto.paperIds = collection.papers.map { $0.id.uuidString }
        if let data = collection.smartRulesData {
            dto.smartRulesData = data
        }
        dto.notes = collection.notes ?? ""
        dto.sortOrder = Int32(collection.sortOrder)
        dto.createdDate = toTimestamp(collection.createdDate)
        dto.modifiedDate = toTimestamp(collection.modifiedDate)
        return dto
    }

    // MARK: - Proto → Collection (update existing)

    static func updateCollection(_ collection: Collection, from dto: Pedef_CollectionDTO) {
        collection.name = dto.name
        collection.typeRawValue = fromProto(dto.type).rawValue
        collection.colorHex = dto.colorHex.isEmpty ? nil : dto.colorHex
        collection.iconName = dto.iconName.isEmpty ? nil : dto.iconName
        collection.smartRulesData = dto.smartRulesData.isEmpty ? nil : dto.smartRulesData
        collection.notes = dto.notes.isEmpty ? nil : dto.notes
        collection.sortOrder = Int(dto.sortOrder)
        collection.createdDate = fromTimestamp(dto.createdDate)
        collection.modifiedDate = fromTimestamp(dto.modifiedDate)
    }

    /// Creates a new Collection from a protobuf DTO.
    static func makeCollection(from dto: Pedef_CollectionDTO) -> Collection {
        let collection = Collection(
            name: dto.name,
            type: fromProto(dto.type)
        )
        collection.id = UUID(uuidString: dto.id) ?? UUID()
        updateCollection(collection, from: dto)
        return collection
    }

    // MARK: - Tag → Proto

    static func toProto(_ tag: Tag) -> Pedef_TagDTO {
        var dto = Pedef_TagDTO()
        dto.id = tag.id.uuidString
        dto.name = tag.name
        dto.colorHex = tag.colorHex
        dto.createdDate = toTimestamp(tag.createdDate)
        dto.usageCount = Int32(tag.usageCount)
        dto.paperIds = tag.papers.map { $0.id.uuidString }
        return dto
    }

    // MARK: - Proto → Tag (update existing)

    static func updateTag(_ tag: Tag, from dto: Pedef_TagDTO) {
        tag.name = dto.name
        tag.colorHex = dto.colorHex
        tag.createdDate = fromTimestamp(dto.createdDate)
        tag.usageCount = Int(dto.usageCount)
    }

    /// Creates a new Tag from a protobuf DTO.
    static func makeTag(from dto: Pedef_TagDTO) -> Tag {
        let tag = Tag(name: dto.name, colorHex: dto.colorHex)
        tag.id = UUID(uuidString: dto.id) ?? UUID()
        updateTag(tag, from: dto)
        return tag
    }
}

