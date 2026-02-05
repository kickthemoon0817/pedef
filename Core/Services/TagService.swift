import Foundation
import SwiftData
import OSLog

/// Service for managing tags and paper-tag relationships
@MainActor
final class TagService: ObservableObject {
    private var modelContext: ModelContext?
    private let logger = Logger(subsystem: "com.pedef.app", category: "tag-service")

    @Published var allTags: [Tag] = []
    @Published var recentTags: [Tag] = []
    @Published var popularTags: [Tag] = []

    // MARK: - Configuration

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshTags()
    }

    // MARK: - Tag CRUD Operations

    /// Creates a new tag with the given name and optional color
    @discardableResult
    func createTag(name: String, colorHex: String? = nil) throws -> Tag {
        guard let modelContext else {
            throw TagServiceError.notConfigured
        }

        // Validate tag name
        if let validationError = ValidationHelper.validateTagName(name) {
            throw TagServiceError.validationFailed(validationError)
        }

        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if tag already exists
        if let existingTag = findTag(named: normalizedName) {
            return existingTag
        }

        let tag = Tag(name: normalizedName, colorHex: colorHex ?? Tag.randomColor())
        modelContext.insert(tag)
        try modelContext.save()

        refreshTags()
        return tag
    }

    /// Deletes a tag and removes it from all papers
    func deleteTag(_ tag: Tag) throws {
        guard let modelContext else {
            throw TagServiceError.notConfigured
        }

        modelContext.delete(tag)
        try modelContext.save()
        refreshTags()
    }

    /// Updates a tag's name or color
    func updateTag(_ tag: Tag, name: String? = nil, colorHex: String? = nil) throws {
        guard let modelContext else {
            throw TagServiceError.notConfigured
        }

        if let name {
            tag.name = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let colorHex {
            tag.colorHex = colorHex
        }

        try modelContext.save()
        refreshTags()
    }

    // MARK: - Tag Lookup

    /// Finds a tag by its name (case-insensitive)
    func findTag(named name: String) -> Tag? {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return allTags.first { $0.name == normalizedName }
    }

    /// Finds tags matching a search query
    func searchTags(matching query: String) -> [Tag] {
        guard !query.isEmpty else { return allTags }
        let lowercasedQuery = query.lowercased()
        return allTags.filter { $0.name.contains(lowercasedQuery) }
    }

    // MARK: - Paper-Tag Operations

    /// Adds a tag to a paper
    func addTag(_ tag: Tag, to paper: Paper) throws {
        guard let modelContext else {
            throw TagServiceError.notConfigured
        }

        guard !paper.tagObjects.contains(where: { $0.id == tag.id }) else {
            return // Already has this tag
        }

        paper.tagObjects.append(tag)
        tag.usageCount += 1
        paper.modifiedDate = Date()

        try modelContext.save()
        refreshTags()
    }

    /// Removes a tag from a paper
    func removeTag(_ tag: Tag, from paper: Paper) throws {
        guard let modelContext else {
            throw TagServiceError.notConfigured
        }

        paper.tagObjects.removeAll { $0.id == tag.id }
        tag.usageCount = max(0, tag.usageCount - 1)
        paper.modifiedDate = Date()

        try modelContext.save()
        refreshTags()
    }

    /// Creates a new tag and adds it to a paper in one operation
    @discardableResult
    func addNewTag(named name: String, to paper: Paper, colorHex: String? = nil) throws -> Tag {
        let tag = try createTag(name: name, colorHex: colorHex)
        try addTag(tag, to: paper)
        return tag
    }

    /// Gets all papers with a specific tag
    func papers(with tag: Tag) -> [Paper] {
        return tag.papers.sorted { ($0.lastOpenedDate ?? .distantPast) > ($1.lastOpenedDate ?? .distantPast) }
    }

    // MARK: - Bulk Operations

    /// Adds multiple tags to a paper
    func addTags(_ tags: [Tag], to paper: Paper) throws {
        for tag in tags {
            try addTag(tag, to: paper)
        }
    }

    /// Removes all tags from a paper
    func removeAllTags(from paper: Paper) throws {
        guard let modelContext else {
            throw TagServiceError.notConfigured
        }

        for tag in paper.tagObjects {
            tag.usageCount = max(0, tag.usageCount - 1)
        }
        paper.tagObjects.removeAll()
        paper.modifiedDate = Date()

        try modelContext.save()
        refreshTags()
    }

    /// Sets the tags for a paper (replaces existing tags)
    func setTags(_ tags: [Tag], for paper: Paper) throws {
        try removeAllTags(from: paper)
        try addTags(tags, to: paper)
    }

    // MARK: - Tag Suggestions

    /// Gets suggested tags based on existing tags and paper content
    func suggestedTags(for paper: Paper) -> [TagSuggestion] {
        let existingTagNames = Set(paper.tagNames)
        return TagSuggestion.allCases.filter { !existingTagNames.contains($0.rawValue) }
    }

    /// Creates suggested tags that don't exist yet
    func createSuggestedTag(_ suggestion: TagSuggestion) throws -> Tag {
        return try createTag(name: suggestion.rawValue, colorHex: suggestion.color)
    }

    // MARK: - Statistics

    /// Gets tags sorted by usage count
    func tagsByUsage() -> [Tag] {
        allTags.sorted { $0.usageCount > $1.usageCount }
    }

    /// Gets tags sorted by creation date (newest first)
    func tagsByDate() -> [Tag] {
        allTags.sorted { $0.createdDate > $1.createdDate }
    }

    /// Gets the most used tags (top N)
    func topTags(limit: Int = 10) -> [Tag] {
        Array(tagsByUsage().prefix(limit))
    }

    // MARK: - Private Methods

    private func refreshTags() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)])

        do {
            allTags = try modelContext.fetch(descriptor)
            popularTags = topTags(limit: 5)
            recentTags = Array(tagsByDate().prefix(5))
        } catch {
            logger.error("Failed to fetch tags: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum TagServiceError: LocalizedError {
    case notConfigured
    case invalidTagName
    case tagNotFound
    case tagAlreadyExists
    case validationFailed(ValidationError)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Tag service is not configured with a model context"
        case .invalidTagName:
            return "Tag name cannot be empty"
        case .tagNotFound:
            return "Tag not found"
        case .tagAlreadyExists:
            return "A tag with this name already exists"
        case .validationFailed(let error):
            return error.errorDescription
        }
    }
}
