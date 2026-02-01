import Foundation
import SwiftData

/// Types of collections for organizing papers
enum CollectionType: String, Codable {
    case folder       // Manual organization
    case smartFolder  // Auto-populated by rules
    case readingList  // Queued for reading
    case favorites    // Starred papers

    var systemImage: String {
        switch self {
        case .folder: return "folder"
        case .smartFolder: return "folder.badge.gearshape"
        case .readingList: return "books.vertical"
        case .favorites: return "star"
        }
    }
}

/// Represents a collection/folder of papers
@Model
final class Collection {
    // MARK: - Identity

    @Attribute(.unique) var id: UUID
    var name: String
    var typeRawValue: String
    var colorHex: String?
    var iconName: String?

    // MARK: - Hierarchy

    var parent: Collection?

    @Relationship(deleteRule: .cascade, inverse: \Collection.parent)
    var children: [Collection]

    // MARK: - Papers

    var papers: [Paper]

    // MARK: - Smart Folder Rules (JSON encoded)

    var smartRulesData: Data?

    // MARK: - Metadata

    var notes: String?
    var sortOrder: Int

    // MARK: - Timestamps

    var createdDate: Date
    var modifiedDate: Date

    // MARK: - Initialization

    init(name: String, type: CollectionType = .folder) {
        self.id = UUID()
        self.name = name
        self.typeRawValue = type.rawValue
        self.colorHex = nil
        self.iconName = nil
        self.parent = nil
        self.children = []
        self.papers = []
        self.smartRulesData = nil
        self.notes = nil
        self.sortOrder = 0
        self.createdDate = Date()
        self.modifiedDate = Date()
    }
}

// MARK: - Computed Properties

extension Collection {
    var type: CollectionType {
        get { CollectionType(rawValue: typeRawValue) ?? .folder }
        set { typeRawValue = newValue.rawValue }
    }

    var paperCount: Int {
        papers.count
    }

    var totalPaperCount: Int {
        papers.count + children.reduce(0) { $0 + $1.totalPaperCount }
    }

    var isSmartFolder: Bool {
        type == .smartFolder
    }

    var hasChildren: Bool {
        !children.isEmpty
    }

    var depth: Int {
        var count = 0
        var current = parent
        while current != nil {
            count += 1
            current = current?.parent
        }
        return count
    }
}

// MARK: - Smart Folder Rules

struct SmartFolderRule: Codable {
    enum Field: String, Codable, CaseIterable {
        case title
        case author
        case keyword
        case tag
        case abstract
        case journal
        case year
        case readingProgress
        case hasAnnotations
    }

    enum Operator: String, Codable, CaseIterable {
        case contains
        case notContains
        case equals
        case notEquals
        case greaterThan
        case lessThan
        case isEmpty
        case isNotEmpty
    }

    var field: Field
    var op: Operator
    var value: String

    func matches(_ paper: Paper) -> Bool {
        switch field {
        case .title:
            return matchString(paper.title)
        case .author:
            return paper.authors.contains { matchString($0) }
        case .keyword:
            return paper.keywords.contains { matchString($0) }
        case .tag:
            return paper.tags.contains { matchString($0) }
        case .abstract:
            return matchString(paper.abstract ?? "")
        case .journal:
            return matchString(paper.journal ?? "")
        case .year:
            guard let date = paper.publishedDate else { return false }
            let year = Calendar.current.component(.year, from: date)
            return matchNumber(Double(year))
        case .readingProgress:
            return matchNumber(paper.readingProgress * 100)
        case .hasAnnotations:
            return paper.hasAnnotations
        }
    }

    private func matchString(_ target: String) -> Bool {
        let lowercaseTarget = target.lowercased()
        let lowercaseValue = value.lowercased()

        switch op {
        case .contains:
            return lowercaseTarget.contains(lowercaseValue)
        case .notContains:
            return !lowercaseTarget.contains(lowercaseValue)
        case .equals:
            return lowercaseTarget == lowercaseValue
        case .notEquals:
            return lowercaseTarget != lowercaseValue
        case .isEmpty:
            return target.isEmpty
        case .isNotEmpty:
            return !target.isEmpty
        default:
            return false
        }
    }

    private func matchNumber(_ target: Double) -> Bool {
        guard let numValue = Double(value) else { return false }

        switch op {
        case .equals:
            return target == numValue
        case .notEquals:
            return target != numValue
        case .greaterThan:
            return target > numValue
        case .lessThan:
            return target < numValue
        default:
            return false
        }
    }
}

struct SmartFolderRuleSet: Codable {
    enum Combinator: String, Codable {
        case all  // AND
        case any  // OR
    }

    var combinator: Combinator
    var rules: [SmartFolderRule]

    func matches(_ paper: Paper) -> Bool {
        switch combinator {
        case .all:
            return rules.allSatisfy { $0.matches(paper) }
        case .any:
            return rules.contains { $0.matches(paper) }
        }
    }
}

extension Collection {
    var smartRules: SmartFolderRuleSet? {
        get {
            guard let data = smartRulesData else { return nil }
            return try? JSONDecoder().decode(SmartFolderRuleSet.self, from: data)
        }
        set {
            smartRulesData = try? JSONEncoder().encode(newValue)
        }
    }
}
