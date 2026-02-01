import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tagService: TagService
    @EnvironmentObject private var errorReporter: ErrorReporter
    @Environment(\.modelContext) private var modelContext
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isImporting = false
    @State private var isDragOver = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            detailContent
            .overlay {
                if isDragOver {
                    DragOverlay()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if appState.currentPaper != nil {
                    ReaderToolbar()
                }
            }
        }
        .sheet(isPresented: $appState.isAgentPanelVisible) {
            AgentPanelView()
                .frame(minWidth: 420, minHeight: 550)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .onDrop(of: [.pdf, .fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .importPDF)) { _ in
            isImporting = true
        }
        .onAppear {
            errorReporter.flushPending()
        }
        .alert(item: $errorReporter.currentError) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let paper = appState.currentPaper {
            PDFReaderView(paper: paper)
        } else {
            switch appState.sidebarSelection ?? .library {
            case .library:
                LibraryView(scope: .all)
            case .recentlyRead:
                LibraryView(scope: .recentlyRead)
            case .favorites:
                LibraryView(scope: .favorites)
            case .readingList:
                LibraryView(scope: .readingList)
            case .collection(let id):
                LibraryView(scope: .collection(id))
            case .tag(let id):
                LibraryView(scope: .tag(id))
            case .tags:
                TagManagerView(tagService: tagService)
            case .history:
                TimelineView()
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                importPDF(from: url)
            }
        case .failure(let error):
            errorReporter.report(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                    if let error = error {
                        Task { @MainActor in
                            errorReporter.report(title: "Import Failed", message: error.localizedDescription)
                        }
                        return
                    }

                    guard let url = url else {
                        Task { @MainActor in
                            errorReporter.report(title: "Import Failed", message: "Unable to access the dropped file.")
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        importPDF(from: url)
                    }
                }
            }
        }
        return true
    }

    private func importPDF(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorReporter.report(title: "Access Denied", message: "Unable to access the selected file. Check file permissions and try again.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let title = url.deletingPathExtension().lastPathComponent
            let paper = Paper(title: title, pdfData: data)
            modelContext.insert(paper)
        } catch {
            errorReporter.report(title: "Import Failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Drag Overlay

struct DragOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.1)

            VStack(spacing: 16) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Drop PDFs to Import")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var collections: [Collection]
    @Query private var papers: [Paper]
    @Query private var tags: [Tag]

    private var recentPapersCount: Int {
        papers.filter { paper in
            guard let date = paper.lastOpenedDate else { return false }
            return date > Date().addingTimeInterval(-7 * 24 * 60 * 60)
        }.count
    }

    private var favoritesCount: Int {
        papers.filter { $0.tags.contains("favorite") }.count
    }

    var body: some View {
        List(selection: $appState.sidebarSelection) {
            Section {
                NavigationLink(value: AppState.SidebarItem.library) {
                    Label("All Papers", systemImage: "doc.on.doc.fill")
                }
                .badge(papers.count)

                NavigationLink(value: AppState.SidebarItem.recentlyRead) {
                    Label("Recently Read", systemImage: "clock.fill")
                }
                .badge(recentPapersCount)

                NavigationLink(value: AppState.SidebarItem.favorites) {
                    Label("Favorites", systemImage: "star.fill")
                }
                .badge(favoritesCount)

                NavigationLink(value: AppState.SidebarItem.readingList) {
                    Label("Reading List", systemImage: "books.vertical.fill")
                }

                NavigationLink(value: AppState.SidebarItem.tags) {
                    Label("Tags", systemImage: "tag.fill")
                }
                .badge(tags.count)
            } header: {
                Text("Library")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(collections.filter { $0.parent == nil }) { collection in
                    CollectionRow(collection: collection)
                }

                Button {
                    createCollection()
                } label: {
                    Label("New Collection", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Collections")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink(value: AppState.SidebarItem.history) {
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text("Tools")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pedef")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .importPDF, object: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .help("Import PDF (⇧⌘I)")
            }
        }
    }

    private func createCollection() {
        let collection = Collection(name: "New Collection")
        modelContext.insert(collection)
    }
}

struct CollectionRow: View {
    let collection: Collection
    @State private var isEditing = false
    @State private var editedName = ""

    var body: some View {
        NavigationLink(value: AppState.SidebarItem.collection(collection.id)) {
            Label {
                if isEditing {
                    TextField("Name", text: $editedName, onCommit: {
                        collection.name = editedName
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                } else {
                    Text(collection.name)
                }
            } icon: {
                Image(systemName: collection.type.systemImage)
                    .foregroundStyle(Color(hex: collection.colorHex ?? "#007AFF") ?? .accentColor)
            }
        }
        .badge(collection.paperCount)
        .contextMenu {
            Button("Rename") {
                editedName = collection.name
                isEditing = true
            }
            Button("Change Color") { }
            Divider()
            Button("Delete", role: .destructive) { }
        }
    }
}

// MARK: - Reader Toolbar

struct ReaderToolbar: View {
    @EnvironmentObject private var appState: AppState
    @State private var showHighlightColors = false

    var body: some View {
        Group {
            // Highlight with color picker
            Menu {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    Button {
                        // Create highlight with this color
                        NotificationCenter.default.post(name: .highlightSelection, object: color)
                    } label: {
                        Label(color.displayName, systemImage: "circle.fill")
                    }
                }
            } label: {
                Image(systemName: "highlighter")
            } primaryAction: {
                NotificationCenter.default.post(name: .highlightSelection, object: nil)
            }
            .help("Highlight Selection (⌘H)")

            Button {
                NotificationCenter.default.post(name: .addNote, object: nil)
            } label: {
                Image(systemName: "note.text.badge.plus")
            }
            .help("Add Note (⇧⌘N)")

            Button {
                NotificationCenter.default.post(name: .addBookmark, object: nil)
            } label: {
                Image(systemName: "bookmark")
            }
            .help("Add Bookmark (⇧⌘B)")

            Divider()

            Button {
                appState.isAgentPanelVisible.toggle()
            } label: {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.multicolor)
            }
            .help("Ask AI Assistant (⌘K)")

            Button {
                appState.closePaper()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Close Paper")
        }
    }
}

// MARK: - Library View

fileprivate enum LibraryScope {
    case all
    case recentlyRead
    case favorites
    case readingList
    case collection(UUID)
    case tag(UUID)
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Paper.importedDate, order: .reverse) private var papers: [Paper]
    @Query private var collections: [Collection]
    @State private var searchText = ""
    @State private var selectedPapers: Set<UUID> = []
    @State private var viewMode: ViewMode = .grid
    @State private var sortOrder: SortOrder = .dateImported

    fileprivate let scope: LibraryScope

    fileprivate init(scope: LibraryScope = .all) {
        self.scope = scope
    }

    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"

        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    enum SortOrder: String, CaseIterable {
        case dateImported = "Date Imported"
        case dateRead = "Last Read"
        case title = "Title"
        case author = "Author"
    }

    private var filteredPapers: [Paper] {
        var result = scopedPapers
        if !searchText.isEmpty {
            result = result.filter { $0.searchableText.localizedCaseInsensitiveContains(searchText) }
        }
        return sortPapers(result)
    }

    private var scopedPapers: [Paper] {
        switch scope {
        case .all:
            return papers
        case .recentlyRead:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            return papers.filter { ($0.lastOpenedDate ?? .distantPast) > cutoff }
        case .favorites:
            return papers.filter { paper in
                paper.tags.contains("favorite") || paper.tagObjects.contains { $0.name == "favorite" }
            }
        case .readingList:
            return papers.filter { !$0.isRead }
        case .collection(let id):
            return papers.filter { paper in
                paper.collections.contains { $0.id == id }
            }
        case .tag(let id):
            return papers.filter { paper in
                paper.tagObjects.contains { $0.id == id }
            }
        }
    }

    private var libraryTitle: String {
        switch scope {
        case .all:
            return "Library"
        case .recentlyRead:
            return "Recently Read"
        case .favorites:
            return "Favorites"
        case .readingList:
            return "Reading List"
        case .collection(let id):
            return collections.first { $0.id == id }?.name ?? "Collection"
        case .tag(let id):
            return papers.flatMap(\.tagObjects).first { $0.id == id }?.name ?? "Tag"
        }
    }

    private func sortPapers(_ papers: [Paper]) -> [Paper] {
        switch sortOrder {
        case .dateImported:
            return papers.sorted { $0.importedDate > $1.importedDate }
        case .dateRead:
            return papers.sorted { ($0.lastOpenedDate ?? .distantPast) > ($1.lastOpenedDate ?? .distantPast) }
        case .title:
            return papers.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author:
            return papers.sorted {
                ($0.authors.first ?? "").localizedCaseInsensitiveCompare($1.authors.first ?? "") == .orderedAscending
            }
        }
    }

    var body: some View {
        Group {
            if papers.isEmpty {
                EmptyLibraryView()
            } else {
                switch viewMode {
                case .grid:
                    PaperGridView(papers: filteredPapers, selection: $selectedPapers)
                case .list:
                    PaperListView(papers: filteredPapers, selection: $selectedPapers)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search papers, authors, keywords...")
        .navigationTitle(libraryTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            if sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("Sort Order")

                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("View Mode")
            }
        }
    }
}

struct EmptyLibraryView: View {
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 8) {
                Text("Your Library is Empty")
                    .font(.title2.weight(.semibold))

                Text("Import PDFs to start organizing your research papers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: .importPDF, object: nil)
                } label: {
                    Label("Import PDF", systemImage: "plus.circle.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("or drag and drop files here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Keyboard shortcut hints
            HStack(spacing: 24) {
                KeyboardShortcutHint(keys: "⇧⌘I", action: "Import")
                KeyboardShortcutHint(keys: "⌘K", action: "AI Assistant")
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct KeyboardShortcutHint: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Paper Grid View

struct PaperGridView: View {
    let papers: [Paper]
    @Binding var selection: Set<UUID>
    @EnvironmentObject private var appState: AppState

    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(papers) { paper in
                    PaperCard(paper: paper, isSelected: selection.contains(paper.id))
                        .onTapGesture {
                            appState.openPaper(paper)
                        }
                        .contextMenu {
                            PaperContextMenu(paper: paper)
                        }
                }
            }
            .padding(20)
        }
    }
}

struct PaperCard: View {
    let paper: Paper
    let isSelected: Bool
    @State private var isHovering = false
    @Environment(\.modelContext) private var modelContext

    private var isFavorite: Bool {
        paper.tags.contains("favorite")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
                    .aspectRatio(0.75, contentMode: .fit)
                    .overlay {
                        if let thumbnailData = paper.thumbnailData,
                           let nsImage = NSImage(data: thumbnailData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipped()
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.tertiary)
                                Text("PDF")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.quaternary)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Quick actions overlay
                if isHovering {
                    HStack(spacing: 4) {
                        Button {
                            toggleFavorite()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundStyle(isFavorite ? .yellow : .white)
                                .padding(6)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                // Reading progress indicator
                if paper.readingProgress > 0 && paper.readingProgress < 1 {
                    CircularProgressView(progress: paper.readingProgress)
                        .frame(width: 28, height: 28)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(paper.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(paper.formattedAuthors)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if paper.hasAnnotations {
                        Label("\(paper.annotations.count)", systemImage: "highlighter")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if paper.isRead {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    if let date = paper.lastOpenedDate {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovering ? Color.secondary.opacity(0.05) : Color.clear))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
    }

    private func toggleFavorite() {
        if isFavorite {
            paper.tags.removeAll { $0 == "favorite" }
        } else {
            paper.tags.append("favorite")
        }
    }
}

struct PaperContextMenu: View {
    let paper: Paper
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            Button {
                // Open
            } label: {
                Label("Open", systemImage: "doc.text")
            }

            Divider()

            Button {
                if paper.tags.contains("favorite") {
                    paper.tags.removeAll { $0 == "favorite" }
                } else {
                    paper.tags.append("favorite")
                }
            } label: {
                Label(paper.tags.contains("favorite") ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: paper.tags.contains("favorite") ? "star.slash" : "star")
            }

            Menu("Add to Collection") {
                Button("New Collection...") { }
            }

            Divider()

            Button {
                // Export
            } label: {
                Label("Export...", systemImage: "square.and.arrow.up")
            }

            Button {
                // Show in Finder
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive) {
                modelContext.delete(paper)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Paper List View

struct PaperListView: View {
    let papers: [Paper]
    @Binding var selection: Set<UUID>
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(papers, selection: $selection) { paper in
            PaperRow(paper: paper)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    appState.openPaper(paper)
                }
                .contextMenu {
                    PaperContextMenu(paper: paper)
                }
        }
        .listStyle(.inset)
    }
}

struct PaperRow: View {
    let paper: Paper
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 44, height: 60)
                .overlay {
                    if let thumbnailData = paper.thumbnailData,
                       let nsImage = NSImage(data: thumbnailData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(paper.formattedAuthors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    if let journal = paper.journal {
                        Text(journal)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if paper.hasAnnotations {
                        Label("\(paper.annotations.count)", systemImage: "highlighter")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if paper.tags.contains("favorite") {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }

            Spacer()

            // Right side indicators
            VStack(alignment: .trailing, spacing: 4) {
                if paper.readingProgress > 0 && paper.readingProgress < 1 {
                    CircularProgressView(progress: paper.readingProgress)
                        .frame(width: 28, height: 28)
                } else if paper.isRead {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }

                if let date = paper.lastOpenedDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .background(isHovering ? Color.secondary.opacity(0.05) : Color.clear)
        .onHover { isHovering = $0 }
    }
}

struct CircularProgressView: View {
    let progress: Double
    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 3)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(animatedProgress * 100))")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = progress
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(HistoryService())
        .frame(width: 1200, height: 800)
}
