import Testing
import Foundation
import CoreGraphics
import AppKit
import PDFKit
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

// MARK: - Validation Tests

@Suite("Validation Helper Tests")
struct ValidationHelperTests {
    @Test("Valid tag names pass validation")
    func testValidTagNames() {
        #expect(ValidationHelper.validateTagName("research") == nil)
        #expect(ValidationHelper.validateTagName("machine-learning") == nil)
        #expect(ValidationHelper.validateTagName("AI & ML") == nil)
        #expect(ValidationHelper.validateTagName("2024") == nil)
    }

    @Test("Empty tag names fail validation")
    func testEmptyTagNames() {
        let error = ValidationHelper.validateTagName("")
        #expect(error == .emptyInput(field: "tag name"))

        let whitespaceError = ValidationHelper.validateTagName("   ")
        #expect(whitespaceError == .emptyInput(field: "tag name"))
    }

    @Test("Tag names with forbidden characters fail validation")
    func testForbiddenCharactersInTags() {
        let error = ValidationHelper.validateTagName("tag<script>")
        #expect(error == .invalidCharacters(field: "tag name"))
    }

    @Test("Reserved tag names fail validation")
    func testReservedTagNames() {
        let error = ValidationHelper.validateTagName("favorite")
        #expect(error == .reservedName(name: "favorite"))

        let allError = ValidationHelper.validateTagName("All")
        #expect(allError == .reservedName(name: "All"))
    }

    @Test("Long tag names fail validation")
    func testLongTagNames() {
        let longName = String(repeating: "a", count: 60)
        let error = ValidationHelper.validateTagName(longName)
        #expect(error == .tooLong(field: "tag name", maxLength: 50))
    }

    @Test("Valid collection names pass validation")
    func testValidCollectionNames() {
        #expect(ValidationHelper.validateCollectionName("My Research") == nil)
        #expect(ValidationHelper.validateCollectionName("2024 Papers") == nil)
    }

    @Test("Empty collection names fail validation")
    func testEmptyCollectionNames() {
        let error = ValidationHelper.validateCollectionName("")
        #expect(error == .emptyInput(field: "collection name"))
    }

    @Test("Valid DOIs pass validation")
    func testValidDOIs() {
        #expect(ValidationHelper.validateDOI("10.1000/xyz123") == nil)
        #expect(ValidationHelper.validateDOI("10.1038/nature12373") == nil)
        #expect(ValidationHelper.validateDOI("") == nil) // Empty is OK (optional field)
    }

    @Test("Invalid DOIs fail validation")
    func testInvalidDOIs() {
        let error = ValidationHelper.validateDOI("not-a-doi")
        #expect(error == .invalidFormat(field: "DOI"))

        let error2 = ValidationHelper.validateDOI("11.1000/xyz") // Wrong prefix
        #expect(error2 == .invalidFormat(field: "DOI"))
    }

    @Test("String extensions for validation")
    func testStringValidationExtensions() {
        #expect("research".isValidTagName == true)
        #expect("".isValidTagName == false)
        #expect("favorite".isValidTagName == false)

        #expect("My Collection".isValidCollectionName == true)
        #expect("".isValidCollectionName == false)
    }

    @Test("String sanitization")
    func testStringSanitization() {
        let sanitized = "test<tag>".sanitizedAsTag
        #expect(sanitized == "testtag")

        let normal = "normal-tag".sanitizedAsTag
        #expect(normal == "normal-tag")
    }

    @Test("String truncation")
    func testStringTruncation() {
        let short = "short"
        #expect(ValidationHelper.truncate(short, maxLength: 10) == "short")

        let long = "this is a very long string"
        let truncated = ValidationHelper.truncate(long, maxLength: 10)
        #expect(truncated == "this is...")
        #expect(truncated.count == 10)
    }
}

@Suite("Keychain Service Tests")
struct KeychainServiceTests {
    @Test("Valid API key format detection")
    func testValidAPIKeyFormat() {
        #expect(KeychainService.isValidAPIKeyFormat("sk-ant-api03-abcdefghijklmnopqrstuvwxyz") == true)
        #expect(KeychainService.isValidAPIKeyFormat("sk-ant-1234567890abcdef") == true)
    }

    @Test("Invalid API key format detection")
    func testInvalidAPIKeyFormat() {
        #expect(KeychainService.isValidAPIKeyFormat("invalid-key") == false)
        #expect(KeychainService.isValidAPIKeyFormat("sk-wrong-prefix") == false)
        #expect(KeychainService.isValidAPIKeyFormat("") == false)
        #expect(KeychainService.isValidAPIKeyFormat("sk-ant-") == false) // Too short
    }
}

@Suite("PDF Metadata Tests")
struct PDFMetadataTests {
    @Test("PDFMetadata initialization")
    func testPDFMetadataInitialization() {
        let metadata = PDFMetadata(
            title: "Test Paper",
            authors: ["John Doe", "Jane Smith"],
            subject: "Computer Science",
            keywords: ["AI", "ML"],
            creator: "LaTeX",
            creationDate: Date(),
            modificationDate: nil,
            pageCount: 10
        )

        #expect(metadata.title == "Test Paper")
        #expect(metadata.authors.count == 2)
        #expect(metadata.keywords.count == 2)
        #expect(metadata.pageCount == 10)
    }
}

@Suite("Archive Statistics Tests")
struct ArchiveStatisticsTests {
    @Test("Formatted reading time")
    func testFormattedReadingTime() {
        let stats = ArchiveStatistics(
            totalPapers: 10,
            readPapers: 5,
            favoritePapers: 2,
            totalAnnotations: 50,
            totalReadingTimeSeconds: 3725, // 1h 2m 5s
            totalFileSizeBytes: 1024 * 1024 * 100, // 100 MB
            uniqueAuthors: 20,
            uniqueKeywords: 15
        )

        #expect(stats.formattedReadingTime == "1h 2m")
        #expect(stats.readingProgress == 0.5)
    }

    @Test("Reading progress calculation")
    func testReadingProgressCalculation() {
        let noProgress = ArchiveStatistics(
            totalPapers: 0, readPapers: 0, favoritePapers: 0,
            totalAnnotations: 0, totalReadingTimeSeconds: 0,
            totalFileSizeBytes: 0, uniqueAuthors: 0, uniqueKeywords: 0
        )
        #expect(noProgress.readingProgress == 0)

        let fullProgress = ArchiveStatistics(
            totalPapers: 10, readPapers: 10, favoritePapers: 0,
            totalAnnotations: 0, totalReadingTimeSeconds: 0,
            totalFileSizeBytes: 0, uniqueAuthors: 0, uniqueKeywords: 0
        )
        #expect(fullProgress.readingProgress == 1.0)
    }
}

@Suite("Reader MCP Entrypoint Tests")
@MainActor
struct ReaderMCPEntrypointTests {
    @Test("Lists reader and developer entrypoints")
    func testEntrypointCatalog() {
        let service = ReaderMCPService.shared

        let reader = service.listReaderEntrypoints().map(\.name)
        let developer = service.listDeveloperEntrypoints().map(\.name)

        #expect(reader.contains("pdf.get_text"))
        #expect(reader.contains("pdf.capture_region"))
        #expect(reader.contains("pdf.caption_region"))
        #expect(developer.contains("dev.capture_page"))
        #expect(developer.contains("dev.snapshot_reader_state"))
    }

    @Test("Captures region and captions through session entrypoints")
    func testCaptureAndCaptionEntrypoints() {
        let service = ReaderMCPService.shared
        let paper = Paper(title: "MCP Capture", pdfData: makeImageBackedPDFData(), pageCount: 1)

        let session = service.openSession(for: paper, currentPage: 0)
        defer { service.closeSession(session.id) }

        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let capture = service.captureRegion(sessionID: session.id, pageIndex: 0, rect: rect, appearance: .light)

        #expect(capture != nil)
        #expect(capture?.mimeType == "image/png")
        #expect(capture?.pngData.isEmpty == false)

        let caption = service.captionRegion(sessionID: session.id, pageIndex: 0, rect: rect, appearance: .dark)
        #expect(caption != nil)
        #expect(caption?.caption.isEmpty == false)
        #expect(caption?.source.pageIndex == 0)
    }

    @Test("Exports bridge snapshot for MCP adapter")
    func testBridgeSnapshotExport() {
        let service = ReaderMCPService.shared
        let paper = Paper(title: "Bridge Export", pdfData: makeImageBackedPDFData(), pageCount: 1)
        let session = service.openSession(for: paper, currentPage: 0)
        defer { service.closeSession(session.id) }

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pedef-mcp-bridge-test-\(UUID().uuidString).json")

        let written = service.writeBridgeSnapshot(fileURL: exportURL)
        #expect(written == exportURL)

        let data = try? Data(contentsOf: exportURL)
        #expect(data != nil)

        if let data,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sessions = object["sessions"] as? [String: Any] {
            #expect(sessions.keys.contains(session.id.uuidString))
        } else {
            #expect(Bool(false))
        }

        try? FileManager.default.removeItem(at: exportURL)
    }

    private func makeImageBackedPDFData() -> Data {
        let imageSize = CGSize(width: 256, height: 256)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        image.unlockFocus()

        let document = PDFDocument()
        if let page = PDFPage(image: image) {
            document.insert(page, at: 0)
        }

        return document.dataRepresentation() ?? Data()
    }
}
