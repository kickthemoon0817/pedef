import Foundation
import CryptoKit

/// Manages PDF blob storage on the filesystem.
///
/// PDFs are stored as `<paperID>.pdf` inside the configured directory.
/// Thread-safety: FileManager operations are thread-safe on Darwin.
struct FileStore: Sendable {
    let directory: URL

    /// Creates a FileStore, ensuring the storage directory exists.
    init(directory: String) throws {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        self.directory = url
    }

    // MARK: - PDF Operations

    /// Save PDF data for a paper. Overwrites if exists.
    func savePDF(paperID: String, data: Data) throws {
        let path = try pdfURL(for: paperID)
        try data.write(to: path, options: .atomic)
    }

    /// Read PDF data for a paper. Returns nil if not found.
    func readPDF(paperID: String) -> Data? {
        guard let path = try? pdfURL(for: paperID) else { return nil }
        return try? Data(contentsOf: path)
    }

    /// Delete PDF file for a paper. Returns true if deleted.
    @discardableResult
    func deletePDF(paperID: String) -> Bool {
        guard let path = try? pdfURL(for: paperID) else { return false }
        do {
            try FileManager.default.removeItem(at: path)
            return true
        } catch {
            return false
        }
    }

    /// Check if a PDF exists for a paper.
    func pdfExists(paperID: String) -> Bool {
        guard let path = try? pdfURL(for: paperID) else { return false }
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Get the file size of a stored PDF. Returns nil if not found.
    func pdfFileSize(paperID: String) -> Int64? {
        guard let path = try? pdfURL(for: paperID) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path) else {
            return nil
        }
        return attrs[.size] as? Int64
    }

    // MARK: - Hashing

    /// Compute SHA-256 hash of data, returned as lowercase hex string.
    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Helpers

    private func pdfURL(for paperID: String) throws -> URL {
        // Validate paperID to prevent path traversal attacks
        guard !paperID.isEmpty else { throw FileStoreError.invalidPaperID }
        guard !paperID.contains("/") && !paperID.contains("\\") && !paperID.contains("..") else {
            throw FileStoreError.invalidPaperID
        }
        return directory.appendingPathComponent("\(paperID).pdf")
    }
}

// MARK: - Error Types

enum FileStoreError: Error {
    case invalidPaperID
}
