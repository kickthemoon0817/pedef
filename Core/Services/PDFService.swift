import Foundation
import PDFKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Service for PDF parsing, text extraction, and thumbnail generation
final class PDFService {
    static let shared = PDFService()

    private init() {}

    // MARK: - Text Extraction

    /// Extract all text content from a PDF document
    func extractText(from data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }
        return extractText(from: document)
    }

    /// Extract all text content from a PDFDocument
    func extractText(from document: PDFDocument) -> String {
        var fullText = ""

        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex) {
                if let pageText = page.string {
                    fullText += pageText
                    fullText += "\n\n"
                }
            }
        }

        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract text from a specific page
    func extractText(from data: Data, pageIndex: Int) -> String? {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: pageIndex) else {
            return nil
        }
        return page.string
    }

    /// Extract text from a range of pages
    func extractText(from data: Data, pageRange: Range<Int>) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }

        var text = ""
        for pageIndex in pageRange where pageIndex < document.pageCount {
            if let page = document.page(at: pageIndex), let pageText = page.string {
                text += pageText
                text += "\n\n"
            }
        }
        return text.isEmpty ? nil : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Metadata Extraction

    /// Extract metadata from a PDF document
    func extractMetadata(from data: Data) -> PDFMetadata? {
        guard let document = PDFDocument(data: data) else { return nil }
        return extractMetadata(from: document)
    }

    /// Extract metadata from a PDFDocument
    func extractMetadata(from document: PDFDocument) -> PDFMetadata {
        let attributes = document.documentAttributes ?? [:]

        let title = attributes[PDFDocumentAttribute.titleAttribute] as? String
        let author = attributes[PDFDocumentAttribute.authorAttribute] as? String
        let subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String
        let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] as? String
        let creator = attributes[PDFDocumentAttribute.creatorAttribute] as? String
        let creationDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date
        let modificationDate = attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date

        // Try to extract authors from the author string (often comma or semicolon separated)
        let authors = author.map { parseAuthors($0) } ?? []

        // Try to extract keywords from the keywords string
        let keywordList = keywords.map { parseKeywords($0) } ?? []

        return PDFMetadata(
            title: title,
            authors: authors,
            subject: subject,
            keywords: keywordList,
            creator: creator,
            creationDate: creationDate,
            modificationDate: modificationDate,
            pageCount: document.pageCount
        )
    }

    /// Parse author string into individual author names
    private func parseAuthors(_ authorString: String) -> [String] {
        // Common separators: comma, semicolon, "and", "&"
        let separators = CharacterSet(charactersIn: ",;")
        var authors = authorString.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Handle "and" and "&" separators
        authors = authors.flatMap { part -> [String] in
            let parts = part.components(separatedBy: " and ")
                .flatMap { $0.components(separatedBy: " & ") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return parts
        }

        return authors
    }

    /// Parse keywords string into individual keywords
    private func parseKeywords(_ keywordsString: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;")
        return keywordsString.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Thumbnail Generation

    /// Generate a thumbnail image for the first page of a PDF
    func generateThumbnail(from data: Data, size: CGSize = CGSize(width: 200, height: 280)) -> Data? {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: 0) else {
            return nil
        }

        return generateThumbnail(from: page, size: size)
    }

    /// Generate a thumbnail from a specific PDF page
    func generateThumbnail(from page: PDFPage, size: CGSize) -> Data? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(size.width / pageRect.width, size.height / pageRect.height)
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        #if os(macOS)
        let image = NSImage(size: scaledSize)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: scaledSize))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }

        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapRep.representation(using: .png, properties: [:])
        #else
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { ctx in
            let cgContext = ctx.cgContext
            cgContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            cgContext.fill(CGRect(origin: .zero, size: scaledSize))
            cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: cgContext)
        }
        return image.pngData()
        #endif
    }

    // MARK: - Document Analysis

    /// Get basic information about a PDF without fully parsing it
    func getDocumentInfo(from data: Data) -> PDFDocumentInfo? {
        guard let document = PDFDocument(data: data) else { return nil }

        return PDFDocumentInfo(
            pageCount: document.pageCount,
            isEncrypted: document.isEncrypted,
            isLocked: document.isLocked,
            allowsCopying: document.allowsCopying,
            allowsPrinting: document.allowsPrinting
        )
    }

    /// Check if data is a valid PDF
    func isValidPDF(_ data: Data) -> Bool {
        PDFDocument(data: data) != nil
    }

    // MARK: - Search

    /// Search for text within a PDF document
    func search(query: String, in data: Data) -> [PDFSearchResult] {
        guard let document = PDFDocument(data: data) else { return [] }

        var results: [PDFSearchResult] = []
        let selections = document.findString(query, withOptions: .caseInsensitive)

        for selection in selections {
            if let page = selection.pages.first {
                let pageIndex = document.index(for: page)
                let result = PDFSearchResult(
                    pageIndex: pageIndex,
                    text: selection.string ?? query,
                    bounds: selection.bounds(for: page)
                )
                results.append(result)
            }
        }

        return results
    }
}

// MARK: - Supporting Types

struct PDFMetadata {
    let title: String?
    let authors: [String]
    let subject: String?
    let keywords: [String]
    let creator: String?
    let creationDate: Date?
    let modificationDate: Date?
    let pageCount: Int
}

struct PDFDocumentInfo {
    let pageCount: Int
    let isEncrypted: Bool
    let isLocked: Bool
    let allowsCopying: Bool
    let allowsPrinting: Bool
}

struct PDFSearchResult {
    let pageIndex: Int
    let text: String
    let bounds: CGRect
}

