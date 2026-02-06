import SwiftUI
import PDFKit

struct PDFReaderView: View {
    @Bindable var paper: Paper
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var historyService: HistoryService
    @State private var pdfDocument: PDFDocument?
    @State private var currentScale: CGFloat = 1.0
    @State private var showOutline: Bool = false
    @State private var showAnnotationSidebar: Bool = true
    @State private var showThumbnails: Bool = false
    @State private var showPageJumpSheet: Bool = false
    @State private var pageJumpText: String = ""

    var body: some View {
        HSplitView {
            // Thumbnail sidebar (optional)
            if showThumbnails {
                ThumbnailSidebarView(
                    document: pdfDocument,
                    currentPage: appState.currentPage,
                    onPageSelect: { page in
                        handlePageChange(page: page)
                    }
                )
                .frame(width: 120)
                .transition(.move(edge: .leading))
            }

            // Main PDF View
            VStack(spacing: 0) {
                // PDF Viewer
                PDFKitView(
                    document: $pdfDocument,
                    currentPage: $appState.currentPage,
                    scale: $currentScale,
                    selectedText: $appState.selectedText,
                    onPageChange: handlePageChange
                )

                // Bottom toolbar
                ReaderBottomToolbar(
                    paper: paper,
                    currentPage: appState.currentPage,
                    totalPages: pdfDocument?.pageCount ?? 0,
                    scale: $currentScale,
                    onPageTap: { showPageJumpSheet = true },
                    onPreviousPage: navigateToPreviousPage,
                    onNextPage: navigateToNextPage
                )
            }

            // Annotation Sidebar
            if showAnnotationSidebar {
                AnnotationSidebarView(paper: paper, currentPage: appState.currentPage)
                    .frame(minWidth: 260, maxWidth: 360)
            }
        }
        .navigationTitle(paper.title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                // Thumbnails toggle
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showThumbnails.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .symbolVariant(showThumbnails ? .fill : .none)
                }
                .help("Toggle Thumbnails")

                // Outline popover
                Button {
                    showOutline.toggle()
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .help("Table of Contents")
                .popover(isPresented: $showOutline) {
                    OutlinePopover(
                        outline: pdfDocument?.outlineRoot,
                        onSelect: navigateToOutlineItem
                    )
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Annotation sidebar toggle
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showAnnotationSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .symbolVariant(showAnnotationSidebar ? .fill : .none)
                }
                .help("Toggle Annotations")
            }
        }
        .sheet(isPresented: $showPageJumpSheet) {
            PageJumpSheet(
                currentPage: appState.currentPage,
                totalPages: pdfDocument?.pageCount ?? 0,
                onJump: { page in
                    handlePageChange(page: page)
                    showPageJumpSheet = false
                }
            )
        }
        .onAppear {
            loadPDF()
            historyService.recordAction(.openPaper, paperId: paper.id)
        }
        .onDisappear {
            savePaperState()
            historyService.recordAction(.closePaper, paperId: paper.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousPage)) { _ in
            navigateToPreviousPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextPage)) { _ in
            navigateToNextPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            zoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            zoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightSelection)) { _ in
            createHighlight()
        }
    }

    // MARK: - Actions

    private func loadPDF() {
        pdfDocument = PDFDocument(data: paper.pdfData)
        if paper.pageCount == 0, let doc = pdfDocument {
            paper.pageCount = doc.pageCount
        }
        appState.currentPage = paper.currentPage
    }

    private func savePaperState() {
        paper.currentPage = appState.currentPage
        if let pageCount = pdfDocument?.pageCount, pageCount > 0 {
            paper.readingProgress = Double(appState.currentPage + 1) / Double(pageCount)
        }
        paper.lastOpenedDate = Date()
    }

    private func handlePageChange(page: Int) {
        let oldPage = appState.currentPage
        appState.currentPage = page
        historyService.recordAction(
            .navigatePage,
            paperId: paper.id,
            details: PageNavigationDetails(fromPage: oldPage, toPage: page)
        )
    }

    private func navigateToPreviousPage() {
        if appState.currentPage > 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                handlePageChange(page: appState.currentPage - 1)
            }
        }
    }

    private func navigateToNextPage() {
        if let pageCount = pdfDocument?.pageCount, appState.currentPage < pageCount - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                handlePageChange(page: appState.currentPage + 1)
            }
        }
    }

    private func navigateToOutlineItem(_ destination: PDFDestination) {
        if let page = destination.page,
           let pageIndex = pdfDocument?.index(for: page) {
            handlePageChange(page: pageIndex)
        }
        showOutline = false
    }

    private func zoomIn() {
        let oldScale = currentScale
        withAnimation(.easeOut(duration: 0.15)) {
            currentScale = min(currentScale * 1.25, 4.0)
        }
        historyService.recordAction(
            .zoom,
            paperId: paper.id,
            details: ZoomDetails(fromScale: oldScale, toScale: currentScale)
        )
    }

    private func zoomOut() {
        let oldScale = currentScale
        withAnimation(.easeOut(duration: 0.15)) {
            currentScale = max(currentScale / 1.25, 0.25)
        }
        historyService.recordAction(
            .zoom,
            paperId: paper.id,
            details: ZoomDetails(fromScale: oldScale, toScale: currentScale)
        )
    }

    private func createHighlight() {
        guard let selectedText = appState.selectedText, !selectedText.isEmpty else { return }
        let annotation = Annotation(
            type: .highlight,
            pageIndex: appState.currentPage,
            bounds: .zero
        )
        annotation.selectedText = selectedText
        annotation.paper = paper
        paper.annotations.append(annotation)

        historyService.recordAction(
            .createHighlight,
            paperId: paper.id,
            annotationId: annotation.id,
            details: AnnotationDetails(
                pageIndex: appState.currentPage,
                annotationType: "highlight",
                selectedText: selectedText
            )
        )

        appState.selectedText = nil
    }
}

// MARK: - Thumbnail Sidebar

struct ThumbnailSidebarView: View {
    let document: PDFDocument?
    let currentPage: Int
    let onPageSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let doc = document {
                        ForEach(0..<doc.pageCount, id: \.self) { index in
                            ThumbnailItem(
                                document: doc,
                                pageIndex: index,
                                isSelected: index == currentPage,
                                onTap: { onPageSelect(index) }
                            )
                            .id(index)
                        }
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: currentPage) { _, newPage in
                withAnimation {
                    proxy.scrollTo(newPage, anchor: .center)
                }
            }
        }
    }
}

struct ThumbnailItem: View {
    let document: PDFDocument
    let pageIndex: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Group {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

                Text("\(pageIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        guard let page = document.page(at: pageIndex) else { return }
        let size = CGSize(width: 100, height: 140)
        thumbnail = page.thumbnail(of: size, for: .mediaBox)
    }
}

// MARK: - PDFKit Wrapper

struct PDFKitView: NSViewRepresentable {
    @Binding var document: PDFDocument?
    @Binding var currentPage: Int
    @Binding var scale: CGFloat
    @Binding var selectedText: String?
    var onPageChange: (Int) -> Void

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(Color(nsColor: .windowBackgroundColor))
        pdfView.delegate = context.coordinator

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        if let doc = document,
           let page = doc.page(at: currentPage),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }

        pdfView.scaleFactor = scale
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PDFViewDelegate {
        var parent: PDFKitView

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let pageIndex = pdfView.document?.index(for: currentPage) else {
                return
            }
            DispatchQueue.main.async {
                if self.parent.currentPage != pageIndex {
                    self.parent.onPageChange(pageIndex)
                }
            }
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            DispatchQueue.main.async {
                self.parent.selectedText = pdfView.currentSelection?.string
            }
        }
    }
}

// MARK: - Bottom Toolbar

struct ReaderBottomToolbar: View {
    let paper: Paper
    let currentPage: Int
    let totalPages: Int
    @Binding var scale: CGFloat
    let onPageTap: () -> Void
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void

    private var canZoomOut: Bool {
        scale > 0.25
    }

    private var canZoomIn: Bool {
        scale < 4.0
    }

    var body: some View {
        HStack(spacing: 16) {
            // Page navigation
            HStack(spacing: 8) {
                Button(action: onPreviousPage) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(currentPage <= 0)
                .help("Previous Page")

                Button(action: onPageTap) {
                    Text("Page \(currentPage + 1) of \(totalPages)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Jump to page...")

                Button(action: onNextPage) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= totalPages - 1)
                .help("Next Page")
            }

            Spacer()

            // Zoom controls
            HStack(spacing: 6) {
                Button {
                    scale = max(scale / 1.25, 0.25)
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(!canZoomOut)
                .help("Zoom Out")

                Text("\(Int(scale * 100))%")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .frame(minWidth: 44)

                Button {
                    scale = min(scale * 1.25, 4.0)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(!canZoomIn)
                .help("Zoom In")

                Menu {
                    Button("50%") { scale = 0.5 }
                    Button("75%") { scale = 0.75 }
                    Button("100%") { scale = 1.0 }
                    Button("125%") { scale = 1.25 }
                    Button("150%") { scale = 1.5 }
                    Button("200%") { scale = 2.0 }
                    Divider()
                    Button("Fit Width") { scale = 1.0 }
                    Button("Fit Page") { scale = 1.0 }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)
                .help("Zoom Presets")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Reading progress
            HStack(spacing: 8) {
                if paper.readingProgress > 0 {
                    ProgressView(value: paper.readingProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 60)
                        .tint(.accentColor)

                    Text("\(Int(paper.readingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Page Jump Sheet

struct PageJumpSheet: View {
    let currentPage: Int
    let totalPages: Int
    let onJump: (Int) -> Void

    @State private var inputText = ""
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Go to Page")
                .font(.headline)

            HStack {
                TextField("Page number", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .focused($isFocused)
                    .onSubmit(jumpToPage)

                Text("of \(totalPages)")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Go") {
                    jumpToPage()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 240)
        .onAppear {
            inputText = "\(currentPage + 1)"
            isFocused = true
        }
    }

    private func jumpToPage() {
        if let page = Int(inputText), page >= 1, page <= totalPages {
            onJump(page - 1)
        }
    }
}

// MARK: - Outline Popover

struct OutlinePopover: View {
    let outline: PDFOutline?
    let onSelect: (PDFDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents")
                .font(.headline)
                .padding()

            Divider()

            if let outline = outline {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        OutlineItemView(item: outline, depth: 0, onSelect: onSelect)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No table of contents")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .frame(width: 300, height: 400)
    }
}

struct OutlineItemView: View {
    let item: PDFOutline
    let depth: Int
    let onSelect: (PDFDestination) -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = item.label {
                Button {
                    if let destination = item.destination {
                        onSelect(destination)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if item.numberOfChildren > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isExpanded.toggle()
                                    }
                                }
                        }

                        Text(label)
                            .font(.subheadline)
                            .lineLimit(2)

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth * 16) + 12)
                    .padding(.vertical, 6)
                    .padding(.trailing, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                ForEach(0..<item.numberOfChildren, id: \.self) { index in
                    if let child = item.child(at: index) {
                        OutlineItemView(item: child, depth: depth + 1, onSelect: onSelect)
                    }
                }
            }
        }
    }
}

// MARK: - Annotation Sidebar

struct AnnotationSidebarView: View {
    @Bindable var paper: Paper
    let currentPage: Int
    @State private var selectedAnnotation: Annotation?
    @State private var filterType: AnnotationType?
    @State private var searchText = ""

    var filteredAnnotations: [Annotation] {
        var result = Annotation.sortByPosition(paper.annotations)
        if let filter = filterType {
            result = result.filter { $0.type == filter }
        }
        if !searchText.isEmpty {
            result = result.filter {
                ($0.selectedText ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.noteContent ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var annotationsOnCurrentPage: [Annotation] {
        filteredAnnotations.filter { $0.pageIndex == currentPage }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Annotations")
                    .font(.headline)

                Spacer()

                Text("\(paper.annotations.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())

                Menu {
                    Button("All") { filterType = nil }
                    Divider()
                    ForEach(AnnotationType.allCases, id: \.self) { type in
                        Button {
                            filterType = type
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: filterType == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .menuStyle(.borderlessButton)
            }
            .padding()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search annotations...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Annotation List
            if filteredAnnotations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "highlighter")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)

                    Text("No Annotations")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Select text and use ⌘H to highlight")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    if !annotationsOnCurrentPage.isEmpty {
                        Section("This Page") {
                            ForEach(annotationsOnCurrentPage) { annotation in
                                AnnotationRow(annotation: annotation)
                            }
                        }
                    }

                    let otherAnnotations = filteredAnnotations.filter { $0.pageIndex != currentPage }
                    if !otherAnnotations.isEmpty {
                        Section("Other Pages (\(otherAnnotations.count))") {
                            ForEach(otherAnnotations) { annotation in
                                AnnotationRow(annotation: annotation)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct AnnotationRow: View {
    @Bindable var annotation: Annotation
    @Environment(\.modelContext) private var modelContext
    @State private var isHovering = false
    @State private var showEditNote = false
    @State private var showColorPicker = false
    @State private var showAddTag = false
    @State private var editingNote = ""
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: annotation.colorHex) ?? .yellow)
                    .frame(width: 10, height: 10)

                Image(systemName: annotation.type.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Page \(annotation.pageIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(annotation.createdDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let text = annotation.selectedText, !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .lineLimit(3)
                    .padding(.leading, 18)
            }

            if let note = annotation.noteContent, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 18)
                    .padding(.top, 2)
            }

            if !annotation.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(annotation.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.vertical, 6)
        .background(isHovering ? Color.secondary.opacity(0.05) : Color.clear)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Edit Note") {
                editingNote = annotation.noteContent ?? ""
                showEditNote = true
            }

            Menu("Change Color") {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    Button {
                        annotation.colorHex = color.rawValue
                        annotation.modifiedDate = Date()
                    } label: {
                        Label(color.displayName, systemImage: "circle.fill")
                    }
                }
            }

            Button("Add Tag") {
                showAddTag = true
            }

            Divider()

            Button("Copy Text") {
                if let text = annotation.selectedText {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .disabled(annotation.selectedText?.isEmpty ?? true)

            Divider()

            Button("Delete", role: .destructive) {
                if let paper = annotation.paper {
                    paper.annotations.removeAll { $0.id == annotation.id }
                }
                modelContext.delete(annotation)
            }
        }
        .popover(isPresented: $showEditNote) {
            VStack(spacing: 12) {
                Text("Edit Note")
                    .font(.headline)

                TextEditor(text: $editingNote)
                    .frame(width: 250, height: 100)
                    .font(.body)

                HStack {
                    Button("Cancel") {
                        showEditNote = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Save") {
                        annotation.noteContent = editingNote.isEmpty ? nil : editingNote
                        annotation.modifiedDate = Date()
                        showEditNote = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300)
        }
        .popover(isPresented: $showAddTag) {
            VStack(spacing: 12) {
                Text("Add Tag")
                    .font(.headline)

                TextField("Tag name", text: $newTag)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        newTag = ""
                        showAddTag = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Add") {
                        if !newTag.isEmpty && !annotation.tags.contains(newTag) {
                            annotation.tags.append(newTag.lowercased())
                            annotation.modifiedDate = Date()
                        }
                        newTag = ""
                        showAddTag = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(newTag.isEmpty)
                }
            }
            .padding()
            .frame(width: 250)
        }
    }
}
