import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct PedefApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var appState = AppState()
    @StateObject private var historyService = HistoryService()
    @StateObject private var tagService = TagService()
    @StateObject private var errorReporter = ErrorReporter()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Paper.self,
            Annotation.self,
            Collection.self,
            Tag.self,
            ActionHistory.self,
            ReadingSession.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        let fallbackConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            ErrorReporter.pendingError = ErrorReporter.ErrorItem(
                title: "Storage Error",
                message: "Failed to open the library. Running with temporary storage. \(error.localizedDescription)"
            )
            return try! ModelContainer(for: schema, configurations: [fallbackConfiguration])
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(historyService)
                .environmentObject(tagService)
                .environmentObject(errorReporter)
                .tint(PedefTheme.Brand.indigo)
                .onAppear {
                    tagService.configure(with: sharedModelContainer.mainContext)
                    historyService.setModelContext(sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            PedefCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(errorReporter)
        }

        Window("Agent Assistant", id: "agent-panel") {
            AgentPanelView()
                .environmentObject(appState)
                .environmentObject(errorReporter)
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
        case tag(UUID)
        case tags
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

// MARK: - App Delegate

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring app to foreground when launched
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Bring app to foreground when dock icon is clicked
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even if all windows are closed (standard macOS behavior)
        return false
    }
}
#endif
