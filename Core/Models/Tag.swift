import Foundation
import SwiftData

/// Represents a tag for organizing and categorizing papers
@Model
final class Tag {
    // MARK: - Identity

    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String

    // MARK: - Metadata

    var createdDate: Date
    var usageCount: Int

    // MARK: - Relationships

    @Relationship(inverse: \Paper.tagObjects)
    var papers: [Paper]

    // MARK: - Initialization

    init(name: String, colorHex: String = "#007AFF") {
        self.id = UUID()
        self.name = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorHex = colorHex
        self.createdDate = Date()
        self.usageCount = 0
        self.papers = []
    }
}

// MARK: - Predefined Tags

extension Tag {
    static let predefinedColors: [String] = PedefTheme.TagPalette.colors

    static func randomColor() -> String {
        predefinedColors.randomElement() ?? "#2D3561"
    }
}

// MARK: - Tag Suggestions

enum TagSuggestion: String, CaseIterable {
    case toRead = "to-read"
    case reading = "reading"
    case finished = "finished"
    case important = "important"
    case reference = "reference"
    case review = "review"
    case methodology = "methodology"
    case theory = "theory"
    case empirical = "empirical"
    case metaAnalysis = "meta-analysis"

    var displayName: String {
        rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var color: String {
        switch self {
        case .toRead: return "#3B82F6"       // Blue
        case .reading: return "#EAB308"      // Yellow
        case .finished: return "#22C55E"     // Green
        case .important: return "#F43F5E"    // Rose
        case .reference: return "#8B5CF6"    // Violet
        case .review: return "#14B8A6"       // Teal
        case .methodology: return "#6366F1"  // Indigo
        case .theory: return "#EC4899"       // Pink
        case .empirical: return "#F97316"    // Orange
        case .metaAnalysis: return "#EF4444" // Red
        }
    }
}
