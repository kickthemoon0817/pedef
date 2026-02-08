import Foundation
import CoreGraphics

struct PDFCaptionResult {
    let caption: String
    let confidence: Double
    let evidence: [String]
}

final class PDFCaptionService {
    static let shared = PDFCaptionService()

    private init() {}

    func caption(for capture: PDFCaptureResult, pageContext: String?) -> PDFCaptionResult {
        let extracted = capture.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let context = pageContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let primaryText = extracted.isEmpty ? context : extracted
        let summary = summarize(text: primaryText)

        let caption: String
        if isTableLike(primaryText) {
            caption = "Table-like region on page \(capture.pageIndex + 1) with structured numeric/text values. \(summary)"
        } else if isFigureMentioned(primaryText) {
            caption = "Figure-oriented region on page \(capture.pageIndex + 1). \(summary)"
        } else if !summary.isEmpty {
            caption = "Captured region on page \(capture.pageIndex + 1). \(summary)"
        } else {
            caption = "Captured visual region on page \(capture.pageIndex + 1), but there is not enough local text for a precise caption."
        }

        return PDFCaptionResult(
            caption: caption,
            confidence: confidenceScore(extractedText: extracted, contextText: context),
            evidence: evidence(from: extracted, context: context)
        )
    }

    private func summarize(text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "" }

        let maxLength = 180
        if collapsed.count <= maxLength {
            return collapsed
        }

        let index = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func confidenceScore(extractedText: String, contextText: String) -> Double {
        if extractedText.count > 240 { return 0.90 }
        if extractedText.count > 120 { return 0.82 }
        if extractedText.count > 40 { return 0.74 }
        if !contextText.isEmpty { return 0.58 }
        return 0.36
    }

    private func evidence(from extractedText: String, context: String) -> [String] {
        var evidence: [String] = []

        if !extractedText.isEmpty {
            evidence.append("Local region text extracted")
        }

        if !context.isEmpty {
            evidence.append("Page-level context text extracted")
        }

        if evidence.isEmpty {
            evidence.append("Image-only capture without text evidence")
        }

        return evidence
    }

    private func isFigureMentioned(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("figure") || lowered.contains("fig.") || lowered.contains("diagram") || lowered.contains("plot")
    }

    private func isTableLike(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        let digitCount = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let newlineCount = text.filter { $0 == "\n" }.count
        let ratio = Double(digitCount) / Double(max(text.count, 1))

        return ratio > 0.15 && newlineCount >= 2
    }
}
