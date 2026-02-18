import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Collection Colors

enum CollectionColor: CaseIterable {
    case indigo, purple, blue, teal, green, yellow, orange, pink, gray

    var hex: String {
        PedefTheme.CollectionPalette.colors[CollectionColor.allCases.firstIndex(of: self) ?? 0].hex
    }

    var displayName: String {
        PedefTheme.CollectionPalette.colors[CollectionColor.allCases.firstIndex(of: self) ?? 0].name
    }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tagService: TagService
    @EnvironmentObject private var errorReporter: ErrorReporter
    @Environment(\.modelContext) private var modelContext
    @State private var isImporting = false
    @State private var isDragOver = false

    var body: some View {
        HStack(spacing: 0) {
            // Custom sidebar
            SidebarView()
                .frame(width: 240)

            // Thin custom divider
            Rectangle()
                .fill(PedefTheme.TextColor.tertiary.opacity(0.15))
                .frame(width: 1)

            // Detail content
            VStack(spacing: 0) {
                detailContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PedefTheme.Surface.primary)
            .overlay {
                if isDragOver {
                    DragOverlay()
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
        .onChange(of: appState.sidebarSelection) {
            if appState.currentPaper != nil {
                appState.closePaper()
            }
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

            // Validate PDF
            guard PDFService.shared.isValidPDF(data) else {
                errorReporter.report(title: "Invalid File", message: "The selected file is not a valid PDF document.")
                return
            }

            // Extract metadata
            let metadata = PDFService.shared.extractMetadata(from: data)
            let documentInfo = PDFService.shared.getDocumentInfo(from: data)

            // Use extracted title or filename as fallback
            let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? metadata!.title!
                : url.deletingPathExtension().lastPathComponent

            let paper = Paper(
                title: title,
                authors: metadata?.authors ?? [],
                pdfData: data,
                pageCount: documentInfo?.pageCount ?? 0
            )

            // Set additional metadata
            paper.abstract = metadata?.subject
            paper.keywords = metadata?.keywords ?? []

            // Generate thumbnail
            if let thumbnailData = PDFService.shared.generateThumbnail(from: data) {
                paper.thumbnailData = thumbnailData
            }

            modelContext.insert(paper)
            try modelContext.save()
        } catch {
            errorReporter.report(title: "Import Failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Drag Overlay

struct DragOverlay: View {
    var body: some View {
        ZStack {
            PedefTheme.Brand.indigo.opacity(0.10)

            VStack(spacing: PedefTheme.Spacing.lg) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(PedefTheme.Brand.indigo)

                Text("Drop PDFs to Import")
                    .font(PedefTheme.Typography.title3)
                    .foregroundStyle(.primary)
            }
            .padding(PedefTheme.Spacing.xxxxl)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.xl))
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
        VStack(spacing: 0) {
            // Custom sidebar header (also serves as window drag region)
            HStack {
                Text("Pedef")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PedefTheme.Brand.indigo)

                Spacer()

                Button {
                    NotificationCenter.default.post(name: .importPDF, object: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PedefTheme.Brand.indigo)
                        .frame(width: 24, height: 24)
                        .background(PedefTheme.Brand.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                }
                .buttonStyle(.plain)
                .help("Import PDF (⇧⌘I)")
            }
            .padding(.horizontal, PedefTheme.Spacing.lg)
            .padding(.top, PedefTheme.Spacing.xl)
            .padding(.bottom, PedefTheme.Spacing.md)
            .background(WindowDragArea())

            // Sidebar content
            ScrollView {
                VStack(alignment: .leading, spacing: PedefTheme.Spacing.xxs) {
                    // LIBRARY section
                    SidebarSectionHeader(title: "LIBRARY")

                    SidebarItem(
                        icon: "doc.on.doc.fill",
                        label: "All Papers",
                        count: papers.count,
                        isSelected: appState.sidebarSelection == .library
                    ) { appState.sidebarSelection = .library }

                    SidebarItem(
                        icon: "clock.fill",
                        label: "Recently Read",
                        count: recentPapersCount,
                        isSelected: appState.sidebarSelection == .recentlyRead
                    ) { appState.sidebarSelection = .recentlyRead }

                    SidebarItem(
                        icon: "star.fill",
                        label: "Favorites",
                        count: favoritesCount,
                        isSelected: appState.sidebarSelection == .favorites
                    ) { appState.sidebarSelection = .favorites }

                    SidebarItem(
                        icon: "books.vertical.fill",
                        label: "Reading List",
                        isSelected: appState.sidebarSelection == .readingList
                    ) { appState.sidebarSelection = .readingList }

                    SidebarItem(
                        icon: "tag.fill",
                        label: "Tags",
                        count: tags.count,
                        isSelected: appState.sidebarSelection == .tags
                    ) { appState.sidebarSelection = .tags }

                    // COLLECTIONS section
                    SidebarSectionHeader(title: "COLLECTIONS")
                        .padding(.top, PedefTheme.Spacing.sm)

                    ForEach(collections.filter { $0.parent == nil }) { collection in
                        SidebarCollectionItem(
                            collection: collection,
                            isSelected: appState.sidebarSelection == .collection(collection.id)
                        ) {
                            appState.sidebarSelection = .collection(collection.id)
                        }
                    }

                    Button {
                        createCollection()
                    } label: {
                        HStack(spacing: PedefTheme.Spacing.sm) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(PedefTheme.TextColor.tertiary)
                                .frame(width: 20)
                            Text("New Collection")
                                .font(PedefTheme.Typography.callout)
                                .foregroundStyle(PedefTheme.TextColor.tertiary)
                        }
                        .padding(.horizontal, PedefTheme.Spacing.md)
                        .padding(.vertical, PedefTheme.Spacing.xs)
                    }
                    .buttonStyle(.plain)

                    // TOOLS section
                    SidebarSectionHeader(title: "TOOLS")
                        .padding(.top, PedefTheme.Spacing.sm)

                    SidebarItem(
                        icon: "clock.arrow.circlepath",
                        label: "Activity",
                        isSelected: appState.sidebarSelection == .history
                    ) { appState.sidebarSelection = .history }
                }
                .padding(.horizontal, PedefTheme.Spacing.sm)
                .padding(.bottom, PedefTheme.Spacing.lg)
            }
        }
        .background(PedefTheme.Surface.sidebar)
    }

    private func createCollection() {
        let collection = Collection(name: "New Collection")
        modelContext.insert(collection)
    }
}

// MARK: - Custom Sidebar Components

struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(PedefTheme.Typography.caption2)
            .tracking(1.2)
            .foregroundStyle(PedefTheme.TextColor.tertiary)
            .padding(.horizontal, PedefTheme.Spacing.md)
            .padding(.top, PedefTheme.Spacing.xs)
            .padding(.bottom, PedefTheme.Spacing.xxs)
    }
}

struct SidebarItem: View {
    let icon: String
    let label: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PedefTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? PedefTheme.Brand.indigo : PedefTheme.TextColor.secondary)
                    .frame(width: 20)

                Text(label)
                    .font(PedefTheme.Typography.callout)
                    .foregroundStyle(isSelected ? PedefTheme.TextColor.primary : PedefTheme.TextColor.secondary)

                Spacer()

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(PedefTheme.Typography.caption2)
                        .foregroundStyle(PedefTheme.TextColor.tertiary)
                        .padding(.horizontal, PedefTheme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.xs))
                }
            }
            .padding(.horizontal, PedefTheme.Spacing.md)
            .padding(.vertical, PedefTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: PedefTheme.Radius.sm)
                    .fill(isSelected ? PedefTheme.Surface.selected : (isHovered ? PedefTheme.Surface.hover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(count != nil && count! > 0 ? "\(label), \(count!) items" : label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SidebarCollectionItem: View {
    let collection: Collection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var editedName = ""

    var body: some View {
        Button(action: action) {
            HStack(spacing: PedefTheme.Spacing.sm) {
                Image(systemName: collection.type.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: collection.colorHex ?? PedefTheme.CollectionPalette.colors[0].hex) ?? PedefTheme.Brand.indigo)
                    .frame(width: 20)

                if isEditing {
                    TextField("Name", text: $editedName, onCommit: {
                        collection.name = editedName
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                    .font(PedefTheme.Typography.callout)
                } else {
                    Text(collection.name)
                        .font(PedefTheme.Typography.callout)
                        .foregroundStyle(isSelected ? PedefTheme.TextColor.primary : PedefTheme.TextColor.secondary)
                }

                Spacer()

                if collection.paperCount > 0 {
                    Text("\(collection.paperCount)")
                        .font(PedefTheme.Typography.caption2)
                        .foregroundStyle(PedefTheme.TextColor.tertiary)
                        .padding(.horizontal, PedefTheme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.xs))
                }
            }
            .padding(.horizontal, PedefTheme.Spacing.md)
            .padding(.vertical, PedefTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: PedefTheme.Radius.sm)
                    .fill(isSelected ? PedefTheme.Surface.selected : (isHovered ? PedefTheme.Surface.hover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Rename") {
                editedName = collection.name
                isEditing = true
            }

            Menu("Change Color") {
                ForEach(CollectionColor.allCases, id: \.self) { color in
                    Button {
                        collection.colorHex = color.hex
                        collection.modifiedDate = Date()
                    } label: {
                        Label(color.displayName, systemImage: "circle.fill")
                    }
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                modelContext.delete(collection)
            }
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
        VStack(spacing: 0) {
            // Custom branded header bar
            HStack(spacing: PedefTheme.Spacing.md) {
                Text(libraryTitle)
                    .font(PedefTheme.Typography.title3)
                    .foregroundStyle(PedefTheme.TextColor.primary)

                Text("\(filteredPapers.count)")
                    .font(PedefTheme.Typography.caption)
                    .foregroundStyle(PedefTheme.TextColor.tertiary)
                    .padding(.horizontal, PedefTheme.Spacing.sm)
                    .padding(.vertical, PedefTheme.Spacing.xxxs)
                    .background(PedefTheme.Surface.hover, in: Capsule())

                Spacer()

                // Search field
                PedefSearchField(text: $searchText, placeholder: "Search papers...")
                    .frame(maxWidth: 240)

                // Sort button
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
                    HStack(spacing: PedefTheme.Spacing.xxs) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                        Text(sortOrder.rawValue)
                            .font(PedefTheme.Typography.caption)
                    }
                    .foregroundStyle(PedefTheme.TextColor.secondary)
                    .padding(.horizontal, PedefTheme.Spacing.sm)
                    .padding(.vertical, PedefTheme.Spacing.xs)
                    .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Sort Order")

                // View mode toggle
                PedefSegmentedPicker(
                    selection: $viewMode,
                    items: ViewMode.allCases.map { ($0, $0.icon) }
                )
                .help("View Mode")
            }
            .padding(.horizontal, PedefTheme.Spacing.xl)
            .padding(.vertical, PedefTheme.Spacing.md)
            .background(PedefTheme.Surface.bar)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(PedefTheme.TextColor.tertiary.opacity(0.15))
                    .frame(height: 1)
            }
            .background(WindowDragArea())

            // Content
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
    }
}

struct EmptyLibraryView: View {
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: PedefTheme.Spacing.xxl) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(PedefTheme.Brand.indigo.opacity(0.3))
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: PedefTheme.Spacing.sm) {
                Text("Your Library is Empty")
                    .font(PedefTheme.Typography.title2)

                Text("Import PDFs to start organizing your research papers")
                    .font(PedefTheme.Typography.subheadline)
                    .foregroundStyle(PedefTheme.TextColor.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: PedefTheme.Spacing.md) {
                Button {
                    NotificationCenter.default.post(name: .importPDF, object: nil)
                } label: {
                    Label("Import PDF", systemImage: "plus.circle.fill")
                        .font(PedefTheme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(minWidth: 160)
                        .padding(.horizontal, PedefTheme.Spacing.xxl)
                        .padding(.vertical, PedefTheme.Spacing.md)
                        .background(PedefTheme.Brand.indigo, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.md))
                }
                .buttonStyle(.plain)

                Text("or drag and drop files here")
                    .font(PedefTheme.Typography.caption)
                    .foregroundStyle(PedefTheme.TextColor.tertiary)
            }

            // Keyboard shortcut hints
            HStack(spacing: PedefTheme.Spacing.xxl) {
                KeyboardShortcutHint(keys: "⇧⌘I", action: "Import")
                KeyboardShortcutHint(keys: "⌘K", action: "AI Assistant")
            }
            .padding(.top, PedefTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PedefTheme.Surface.primary)
    }
}

struct KeyboardShortcutHint: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(spacing: PedefTheme.Spacing.xs) {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, PedefTheme.Spacing.xs)
                .padding(.vertical, 3)
                .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.xs))

            Text(action)
                .font(PedefTheme.Typography.caption)
                .foregroundStyle(PedefTheme.TextColor.secondary)
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
                    Button {
                        appState.openPaper(paper)
                    } label: {
                        PaperCard(paper: paper, isSelected: selection.contains(paper.id))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        PaperContextMenu(paper: paper)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(paperAccessibilityLabel(for: paper))
                    .accessibilityHint("Double tap to open this paper")
                }
            }
            .padding(20)
        }
    }

    private func paperAccessibilityLabel(for paper: Paper) -> String {
        var components: [String] = [paper.title]
        if !paper.authors.isEmpty {
            components.append("by \(paper.formattedAuthors)")
        }
        if paper.isRead {
            components.append("read")
        } else if paper.readingProgress > 0 {
            components.append("\(Int(paper.readingProgress * 100))% complete")
        }
        if paper.tags.contains("favorite") {
            components.append("favorite")
        }
        if paper.hasAnnotations {
            components.append("\(paper.annotations.count) annotations")
        }
        return components.joined(separator: ", ")
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
                RoundedRectangle(cornerRadius: PedefTheme.Radius.md)
                    .fill(PedefTheme.Surface.hover)
                    .aspectRatio(0.75, contentMode: .fit)
                    .overlay {
                        if let thumbnailData = paper.thumbnailData,
                           let image = PlatformImage(data: thumbnailData) {
                            Image(platformImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipped()
                        } else {
                            VStack(spacing: PedefTheme.Spacing.sm) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(PedefTheme.TextColor.tertiary)
                                Text("PDF")
                                    .font(PedefTheme.Typography.caption2)
                                    .foregroundStyle(PedefTheme.TextColor.tertiary)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.md))

                // Quick actions overlay
                if isHovering {
                    HStack(spacing: PedefTheme.Spacing.xxs) {
                        Button {
                            toggleFavorite()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundStyle(isFavorite ? PedefTheme.Brand.purple : .white)
                                .padding(6)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                    }
                    .padding(PedefTheme.Spacing.sm)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                // Reading progress indicator
                if paper.readingProgress > 0 && paper.readingProgress < 1 {
                    CircularProgressView(progress: paper.readingProgress)
                        .frame(width: 28, height: 28)
                        .padding(PedefTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: PedefTheme.Spacing.xxs) {
                Text(paper.title)
                    .font(PedefTheme.Typography.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(paper.formattedAuthors)
                    .font(PedefTheme.Typography.caption)
                    .foregroundStyle(PedefTheme.TextColor.secondary)
                    .lineLimit(1)

                HStack(spacing: PedefTheme.Spacing.xs) {
                    if paper.hasAnnotations {
                        Label("\(paper.annotations.count)", systemImage: "highlighter")
                            .font(PedefTheme.Typography.caption2)
                            .foregroundStyle(PedefTheme.Semantic.warning)
                    }

                    if paper.isRead {
                        Image(systemName: "checkmark.circle.fill")
                            .font(PedefTheme.Typography.caption2)
                            .foregroundStyle(PedefTheme.Semantic.success)
                    }

                    Spacer()

                    if let date = paper.lastOpenedDate {
                        Text(date, style: .relative)
                            .font(PedefTheme.Typography.caption2)
                            .foregroundStyle(PedefTheme.TextColor.tertiary)
                    }
                }
            }
            .padding(.top, PedefTheme.Spacing.md)
            .padding(.horizontal, PedefTheme.Spacing.xxs)
        }
        .padding(PedefTheme.Spacing.md)
        .pedefCard(isHovering: isHovering, isSelected: isSelected)
        .onHover { hovering in
            withAnimation(PedefTheme.Animation.quick) {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(PedefTheme.Animation.spring, value: isHovering)
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var collections: [Collection]

    var body: some View {
        Group {
            Button {
                appState.openPaper(paper)
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
                ForEach(collections.filter { $0.type == .folder }) { collection in
                    Button {
                        if !paper.collections.contains(where: { $0.id == collection.id }) {
                            paper.collections.append(collection)
                        }
                    } label: {
                        HStack {
                            Text(collection.name)
                            if paper.collections.contains(where: { $0.id == collection.id }) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if !collections.isEmpty {
                    Divider()
                }

                Button {
                    let newCollection = Collection(name: "New Collection")
                    modelContext.insert(newCollection)
                    paper.collections.append(newCollection)
                } label: {
                    Label("New Collection...", systemImage: "plus")
                }
            }

            Divider()

            Button {
                exportPaper()
            } label: {
                Label("Export...", systemImage: "square.and.arrow.up")
            }

            Button {
                showInFinder()
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

    private func exportPaper() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(paper.title).pdf"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try paper.pdfData.write(to: url)
                } catch {
                    // Error handled silently - could add error reporting
                    print("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showInFinder() {
        // Create a temporary file to show in Finder
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("\(paper.title).pdf")

        do {
            try paper.pdfData.write(to: tempURL)
            PlatformFileActions.revealInFileBrowser(url: tempURL)
        } catch {
            // Fallback: open Documents folder
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                PlatformFileActions.openDirectory(url: documentsURL)
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
            RoundedRectangle(cornerRadius: PedefTheme.Radius.sm)
                .fill(PedefTheme.Surface.hover)
                .frame(width: 44, height: 60)
                .overlay {
                    if let thumbnailData = paper.thumbnailData,
                       let image = PlatformImage(data: thumbnailData) {
                        Image(platformImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(PedefTheme.TextColor.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))

            VStack(alignment: .leading, spacing: PedefTheme.Spacing.xxs) {
                Text(paper.title)
                    .font(PedefTheme.Typography.headline)
                    .lineLimit(1)

                Text(paper.formattedAuthors)
                    .font(PedefTheme.Typography.subheadline)
                    .foregroundStyle(PedefTheme.TextColor.secondary)
                    .lineLimit(1)

                HStack(spacing: PedefTheme.Spacing.md) {
                    if let journal = paper.journal {
                        Text(journal)
                            .font(PedefTheme.Typography.caption)
                            .foregroundStyle(PedefTheme.TextColor.tertiary)
                    }

                    if paper.hasAnnotations {
                        Label("\(paper.annotations.count)", systemImage: "highlighter")
                            .font(PedefTheme.Typography.caption)
                            .foregroundStyle(PedefTheme.Semantic.warning)
                    }

                    if paper.tags.contains("favorite") {
                        Image(systemName: "star.fill")
                            .font(PedefTheme.Typography.caption)
                            .foregroundStyle(PedefTheme.Brand.purple)
                    }
                }
            }

            Spacer()

            // Right side indicators
            VStack(alignment: .trailing, spacing: PedefTheme.Spacing.xxs) {
                if paper.readingProgress > 0 && paper.readingProgress < 1 {
                    CircularProgressView(progress: paper.readingProgress)
                        .frame(width: 28, height: 28)
                } else if paper.isRead {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PedefTheme.Semantic.success)
                }

                if let date = paper.lastOpenedDate {
                    Text(date, style: .relative)
                        .font(PedefTheme.Typography.caption2)
                        .foregroundStyle(PedefTheme.TextColor.tertiary)
                }
            }
        }
        .padding(.vertical, PedefTheme.Spacing.xs)
        .background(isHovering ? PedefTheme.Surface.hover : Color.clear)
        .onHover { isHovering = $0 }
    }
}

struct CircularProgressView: View {
    let progress: Double
    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(PedefTheme.Brand.indigo.opacity(0.15), lineWidth: 3)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(PedefTheme.Brand.indigo, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
