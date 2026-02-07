import Foundation
import SwiftData
import CoreGraphics

/// Types of annotations that can be added to papers
enum AnnotationType: String, Codable, CaseIterable {
    case highlight
    case underline
    case strikethrough
    case textNote
    case stickyNote
    case freehandDrawing
    case shape
    case bookmark

    var displayName: String {
        switch self {
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .textNote: return "Text Note"
        case .stickyNote: return "Sticky Note"
        case .freehandDrawing: return "Drawing"
        case .shape: return "Shape"
        case .bookmark: return "Bookmark"
        }
    }

    var systemImage: String {
        switch self {
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        case .textNote: return "text.bubble"
        case .stickyNote: return "note.text"
        case .freehandDrawing: return "pencil.tip"
        case .shape: return "square.on.circle"
        case .bookmark: return "bookmark.fill"
        }
    }
}

/// Predefined annotation colors
enum AnnotationColor: String, Codable, CaseIterable {
    case yellow = "#F5C842"
    case green = "#34D399"
    case blue = "#60A5FA"
    case pink = "#F472B6"
    case purple = "#A78BFA"
    case orange = "#FB923C"
    case red = "#F87171"

    var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .orange: return "Orange"
        case .red: return "Red"
        }
    }
}

/// Represents an annotation on a paper
@Model
final class Annotation {
    // MARK: - Identity

    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var colorHex: String

    // MARK: - Location

    var pageIndex: Int
    var boundsX: Double
    var boundsY: Double
    var boundsWidth: Double
    var boundsHeight: Double

    // MARK: - Content

    var selectedText: String?  // For text-based annotations
    var noteContent: String?   // User's note/comment
    var drawingData: Data?     // Serialized drawing paths

    // MARK: - Organization

    var tags: [String]

    // MARK: - Relationship

    var paper: Paper?

    // MARK: - Timestamps

    var createdDate: Date
    var modifiedDate: Date

    // MARK: - Initialization

    init(
        type: AnnotationType,
        pageIndex: Int,
        bounds: CGRect,
        color: AnnotationColor = .yellow
    ) {
        self.id = UUID()
        self.typeRawValue = type.rawValue
        self.colorHex = color.rawValue
        self.pageIndex = pageIndex
        self.boundsX = bounds.origin.x
        self.boundsY = bounds.origin.y
        self.boundsWidth = bounds.width
        self.boundsHeight = bounds.height
        self.selectedText = nil
        self.noteContent = nil
        self.drawingData = nil
        self.tags = []
        self.paper = nil
        self.createdDate = Date()
        self.modifiedDate = Date()
    }
}

// MARK: - Computed Properties

extension Annotation {
    var type: AnnotationType {
        get { AnnotationType(rawValue: typeRawValue) ?? .highlight }
        set { typeRawValue = newValue.rawValue }
    }

    var bounds: CGRect {
        get {
            CGRect(x: boundsX, y: boundsY, width: boundsWidth, height: boundsHeight)
        }
        set {
            boundsX = newValue.origin.x
            boundsY = newValue.origin.y
            boundsWidth = newValue.width
            boundsHeight = newValue.height
        }
    }

    var hasNote: Bool {
        noteContent != nil && !noteContent!.isEmpty
    }

    var displayText: String {
        if let note = noteContent, !note.isEmpty {
            return note
        }
        if let selected = selectedText, !selected.isEmpty {
            return selected
        }
        return type.displayName
    }
}

// MARK: - Sorting

extension Annotation {
    static func sortByPosition(_ annotations: [Annotation]) -> [Annotation] {
        annotations.sorted { a, b in
            if a.pageIndex != b.pageIndex {
                return a.pageIndex < b.pageIndex
            }
            if a.boundsY != b.boundsY {
                return a.boundsY < b.boundsY
            }
            return a.boundsX < b.boundsX
        }
    }
}
