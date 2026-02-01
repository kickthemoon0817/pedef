import SwiftUI
import SwiftData

@main
struct PedefApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var historyService = HistoryService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Paper.self,
            Annotation.self,
            Collection.self,
            ActionHistory.self,
            ReadingSession.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(historyService)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            PedefCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        Window("Agent Assistant", id: "agent-panel") {
            AgentPanelView()
                .environmentObject(appState)
        }
        .defaultSize(width: 400, height: 600)
        #endif
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var currentPaper: Paper?
    @Published var selectedText: String?
    @Published var currentPage: Int = 0
    @Published var isAgentPanelVisible: Bool = false
    @Published var searchQuery: String = ""
    @Published var sidebarSelection: SidebarItem? = .library

    enum SidebarItem: Hashable {
        case library
        case collection(UUID)
        case readingList
        case favorites
        case recentlyRead
        case history
    }

    func openPaper(_ paper: Paper) {
        currentPaper = paper
        currentPage = paper.currentPage
    }

    func closePaper() {
        currentPaper = nil
        selectedText = nil
        currentPage = 0
    }
}

// MARK: - Commands

struct PedefCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import PDF...") {
                NotificationCenter.default.post(name: .importPDF, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandMenu("Paper") {
            Button("Previous Page") {
                NotificationCenter.default.post(name: .previousPage, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Next Page") {
                NotificationCenter.default.post(name: .nextPage, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button("Zoom In") {
                NotificationCenter.default.post(name: .zoomIn, object: nil)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                NotificationCenter.default.post(name: .zoomOut, object: nil)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Fit to Width") {
                NotificationCenter.default.post(name: .fitToWidth, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu("Annotate") {
            Button("Highlight Selection") {
                NotificationCenter.default.post(name: .highlightSelection, object: nil)
            }
            .keyboardShortcut("h", modifiers: .command)

            Button("Add Note") {
                NotificationCenter.default.post(name: .addNote, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Add Bookmark") {
                NotificationCenter.default.post(name: .addBookmark, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        CommandMenu("Agent") {
            Button("Ask AI...") {
                NotificationCenter.default.post(name: .openAgentPanel, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button("Summarize Paper") {
                NotificationCenter.default.post(name: .summarizePaper, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Explain Selection") {
                NotificationCenter.default.post(name: .explainSelection, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let importPDF = Notification.Name("importPDF")
    static let previousPage = Notification.Name("previousPage")
    static let nextPage = Notification.Name("nextPage")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let fitToWidth = Notification.Name("fitToWidth")
    static let highlightSelection = Notification.Name("highlightSelection")
    static let addNote = Notification.Name("addNote")
    static let addBookmark = Notification.Name("addBookmark")
    static let openAgentPanel = Notification.Name("openAgentPanel")
    static let summarizePaper = Notification.Name("summarizePaper")
    static let explainSelection = Notification.Name("explainSelection")
}
