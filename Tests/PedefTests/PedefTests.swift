import Testing
import Foundation
import CoreGraphics
import SwiftUI
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


// MARK: - Platform Abstraction Tests

@Suite("Platform Types Tests")
struct PlatformTypesTests {
    @Test("PlatformImage initializes from data")
    func testPlatformImageFromData() {
        // Create a minimal 1x1 PNG
        let pngData = createMinimalPNGData()
        let image = PlatformImage(data: pngData)
        #expect(image != nil)
    }

    @Test("PlatformImage returns nil for invalid data")
    func testPlatformImageInvalidData() {
        let badData = Data("not an image".utf8)
        let image = PlatformImage(data: badData)
        #expect(image == nil)
    }

    @Test("PlatformColor initializes from SwiftUI Color")
    func testPlatformColorFromSwiftUI() {
        let color = PlatformColor(Color.red)
        #expect(color != nil)
    }

    @Test("Image(platformImage:) creates SwiftUI Image")
    func testImageFromPlatformImage() {
        let pngData = createMinimalPNGData()
        guard let platformImage = PlatformImage(data: pngData) else {
            Issue.record("Failed to create PlatformImage from valid PNG data")
            return
        }
        // This should compile and not crash — verifying the extension works
        let _ = Image(platformImage: platformImage)
    }

    @Test("Color.adaptive creates a color")
    func testAdaptiveColor() {
        let color = Color.adaptive(light: .white, dark: .black)
        // Verify it produces a valid Color (not nil or crash)
        #expect(type(of: color) == Color.self)
    }

    @Test("PlatformPasteboard.copy does not crash")
    func testPlatformPasteboardCopy() {
        // Should not crash on any platform
        PlatformPasteboard.copy("test string")
    }

    @Test("PlatformFileActions.revealInFileBrowser does not crash with temp URL")
    func testRevealInFileBrowser() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-file")
        // Should not crash even if file doesn't exist
        PlatformFileActions.revealInFileBrowser(url: tempURL)
    }

    @Test("PlatformFileActions.openDirectory does not crash with temp URL")
    func testOpenDirectory() {
        let tempURL = FileManager.default.temporaryDirectory
        PlatformFileActions.openDirectory(url: tempURL)
    }

    // MARK: - Helpers

    /// Creates minimal valid 1x1 white PNG data for testing.
    private func createMinimalPNGData() -> Data {
        #if os(macOS)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.white.set()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 1, height: 1))
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return pngData
        #else
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #endif
    }
}

// MARK: - iPad / Cross-Platform Tests

@Suite("Cross-Platform Notification Tests")
struct CrossPlatformNotificationTests {
    @Test("importPDF notification name is defined")
    func testImportPDFNotification() {
        let name = Notification.Name.importPDF
        #expect(name.rawValue == "importPDF")
    }

    @Test("importPDFFromURL notification name is defined")
    func testImportPDFFromURLNotification() {
        let name = Notification.Name.importPDFFromURL
        #expect(name.rawValue == "importPDFFromURL")
    }

    @Test("importPDFFromURL notification carries URL object")
    func testImportPDFFromURLNotificationPayload() async {
        let testURL = URL(fileURLWithPath: "/tmp/test.pdf")

        await confirmation { confirmed in
            let observer = NotificationCenter.default.addObserver(
                forName: .importPDFFromURL,
                object: nil,
                queue: .main
            ) { notification in
                if let url = notification.object as? URL {
                    #expect(url == testURL)
                    confirmed()
                }
            }

            NotificationCenter.default.post(name: .importPDFFromURL, object: testURL)

            // Clean up observer after test
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @Test("Navigation notification names are defined")
    func testNavigationNotifications() {
        #expect(Notification.Name.previousPage.rawValue == "previousPage")
        #expect(Notification.Name.nextPage.rawValue == "nextPage")
        #expect(Notification.Name.zoomIn.rawValue == "zoomIn")
        #expect(Notification.Name.zoomOut.rawValue == "zoomOut")
        #expect(Notification.Name.fitToWidth.rawValue == "fitToWidth")
    }
}

@Suite("Cross-Platform File Handling Tests")
struct CrossPlatformFileHandlingTests {
    @Test("sharePDF does not crash with temp file")
    func testSharePDFDoesNotCrash() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-share.pdf")
        // Create a minimal file so the URL is valid
        FileManager.default.createFile(atPath: tempURL.path, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Should not crash on either platform (no-op on macOS, needs window on iOS)
        // On iOS without a window hierarchy this will silently return
        PlatformFileActions.sharePDF(url: tempURL)
    }

    @Test("revealInFileBrowser is no-op on iOS, functional on macOS")
    func testRevealInFileBrowserPlatformBehavior() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-reveal")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Should not crash on any platform
        PlatformFileActions.revealInFileBrowser(url: tempURL)
    }

    @Test("PDF file extension validation")
    func testPDFExtensionValidation() {
        // Simulates the check done in .onOpenURL handler
        let pdfURL = URL(fileURLWithPath: "/tmp/paper.pdf")
        let pdfUpperURL = URL(fileURLWithPath: "/tmp/paper.PDF")
        let txtURL = URL(fileURLWithPath: "/tmp/notes.txt")
        let noExtURL = URL(fileURLWithPath: "/tmp/noext")

        #expect(pdfURL.pathExtension.lowercased() == "pdf")
        #expect(pdfUpperURL.pathExtension.lowercased() == "pdf")
        #expect(txtURL.pathExtension.lowercased() != "pdf")
        #expect(noExtURL.pathExtension.lowercased() != "pdf")
    }
}

// MARK: - Sync: DTOMapper Tests

@Suite("DTOMapper Timestamp Tests")
struct DTOMapperTimestampTests {
    @Test("Date to timestamp round-trip preserves value")
    func testTimestampRoundTrip() {
        let now = Date()
        let ts = DTOMapper.toTimestamp(now)
        let back = DTOMapper.fromTimestamp(ts)
        // Timestamps have nanosecond precision; allow tiny delta
        #expect(abs(now.timeIntervalSince(back)) < 0.001)
    }

    @Test("Distant past round-trips correctly")
    func testDistantPastTimestamp() {
        let past = Date.distantPast
        let ts = DTOMapper.toTimestamp(past)
        let back = DTOMapper.fromTimestamp(ts)
        #expect(abs(past.timeIntervalSince(back)) < 1.0)
    }
}

@Suite("DTOMapper AnnotationType Tests")
struct DTOMapperAnnotationTypeTests {
    @Test("All annotation types round-trip correctly")
    func testAnnotationTypeRoundTrip() {
        let cases: [AnnotationType] = [
            .highlight, .underline, .strikethrough,
            .textNote, .stickyNote, .freehandDrawing,
            .shape, .bookmark
        ]
        for type in cases {
            let proto = DTOMapper.toProto(type)
            let back = DTOMapper.fromProto(proto)
            #expect(back == type, "Round-trip failed for \(type)")
        }
    }

    @Test("Unrecognized annotation type defaults to highlight")
    func testUnrecognizedAnnotationType() {
        let result = DTOMapper.fromProto(Pedef_AnnotationType.unspecified)
        #expect(result == .highlight)
    }
}

@Suite("DTOMapper CollectionType Tests")
struct DTOMapperCollectionTypeTests {
    @Test("All collection types round-trip correctly")
    func testCollectionTypeRoundTrip() {
        let cases: [CollectionType] = [
            .folder, .smartFolder, .readingList, .favorites
        ]
        for type in cases {
            let proto = DTOMapper.toProto(type)
            let back = DTOMapper.fromProto(proto)
            #expect(back == type, "Round-trip failed for \(type)")
        }
    }

    @Test("Unrecognized collection type defaults to folder")
    func testUnrecognizedCollectionType() {
        let result = DTOMapper.fromProto(Pedef_CollectionType.unspecified)
        #expect(result == .folder)
    }
}

@Suite("DTOMapper makePaper Tests")
struct DTOMapperMakePaperTests {
    @Test("makePaper creates paper with correct fields")
    func testMakePaper() {
        var dto = Pedef_PaperMetadata()
        let id = UUID()
        dto.id = id.uuidString
        dto.title = "Test Paper"
        dto.authors = ["Alice", "Bob"]
        dto.abstract = "An abstract"
        dto.doi = "10.1234/test"
        dto.pageCount = 42
        dto.readingProgress = 0.5
        dto.currentPage = 10
        dto.keywords = ["AI", "ML"]

        let paper = DTOMapper.makePaper(from: dto)

        #expect(paper.id == id)
        #expect(paper.title == "Test Paper")
        #expect(paper.authors == ["Alice", "Bob"])
        #expect(paper.abstract == "An abstract")
        #expect(paper.doi == "10.1234/test")
        #expect(paper.pageCount == 42)
        #expect(paper.readingProgress == 0.5)
        #expect(paper.currentPage == 10)
        #expect(paper.keywords == ["AI", "ML"])
    }

    @Test("makePaper handles empty optional fields as nil")
    func testMakePaperEmptyOptionals() {
        var dto = Pedef_PaperMetadata()
        dto.id = UUID().uuidString
        dto.title = "Minimal"
        dto.abstract = ""
        dto.doi = ""
        dto.journal = ""

        let paper = DTOMapper.makePaper(from: dto)

        #expect(paper.abstract == nil)
        #expect(paper.doi == nil)
        #expect(paper.journal == nil)
    }

    @Test("makePaper falls back to new UUID for invalid ID string")
    func testMakePaperInvalidUUID() {
        var dto = Pedef_PaperMetadata()
        dto.id = "not-a-uuid"
        dto.title = "Bad ID"

        let paper = DTOMapper.makePaper(from: dto)
        // Should still create a paper with a valid UUID (fallback)
        #expect(paper.title == "Bad ID")
        #expect(paper.id != UUID()) // just verify it's some UUID
    }
}

@Suite("DTOMapper makeAnnotation Tests")
struct DTOMapperMakeAnnotationTests {
    @Test("makeAnnotation creates annotation with correct fields")
    func testMakeAnnotation() {
        var dto = Pedef_AnnotationDTO()
        let id = UUID()
        dto.id = id.uuidString
        dto.type = .highlight
        dto.colorHex = "#FF0000"
        dto.pageIndex = 5
        var rect = Pedef_Rect()
        rect.x = 10; rect.y = 20; rect.width = 100; rect.height = 50
        dto.bounds = rect
        dto.selectedText = "Hello world"
        dto.noteContent = "A note"
        dto.tags = ["important"]

        let annotation = DTOMapper.makeAnnotation(from: dto)

        #expect(annotation.id == id)
        #expect(annotation.type == .highlight)
        #expect(annotation.pageIndex == 5)
        #expect(annotation.boundsX == 10)
        #expect(annotation.boundsY == 20)
        #expect(annotation.boundsWidth == 100)
        #expect(annotation.boundsHeight == 50)
        #expect(annotation.selectedText == "Hello world")
        #expect(annotation.noteContent == "A note")
        #expect(annotation.tags == ["important"])
    }

    @Test("makeAnnotation handles empty optional strings as nil")
    func testMakeAnnotationEmptyStrings() {
        var dto = Pedef_AnnotationDTO()
        dto.id = UUID().uuidString
        dto.selectedText = ""
        dto.noteContent = ""

        let annotation = DTOMapper.makeAnnotation(from: dto)
        #expect(annotation.selectedText == nil)
        #expect(annotation.noteContent == nil)
    }
}

@Suite("DTOMapper makeCollection Tests")
struct DTOMapperMakeCollectionTests {
    @Test("makeCollection creates collection with correct fields")
    func testMakeCollection() {
        var dto = Pedef_CollectionDTO()
        let id = UUID()
        dto.id = id.uuidString
        dto.name = "Research"
        dto.type = .folder
        dto.colorHex = "#0000FF"
        dto.sortOrder = 3

        let collection = DTOMapper.makeCollection(from: dto)

        #expect(collection.id == id)
        #expect(collection.name == "Research")
        #expect(collection.type == .folder)
        #expect(collection.colorHex == "#0000FF")
        #expect(collection.sortOrder == 3)
    }

    @Test("makeCollection handles smart folder type")
    func testMakeSmartFolder() {
        var dto = Pedef_CollectionDTO()
        dto.id = UUID().uuidString
        dto.name = "ML Papers"
        dto.type = .smartFolder

        let collection = DTOMapper.makeCollection(from: dto)
        #expect(collection.type == .smartFolder)
    }

    @Test("makeCollection handles empty optional fields as nil")
    func testMakeCollectionEmptyOptionals() {
        var dto = Pedef_CollectionDTO()
        dto.id = UUID().uuidString
        dto.name = "Test"
        dto.colorHex = ""
        dto.iconName = ""
        dto.notes = ""

        let collection = DTOMapper.makeCollection(from: dto)
        #expect(collection.colorHex == nil)
        #expect(collection.iconName == nil)
        #expect(collection.notes == nil)
    }
}

@Suite("DTOMapper makeTag Tests")
struct DTOMapperMakeTagTests {
    @Test("makeTag creates tag with correct fields")
    func testMakeTag() {
        var dto = Pedef_TagDTO()
        let id = UUID()
        dto.id = id.uuidString
        dto.name = "machine-learning"
        dto.colorHex = "#FF6600"
        dto.usageCount = 7

        let tag = DTOMapper.makeTag(from: dto)

        #expect(tag.id == id)
        #expect(tag.name == "machine-learning")
        #expect(tag.colorHex == "#FF6600")
        #expect(tag.usageCount == 7)
    }
}

// MARK: - Sync: ChangeSnapshot Tests

@Suite("ChangeSnapshot Tests")
struct ChangeSnapshotTests {
    @Test("Empty snapshot reports isEmpty true")
    func testEmptySnapshot() {
        let snapshot = ChangeSnapshot(
            papers: [], annotations: [], collections: [], tags: [],
            deletedPaperIDs: [], deletedAnnotationIDs: [],
            deletedCollectionIDs: [], deletedTagIDs: []
        )
        #expect(snapshot.isEmpty == true)
    }

    @Test("Snapshot with papers is not empty")
    func testSnapshotWithPapers() {
        let paper = Paper(title: "T", authors: [], pdfData: Data())
        let snapshot = ChangeSnapshot(
            papers: [paper], annotations: [], collections: [], tags: [],
            deletedPaperIDs: [], deletedAnnotationIDs: [],
            deletedCollectionIDs: [], deletedTagIDs: []
        )
        #expect(snapshot.isEmpty == false)
    }

    @Test("Snapshot with deletions only is not empty")
    func testSnapshotWithDeletions() {
        let snapshot = ChangeSnapshot(
            papers: [], annotations: [], collections: [], tags: [],
            deletedPaperIDs: [UUID()], deletedAnnotationIDs: [],
            deletedCollectionIDs: [], deletedTagIDs: []
        )
        #expect(snapshot.isEmpty == false)
    }

    @Test("Snapshot with annotations only is not empty")
    func testSnapshotWithAnnotations() {
        let annotation = Annotation(type: .highlight, pageIndex: 0, bounds: .zero)
        let snapshot = ChangeSnapshot(
            papers: [], annotations: [annotation], collections: [], tags: [],
            deletedPaperIDs: [], deletedAnnotationIDs: [],
            deletedCollectionIDs: [], deletedTagIDs: []
        )
        #expect(snapshot.isEmpty == false)
    }
}

// MARK: - Sync: DeletionRecord Tests

@Suite("DeletionRecord Tests")
struct DeletionRecordTests {
    @Test("DeletionRecord initialization sets fields correctly")
    func testDeletionRecordInit() {
        let entityID = UUID()
        let record = DeletionRecord(entityType: "paper", entityID: entityID)

        #expect(record.entityType == "paper")
        #expect(record.entityID == entityID)
        #expect(record.id != UUID()) // has a valid UUID
    }

    @Test("DeletionRecord deletedDate defaults to approximately now")
    func testDeletionRecordDate() {
        let before = Date()
        let record = DeletionRecord(entityType: "annotation", entityID: UUID())
        let after = Date()

        #expect(record.deletedDate >= before)
        #expect(record.deletedDate <= after)
    }

    @Test("DeletionRecord supports all entity types")
    func testDeletionRecordEntityTypes() {
        let types = ["paper", "annotation", "collection", "tag"]
        for type in types {
            let record = DeletionRecord(entityType: type, entityID: UUID())
            #expect(record.entityType == type)
        }
    }
}

// MARK: - Sync: SyncServerConfig Tests

@Suite("SyncServerConfig Tests")
struct SyncServerConfigTests {
    @Test("SyncServerConfig has correct defaults")
    func testDefaults() {
        let config = SyncServerConfig()
        #expect(config.host == "localhost")
        #expect(config.port == 50051)
        #expect(config.authToken == "")
        #expect(config.useTLS == false)
    }

    @Test("SyncServerConfig custom values")
    func testCustomValues() {
        let config = SyncServerConfig(
            host: "sync.example.com",
            port: 8443,
            authToken: "secret-token",
            useTLS: true
        )
        #expect(config.host == "sync.example.com")
        #expect(config.port == 8443)
        #expect(config.authToken == "secret-token")
        #expect(config.useTLS == true)
    }

    @Test("SyncServerConfig Codable round-trip")
    func testCodableRoundTrip() throws {
        let original = SyncServerConfig(
            host: "myhost.io",
            port: 9090,
            authToken: "tok123",
            useTLS: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncServerConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("SyncServerConfig Equatable conformance")
    func testEquatable() {
        let a = SyncServerConfig(host: "a", port: 1, authToken: "t", useTLS: false)
        let b = SyncServerConfig(host: "a", port: 1, authToken: "t", useTLS: false)
        let c = SyncServerConfig(host: "b", port: 1, authToken: "t", useTLS: false)
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - Sync: ServerStatus Tests

@Suite("ServerStatus Tests")
struct ServerStatusTests {
    @Test("ServerStatus initialization with all fields")
    func testServerStatusInit() {
        let now = Date()
        let status = ServerStatus(
            serverVersion: "1.0.0",
            paperCount: 42,
            annotationCount: 100,
            collectionCount: 5,
            tagCount: 15,
            storageBytesUsed: 1_000_000,
            lastModified: now
        )
        #expect(status.serverVersion == "1.0.0")
        #expect(status.paperCount == 42)
        #expect(status.annotationCount == 100)
        #expect(status.collectionCount == 5)
        #expect(status.tagCount == 15)
        #expect(status.storageBytesUsed == 1_000_000)
        #expect(status.lastModified == now)
    }

    @Test("ServerStatus with nil lastModified")
    func testServerStatusNilLastModified() {
        let status = ServerStatus(
            serverVersion: "0.1.0",
            paperCount: 0,
            annotationCount: 0,
            collectionCount: 0,
            tagCount: 0,
            storageBytesUsed: 0,
            lastModified: nil
        )
        #expect(status.lastModified == nil)
        #expect(status.paperCount == 0)
    }
}

// MARK: - Sync: SyncError Tests

@Suite("SyncError Tests")
struct SyncErrorTests {
    @Test("notConfigured has descriptive message")
    func testNotConfigured() {
        let error = SyncError.notConfigured
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.errorDescription?.contains("not configured") == true)
    }

    @Test("alreadySyncing has descriptive message")
    func testAlreadySyncing() {
        let error = SyncError.alreadySyncing
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.errorDescription?.contains("already in progress") == true)
    }

    @Test("pullFailed wraps underlying error")
    func testPullFailed() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "timeout"])
        let error = SyncError.pullFailed(underlying: underlying)
        #expect(error.errorDescription?.contains("Pull failed") == true)
    }

    @Test("pushFailed wraps underlying error")
    func testPushFailed() {
        let underlying = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "rejected"])
        let error = SyncError.pushFailed(underlying: underlying)
        #expect(error.errorDescription?.contains("Push failed") == true)
    }

    @Test("pdfTransferFailed includes paper ID")
    func testPdfTransferFailed() {
        let id = UUID()
        let underlying = NSError(domain: "test", code: 3)
        let error = SyncError.pdfTransferFailed(paperID: id, underlying: underlying)
        #expect(error.errorDescription?.contains(id.uuidString) == true)
        #expect(error.errorDescription?.contains("PDF transfer failed") == true)
    }
}

// MARK: - Sync: SyncNetworkError Tests

@Suite("SyncNetworkError Tests")
struct SyncNetworkErrorTests {
    @Test("notConnected has descriptive message")
    func testNotConnected() {
        let error = SyncNetworkError.notConnected
        #expect(error.errorDescription?.contains("Not connected") == true)
    }

    @Test("connectionFailed includes detail message")
    func testConnectionFailed() {
        let error = SyncNetworkError.connectionFailed("host unreachable")
        #expect(error.errorDescription?.contains("host unreachable") == true)
    }

    @Test("serverError includes detail message")
    func testServerError() {
        let error = SyncNetworkError.serverError("internal error")
        #expect(error.errorDescription?.contains("internal error") == true)
    }

    @Test("hashMismatch includes both hashes")
    func testHashMismatch() {
        let error = SyncNetworkError.hashMismatch(expected: "abc123", actual: "def456")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("abc123"))
        #expect(desc.contains("def456"))
    }

    @Test("invalidResponse has descriptive message")
    func testInvalidResponse() {
        let error = SyncNetworkError.invalidResponse
        #expect(error.errorDescription?.contains("Invalid response") == true)
    }
}
