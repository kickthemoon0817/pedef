# Pedef - Academic PDF Reader & Knowledge Archive

A native macOS application for academic paper reading, annotation, and personal knowledge management with AI-assisted capabilities.

## Project Overview

**Pedef** is designed for researchers, academics, and knowledge workers who need a powerful tool to:
- Read and annotate PDF documents (especially academic papers)
- Build a personal archive of research papers
- Track reading history and action trails
- Leverage AI agents for document analysis, summarization, and research assistance

## Architecture

### Tech Stack

- **Platform**: macOS 14.0+ (Sonoma)
- **Language**: Swift 6.2+ (Swift Language Mode 5 for compatibility)
- **UI Framework**: SwiftUI with AppKit integration where needed
- **PDF Engine**: PDFKit (native) with custom rendering layer
- **Database**: SwiftData for persistence
- **AI Integration**: Claude API via SwiftAnthropic v2.2.0
- **Markdown**: swift-markdown-ui v2.4.1
- **Security**: KeychainAccess v4.2.2
- **Build System**: Swift Package Manager / Xcode 15+

### Core Modules

```
pedef/
├── App/
│   ├── PedefApp.swift           # Application entry point
│   └── AppDelegate.swift        # macOS app lifecycle
├── Core/
│   ├── Models/                  # Data models
│   │   ├── Paper.swift          # Academic paper entity
│   │   ├── Annotation.swift     # Highlights, notes, drawings
│   │   ├── Collection.swift     # Paper collections/folders
│   │   ├── ActionHistory.swift  # User action tracking
│   │   └── UserProfile.swift    # User preferences
│   ├── Services/
│   │   ├── PDFService.swift     # PDF parsing and rendering
│   │   ├── ArchiveService.swift # Paper storage and retrieval
│   │   ├── SearchService.swift  # Full-text and metadata search
│   │   ├── SyncService.swift    # Cloud sync (future)
│   │   └── HistoryService.swift # Action history management
│   └── Agents/
│       ├── AgentProtocol.swift  # Base agent interface
│       ├── SummaryAgent.swift   # Paper summarization
│       ├── CitationAgent.swift  # Citation extraction/formatting
│       ├── QAAgent.swift        # Question answering on papers
│       └── ResearchAgent.swift  # Cross-paper research assistant
├── Features/
│   ├── Reader/
│   │   ├── PDFReaderView.swift  # Main PDF viewing
│   │   ├── PageNavigator.swift  # Page navigation
│   │   └── ReadingMode.swift    # Focus/distraction-free modes
│   ├── Annotations/
│   │   ├── HighlightTool.swift  # Text highlighting
│   │   ├── NoteSidebar.swift    # Margin notes
│   │   └── DrawingCanvas.swift  # Freeform annotations
│   ├── Library/
│   │   ├── LibraryView.swift    # Paper archive browser
│   │   ├── CollectionView.swift # Collection management
│   │   └── ImportView.swift     # PDF import workflow
│   ├── History/
│   │   ├── TimelineView.swift   # Action history timeline
│   │   ├── UndoManager.swift    # Multi-level undo/redo
│   │   └── SessionReplay.swift  # Review past sessions
│   └── Agent/
│       ├── AgentPanel.swift     # AI assistant interface
│       ├── ChatView.swift       # Conversational UI
│       └── ActionSuggestions.swift # Proactive suggestions
├── Shared/
│   ├── Components/              # Reusable UI components
│   ├── Extensions/              # Swift extensions
│   └── Utilities/               # Helper functions
├── Resources/
│   ├── Assets.xcassets          # Images, icons, colors
│   └── Localizable.strings      # Internationalization
└── Tests/
    ├── UnitTests/
    ├── IntegrationTests/
    └── UITests/
```

## Key Features

### 1. PDF Reader
- High-fidelity PDF rendering with smooth scrolling
- Multiple viewing modes: single page, continuous, two-page spread
- Text selection and search within documents
- Outline/table of contents navigation
- Zoom and page fit options
- Dark mode and custom color themes
- Reading progress tracking

### 2. Annotation System
- **Highlights**: Multiple colors with labels/tags
- **Sticky Notes**: Expandable margin notes
- **Text Notes**: Inline annotations
- **Drawings**: Freeform pen/shape tools
- **Bookmarks**: Quick navigation markers
- All annotations are non-destructive and exportable

### 3. Personal Archive
- **Import**: Drag-drop, file picker, URL import, DOI lookup
- **Metadata**: Auto-extraction of title, authors, abstract, keywords
- **Collections**: Folders, smart collections, tags
- **Search**: Full-text search across all papers and notes
- **Deduplication**: Detect and merge duplicate papers

### 4. Action History System
- Track all user actions with timestamps
- Granular undo/redo with branching history
- Session replay for review
- Reading statistics and analytics
- Export reading history for research

### 5. AI Agents
- **Summary Agent**: Generate paper summaries at different detail levels
- **Citation Agent**: Extract, format, and manage citations
- **Q&A Agent**: Ask questions about the current paper
- **Research Agent**: Find connections across papers, suggest related work
- **Writing Agent**: Help draft responses, notes, reviews

## Data Models

### Paper
```swift
@Model
class Paper {
    var id: UUID
    var title: String
    var authors: [String]
    var abstract: String?
    var doi: String?
    var arxivId: String?
    var publishedDate: Date?
    var importedDate: Date
    var pdfData: Data
    var thumbnailData: Data?
    var collections: [Collection]
    var annotations: [Annotation]
    var metadata: [String: String]
    var readingProgress: Double
    var lastOpenedDate: Date?
}
```

### Annotation
```swift
@Model
class Annotation {
    var id: UUID
    var type: AnnotationType  // highlight, note, drawing, bookmark
    var pageIndex: Int
    var bounds: CGRect
    var content: String?
    var color: String
    var createdDate: Date
    var modifiedDate: Date
    var tags: [String]
}
```

### ActionHistory
```swift
@Model
class ActionHistory {
    var id: UUID
    var actionType: ActionType
    var timestamp: Date
    var paperId: UUID?
    var details: [String: Any]
    var undoData: Data?
    var sessionId: UUID
}
```

## Agent Integration

### Agent Protocol
```swift
protocol PedefAgent {
    var name: String { get }
    var description: String { get }
    var capabilities: [AgentCapability] { get }

    func execute(context: AgentContext) async throws -> AgentResult
    func stream(context: AgentContext) -> AsyncThrowingStream<AgentChunk, Error>
}
```

### Agent Context
Agents receive:
- Current paper content (full text or selection)
- User's annotations and notes
- Related papers in the archive
- Conversation history
- User preferences

### Available Actions
Agents can:
- Add annotations to papers
- Create notes
- Search the archive
- Suggest related papers
- Generate formatted citations
- Draft text responses

## Development Guidelines

### Code Style
- Follow Swift API Design Guidelines
- Use SwiftLint for consistency
- Prefer value types where appropriate
- Use async/await for asynchronous operations
- Document public APIs with DocC comments

### Testing
- Unit tests for all services and models
- Integration tests for database operations
- UI tests for critical user flows
- Minimum 70% code coverage target

### Performance
- Lazy loading for PDF pages
- Background indexing for search
- Efficient memory management for large PDFs
- Responsive UI on main thread

### Accessibility
- Full VoiceOver support
- Keyboard navigation
- Dynamic Type support
- Sufficient color contrast

## Build & Run

```bash
# Clone repository
git clone https://github.com/user/pedef.git
cd pedef

# Open in Xcode
open Pedef.xcodeproj

# Or build from command line
xcodebuild -scheme Pedef -configuration Debug build

# Run tests
xcodebuild -scheme Pedef test
```

## Configuration

### Environment Variables
- `ANTHROPIC_API_KEY`: API key for Claude integration
- `PEDEF_DEBUG_LOGGING`: Enable verbose logging

### User Defaults
- `readingTheme`: Light/Dark/Sepia/Custom
- `defaultHighlightColor`: Hex color
- `autoSaveInterval`: Seconds between auto-saves
- `agentEnabled`: Toggle AI features

## Roadmap

### Phase 1: Core Reader (MVP)
- [ ] Basic PDF viewing and navigation
- [ ] Text selection and search
- [ ] Highlight annotations
- [ ] Simple library management
- [ ] Local storage with SwiftData

### Phase 2: Advanced Annotations
- [ ] All annotation types
- [ ] Tag system
- [ ] Export annotations
- [ ] Reading statistics

### Phase 3: Agent Integration
- [ ] Claude API integration
- [ ] Summary agent
- [ ] Q&A agent
- [ ] Citation agent

### Phase 4: Power Features
- [ ] Cross-paper search
- [ ] Research agent
- [ ] Action history with replay
- [ ] Cloud sync
- [ ] Collaboration features

## Contributing

1. Create a feature branch from `main`
2. Follow code style guidelines
3. Add tests for new functionality
4. Update documentation as needed
5. Submit PR with clear description

## License

Private - All rights reserved

---

*Pedef: Your Personal Academic Knowledge Base*
