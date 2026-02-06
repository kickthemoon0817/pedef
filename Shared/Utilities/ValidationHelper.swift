import Foundation

/// Helper for validating user inputs throughout the app
enum ValidationHelper {

    // MARK: - Tag Validation

    /// Maximum length for tag names
    static let maxTagLength = 50

    /// Characters not allowed in tag names
    static let forbiddenTagCharacters = CharacterSet(charactersIn: "<>\"'\\`|")

    /// Validate a tag name and return any error
    static func validateTagName(_ name: String) -> ValidationError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .emptyInput(field: "tag name")
        }

        if trimmed.count > maxTagLength {
            return .tooLong(field: "tag name", maxLength: maxTagLength)
        }

        if trimmed.rangeOfCharacter(from: forbiddenTagCharacters) != nil {
            return .invalidCharacters(field: "tag name")
        }

        // Check for reserved names
        let reserved = ["favorite", "favorites", "all", "unread", "recent"]
        if reserved.contains(trimmed.lowercased()) {
            return .reservedName(name: trimmed)
        }

        return nil
    }

    // MARK: - Collection Validation

    /// Maximum length for collection names
    static let maxCollectionNameLength = 100

    /// Validate a collection name
    static func validateCollectionName(_ name: String) -> ValidationError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .emptyInput(field: "collection name")
        }

        if trimmed.count > maxCollectionNameLength {
            return .tooLong(field: "collection name", maxLength: maxCollectionNameLength)
        }

        return nil
    }

    // MARK: - Paper Validation

    /// Maximum length for paper titles
    static let maxPaperTitleLength = 500

    /// Validate a paper title
    static func validatePaperTitle(_ title: String) -> ValidationError? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .emptyInput(field: "paper title")
        }

        if trimmed.count > maxPaperTitleLength {
            return .tooLong(field: "paper title", maxLength: maxPaperTitleLength)
        }

        return nil
    }

    // MARK: - Search Query Validation

    /// Minimum length for search queries
    static let minSearchQueryLength = 2

    /// Maximum length for search queries
    static let maxSearchQueryLength = 500

    /// Validate a search query
    static func validateSearchQuery(_ query: String) -> ValidationError? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return nil // Empty search is allowed (shows all results)
        }

        if trimmed.count < minSearchQueryLength {
            return .tooShort(field: "search query", minLength: minSearchQueryLength)
        }

        if trimmed.count > maxSearchQueryLength {
            return .tooLong(field: "search query", maxLength: maxSearchQueryLength)
        }

        return nil
    }

    // MARK: - Note Validation

    /// Maximum length for notes
    static let maxNoteLength = 10000

    /// Validate a note
    static func validateNote(_ note: String) -> ValidationError? {
        if note.count > maxNoteLength {
            return .tooLong(field: "note", maxLength: maxNoteLength)
        }
        return nil
    }

    // MARK: - URL Validation

    /// Validate a URL string
    static func validateURL(_ urlString: String) -> ValidationError? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .emptyInput(field: "URL")
        }

        guard let url = URL(string: trimmed) else {
            return .invalidFormat(field: "URL")
        }

        // Check for valid schemes
        let validSchemes = ["http", "https", "file"]
        guard let scheme = url.scheme?.lowercased(), validSchemes.contains(scheme) else {
            return .invalidFormat(field: "URL")
        }

        return nil
    }

    // MARK: - DOI Validation

    /// Validate a DOI string
    static func validateDOI(_ doi: String) -> ValidationError? {
        let trimmed = doi.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return nil // Optional field
        }

        // DOI format: 10.xxxx/xxxxx
        let doiPattern = #"^10\.\d{4,}/[^\s]+$"#
        let regex = try? NSRegularExpression(pattern: doiPattern)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        if regex?.firstMatch(in: trimmed, range: range) == nil {
            return .invalidFormat(field: "DOI")
        }

        return nil
    }

    // MARK: - Helper Methods

    /// Sanitize a string by removing forbidden characters
    static func sanitize(_ input: String, forbiddenCharacters: CharacterSet) -> String {
        input.components(separatedBy: forbiddenCharacters).joined()
    }

    /// Truncate a string to a maximum length
    static func truncate(_ input: String, maxLength: Int) -> String {
        if input.count <= maxLength {
            return input
        }
        let index = input.index(input.startIndex, offsetBy: maxLength - 3)
        return String(input[..<index]) + "..."
    }
}

// MARK: - Validation Error

enum ValidationError: LocalizedError, Equatable {
    case emptyInput(field: String)
    case tooShort(field: String, minLength: Int)
    case tooLong(field: String, maxLength: Int)
    case invalidCharacters(field: String)
    case invalidFormat(field: String)
    case reservedName(name: String)

    var errorDescription: String? {
        switch self {
        case .emptyInput(let field):
            return "\(field.capitalized) cannot be empty"
        case .tooShort(let field, let minLength):
            return "\(field.capitalized) must be at least \(minLength) characters"
        case .tooLong(let field, let maxLength):
            return "\(field.capitalized) cannot exceed \(maxLength) characters"
        case .invalidCharacters(let field):
            return "\(field.capitalized) contains invalid characters"
        case .invalidFormat(let field):
            return "\(field.capitalized) has an invalid format"
        case .reservedName(let name):
            return "'\(name)' is a reserved name"
        }
    }
}

// MARK: - String Extension for Validation

extension String {
    /// Returns true if this string passes tag name validation
    var isValidTagName: Bool {
        ValidationHelper.validateTagName(self) == nil
    }

    /// Returns true if this string passes collection name validation
    var isValidCollectionName: Bool {
        ValidationHelper.validateCollectionName(self) == nil
    }

    /// Returns true if this string passes paper title validation
    var isValidPaperTitle: Bool {
        ValidationHelper.validatePaperTitle(self) == nil
    }

    /// Returns a sanitized version of this string suitable for use as a tag
    var sanitizedAsTag: String {
        ValidationHelper.sanitize(self, forbiddenCharacters: ValidationHelper.forbiddenTagCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
