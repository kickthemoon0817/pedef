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
    static let predefinedColors: [String] = [
        "#FF6B6B",  // Red
        "#4ECDC4",  // Teal
        "#45B7D1",  // Blue
        "#96CEB4",  // Green
        "#FFEAA7",  // Yellow
        "#DDA0DD",  // Plum
        "#98D8C8",  // Mint
        "#F7DC6F",  // Gold
        "#BB8FCE",  // Purple
        "#85C1E9",  // Sky
    ]

    static func randomColor() -> String {
        predefinedColors.randomElement() ?? "#007AFF"
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
        case .toRead: return "#45B7D1"
        case .reading: return "#F7DC6F"
        case .finished: return "#96CEB4"
        case .important: return "#FF6B6B"
        case .reference: return "#BB8FCE"
        case .review: return "#4ECDC4"
        case .methodology: return "#85C1E9"
        case .theory: return "#DDA0DD"
        case .empirical: return "#98D8C8"
        case .metaAnalysis: return "#FFEAA7"
        }
    }
}
