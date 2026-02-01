import Foundation
import SwiftData

/// Types of actions that can be tracked in history
enum ActionType: String, Codable, CaseIterable {
    // Document actions
    case openPaper
    case closePaper
    case navigatePage
    case scrollPage
    case zoom
    case search

    // Annotation actions
    case createHighlight
    case createNote
    case createBookmark
    case createDrawing
    case editAnnotation
    case deleteAnnotation
    case moveAnnotation

    // Library actions
    case importPaper
    case deletePaper
    case movePaper
    case createCollection
    case deleteCollection
    case addToCollection
    case removeFromCollection
    case addTag
    case removeTag

    // Agent actions
    case agentQuery
    case agentSuggestionAccepted
    case agentSuggestionRejected

    // Session actions
    case sessionStart
    case sessionEnd

    var category: ActionCategory {
        switch self {
        case .openPaper, .closePaper, .navigatePage, .scrollPage, .zoom, .search:
            return .reading
        case .createHighlight, .createNote, .createBookmark, .createDrawing,
             .editAnnotation, .deleteAnnotation, .moveAnnotation:
            return .annotation
        case .importPaper, .deletePaper, .movePaper, .createCollection,
             .deleteCollection, .addToCollection, .removeFromCollection,
             .addTag, .removeTag:
            return .library
        case .agentQuery, .agentSuggestionAccepted, .agentSuggestionRejected:
            return .agent
        case .sessionStart, .sessionEnd:
            return .session
        }
    }

    var displayName: String {
        switch self {
        case .openPaper: return "Opened paper"
        case .closePaper: return "Closed paper"
        case .navigatePage: return "Navigated to page"
        case .scrollPage: return "Scrolled"
        case .zoom: return "Zoomed"
        case .search: return "Searched"
        case .createHighlight: return "Created highlight"
        case .createNote: return "Created note"
        case .createBookmark: return "Created bookmark"
        case .createDrawing: return "Created drawing"
        case .editAnnotation: return "Edited annotation"
        case .deleteAnnotation: return "Deleted annotation"
        case .moveAnnotation: return "Moved annotation"
        case .importPaper: return "Imported paper"
        case .deletePaper: return "Deleted paper"
        case .movePaper: return "Moved paper"
        case .createCollection: return "Created collection"
        case .deleteCollection: return "Deleted collection"
        case .addToCollection: return "Added to collection"
        case .removeFromCollection: return "Removed from collection"
        case .addTag: return "Added tag"
        case .removeTag: return "Removed tag"
        case .agentQuery: return "Asked AI agent"
        case .agentSuggestionAccepted: return "Accepted AI suggestion"
        case .agentSuggestionRejected: return "Rejected AI suggestion"
        case .sessionStart: return "Session started"
        case .sessionEnd: return "Session ended"
        }
    }

    var isUndoable: Bool {
        switch self {
        case .openPaper, .closePaper, .navigatePage, .scrollPage, .zoom, .search,
             .sessionStart, .sessionEnd, .agentQuery:
            return false
        default:
            return true
        }
    }
}

enum ActionCategory: String, Codable {
    case reading
    case annotation
    case library
    case agent
    case session

    var displayName: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .reading: return "book"
        case .annotation: return "pencil"
        case .library: return "folder"
        case .agent: return "sparkles"
        case .session: return "clock"
        }
    }
}

/// Represents a single action in the user's history
@Model
final class ActionHistory {
    // MARK: - Identity

    @Attribute(.unique) var id: UUID
    var actionTypeRawValue: String

    // MARK: - Context

    var paperId: UUID?
    var annotationId: UUID?
    var collectionId: UUID?
    var sessionId: UUID

    // MARK: - Details

    /// JSON-encoded action-specific details
    var detailsData: Data?

    /// JSON-encoded data needed to undo this action
    @Attribute(.externalStorage) var undoData: Data?

    // MARK: - Timestamps

    var timestamp: Date
    var duration: TimeInterval?  // For actions with duration (e.g., reading time)

    // MARK: - Initialization

    init(
        type: ActionType,
        sessionId: UUID,
        paperId: UUID? = nil,
        annotationId: UUID? = nil,
        collectionId: UUID? = nil
    ) {
        self.id = UUID()
        self.actionTypeRawValue = type.rawValue
        self.sessionId = sessionId
        self.paperId = paperId
        self.annotationId = annotationId
        self.collectionId = collectionId
        self.detailsData = nil
        self.undoData = nil
        self.timestamp = Date()
        self.duration = nil
    }
}

// MARK: - Computed Properties

extension ActionHistory {
    var actionType: ActionType {
        get { ActionType(rawValue: actionTypeRawValue) ?? .openPaper }
        set { actionTypeRawValue = newValue.rawValue }
    }

    var category: ActionCategory {
        actionType.category
    }

    var isUndoable: Bool {
        actionType.isUndoable && undoData != nil
    }
}

// MARK: - Details Encoding

extension ActionHistory {
    func setDetails<T: Encodable>(_ details: T) {
        detailsData = try? JSONEncoder().encode(details)
    }

    func getDetails<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = detailsData else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func setUndoData<T: Encodable>(_ data: T) {
        undoData = try? JSONEncoder().encode(data)
    }

    func getUndoData<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = undoData else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Action Details Types

struct PageNavigationDetails: Codable {
    var fromPage: Int
    var toPage: Int
}

struct ZoomDetails: Codable {
    var fromScale: Double
    var toScale: Double
}

struct SearchDetails: Codable {
    var query: String
    var resultsCount: Int
}

struct AnnotationDetails: Codable {
    var pageIndex: Int
    var annotationType: String
    var selectedText: String?
}

struct AgentQueryDetails: Codable {
    var agentName: String
    var query: String
    var responsePreview: String?
}

// MARK: - Reading Session

@Model
final class ReadingSession {
    @Attribute(.unique) var id: UUID
    var startTime: Date
    var endTime: Date?
    var papersOpened: [UUID]
    var totalActions: Int
    var deviceInfo: String?

    init() {
        self.id = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.papersOpened = []
        self.totalActions = 0
        self.deviceInfo = nil
    }

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var isActive: Bool {
        endTime == nil
    }
}
