import Foundation
import OSLog

@MainActor
final class ErrorReporter: ObservableObject {
    struct ErrorItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    static var pendingError: ErrorItem?

    @Published var currentError: ErrorItem?

    private let logger = Logger(subsystem: "com.pedef.app", category: "error")

    func report(title: String = "Error", message: String) {
        logger.error("\(title, privacy: .public): \(message, privacy: .public)")
        currentError = ErrorItem(title: title, message: message)
    }

    func report(_ error: Error, title: String = "Error") {
        report(title: title, message: error.localizedDescription)
    }

    func flushPending() {
        if let pending = Self.pendingError {
            currentError = pending
            Self.pendingError = nil
        }
    }
}
