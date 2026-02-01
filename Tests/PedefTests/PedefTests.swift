import Testing
import Foundation
import CoreGraphics
@testable import Pedef

@Suite("Paper Model Tests")
struct PaperTests {
    @Test("Paper initialization with required fields")
    func testPaperInitialization() {
        let pdfData = Data("test pdf content".utf8)
        let paper = Paper(title: "Test Paper", authors: ["Author One"], pdfData: pdfData)

        #expect(paper.title == "Test Paper")
        #expect(paper.authors == ["Author One"])
        #expect(paper.readingProgress == 0.0)
        #expect(paper.isRead == false)
    }

    @Test("Paper formatted authors")
    func testFormattedAuthors() {
        let pdfData = Data()

        let singleAuthor = Paper(title: "Test", authors: ["John Doe"], pdfData: pdfData)
        #expect(singleAuthor.formattedAuthors == "John Doe")

        let twoAuthors = Paper(title: "Test", authors: ["John Doe", "Jane Smith"], pdfData: pdfData)
        #expect(twoAuthors.formattedAuthors == "John Doe and Jane Smith")

        let manyAuthors = Paper(title: "Test", authors: ["John Doe", "Jane Smith", "Bob Wilson"], pdfData: pdfData)
        #expect(manyAuthors.formattedAuthors == "John Doe et al.")
    }
}

@Suite("Annotation Tests")
struct AnnotationTests {
    @Test("Annotation initialization")
    func testAnnotationInitialization() {
        let bounds = CGRect(x: 10, y: 20, width: 100, height: 50)
        let annotation = Annotation(type: .highlight, pageIndex: 0, bounds: bounds)

        #expect(annotation.type == .highlight)
        #expect(annotation.pageIndex == 0)
        #expect(annotation.bounds == bounds)
    }

    @Test("Annotation type display names")
    func testAnnotationTypeDisplayNames() {
        #expect(AnnotationType.highlight.displayName == "Highlight")
        #expect(AnnotationType.textNote.displayName == "Text Note")
        #expect(AnnotationType.bookmark.displayName == "Bookmark")
    }
}

@Suite("Collection Tests")
struct CollectionTests {
    @Test("Collection initialization")
    func testCollectionInitialization() {
        let collection = Collection(name: "Research", type: .folder)

        #expect(collection.name == "Research")
        #expect(collection.type == .folder)
        #expect(collection.paperCount == 0)
    }

    @Test("Smart folder rule matching")
    func testSmartFolderRuleMatching() {
        let rule = SmartFolderRule(field: .title, op: .contains, value: "machine learning")
        let pdfData = Data()

        let matchingPaper = Paper(title: "Introduction to Machine Learning", pdfData: pdfData)
        #expect(rule.matches(matchingPaper) == true)

        let nonMatchingPaper = Paper(title: "Deep Neural Networks", pdfData: pdfData)
        #expect(rule.matches(nonMatchingPaper) == false)
    }
}

@Suite("Action History Tests")
struct ActionHistoryTests {
    @Test("Action type categories")
    func testActionTypeCategories() {
        #expect(ActionType.openPaper.category == .reading)
        #expect(ActionType.createHighlight.category == .annotation)
        #expect(ActionType.importPaper.category == .library)
        #expect(ActionType.agentQuery.category == .agent)
    }

    @Test("Undoable actions")
    func testUndoableActions() {
        #expect(ActionType.openPaper.isUndoable == false)
        #expect(ActionType.createHighlight.isUndoable == true)
        #expect(ActionType.deleteAnnotation.isUndoable == true)
    }
}
