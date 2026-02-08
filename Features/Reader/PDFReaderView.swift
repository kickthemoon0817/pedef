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
                isAgentVisible: appState.isAgentPanelVisible
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

                    AnnotationSidebarView(paper: paper, currentPage: appState.currentPage)
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
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
        if let sessionID = appState.readerMCPSessionID {
            ReaderMCPService.shared.updateCurrentPage(sessionID: sessionID, currentPage: page)
        }
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
                    Image(systemName: "bookmark")
                }
                .buttonStyle(PedefToolbarButtonStyle())
                .help("Bookmark (⇧⌘B)")

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
                    .font(PedefTheme.Typography.headline)
                    .foregroundStyle(PedefTheme.TextColor.primary)

                Spacer()

                Text("\(paper.annotations.count)")
                    .font(PedefTheme.Typography.caption)
                    .foregroundStyle(PedefTheme.TextColor.tertiary)
                    .padding(.horizontal, PedefTheme.Spacing.sm)
                    .padding(.vertical, PedefTheme.Spacing.xxxs)
                    .background(PedefTheme.Surface.hover, in: Capsule())

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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(filterType != nil ? PedefTheme.Brand.indigo : PedefTheme.TextColor.tertiary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, PedefTheme.Spacing.lg)
            .padding(.vertical, PedefTheme.Spacing.md)

            // Search
            PedefSearchField(text: $searchText, placeholder: "Search annotations...")
                .padding(.horizontal, PedefTheme.Spacing.lg)
                .padding(.bottom, PedefTheme.Spacing.sm)

            Rectangle()
                .fill(PedefTheme.TextColor.tertiary.opacity(0.12))
                .frame(height: 1)

            // Annotation List
            if filteredAnnotations.isEmpty {
                VStack(spacing: PedefTheme.Spacing.md) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 32))
                        .foregroundStyle(PedefTheme.TextColor.tertiary)

                    Text("No Annotations")
                        .font(PedefTheme.Typography.headline)
                        .foregroundStyle(PedefTheme.TextColor.secondary)

                    Text("Select text and use ⌘H to highlight")
                        .font(PedefTheme.Typography.caption)
                        .foregroundStyle(PedefTheme.TextColor.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !annotationsOnCurrentPage.isEmpty {
                            AnnotationSectionHeader(title: "This Page", count: annotationsOnCurrentPage.count)
                            ForEach(annotationsOnCurrentPage) { annotation in
                                AnnotationRow(annotation: annotation)
                            }
                        }

                        let otherAnnotations = filteredAnnotations.filter { $0.pageIndex != currentPage }
                        if !otherAnnotations.isEmpty {
                            AnnotationSectionHeader(title: "Other Pages", count: otherAnnotations.count)
                            ForEach(otherAnnotations) { annotation in
                                AnnotationRow(annotation: annotation)
                            }
                        }
                    }
                    .padding(.vertical, PedefTheme.Spacing.xs)
                }
            }
        }
        .background(PedefTheme.Surface.sidebar)
    }
}

struct AnnotationSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(PedefTheme.Typography.caption2)
                .tracking(0.8)
                .foregroundStyle(PedefTheme.TextColor.tertiary)

            Text("\(count)")
                .font(PedefTheme.Typography.caption2)
                .foregroundStyle(PedefTheme.TextColor.tertiary)
                .padding(.horizontal, PedefTheme.Spacing.xs)
                .padding(.vertical, 1)
                .background(PedefTheme.Surface.hover, in: Capsule())

            Spacer()
        }
        .padding(.horizontal, PedefTheme.Spacing.lg)
        .padding(.top, PedefTheme.Spacing.md)
        .padding(.bottom, PedefTheme.Spacing.xs)
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
                HStack(spacing: PedefTheme.Spacing.xxs) {
                    ForEach(annotation.tags, id: \.self) { tag in
                        Text(tag)
                            .font(PedefTheme.Typography.caption2)
                            .padding(.horizontal, PedefTheme.Spacing.xs)
                            .padding(.vertical, PedefTheme.Spacing.xxxs)
                            .background(PedefTheme.Brand.indigo.opacity(0.10), in: Capsule())
                            .foregroundStyle(PedefTheme.Brand.indigo)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.horizontal, PedefTheme.Spacing.lg)
        .padding(.vertical, PedefTheme.Spacing.sm)
        .background(isHovering ? PedefTheme.Surface.hover : Color.clear)
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
            VStack(spacing: PedefTheme.Spacing.md) {
                Text("Edit Note")
                    .font(PedefTheme.Typography.headline)

                TextEditor(text: $editingNote)
                    .frame(width: 250, height: 100)
                    .font(PedefTheme.Typography.body)
                    .padding(PedefTheme.Spacing.xs)
                    .background(PedefTheme.Surface.hover)
                    .clipShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))

                HStack {
                    Button("Cancel") {
                        showEditNote = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PedefTheme.TextColor.secondary)
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        annotation.noteContent = editingNote.isEmpty ? nil : editingNote
                        annotation.modifiedDate = Date()
                        showEditNote = false
                    } label: {
                        Text("Save")
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
            .padding(PedefTheme.Spacing.lg)
            .frame(width: 300)
        }
        .popover(isPresented: $showAddTag) {
            VStack(spacing: PedefTheme.Spacing.md) {
                Text("Add Tag")
                    .font(PedefTheme.Typography.headline)

                TextField("Tag name", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(PedefTheme.Typography.body)
                    .padding(PedefTheme.Spacing.sm)
                    .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: PedefTheme.Radius.sm)
                            .stroke(PedefTheme.Brand.indigo.opacity(0.5), lineWidth: 1)
                    )

                HStack {
                    Button("Cancel") {
                        newTag = ""
                        showAddTag = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PedefTheme.TextColor.secondary)
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        if !newTag.isEmpty && !annotation.tags.contains(newTag) {
                            annotation.tags.append(newTag.lowercased())
                            annotation.modifiedDate = Date()
                        }
                        newTag = ""
                        showAddTag = false
                    } label: {
                        Text("Add")
                            .font(PedefTheme.Typography.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, PedefTheme.Spacing.lg)
                            .padding(.vertical, PedefTheme.Spacing.xs)
                            .background(newTag.isEmpty ? PedefTheme.TextColor.tertiary : PedefTheme.Brand.indigo, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTag.isEmpty)
                }
            }
            .padding(PedefTheme.Spacing.lg)
            .frame(width: 250)
        }
    }
}
