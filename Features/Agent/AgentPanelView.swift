import SwiftUI
import MarkdownUI

struct AgentPanelView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = AgentPanelViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            AgentPanelHeader(
                selectedAgent: $viewModel.selectedAgent,
                availableAgents: viewModel.availableAgents,
                onClear: { viewModel.clearMessages() }
            )

            Divider()

            // Context Banner
            if let paper = appState.currentPaper {
                ContextBanner(paper: paper, selectedText: appState.selectedText)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Messages or Welcome
            if viewModel.messages.isEmpty && !viewModel.isStreaming {
                WelcomeView(onAction: handleQuickAction)
            } else {
                MessagesScrollView(
                    messages: viewModel.messages,
                    isStreaming: viewModel.isStreaming,
                    streamingText: viewModel.streamingText
                )
            }

            Divider()

            // Input Area
            AgentInputArea(
                text: $inputText,
                isDisabled: viewModel.isStreaming,
                placeholder: getPlaceholder(),
                onSubmit: sendMessage
            )
            .focused($isInputFocused)
        }
        .frame(minWidth: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isInputFocused = true
            viewModel.setContext(
                paper: appState.currentPaper,
                selectedText: appState.selectedText
            )
        }
        .onChange(of: appState.selectedText) { _, newValue in
            viewModel.updateSelectedText(newValue)
        }
    }

    private func getPlaceholder() -> String {
        if appState.selectedText != nil {
            return "Ask about selected text..."
        } else if appState.currentPaper != nil {
            return "Ask about this paper..."
        }
        return "Ask anything..."
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let query = inputText
        inputText = ""
        Task {
            await viewModel.sendMessage(query)
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        Task {
            await viewModel.executeQuickAction(action)
        }
    }
}

// MARK: - Header

struct AgentPanelHeader: View {
    @Binding var selectedAgent: String
    let availableAgents: [AgentInfo]
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("AI Assistant")
                    .font(.headline)

                Text("Powered by Claude")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Agent picker
            Menu {
                ForEach(availableAgents) { agent in
                    Button {
                        selectedAgent = agent.id
                    } label: {
                        HStack {
                            Text(agent.name)
                            if selectedAgent == agent.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(availableAgents.first { $0.id == selectedAgent }?.name ?? "Agent")
                        .font(.caption.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)

            // Clear button
            Button(action: onClear) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear conversation")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

// MARK: - Context Banner

struct ContextBanner: View {
    let paper: Paper
    let selectedText: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.blue)

                    Text(paper.title)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(.caption)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if !paper.authors.isEmpty {
                        Text(paper.formattedAuthors)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let selection = selectedText, !selection.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Rectangle()
                                .fill(.blue)
                                .frame(width: 2)

                            Text(selection)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                        .padding(.top, 4)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.06))
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    let onAction: (QuickAction) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                // Greeting
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolEffect(.variableColor.iterative)

                    Text("How can I help you?")
                        .font(.title2.weight(.semibold))

                    Text("Ask questions about your papers, get summaries, or explore connections.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggestions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(QuickAction.allCases) { action in
                            QuickActionButton(action: action) {
                                onAction(action)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct QuickActionButton: View {
    let action: QuickAction
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .font(.body)
                    .foregroundStyle(action.color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(action.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(12)
            .background(isHovering ? Color.secondary.opacity(0.1) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Quick Actions

enum QuickAction: String, CaseIterable, Identifiable {
    case summarize
    case explain
    case findRelated
    case extractCitations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize: return "Summarize Paper"
        case .explain: return "Explain Concepts"
        case .findRelated: return "Find Related Work"
        case .extractCitations: return "Extract Citations"
        }
    }

    var description: String {
        switch self {
        case .summarize: return "Get a concise overview of the key findings"
        case .explain: return "Break down complex ideas in simple terms"
        case .findRelated: return "Discover similar papers in your field"
        case .extractCitations: return "Format references in your preferred style"
        }
    }

    var icon: String {
        switch self {
        case .summarize: return "doc.text.magnifyingglass"
        case .explain: return "lightbulb.fill"
        case .findRelated: return "point.3.connected.trianglepath.dotted"
        case .extractCitations: return "quote.bubble.fill"
        }
    }

    var color: Color {
        switch self {
        case .summarize: return .blue
        case .explain: return .yellow
        case .findRelated: return .purple
        case .extractCitations: return .green
        }
    }
}

// MARK: - Messages View

struct MessagesScrollView: View {
    let messages: [AgentMessage]
    let isStreaming: Bool
    let streamingText: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if isStreaming {
                        StreamingBubble(text: streamingText)
                            .id("streaming")
                    }
                }
                .padding(16)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: streamingText) { _, _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }
}

struct MessageBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                MessageAvatar(isAssistant: true)
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .assistant {
                    Markdown(message.content)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(message.role == .user ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if message.role == .user {
                MessageAvatar(isAssistant: false)
            } else {
                Spacer(minLength: 40)
            }
        }
    }
}

struct MessageAvatar: View {
    let isAssistant: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isAssistant ?
                    LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing) :
                    LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 28, height: 28)

            Image(systemName: isAssistant ? "sparkles" : "person.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isAssistant ? .white : .secondary)
        }
    }
}

struct StreamingBubble: View {
    let text: String
    @State private var dotAnimation = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MessageAvatar(isAssistant: true)

            VStack(alignment: .leading, spacing: 6) {
                if text.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(.secondary)
                                .frame(width: 6, height: 6)
                                .scaleEffect(dotAnimation == i ? 1.3 : 1.0)
                                .animation(
                                    .easeInOut(duration: 0.4)
                                    .repeatForever()
                                    .delay(Double(i) * 0.15),
                                    value: dotAnimation
                                )
                        }
                    }
                    .onAppear {
                        dotAnimation = 2
                    }
                } else {
                    Markdown(text)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Input Area

struct AgentInputArea: View {
    @Binding var text: String
    let isDisabled: Bool
    let placeholder: String
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }

                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .onSubmit {
                        if !text.isEmpty {
                            onSubmit()
                        }
                    }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .disabled(isDisabled)

            Button(action: onSubmit) {
                ZStack {
                    Circle()
                        .fill(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 32)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canSend ? .white : .secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
        .padding(12)
        .background(.bar)
    }

    private var canSend: Bool {
        !isDisabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - View Model

struct AgentInfo: Identifiable {
    let id: String
    let name: String
}

@MainActor
final class AgentPanelViewModel: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var isStreaming = false
    @Published var streamingText = ""
    @Published var selectedAgent = "summary"

    let availableAgents: [AgentInfo] = [
        AgentInfo(id: "summary", name: "Summary"),
        AgentInfo(id: "qa", name: "Q&A"),
        AgentInfo(id: "citation", name: "Citation"),
        AgentInfo(id: "research", name: "Research")
    ]

    private var currentPaper: Paper?
    private var selectedText: String?
    private let summaryAgent = SummaryAgent()

    func setContext(paper: Paper?, selectedText: String?) {
        self.currentPaper = paper
        self.selectedText = selectedText
    }

    func updateSelectedText(_ text: String?) {
        self.selectedText = text
    }

    func clearMessages() {
        withAnimation {
            messages.removeAll()
            streamingText = ""
        }
    }

    func sendMessage(_ query: String) async {
        let userMessage = AgentMessage(role: .user, content: query)
        messages.append(userMessage)

        isStreaming = true
        streamingText = ""

        do {
            let context = AgentContext(
                currentPaper: currentPaper,
                selectedText: selectedText,
                paperFullText: nil,
                annotations: currentPaper?.annotations ?? [],
                conversationHistory: messages
            )

            for try await chunk in summaryAgent.stream(query: query, context: context) {
                streamingText += chunk.content
                if chunk.isComplete {
                    break
                }
            }

            let assistantMessage = AgentMessage(role: .assistant, content: streamingText)
            messages.append(assistantMessage)
        } catch {
            let errorMessage = AgentMessage(role: .assistant, content: "I encountered an error: \(error.localizedDescription). Please try again.")
            messages.append(errorMessage)
        }

        isStreaming = false
        streamingText = ""
    }

    func executeQuickAction(_ action: QuickAction) async {
        let query: String
        switch action {
        case .summarize:
            query = "Please provide a comprehensive summary of this paper, including the main research question, methodology, key findings, and contributions."
        case .explain:
            if let text = selectedText, !text.isEmpty {
                query = "Please explain this in simple terms: \(text)"
            } else {
                query = "Please explain the main concepts and terminology in this paper in simple, accessible language."
            }
        case .findRelated:
            query = "Based on this paper's topic and methodology, what are some related papers or research directions I should explore?"
        case .extractCitations:
            query = "Please extract and format the key citations from this paper in APA format."
        }

        await sendMessage(query)
    }
}

// MARK: - Settings Views

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AgentSettingsView()
                .tabItem {
                    Label("AI Agent", systemImage: "sparkles")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 500, height: 350)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("autoSaveInterval") private var autoSaveInterval = 30
    @AppStorage("rememberLastPaper") private var rememberLastPaper = true
    @AppStorage("showReadingProgress") private var showReadingProgress = true

    var body: some View {
        Form {
            Section {
                Picker("Auto-save interval", selection: $autoSaveInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("5 minutes").tag(300)
                }

                Toggle("Remember last opened paper", isOn: $rememberLastPaper)
                Toggle("Show reading progress", isOn: $showReadingProgress)
            } header: {
                Text("Reading")
            }

            Section {
                HStack {
                    Text("Library Location")
                    Spacer()
                    Text("~/Documents/Pedef")
                        .foregroundStyle(.secondary)
                    Button("Change...") { }
                        .buttonStyle(.link)
                }
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AgentSettingsView: View {
    @AppStorage("agentEnabled") private var agentEnabled = true
    @AppStorage("summaryLength") private var summaryLength = "medium"
    @AppStorage("citationStyle") private var citationStyle = "apa"
    @StateObject private var keychainService = KeychainService.shared
    @State private var apiKeyInput = ""
    @State private var showAPIKey = false
    @State private var isSaving = false
    @State private var saveMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI features", isOn: $agentEnabled)
            }

            Section {
                Picker("Summary length", selection: $summaryLength) {
                    Text("Brief (1-2 sentences)").tag("brief")
                    Text("Medium (1 paragraph)").tag("medium")
                    Text("Detailed (multiple paragraphs)").tag("detailed")
                }

                Picker("Citation style", selection: $citationStyle) {
                    Text("APA (7th Edition)").tag("apa")
                    Text("MLA (9th Edition)").tag("mla")
                    Text("Chicago").tag("chicago")
                    Text("IEEE").tag("ieee")
                    Text("BibTeX").tag("bibtex")
                }
            } header: {
                Text("Preferences")
            }

            Section {
                HStack {
                    if showAPIKey {
                        TextField("API Key", text: $apiKeyInput, prompt: Text("sk-ant-..."))
                            .textFieldStyle(.plain)
                    } else {
                        SecureField("API Key", text: $apiKeyInput, prompt: Text("sk-ant-..."))
                            .textFieldStyle(.plain)
                    }

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    if keychainService.hasAPIKey {
                        Label("API key configured", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("No API key configured", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    if !apiKeyInput.isEmpty {
                        Button("Save") {
                            saveAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isSaving)
                    }

                    if keychainService.hasAPIKey {
                        Button("Clear") {
                            clearAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let message = saveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.contains("Error") ? .red : .green)
                }

                Text("Get your API key from console.anthropic.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Your API key is stored securely in the system Keychain.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("Anthropic API")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            // Load masked version if key exists
            if keychainService.hasAPIKey {
                apiKeyInput = ""
            }
        }
    }

    private func saveAPIKey() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            saveMessage = "Error: Please enter an API key"
            return
        }

        guard KeychainService.isValidAPIKeyFormat(trimmedKey) else {
            saveMessage = "Error: Invalid API key format. Should start with 'sk-ant-'"
            return
        }

        isSaving = true
        keychainService.anthropicAPIKey = trimmedKey
        apiKeyInput = ""
        saveMessage = "API key saved securely"
        isSaving = false

        // Clear message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveMessage = nil
        }
    }

    private func clearAPIKey() {
        keychainService.clearAPIKey()
        apiKeyInput = ""
        saveMessage = "API key cleared"

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveMessage = nil
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("readingTheme") private var readingTheme = "system"
    @AppStorage("defaultHighlightColor") private var defaultHighlightColor = "yellow"

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $readingTheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Sepia").tag("sepia")
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Picker("Default highlight color", selection: $defaultHighlightColor) {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(Color(hex: color.rawValue) ?? .yellow)
                                .frame(width: 12, height: 12)
                            Text(color.displayName)
                        }
                        .tag(color.rawValue)
                    }
                }
            } header: {
                Text("Annotations")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                ShortcutRow(action: "Import PDF", shortcut: "⇧⌘I")
                ShortcutRow(action: "Highlight Selection", shortcut: "⌘H")
                ShortcutRow(action: "Add Note", shortcut: "⇧⌘N")
                ShortcutRow(action: "Add Bookmark", shortcut: "⇧⌘B")
            } header: {
                Text("Annotations")
            }

            Section {
                ShortcutRow(action: "Previous Page", shortcut: "⌘←")
                ShortcutRow(action: "Next Page", shortcut: "⌘→")
                ShortcutRow(action: "Zoom In", shortcut: "⌘+")
                ShortcutRow(action: "Zoom Out", shortcut: "⌘-")
            } header: {
                Text("Navigation")
            }

            Section {
                ShortcutRow(action: "Open AI Assistant", shortcut: "⌘K")
                ShortcutRow(action: "Summarize Paper", shortcut: "⇧⌘S")
            } header: {
                Text("AI Assistant")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutRow: View {
    let action: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Preview

#Preview("Agent Panel") {
    AgentPanelView()
        .environmentObject(AppState())
        .frame(width: 420, height: 600)
}

#Preview("Settings") {
    SettingsView()
        .environmentObject(AppState())
}
