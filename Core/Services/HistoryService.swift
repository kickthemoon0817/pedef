import Foundation
import SwiftData
import Combine
import OSLog

/// Service for managing user action history
@MainActor
final class HistoryService: ObservableObject {
    @Published private(set) var currentSession: ReadingSession?
    @Published private(set) var recentActions: [ActionHistory] = []

    private var modelContext: ModelContext?
    private var undoStack: [ActionHistory] = []
    private var redoStack: [ActionHistory] = []

    private let logger = Logger(subsystem: "com.pedef.app", category: "history-service")

    private let maxUndoStackSize = 100
    private let recentActionsLimit = 50

    init() {
        startNewSession()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadRecentActions()
    }

    // MARK: - Session Management

    func startNewSession() {
        let session = ReadingSession()
        currentSession = session
        modelContext?.insert(session)

        recordAction(.sessionStart)
    }

    func endCurrentSession() {
        currentSession?.endTime = Date()
        recordAction(.sessionEnd)
        saveContext()
    }

    // MARK: - Action Recording

    func recordAction(
        _ type: ActionType,
        paperId: UUID? = nil,
        annotationId: UUID? = nil,
        collectionId: UUID? = nil
    ) {
        guard let sessionId = currentSession?.id else { return }

        let action = ActionHistory(
            type: type,
            sessionId: sessionId,
            paperId: paperId,
            annotationId: annotationId,
            collectionId: collectionId
        )

        modelContext?.insert(action)
        recentActions.insert(action, at: 0)
        if recentActions.count > recentActionsLimit {
            recentActions.removeLast()
        }

        // Track in undo stack if undoable
        if type.isUndoable {
            pushToUndoStack(action)
        }

        // Update session stats
        currentSession?.totalActions += 1
        if let paperId = paperId, !(currentSession?.papersOpened.contains(paperId) ?? false) {
            currentSession?.papersOpened.append(paperId)
        }

        saveContext()
    }

    func recordAction<T: Encodable>(
        _ type: ActionType,
        paperId: UUID? = nil,
        annotationId: UUID? = nil,
        collectionId: UUID? = nil,
        details: T
    ) {
        guard let sessionId = currentSession?.id else { return }

        let action = ActionHistory(
            type: type,
            sessionId: sessionId,
            paperId: paperId,
            annotationId: annotationId,
            collectionId: collectionId
        )
        action.setDetails(details)

        modelContext?.insert(action)
        recentActions.insert(action, at: 0)
        if recentActions.count > recentActionsLimit {
            recentActions.removeLast()
        }

        if type.isUndoable {
            pushToUndoStack(action)
        }

        currentSession?.totalActions += 1
        saveContext()
    }

    // MARK: - Undo/Redo

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var undoActionName: String? {
        undoStack.last?.actionType.displayName
    }

    var redoActionName: String? {
        redoStack.last?.actionType.displayName
    }

    func undo() -> ActionHistory? {
        guard let action = undoStack.popLast() else { return nil }
        redoStack.append(action)
        return action
    }

    func redo() -> ActionHistory? {
        guard let action = redoStack.popLast() else { return nil }
        undoStack.append(action)
        return action
    }

    func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func pushToUndoStack(_ action: ActionHistory) {
        undoStack.append(action)
        if undoStack.count > maxUndoStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()  // Clear redo stack on new action
    }

    // MARK: - Query History

    func getActions(
        forPaper paperId: UUID,
        limit: Int = 100
    ) -> [ActionHistory] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ActionHistory>(
            predicate: #Predicate { $0.paperId == paperId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            return Array(try modelContext.fetch(descriptor).prefix(limit))
        } catch {
            logger.error("Failed to fetch actions for paper: \(error.localizedDescription)")
            return []
        }
    }

    func getActions(
        ofType type: ActionType,
        limit: Int = 100
    ) -> [ActionHistory] {
        guard let modelContext else { return [] }
        let typeRaw = type.rawValue
        let descriptor = FetchDescriptor<ActionHistory>(
            predicate: #Predicate { $0.actionTypeRawValue == typeRaw },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            return Array(try modelContext.fetch(descriptor).prefix(limit))
        } catch {
            logger.error("Failed to fetch actions by type: \(error.localizedDescription)")
            return []
        }
    }

    func getActions(
        inDateRange range: ClosedRange<Date>,
        limit: Int = 100
    ) -> [ActionHistory] {
        guard let modelContext else { return [] }
        let start = range.lowerBound
        let end = range.upperBound
        let descriptor = FetchDescriptor<ActionHistory>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp <= end },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            return Array(try modelContext.fetch(descriptor).prefix(limit))
        } catch {
            logger.error("Failed to fetch actions by date range: \(error.localizedDescription)")
            return []
        }
    }

    func getSessions(limit: Int = 20) -> [ReadingSession] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ReadingSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        do {
            return Array(try modelContext.fetch(descriptor).prefix(limit))
        } catch {
            logger.error("Failed to fetch sessions: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Statistics

    func getReadingStats(forPaper paperId: UUID) -> ReadingStats {
        let actions = getActions(forPaper: paperId, limit: 1000)

        var totalTime: TimeInterval = 0
        var openTime: Date?

        for action in actions.reversed() {
            switch action.actionType {
            case .openPaper:
                openTime = action.timestamp
            case .closePaper:
                if let start = openTime {
                    totalTime += action.timestamp.timeIntervalSince(start)
                    openTime = nil
                }
            default:
                break
            }
        }

        let pageNavigations = actions.filter { $0.actionType == .navigatePage }.count
        let annotations = actions.filter { $0.category == .annotation }.count

        return ReadingStats(
            totalReadingTime: totalTime,
            pageNavigations: pageNavigations,
            annotationsCreated: annotations,
            sessionsCount: Set(actions.map(\.sessionId)).count
        )
    }

    func getOverallStats() -> OverallStats {
        let sessions = getSessions(limit: 100)

        let totalReadingTime = sessions.compactMap(\.duration).reduce(0, +)
        let papersRead = Set(sessions.flatMap(\.papersOpened)).count
        let totalAnnotations = getActions(ofType: .createHighlight, limit: 1000).count
            + getActions(ofType: .createNote, limit: 1000).count

        return OverallStats(
            totalReadingTime: totalReadingTime,
            papersRead: papersRead,
            totalAnnotations: totalAnnotations,
            sessionsCount: sessions.count
        )
    }

    // MARK: - Private

    private func loadRecentActions() {
        guard let modelContext else {
            recentActions = []
            return
        }
        let descriptor = FetchDescriptor<ActionHistory>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            recentActions = Array(try modelContext.fetch(descriptor).prefix(recentActionsLimit))
        } catch {
            logger.error("Failed to load recent actions: \(error.localizedDescription)")
            recentActions = []
        }
    }

    private func saveContext() {
        guard let modelContext else { return }
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save history context: \(error.localizedDescription)")
        }
    }
}

// MARK: - Statistics Types

struct ReadingStats {
    var totalReadingTime: TimeInterval
    var pageNavigations: Int
    var annotationsCreated: Int
    var sessionsCount: Int

    var formattedReadingTime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: totalReadingTime) ?? "0m"
    }
}

struct OverallStats {
    var totalReadingTime: TimeInterval
    var papersRead: Int
    var totalAnnotations: Int
    var sessionsCount: Int

    var formattedReadingTime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: totalReadingTime) ?? "0m"
    }
}
