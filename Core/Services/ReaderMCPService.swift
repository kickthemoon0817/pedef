import Foundation
import CoreGraphics

enum ReaderMCPEndpointAudience: String {
    case reader
    case developer
}

struct ReaderMCPEndpoint: Identifiable {
    let id: String
    let name: String
    let description: String
    let expectedInput: [String]
    let audience: ReaderMCPEndpointAudience
}

struct ReaderMCPSession: Identifiable {
    let id: UUID
    let paperID: UUID
    let paperTitle: String
    var currentPage: Int
    let openedAt: Date
    var updatedAt: Date
}

struct ReaderMCPPageInfo {
    let pageIndex: Int
    let label: String
    let preview: String
}

struct ReaderMCPSourceReference {
    let paperID: UUID
    let paperTitle: String
    let pageIndex: Int
    let bounds: CGRect
    let excerpt: String?
}

struct ReaderMCPTextPayload {
    let text: String
    let spans: [PDFTextSpan]
    let sources: [ReaderMCPSourceReference]
}

struct ReaderMCPImagePayload {
    let pngData: Data
    let mimeType: String
    let appearance: PDFCaptureAppearance
    let extractedText: String?
    let source: ReaderMCPSourceReference
}

struct ReaderMCPCaptionPayload {
    let caption: String
    let confidence: Double
    let evidence: [String]
    let source: ReaderMCPSourceReference
}

struct ReaderMCPStateSnapshot {
    let sessionID: UUID
    let paperID: UUID
    let paperTitle: String
    let currentPage: Int
    let pageCount: Int
    let annotationCount: Int
    let lastUpdatedAt: Date
}

@MainActor
final class ReaderMCPService {
    static let shared = ReaderMCPService()

    private var sessions: [UUID: ReaderMCPSession] = [:]
    private var sessionPapers: [UUID: Paper] = [:]

    private init() {}

    func openSession(for paper: Paper, currentPage: Int? = nil) -> ReaderMCPSession {
        let now = Date()
        let current = max(currentPage ?? paper.currentPage, 0)
        let session = ReaderMCPSession(
            id: UUID(),
            paperID: paper.id,
            paperTitle: paper.title,
            currentPage: current,
            openedAt: now,
            updatedAt: now
        )

        sessions[session.id] = session
        sessionPapers[session.id] = paper
        _ = writeBridgeSnapshot()
        return session
    }

    func closeSession(_ sessionID: UUID) {
        sessions.removeValue(forKey: sessionID)
        sessionPapers.removeValue(forKey: sessionID)
        _ = writeBridgeSnapshot()
    }

    func session(for sessionID: UUID) -> ReaderMCPSession? {
        sessions[sessionID]
    }

    func updateCurrentPage(sessionID: UUID, currentPage: Int) {
        guard var session = sessions[sessionID] else { return }
        session.currentPage = max(currentPage, 0)
        session.updatedAt = Date()
        sessions[sessionID] = session
        _ = writeBridgeSnapshot()
    }

    func listReaderEntrypoints() -> [ReaderMCPEndpoint] {
        [
            ReaderMCPEndpoint(
                id: "pdf.open",
                name: "pdf.open",
                description: "Open a paper and create an MCP session.",
                expectedInput: ["paper_id", "current_page optional"],
                audience: .reader
            ),
            ReaderMCPEndpoint(
                id: "pdf.close",
                name: "pdf.close",
                description: "Close the current MCP session.",
                expectedInput: ["session_id"],
                audience: .reader
            ),
            ReaderMCPEndpoint(
                id: "pdf.list_pages",
                name: "pdf.list_pages",
                description: "Return available pages with short previews.",
                expectedInput: ["session_id"],
                audience: .reader
            ),
            ReaderMCPEndpoint(
                id: "pdf.get_text",
                name: "pdf.get_text",
                description: "Extract text and text spans from a page or range.",
                expectedInput: ["session_id", "page_index or page_range"],
                audience: .reader
            ),
            ReaderMCPEndpoint(
                id: "pdf.capture_region",
                name: "pdf.capture_region",
                description: "Capture an internal image from PDF vectors.",
                expectedInput: ["session_id", "page_index", "rect", "appearance optional"],
                audience: .reader
            ),
            ReaderMCPEndpoint(
                id: "pdf.caption_region",
                name: "pdf.caption_region",
                description: "Generate a caption from a captured region and context.",
                expectedInput: ["session_id", "page_index", "rect optional", "appearance optional"],
                audience: .reader
            ),
            ReaderMCPEndpoint(
                id: "pdf.add_source_annotation",
                name: "pdf.add_source_annotation",
                description: "Create a source-linked note annotation.",
                expectedInput: ["session_id", "source_ref", "note_content"],
                audience: .reader
            )
        ]
    }

    func listDeveloperEntrypoints() -> [ReaderMCPEndpoint] {
        [
            ReaderMCPEndpoint(
                id: "dev.capture_page",
                name: "dev.capture_page",
                description: "Capture a full-page internal rendering for design/dev workflows.",
                expectedInput: ["session_id", "page_index", "appearance optional"],
                audience: .developer
            ),
            ReaderMCPEndpoint(
                id: "dev.snapshot_reader_state",
                name: "dev.snapshot_reader_state",
                description: "Inspect current reader state to assist tool-driven development.",
                expectedInput: ["session_id"],
                audience: .developer
            )
        ]
    }

    func listPages(sessionID: UUID) -> [ReaderMCPPageInfo] {
        guard let (_, paper) = sessionAndPaper(for: sessionID) else { return [] }
        guard let document = PDFService.shared.pdfDocument(from: paper.pdfData) else { return [] }

        let pageCount = document.pageCount
        guard pageCount > 0 else { return [] }

        return (0..<pageCount).map { pageIndex in
            let text = document.page(at: pageIndex)?.string ?? ""
            let preview = makePreview(from: text)
            return ReaderMCPPageInfo(pageIndex: pageIndex, label: "Page \(pageIndex + 1)", preview: preview)
        }
    }

    func getText(sessionID: UUID, pageIndex: Int) -> ReaderMCPTextPayload? {
        guard let (session, paper) = sessionAndPaper(for: sessionID) else { return nil }

        guard let pageText = PDFService.shared.extractText(from: paper.pdfData, pageIndex: pageIndex) else {
            return nil
        }

        touch(sessionID: session.id, currentPage: pageIndex)

        let spans = PDFService.shared.extractTextSpans(from: paper.pdfData, pageIndex: pageIndex)
        let source = ReaderMCPSourceReference(
            paperID: paper.id,
            paperTitle: paper.title,
            pageIndex: pageIndex,
            bounds: .zero,
            excerpt: makePreview(from: pageText)
        )

        return ReaderMCPTextPayload(text: pageText, spans: spans, sources: [source])
    }

    func getText(sessionID: UUID, pageRange: Range<Int>) -> ReaderMCPTextPayload? {
        guard let (session, paper) = sessionAndPaper(for: sessionID) else { return nil }
        guard let text = PDFService.shared.extractText(from: paper.pdfData, pageRange: pageRange) else { return nil }

        let endPage = max(pageRange.upperBound - 1, pageRange.lowerBound)
        touch(sessionID: session.id, currentPage: endPage)

        let pageCount = PDFService.shared.getDocumentInfo(from: paper.pdfData)?.pageCount ?? paper.pageCount
        let validRange = pageRange.clamped(to: 0..<max(pageCount, 0))

        var spans: [PDFTextSpan] = []
        var sources: [ReaderMCPSourceReference] = []
        for pageIndex in validRange {
            spans.append(contentsOf: PDFService.shared.extractTextSpans(from: paper.pdfData, pageIndex: pageIndex))
            sources.append(
                ReaderMCPSourceReference(
                    paperID: paper.id,
                    paperTitle: paper.title,
                    pageIndex: pageIndex,
                    bounds: .zero,
                    excerpt: nil
                )
            )
        }

        return ReaderMCPTextPayload(text: text, spans: spans, sources: sources)
    }

    func captureRegion(
        sessionID: UUID,
        pageIndex: Int,
        rect: CGRect,
        appearance: PDFCaptureAppearance = .system
    ) -> ReaderMCPImagePayload? {
        guard let (session, paper) = sessionAndPaper(for: sessionID),
              let capture = PDFService.shared.captureRegion(
                from: paper.pdfData,
                pageIndex: pageIndex,
                rect: rect,
                options: PDFCaptureOptions(scale: 2.0, appearance: appearance)
              ) else {
            return nil
        }

        touch(sessionID: session.id, currentPage: pageIndex)

        let source = ReaderMCPSourceReference(
            paperID: paper.id,
            paperTitle: paper.title,
            pageIndex: pageIndex,
            bounds: capture.actualBounds,
            excerpt: capture.extractedText
        )

        return ReaderMCPImagePayload(
            pngData: capture.imageData,
            mimeType: "image/png",
            appearance: capture.appearance,
            extractedText: capture.extractedText,
            source: source
        )
    }

    func capturePageForDevelopment(
        sessionID: UUID,
        pageIndex: Int,
        appearance: PDFCaptureAppearance = .system
    ) -> ReaderMCPImagePayload? {
        guard let (session, paper) = sessionAndPaper(for: sessionID),
              let capture = PDFService.shared.capturePage(
                from: paper.pdfData,
                pageIndex: pageIndex,
                options: PDFCaptureOptions(scale: 1.5, appearance: appearance)
              ) else {
            return nil
        }

        touch(sessionID: session.id, currentPage: pageIndex)

        let source = ReaderMCPSourceReference(
            paperID: paper.id,
            paperTitle: paper.title,
            pageIndex: pageIndex,
            bounds: capture.actualBounds,
            excerpt: capture.extractedText
        )

        return ReaderMCPImagePayload(
            pngData: capture.imageData,
            mimeType: "image/png",
            appearance: capture.appearance,
            extractedText: capture.extractedText,
            source: source
        )
    }

    func captionRegion(
        sessionID: UUID,
        pageIndex: Int,
        rect: CGRect?,
        appearance: PDFCaptureAppearance = .system
    ) -> ReaderMCPCaptionPayload? {
        guard let (session, paper) = sessionAndPaper(for: sessionID) else { return nil }

        let capture: PDFCaptureResult?
        if let rect, !rect.isNull, !rect.isEmpty {
            capture = PDFService.shared.captureRegion(
                from: paper.pdfData,
                pageIndex: pageIndex,
                rect: rect,
                options: PDFCaptureOptions(scale: 2.0, appearance: appearance)
            )
        } else {
            capture = PDFService.shared.capturePage(
                from: paper.pdfData,
                pageIndex: pageIndex,
                options: PDFCaptureOptions(scale: 1.5, appearance: appearance)
            )
        }

        guard let capture else { return nil }

        touch(sessionID: session.id, currentPage: pageIndex)

        let pageContext = PDFService.shared.extractText(from: paper.pdfData, pageIndex: pageIndex)
        let caption = PDFCaptionService.shared.caption(for: capture, pageContext: pageContext)
        let source = ReaderMCPSourceReference(
            paperID: paper.id,
            paperTitle: paper.title,
            pageIndex: pageIndex,
            bounds: capture.actualBounds,
            excerpt: capture.extractedText
        )

        return ReaderMCPCaptionPayload(
            caption: caption.caption,
            confidence: caption.confidence,
            evidence: caption.evidence,
            source: source
        )
    }

    func addSourceLinkedAnnotation(
        sessionID: UUID,
        source: ReaderMCPSourceReference,
        noteContent: String
    ) -> Annotation? {
        guard let (_, paper) = sessionAndPaper(for: sessionID),
              source.paperID == paper.id else {
            return nil
        }

        let annotation = Annotation(
            type: .textNote,
            pageIndex: source.pageIndex,
            bounds: source.bounds.isEmpty ? .zero : source.bounds
        )
        annotation.noteContent = noteContent
        annotation.selectedText = source.excerpt
        annotation.paper = paper

        paper.annotations.append(annotation)
        touch(sessionID: sessionID, currentPage: source.pageIndex)
        _ = writeBridgeSnapshot()
        return annotation
    }

    func snapshotState(sessionID: UUID) -> ReaderMCPStateSnapshot? {
        guard let (session, paper) = sessionAndPaper(for: sessionID) else { return nil }

        let pageCount = PDFService.shared.getDocumentInfo(from: paper.pdfData)?.pageCount ?? paper.pageCount
        return ReaderMCPStateSnapshot(
            sessionID: session.id,
            paperID: paper.id,
            paperTitle: paper.title,
            currentPage: session.currentPage,
            pageCount: pageCount,
            annotationCount: paper.annotations.count,
            lastUpdatedAt: session.updatedAt
        )
    }

    func captureAppearance(for readingTheme: String) -> PDFCaptureAppearance {
        switch readingTheme.lowercased() {
        case "light": return .light
        case "dark": return .dark
        default: return .system
        }
    }

    private func makePreview(from text: String, maxLength: Int = 120) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "No text extracted" }
        guard collapsed.count > maxLength else { return collapsed }

        let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func touch(sessionID: UUID, currentPage: Int? = nil) {
        guard var session = sessions[sessionID] else { return }
        if let currentPage {
            session.currentPage = max(currentPage, 0)
        }
        session.updatedAt = Date()
        sessions[sessionID] = session
    }

    @discardableResult
    func writeBridgeSnapshot(fileURL: URL? = nil) -> URL? {
        let url = fileURL ?? defaultBridgeFileURL()
        let snapshot = buildBridgeSnapshot()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    private func defaultBridgeFileURL() -> URL {
        if let configuredPath = ProcessInfo.processInfo.environment["PEDEF_MCP_BRIDGE_FILE"],
           !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath)
        }

        return FileManager.default.temporaryDirectory.appendingPathComponent("pedef-mcp-bridge.json")
    }

    private func buildBridgeSnapshot() -> ReaderMCPBridgeSnapshot {
        let readerEntrypoints = listReaderEntrypoints().map(\.name)
        let developerEntrypoints = listDeveloperEntrypoints().map(\.name)

        var bridgeSessions: [String: ReaderMCPBridgeSession] = [:]

        for (sessionID, session) in sessions {
            guard let paper = sessionPapers[sessionID] else { continue }

            let pageCount = PDFService.shared.getDocumentInfo(from: paper.pdfData)?.pageCount ?? paper.pageCount

            bridgeSessions[sessionID.uuidString] = ReaderMCPBridgeSession(
                sessionID: sessionID.uuidString,
                paperID: paper.id.uuidString,
                paperTitle: paper.title,
                currentPage: session.currentPage,
                pageCount: pageCount,
                annotations: paper.annotations.count
            )
        }

        return ReaderMCPBridgeSnapshot(
            readerEntrypoints: readerEntrypoints,
            developerEntrypoints: developerEntrypoints,
            sessions: bridgeSessions
        )
    }

    private func sessionAndPaper(for sessionID: UUID) -> (ReaderMCPSession, Paper)? {
        guard let session = sessions[sessionID],
              let paper = sessionPapers[sessionID] else {
            return nil
        }
        return (session, paper)
    }
}

private struct ReaderMCPBridgeSnapshot: Codable {
    let readerEntrypoints: [String]
    let developerEntrypoints: [String]
    let sessions: [String: ReaderMCPBridgeSession]

    enum CodingKeys: String, CodingKey {
        case readerEntrypoints = "reader_entrypoints"
        case developerEntrypoints = "developer_entrypoints"
        case sessions
    }
}

private struct ReaderMCPBridgeSession: Codable {
    let sessionID: String
    let paperID: String
    let paperTitle: String
    let currentPage: Int
    let pageCount: Int
    let annotations: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case paperID = "paper_id"
        case paperTitle = "paper_title"
        case currentPage = "current_page"
        case pageCount = "page_count"
        case annotations
    }
}
