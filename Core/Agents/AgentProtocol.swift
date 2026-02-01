import Foundation

// MARK: - Agent Capabilities

/// Defines what actions an agent can perform
enum AgentCapability: String, Codable, CaseIterable {
    case summarize          // Generate summaries
    case answerQuestions    // Q&A about content
    case extractCitations   // Parse and format citations
    case findConnections    // Cross-paper analysis
    case generateNotes      // Create note drafts
    case translateText      // Language translation
    case explainConcepts    // Technical explanations
    case suggestRelated     // Recommend related papers
}

// MARK: - Agent Context

/// Context provided to agents for execution
struct AgentContext {
    /// The current paper being viewed (if any)
    var currentPaper: Paper?

    /// Selected text from the PDF
    var selectedText: String?

    /// Full text content of the current paper
    var paperFullText: String?

    /// User's existing annotations on the paper
    var annotations: [Annotation]

    /// Other papers in the user's archive for cross-referencing
    var archivePapers: [Paper]

    /// Previous conversation messages in this session
    var conversationHistory: [AgentMessage]

    /// User preferences and settings
    var preferences: AgentPreferences

    /// Current page number in the PDF
    var currentPage: Int?

    init(
        currentPaper: Paper? = nil,
        selectedText: String? = nil,
        paperFullText: String? = nil,
        annotations: [Annotation] = [],
        archivePapers: [Paper] = [],
        conversationHistory: [AgentMessage] = [],
        preferences: AgentPreferences = AgentPreferences(),
        currentPage: Int? = nil
    ) {
        self.currentPaper = currentPaper
        self.selectedText = selectedText
        self.paperFullText = paperFullText
        self.annotations = annotations
        self.archivePapers = archivePapers
        self.conversationHistory = conversationHistory
        self.preferences = preferences
        self.currentPage = currentPage
    }
}

/// User preferences that affect agent behavior
struct AgentPreferences {
    var preferredLanguage: String = "en"
    var summaryLength: SummaryLength = .medium
    var citationStyle: CitationStyle = .apa
    var technicalLevel: TechnicalLevel = .advanced

    enum SummaryLength: String, Codable {
        case brief      // 1-2 sentences
        case medium     // 1 paragraph
        case detailed   // Multiple paragraphs
    }

    enum CitationStyle: String, Codable, CaseIterable {
        case apa
        case mla
        case chicago
        case ieee
        case harvard
        case bibtex
    }

    enum TechnicalLevel: String, Codable {
        case beginner
        case intermediate
        case advanced
        case expert
    }
}

// MARK: - Agent Messages

/// A message in the agent conversation
struct AgentMessage: Identifiable, Codable {
    var id: UUID
    var role: Role
    var content: String
    var timestamp: Date
    var metadata: [String: String]?

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    init(role: Role, content: String, metadata: [String: String]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.metadata = metadata
    }
}

// MARK: - Agent Result

/// Result returned by agent execution
struct AgentResult {
    var success: Bool
    var content: String
    var suggestedActions: [AgentAction]
    var metadata: [String: Any]

    init(
        success: Bool = true,
        content: String,
        suggestedActions: [AgentAction] = [],
        metadata: [String: Any] = [:]
    ) {
        self.success = success
        self.content = content
        self.suggestedActions = suggestedActions
        self.metadata = metadata
    }

    static func failure(_ message: String) -> AgentResult {
        AgentResult(success: false, content: message)
    }
}

/// An action suggested by the agent that the user can take
struct AgentAction: Identifiable {
    var id: UUID
    var title: String
    var description: String
    var type: ActionType

    enum ActionType {
        case createHighlight(text: String, page: Int)
        case createNote(content: String, page: Int)
        case addTag(tag: String)
        case openPaper(paperId: UUID)
        case searchArchive(query: String)
        case copyToClipboard(text: String)
        case insertText(text: String)
    }

    init(title: String, description: String, type: ActionType) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.type = type
    }
}

// MARK: - Streaming Support

/// A chunk of streaming response from an agent
struct AgentChunk {
    var content: String
    var isComplete: Bool
    var metadata: [String: Any]?

    init(content: String, isComplete: Bool = false, metadata: [String: Any]? = nil) {
        self.content = content
        self.isComplete = isComplete
        self.metadata = metadata
    }
}

// MARK: - Agent Protocol

/// Protocol that all Pedef agents must conform to
protocol PedefAgent {
    /// Unique identifier for this agent
    var id: String { get }

    /// Human-readable name
    var name: String { get }

    /// Description of what this agent does
    var description: String { get }

    /// Capabilities this agent provides
    var capabilities: [AgentCapability] { get }

    /// System image name for UI display
    var systemImage: String { get }

    /// Execute the agent with given context and return result
    func execute(query: String, context: AgentContext) async throws -> AgentResult

    /// Stream responses for real-time display
    func stream(query: String, context: AgentContext) -> AsyncThrowingStream<AgentChunk, Error>
}

// MARK: - Default Implementation

extension PedefAgent {
    var systemImage: String { "sparkles" }

    func stream(query: String, context: AgentContext) -> AsyncThrowingStream<AgentChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await execute(query: query, context: context)
                    continuation.yield(AgentChunk(content: result.content, isComplete: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Agent Errors

enum AgentError: LocalizedError {
    case noContent
    case apiError(String)
    case timeout
    case rateLimited
    case invalidContext
    case unsupportedOperation

    var errorDescription: String? {
        switch self {
        case .noContent:
            return "No content available for analysis"
        case .apiError(let message):
            return "API error: \(message)"
        case .timeout:
            return "Request timed out"
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .invalidContext:
            return "Invalid context provided"
        case .unsupportedOperation:
            return "This operation is not supported"
        }
    }
}

// MARK: - Agent Registry

/// Manages available agents
@MainActor
final class AgentRegistry: ObservableObject {
    static let shared = AgentRegistry()

    @Published private(set) var agents: [any PedefAgent] = []

    private init() {
        registerDefaultAgents()
    }

    private func registerDefaultAgents() {
        // Will be populated with actual agent implementations
    }

    func register(_ agent: any PedefAgent) {
        agents.append(agent)
    }

    func agent(for capability: AgentCapability) -> (any PedefAgent)? {
        agents.first { $0.capabilities.contains(capability) }
    }

    func agent(withId id: String) -> (any PedefAgent)? {
        agents.first { $0.id == id }
    }
}
