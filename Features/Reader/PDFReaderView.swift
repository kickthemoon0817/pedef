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
        VStack(spacing: 0) {
            // Custom reader header bar
            ReaderHeaderBar(
                paper: paper,
                showThumbnails: $showThumbnails,
                showOutline: $showOutline,
                showAnnotationSidebar: $showAnnotationSidebar,
                pdfDocument: pdfDocument,
                onOutlineSelect: navigateToOutlineItem,
                onClose: { appState.closePaper() },
                onToggleAgent: { appState.isAgentPanelVisible.toggle() },
                isAgentVisible: appState.isAgentPanelVisible,
                isCurrentPageBookmarked: isCurrentPageBookmarked
            )

            // Main content area
            HStack(spacing: 0) {
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

                    // Custom thin divider
                    Rectangle()
                        .fill(PedefTheme.TextColor.tertiary.opacity(0.15))
                        .frame(width: 1)
                }

                // Main PDF View
                VStack(spacing: 0) {
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
                    // Custom thin divider
                    Rectangle()
                        .fill(PedefTheme.TextColor.tertiary.opacity(0.15))
                        .frame(width: 1)

                    AnnotationSidebarView(
                        paper: paper,
                        currentPage: appState.currentPage,
                        onNavigateToPage: { page in handlePageChange(page: page) }
                    )
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .addBookmark)) { _ in
            toggleBookmark()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addNote)) { _ in
            createStickyNote()
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

    private func toggleBookmark() {
        let currentPage = appState.currentPage
        if let existing = paper.annotations.first(where: { $0.type == .bookmark && $0.pageIndex == currentPage }) {
            paper.annotations.removeAll { $0.id == existing.id }
            historyService.recordAction(
                .deleteAnnotation,
                paperId: paper.id,
                annotationId: existing.id
            )
        } else {
            let bookmark = Annotation(type: .bookmark, pageIndex: currentPage, bounds: .zero)
            bookmark.paper = paper
            paper.annotations.append(bookmark)
            historyService.recordAction(
                .createBookmark,
                paperId: paper.id,
                annotationId: bookmark.id,
                details: AnnotationDetails(
                    pageIndex: currentPage,
                    annotationType: "bookmark",
                    selectedText: nil
                )
            )
        }
    }

    private var isCurrentPageBookmarked: Bool {
        paper.annotations.contains { $0.type == .bookmark && $0.pageIndex == appState.currentPage }
    }

    private func createStickyNote() {
        let annotation = Annotation(
            type: .stickyNote,
            pageIndex: appState.currentPage,
            bounds: .zero
        )
        // If there's selected text, use it as context
        if let selectedText = appState.selectedText, !selectedText.isEmpty {
            annotation.selectedText = selectedText
            appState.selectedText = nil
        }
        annotation.paper = paper
        paper.annotations.append(annotation)

        historyService.recordAction(
            .createNote,
            paperId: paper.id,
            annotationId: annotation.id,
            details: AnnotationDetails(
                pageIndex: appState.currentPage,
                annotationType: "stickyNote",
                selectedText: annotation.selectedText
            )
        )

        // Make sure annotation sidebar is visible and switch to notes tab
        if !showAnnotationSidebar {
            showAnnotationSidebar = true
        }
    }
}

// MARK: - Reader Header Bar

struct ReaderHeaderBar: View {
    let paper: Paper
    @Binding var showThumbnails: Bool
    @Binding var showOutline: Bool
    @Binding var showAnnotationSidebar: Bool
    let pdfDocument: PDFDocument?
    let onOutlineSelect: (PDFDestination) -> Void
    let onClose: () -> Void
    let onToggleAgent: () -> Void
    let isAgentVisible: Bool
    var isCurrentPageBookmarked: Bool = false

    var body: some View {
        HStack(spacing: PedefTheme.Spacing.sm) {
            // Left: panel toggles
            HStack(spacing: PedefTheme.Spacing.xxs) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showThumbnails.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .symbolVariant(showThumbnails ? .fill : .none)
                }
                .buttonStyle(PedefToolbarButtonStyle(isActive: showThumbnails))
                .help("Toggle Thumbnails")

                Button {
                    showOutline.toggle()
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .buttonStyle(PedefToolbarButtonStyle(isActive: showOutline))
                .help("Table of Contents")
                .popover(isPresented: $showOutline) {
                    OutlinePopover(
                        outline: pdfDocument?.outlineRoot,
                        onSelect: onOutlineSelect
                    )
                }
            }

            // Center: paper title
            Spacer()

            Text(paper.title)
                .font(PedefTheme.Typography.subheadline)
                .foregroundStyle(PedefTheme.TextColor.primary)
                .lineLimit(1)
                .frame(maxWidth: 400)

            Spacer()

            // Right: annotation tools + toggles
            HStack(spacing: PedefTheme.Spacing.xxs) {
                // Highlight
                Menu {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        Button {
                            NotificationCenter.default.post(name: .highlightSelection, object: color)
                        } label: {
                            Label(color.displayName, systemImage: "circle.fill")
                        }
                    }
                } label: {
                    Image(systemName: "highlighter")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PedefTheme.TextColor.secondary)
                        .frame(width: 28, height: 26)
                } primaryAction: {
                    NotificationCenter.default.post(name: .highlightSelection, object: nil)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Highlight (⌘H)")

                Button {
                    NotificationCenter.default.post(name: .addNote, object: nil)
                } label: {
                    Image(systemName: "note.text.badge.plus")
                }
                .buttonStyle(PedefToolbarButtonStyle())
                .help("Note (⇧⌘N)")

                Button {
                    NotificationCenter.default.post(name: .addBookmark, object: nil)
                } label: {
                    Image(systemName: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(PedefToolbarButtonStyle(isActive: isCurrentPageBookmarked))
                .help(isCurrentPageBookmarked ? "Remove Bookmark (⇧⌘B)" : "Bookmark (⇧⌘B)")

                Rectangle()
                    .fill(PedefTheme.TextColor.tertiary.opacity(0.2))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, PedefTheme.Spacing.xxxs)

                Button(action: onToggleAgent) {
                    HStack(spacing: PedefTheme.Spacing.xxs) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(PedefTheme.Brand.purple)
                        Text("AI")
                            .font(PedefTheme.Typography.caption)
                    }
                }
                .buttonStyle(PedefToolbarButtonStyle(isActive: isAgentVisible))
                .help("AI Assistant (⌘K)")

                Rectangle()
                    .fill(PedefTheme.TextColor.tertiary.opacity(0.2))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, PedefTheme.Spacing.xxxs)

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showAnnotationSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .symbolVariant(showAnnotationSidebar ? .fill : .none)
                }
                .buttonStyle(PedefToolbarButtonStyle(isActive: showAnnotationSidebar))
                .help("Annotations")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PedefTheme.TextColor.tertiary)
                        .frame(width: 22, height: 22)
                        .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.xs))
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
        .padding(.horizontal, PedefTheme.Spacing.lg)
        .padding(.vertical, PedefTheme.Spacing.sm)
        .background(PedefTheme.Surface.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PedefTheme.TextColor.tertiary.opacity(0.15))
                .frame(height: 1)
        }
        .background(WindowDragArea())
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
            .background(PedefTheme.Surface.sidebar)
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
                    RoundedRectangle(cornerRadius: PedefTheme.Radius.xs)
                        .strokeBorder(isSelected ? PedefTheme.Brand.indigo : Color.clear, lineWidth: 2)
                }
                .pedefShadow(PedefTheme.Shadow.sm)

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
        pdfView.backgroundColor = NSColor(PedefTheme.Surface.primary)
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
                .accessibilityLabel("Previous page")
                .accessibilityHint("Go to page \(currentPage)")

                Button(action: onPageTap) {
                    Text("Page \(currentPage + 1) of \(totalPages)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                }
                .buttonStyle(.plain)
                .help("Jump to page...")
                .accessibilityLabel("Page \(currentPage + 1) of \(totalPages)")
                .accessibilityHint("Tap to jump to a specific page")

                Button(action: onNextPage) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= totalPages - 1)
                .help("Next Page")
                .accessibilityLabel("Next page")
                .accessibilityHint("Go to page \(currentPage + 2)")
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
            .padding(.horizontal, PedefTheme.Spacing.md)
            .padding(.vertical, PedefTheme.Spacing.xs)
            .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.md))

            Spacer()

            // Reading progress
            HStack(spacing: 8) {
                if paper.readingProgress > 0 {
                    ProgressView(value: paper.readingProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 60)
                        .tint(PedefTheme.Brand.indigo)

                    Text("\(Int(paper.readingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, PedefTheme.Spacing.lg)
        .padding(.vertical, PedefTheme.Spacing.sm)
        .background(PedefTheme.Surface.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PedefTheme.TextColor.tertiary.opacity(0.15))
                .frame(height: 1)
        }
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
        VStack(spacing: PedefTheme.Spacing.lg) {
            Text("Go to Page")
                .font(PedefTheme.Typography.headline)

            HStack {
                TextField("Page number", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(PedefTheme.Typography.body)
                    .padding(PedefTheme.Spacing.sm)
                    .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: PedefTheme.Radius.sm)
                            .stroke(PedefTheme.Brand.indigo.opacity(0.5), lineWidth: 1)
                    )
                    .frame(width: 100)
                    .focused($isFocused)
                    .onSubmit(jumpToPage)

                Text("of \(totalPages)")
                    .font(PedefTheme.Typography.callout)
                    .foregroundStyle(PedefTheme.TextColor.secondary)
            }

            HStack(spacing: PedefTheme.Spacing.md) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(PedefTheme.TextColor.secondary)
                .keyboardShortcut(.cancelAction)

                Button {
                    jumpToPage()
                } label: {
                    Text("Go")
                        .font(PedefTheme.Typography.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, PedefTheme.Spacing.lg)
                        .padding(.vertical, PedefTheme.Spacing.xs)
                        .background(PedefTheme.Brand.indigo, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PedefTheme.Spacing.xxl)
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
                .font(PedefTheme.Typography.headline)
                .foregroundStyle(PedefTheme.TextColor.primary)
                .padding()

            Divider()

            if let outline = outline {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        OutlineItemView(item: outline, depth: 0, onSelect: onSelect)
                    }
                    .padding(.vertical, PedefTheme.Spacing.sm)
                }
            } else {
                VStack(spacing: PedefTheme.Spacing.sm) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title)
                        .foregroundStyle(PedefTheme.TextColor.tertiary)
                    Text("No table of contents")
                        .font(PedefTheme.Typography.subheadline)
                        .foregroundStyle(PedefTheme.TextColor.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .frame(width: 300, height: 400)
        .background(PedefTheme.Surface.elevated)
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

// NOTE: AnnotationSidebarView, AnnotationSectionHeader, and related
// components have been moved to AnnotationSidebarView.swift for
// better organization and the new tabbed sidebar design.
