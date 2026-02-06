import Foundation
import KeychainAccess
import SwiftAnthropic

/// Agent for summarizing academic papers using SwiftAnthropic
final class SummaryAgent: PedefAgent {
    let id = "summary"
    let name = "Summary"
    let description = "Generate concise summaries of papers at various detail levels"
    let capabilities: [AgentCapability] = [.summarize]
    let systemImage = "doc.text"

    private var service: AnthropicService?

    init(apiKey: String? = nil) {
        refreshAPIKey(apiKey)
    }

    /// Refresh the API key, checking Keychain and environment
    func refreshAPIKey(_ explicitKey: String? = nil) {
        let key = explicitKey ?? getAPIKey()
        if let key = key, !key.isEmpty {
            self.service = AnthropicServiceFactory.service(
                apiKey: key,
                betaHeaders: nil
            )
        } else {
            self.service = nil
        }
    }

    /// Get the API key from Keychain or environment
    private func getAPIKey() -> String? {
        // Try Keychain first via KeychainService (must be called from main actor)
        // For non-main actor contexts, fall back to environment
        if let keychainKey = try? getKeychainAPIKey(), !keychainKey.isEmpty {
            return keychainKey
        }

        // Fall back to environment variable
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }

    private func getKeychainAPIKey() throws -> String? {
        // Access keychain directly without going through MainActor
        // This is a simplified access pattern for the agent
        let keychain = KeychainAccess.Keychain(service: Bundle.main.bundleIdentifier ?? "com.pedef.app")
        return try keychain.get("anthropic_api_key")
    }

    /// Check if the agent is properly configured
    var isConfigured: Bool {
        service != nil
    }

    func execute(query: String, context: AgentContext) async throws -> AgentResult {
        guard let service = service else {
            throw AgentError.apiError("API key not configured. Set ANTHROPIC_API_KEY environment variable.")
        }

        guard let text = context.selectedText ?? context.paperFullText else {
            throw AgentError.noContent
        }

        let summaryLength = context.preferences.summaryLength
        let systemPrompt = buildSystemPrompt(length: summaryLength)
        let userPrompt = buildUserPrompt(
            query: query,
            text: text,
            paperTitle: context.currentPaper?.title,
            paperAuthors: context.currentPaper?.authors
        )

        let messages = [
            MessageParameter.Message(role: .user, content: .text(userPrompt))
        ]

        let parameters = MessageParameter(
            model: .claude35Sonnet,
            messages: messages,
            maxTokens: 2048,
            system: .text(systemPrompt)
        )

        do {
            let response = try await service.createMessage(parameters)
            let responseText = extractText(from: response)

            return AgentResult(
                content: responseText,
                suggestedActions: buildSuggestedActions(context: context)
            )
        } catch {
            throw AgentError.apiError("Failed to get response: \(error.localizedDescription)")
        }
    }

    private func extractText(from response: MessageResponse) -> String {
        response.content.compactMap { block -> String? in
            if case .text(let text, _) = block {
                return text
            }
            return nil
        }.joined()
    }

    private func buildSystemPrompt(length: AgentPreferences.SummaryLength) -> String {
        let lengthInstruction: String
        switch length {
        case .brief:
            lengthInstruction = "Provide a 1-2 sentence summary capturing the key point."
        case .medium:
            lengthInstruction = "Provide a paragraph summary covering main findings and contributions."
        case .detailed:
            lengthInstruction = """
            Provide a detailed summary including:
            - Main research question/objective
            - Methodology
            - Key findings
            - Contributions and implications
            - Limitations (if apparent)
            """
        }

        return """
        You are an expert academic assistant helping researchers understand papers quickly.

        \(lengthInstruction)

        Guidelines:
        - Use precise academic language
        - Focus on novel contributions
        - Maintain objectivity
        - Cite specific findings when relevant
        - Avoid unnecessary filler words
        """
    }

    private func buildUserPrompt(
        query: String,
        text: String,
        paperTitle: String?,
        paperAuthors: [String]?
    ) -> String {
        var prompt = ""

        if let title = paperTitle {
            prompt += "Paper: \(title)\n"
        }
        if let authors = paperAuthors, !authors.isEmpty {
            prompt += "Authors: \(authors.joined(separator: ", "))\n"
        }

        prompt += "\nContent:\n\(text)\n\n"

        if !query.isEmpty && query.lowercased() != "summarize" {
            prompt += "User request: \(query)"
        } else {
            prompt += "Please summarize this content."
        }

        return prompt
    }

    private func buildSuggestedActions(context: AgentContext) -> [AgentAction] {
        var actions: [AgentAction] = []

        if let page = context.currentPage {
            actions.append(AgentAction(
                title: "Save as Note",
                description: "Create a note with this summary",
                type: .createNote(content: "", page: page)
            ))
        }

        actions.append(AgentAction(
            title: "Copy Summary",
            description: "Copy the summary to clipboard",
            type: .copyToClipboard(text: "")
        ))

        return actions
    }
}

// MARK: - Streaming Implementation

extension SummaryAgent {
    func stream(query: String, context: AgentContext) -> AsyncThrowingStream<AgentChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let service = service else {
                    continuation.finish(throwing: AgentError.apiError("API key not configured"))
                    return
                }

                guard let text = context.selectedText ?? context.paperFullText else {
                    continuation.finish(throwing: AgentError.noContent)
                    return
                }

                let summaryLength = context.preferences.summaryLength
                let systemPrompt = buildSystemPrompt(length: summaryLength)
                let userPrompt = buildUserPrompt(
                    query: query,
                    text: text,
                    paperTitle: context.currentPaper?.title,
                    paperAuthors: context.currentPaper?.authors
                )

                let messages = [
                    MessageParameter.Message(role: .user, content: .text(userPrompt))
                ]

                let parameters = MessageParameter(
                    model: .claude35Sonnet,
                    messages: messages,
                    maxTokens: 2048,
                    system: .text(systemPrompt)
                )

                do {
                    let stream = try await service.streamMessage(parameters)
                    for try await response in stream {
                        // Check for text delta in the response
                        if let delta = response.delta, let text = delta.text {
                            continuation.yield(AgentChunk(content: text))
                        }

                        // Check for message stop event
                        if response.streamEvent == .messageStop {
                            continuation.yield(AgentChunk(content: "", isComplete: true))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AgentError.apiError(error.localizedDescription))
                }
            }
        }
    }
}
