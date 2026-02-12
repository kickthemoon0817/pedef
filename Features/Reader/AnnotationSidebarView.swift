import SwiftUI
import SwiftData

// MARK: - Sidebar Tab

enum AnnotationSidebarTab: String, CaseIterable {
    case all = "All"
    case notes = "Notes"
    case bookmarks = "Bookmarks"

    var systemImage: String {
        switch self {
        case .all: return "highlighter"
        case .notes: return "note.text"
        case .bookmarks: return "bookmark"
        }
    }
}

// MARK: - Annotation Sidebar (Tabbed)

struct AnnotationSidebarView: View {
    @Bindable var paper: Paper
    let currentPage: Int
    var onNavigateToPage: ((Int) -> Void)?

    @State private var selectedTab: AnnotationSidebarTab = .all
    @State private var filterType: AnnotationType?
    @State private var filterColor: AnnotationColor?
    @State private var searchText = ""

    // MARK: - Filtered Data

    private var allAnnotations: [Annotation] {
        Annotation.sortByPosition(paper.annotations)
    }

    private var filteredAnnotations: [Annotation] {
        var result = allAnnotations.filter { $0.type != .bookmark }
        if let filter = filterType {
            result = result.filter { $0.type == filter }
        }
        if let color = filterColor {
            result = result.filter { $0.colorHex == color.rawValue }
        }
        if !searchText.isEmpty {
            result = result.filter {
                ($0.selectedText ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.noteContent ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var noteAnnotations: [Annotation] {
        let notes = allAnnotations.filter {
            $0.type == .stickyNote || $0.type == .textNote || $0.hasNote
        }
        if !searchText.isEmpty {
            return notes.filter {
                ($0.noteContent ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.selectedText ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return notes
    }

    private var bookmarkAnnotations: [Annotation] {
        allAnnotations.filter { $0.type == .bookmark }
    }

    private func badgeCount(for tab: AnnotationSidebarTab) -> Int {
        switch tab {
        case .all: return filteredAnnotations.count
        case .notes: return noteAnnotations.count
        case .bookmarks: return bookmarkAnnotations.count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title
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
            }
            .padding(.horizontal, PedefTheme.Spacing.lg)
            .padding(.vertical, PedefTheme.Spacing.md)

            // Tab bar
            SidebarTabBar(selectedTab: $selectedTab, badgeCounts: [
                .all: filteredAnnotations.count,
                .notes: noteAnnotations.count,
                .bookmarks: bookmarkAnnotations.count
            ])
            .padding(.horizontal, PedefTheme.Spacing.lg)
            .padding(.bottom, PedefTheme.Spacing.sm)

            // Search (shown for All and Notes tabs)
            if selectedTab != .bookmarks {
                PedefSearchField(text: $searchText, placeholder: "Search annotations...")
                    .padding(.horizontal, PedefTheme.Spacing.lg)
                    .padding(.bottom, PedefTheme.Spacing.sm)
            }

            // Color filter (All tab only)
            if selectedTab == .all {
                ColorFilterBar(selectedColor: $filterColor)
                    .padding(.horizontal, PedefTheme.Spacing.lg)
                    .padding(.bottom, PedefTheme.Spacing.sm)

                // Type filter
                HStack(spacing: PedefTheme.Spacing.xxs) {
                    if filterType != nil || filterColor != nil {
                        Button {
                            withAnimation(PedefTheme.Animation.quick) {
                                filterType = nil
                                filterColor = nil
                            }
                        } label: {
                            HStack(spacing: PedefTheme.Spacing.xxs) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("Clear")
                                    .font(PedefTheme.Typography.caption2)
                            }
                            .foregroundStyle(PedefTheme.Semantic.error)
                            .padding(.horizontal, PedefTheme.Spacing.xs)
                            .padding(.vertical, PedefTheme.Spacing.xxxs)
                            .background(PedefTheme.Semantic.error.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Menu {
                        Button("All Types") { filterType = nil }
                        Divider()
                        ForEach(AnnotationType.allCases.filter({ $0 != .bookmark }), id: \.self) { type in
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
                .padding(.bottom, PedefTheme.Spacing.xs)
            }

            Rectangle()
                .fill(PedefTheme.TextColor.tertiary.opacity(0.12))
                .frame(height: 1)

            // Tab content
            switch selectedTab {
            case .all:
                AllAnnotationsTabView(
                    annotations: filteredAnnotations,
                    currentPage: currentPage,
                    onNavigateToPage: onNavigateToPage
                )
            case .notes:
                NotesTabView(
                    notes: noteAnnotations,
                    currentPage: currentPage,
                    paper: paper,
                    onNavigateToPage: onNavigateToPage
                )
            case .bookmarks:
                BookmarksTabView(
                    bookmarks: bookmarkAnnotations,
                    currentPage: currentPage,
                    paper: paper,
                    onNavigateToPage: onNavigateToPage
                )
            }
        }
        .background(PedefTheme.Surface.sidebar)
    }
}

// MARK: - Tab Bar

struct SidebarTabBar: View {
    @Binding var selectedTab: AnnotationSidebarTab
    let badgeCounts: [AnnotationSidebarTab: Int]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AnnotationSidebarTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(PedefTheme.Animation.quick) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: PedefTheme.Spacing.xxs) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 11, weight: .medium))
                        Text(tab.rawValue)
                            .font(PedefTheme.Typography.caption)
                        if let count = badgeCounts[tab], count > 0 {
                            Text("\(count)")
                                .font(PedefTheme.Typography.caption2)
                                .foregroundStyle(selectedTab == tab ? PedefTheme.Brand.indigo : PedefTheme.TextColor.tertiary)
                                .padding(.horizontal, PedefTheme.Spacing.xxs)
                                .padding(.vertical, 1)
                                .background(
                                    (selectedTab == tab ? PedefTheme.Brand.indigo : PedefTheme.TextColor.tertiary)
                                        .opacity(0.12),
                                    in: Capsule()
                                )
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? PedefTheme.Brand.indigo : PedefTheme.TextColor.tertiary)
                    .padding(.horizontal, PedefTheme.Spacing.sm)
                    .padding(.vertical, PedefTheme.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: PedefTheme.Radius.xs)
                            .fill(selectedTab == tab ? PedefTheme.Brand.indigo.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
    }
}

// MARK: - Color Filter Bar

struct ColorFilterBar: View {
    @Binding var selectedColor: AnnotationColor?

    var body: some View {
        HStack(spacing: PedefTheme.Spacing.xs) {
            ForEach(AnnotationColor.allCases, id: \.self) { color in
                Button {
                    withAnimation(PedefTheme.Animation.quick) {
                        if selectedColor == color {
                            selectedColor = nil
                        } else {
                            selectedColor = color
                        }
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: color.rawValue) ?? .yellow)
                        .frame(width: selectedColor == color ? 18 : 14, height: selectedColor == color ? 18 : 14)
                        .overlay {
                            if selectedColor == color {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                                Circle()
                                    .strokeBorder(Color(hex: color.rawValue) ?? .yellow, lineWidth: 1)
                                    .padding(2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(color.displayName)
            }

            Spacer()
        }
    }
}

// MARK: - All Annotations Tab

struct AllAnnotationsTabView: View {
    let annotations: [Annotation]
    let currentPage: Int
    var onNavigateToPage: ((Int) -> Void)?

    var annotationsOnCurrentPage: [Annotation] {
        annotations.filter { $0.pageIndex == currentPage }
    }

    var otherAnnotations: [Annotation] {
        annotations.filter { $0.pageIndex != currentPage }
    }

    var body: some View {
        if annotations.isEmpty {
            AnnotationEmptyState(
                icon: "highlighter",
                title: "No Annotations",
                message: "Select text and use ⌘H to highlight\nor ⇧⌘N to add a note"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !annotationsOnCurrentPage.isEmpty {
                        AnnotationSectionHeader(title: "This Page", count: annotationsOnCurrentPage.count)
                        ForEach(annotationsOnCurrentPage) { annotation in
                            EnhancedAnnotationRow(
                                annotation: annotation,
                                onNavigate: { onNavigateToPage?(annotation.pageIndex) }
                            )
                        }
                    }

                    if !otherAnnotations.isEmpty {
                        AnnotationSectionHeader(title: "Other Pages", count: otherAnnotations.count)
                        ForEach(otherAnnotations) { annotation in
                            EnhancedAnnotationRow(
                                annotation: annotation,
                                onNavigate: { onNavigateToPage?(annotation.pageIndex) }
                            )
                        }
                    }
                }
                .padding(.vertical, PedefTheme.Spacing.xs)
            }
        }
    }
}

// MARK: - Section Header

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

// MARK: - Enhanced Annotation Row

struct EnhancedAnnotationRow: View {
    @Bindable var annotation: Annotation
    @Environment(\.modelContext) private var modelContext
    @State private var isHovering = false
    @State private var showEditNote = false
    @State private var showColorPicker = false
    @State private var showAddTag = false
    @State private var editingNote = ""
    @State private var newTag = ""
    var onNavigate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: color dot, type icon, page, time, hover actions
            HStack(spacing: 8) {
                // Color dot — tappable to change color
                Button {
                    showColorPicker.toggle()
                } label: {
                    Circle()
                        .fill(Color(hex: annotation.colorHex) ?? .yellow)
                        .frame(width: 12, height: 12)
                        .overlay {
                            if isHovering {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Change color")
                .popover(isPresented: $showColorPicker) {
                    InlineColorPicker(
                        currentColor: annotation.colorHex,
                        onSelect: { color in
                            annotation.colorHex = color.rawValue
                            annotation.modifiedDate = Date()
                            showColorPicker = false
                        }
                    )
                }

                Image(systemName: annotation.type.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    onNavigate?()
                } label: {
                    Text("Page \(annotation.pageIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(PedefTheme.Brand.indigo)
                }
                .buttonStyle(.plain)
                .help("Jump to page")

                Spacer()

                // Hover actions
                if isHovering {
                    HStack(spacing: PedefTheme.Spacing.xxs) {
                        Button {
                            editingNote = annotation.noteContent ?? ""
                            showEditNote = true
                        } label: {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PedefTheme.TextColor.secondary)
                        .help("Edit comment (⌘E)")

                        Button {
                            showAddTag = true
                        } label: {
                            Image(systemName: "tag")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PedefTheme.TextColor.secondary)
                        .help("Add tag")

                        Button {
                            deleteAnnotation()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PedefTheme.Semantic.error.opacity(0.8))
                        .help("Delete")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Text(annotation.createdDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Selected text
            if let text = annotation.selectedText, !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .lineLimit(3)
                    .padding(.leading, 20)
            }

            // Note/comment
            if let note = annotation.noteContent, !note.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(PedefTheme.Brand.indigo.opacity(0.6))
                        .padding(.top, 2)

                    Text(note)
                        .font(.caption)
                        .foregroundStyle(PedefTheme.TextColor.secondary)
                        .lineLimit(2)
                }
                .padding(.leading, 20)
                .padding(.top, 2)
            }

            // Tags
            if !annotation.tags.isEmpty {
                HStack(spacing: PedefTheme.Spacing.xxs) {
                    ForEach(annotation.tags, id: \.self) { tag in
                        HStack(spacing: 2) {
                            Text(tag)
                                .font(PedefTheme.Typography.caption2)

                            if isHovering {
                                Button {
                                    annotation.tags.removeAll { $0 == tag }
                                    annotation.modifiedDate = Date()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, PedefTheme.Spacing.xs)
                        .padding(.vertical, PedefTheme.Spacing.xxxs)
                        .background(PedefTheme.Brand.indigo.opacity(0.10), in: Capsule())
                        .foregroundStyle(PedefTheme.Brand.indigo)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, PedefTheme.Spacing.lg)
        .padding(.vertical, PedefTheme.Spacing.sm)
        .background(isHovering ? PedefTheme.Surface.hover : Color.clear)
        .onHover { hovering in
            withAnimation(PedefTheme.Animation.quick) {
                isHovering = hovering
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onNavigate?()
        }
        .contextMenu {
            Button("Edit Comment") {
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
                deleteAnnotation()
            }
        }
        .popover(isPresented: $showEditNote) {
            CommentEditorPopover(
                noteContent: annotation.noteContent ?? "",
                onSave: { newNote in
                    annotation.noteContent = newNote.isEmpty ? nil : newNote
                    annotation.modifiedDate = Date()
                    showEditNote = false
                },
                onCancel: { showEditNote = false }
            )
        }
        .popover(isPresented: $showAddTag) {
            TagAddPopover(
                existingTags: annotation.tags,
                onAdd: { tag in
                    if !annotation.tags.contains(tag) {
                        annotation.tags.append(tag.lowercased())
                        annotation.modifiedDate = Date()
                    }
                },
                onDismiss: { showAddTag = false }
            )
        }
    }

    private func deleteAnnotation() {
        if let paper = annotation.paper {
            paper.annotations.removeAll { $0.id == annotation.id }
        }
        modelContext.delete(annotation)
    }
}

// MARK: - Inline Color Picker

struct InlineColorPicker: View {
    let currentColor: String
    let onSelect: (AnnotationColor) -> Void

    var body: some View {
        VStack(spacing: PedefTheme.Spacing.sm) {
            Text("Color")
                .font(PedefTheme.Typography.caption)
                .foregroundStyle(PedefTheme.TextColor.secondary)

            HStack(spacing: PedefTheme.Spacing.sm) {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    Button {
                        onSelect(color)
                    } label: {
                        Circle()
                            .fill(Color(hex: color.rawValue) ?? .yellow)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if currentColor == color.rawValue {
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 2)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(PedefTheme.Spacing.md)
    }
}

// MARK: - Comment Editor Popover

struct CommentEditorPopover: View {
    @State var noteContent: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    init(noteContent: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _noteContent = State(initialValue: noteContent)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: PedefTheme.Spacing.md) {
            HStack {
                Text("Comment")
                    .font(PedefTheme.Typography.headline)
                Spacer()
                if !noteContent.isEmpty {
                    Button {
                        noteContent = ""
                    } label: {
                        Text("Clear")
                            .font(PedefTheme.Typography.caption)
                            .foregroundStyle(PedefTheme.Semantic.error)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextEditor(text: $noteContent)
                .frame(width: 250, height: 100)
                .font(PedefTheme.Typography.body)
                .padding(PedefTheme.Spacing.xs)
                .background(PedefTheme.Surface.hover)
                .clipShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: PedefTheme.Radius.sm)
                        .stroke(PedefTheme.Brand.indigo.opacity(0.3), lineWidth: 1)
                )
                .focused($isFocused)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(PedefTheme.TextColor.secondary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    onSave(noteContent)
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
        .onAppear { isFocused = true }
    }
}

// MARK: - Tag Add Popover

struct TagAddPopover: View {
    let existingTags: [String]
    let onAdd: (String) -> Void
    let onDismiss: () -> Void
    @State private var newTag = ""
    @FocusState private var isFocused: Bool

    // Common annotation tags
    private let suggestedTags = ["important", "question", "todo", "methodology", "result", "definition", "cite"]

    private var unusedSuggestions: [String] {
        suggestedTags.filter { !existingTags.contains($0) }
    }

    var body: some View {
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
                .focused($isFocused)
                .onSubmit {
                    if !newTag.isEmpty {
                        onAdd(newTag)
                        newTag = ""
                    }
                }

            // Quick suggestions
            if !unusedSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: PedefTheme.Spacing.xxs) {
                    Text("Quick add")
                        .font(PedefTheme.Typography.caption2)
                        .foregroundStyle(PedefTheme.TextColor.tertiary)

                    FlowLayout(spacing: 4) {
                        ForEach(unusedSuggestions, id: \.self) { tag in
                            Button {
                                onAdd(tag)
                            } label: {
                                Text(tag)
                                    .font(PedefTheme.Typography.caption2)
                                    .padding(.horizontal, PedefTheme.Spacing.xs)
                                    .padding(.vertical, PedefTheme.Spacing.xxxs)
                                    .background(PedefTheme.Brand.indigo.opacity(0.08), in: Capsule())
                                    .foregroundStyle(PedefTheme.Brand.indigo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(PedefTheme.TextColor.secondary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    if !newTag.isEmpty {
                        onAdd(newTag)
                        newTag = ""
                    }
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
        .onAppear { isFocused = true }
    }
}

// MARK: - Notes Tab

struct NotesTabView: View {
    let notes: [Annotation]
    let currentPage: Int
    @Bindable var paper: Paper
    var onNavigateToPage: ((Int) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @State private var showNewNote = false

    var body: some View {
        VStack(spacing: 0) {
            if notes.isEmpty && !showNewNote {
                AnnotationEmptyState(
                    icon: "note.text",
                    title: "No Notes",
                    message: "Add notes with ⇧⌘N\nor tap + below"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: PedefTheme.Spacing.sm) {
                        if showNewNote {
                            NewStickyNoteCard(
                                pageIndex: currentPage,
                                onSave: { content in
                                    createNote(content: content)
                                    showNewNote = false
                                },
                                onCancel: { showNewNote = false }
                            )
                            .padding(.horizontal, PedefTheme.Spacing.lg)
                        }

                        ForEach(notes) { note in
                            StickyNoteCard(
                                annotation: note,
                                onNavigate: { onNavigateToPage?(note.pageIndex) },
                                onDelete: { deleteNote(note) }
                            )
                            .padding(.horizontal, PedefTheme.Spacing.lg)
                        }
                    }
                    .padding(.vertical, PedefTheme.Spacing.md)
                }
            }

            // Add note button at bottom
            Button {
                withAnimation(PedefTheme.Animation.spring) {
                    showNewNote = true
                }
            } label: {
                HStack(spacing: PedefTheme.Spacing.xs) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(PedefTheme.Brand.indigo)
                    Text("New Note on Page \(currentPage + 1)")
                        .font(PedefTheme.Typography.caption)
                        .foregroundStyle(PedefTheme.Brand.indigo)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PedefTheme.Spacing.sm)
                .background(PedefTheme.Brand.indigo.opacity(0.06))
            }
            .buttonStyle(.plain)
        }
    }

    private func createNote(content: String) {
        let annotation = Annotation(
            type: .stickyNote,
            pageIndex: currentPage,
            bounds: .zero
        )
        annotation.noteContent = content
        annotation.paper = paper
        paper.annotations.append(annotation)
    }

    private func deleteNote(_ note: Annotation) {
        paper.annotations.removeAll { $0.id == note.id }
        modelContext.delete(note)
    }
}

// MARK: - Sticky Note Card

struct StickyNoteCard: View {
    @Bindable var annotation: Annotation
    let onNavigate: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = true
    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: PedefTheme.Spacing.sm) {
            // Header
            HStack(spacing: PedefTheme.Spacing.xs) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: annotation.colorHex) ?? PedefTheme.Semantic.warning)

                Button(action: onNavigate) {
                    Text("Page \(annotation.pageIndex + 1)")
                        .font(PedefTheme.Typography.caption)
                        .foregroundStyle(PedefTheme.Brand.indigo)
                }
                .buttonStyle(.plain)

                Text("·")
                    .foregroundStyle(PedefTheme.TextColor.tertiary)

                Text(annotation.createdDate, style: .relative)
                    .font(PedefTheme.Typography.caption2)
                    .foregroundStyle(PedefTheme.TextColor.tertiary)

                Spacer()

                if isHovering {
                    HStack(spacing: PedefTheme.Spacing.xxs) {
                        Button {
                            editText = annotation.noteContent ?? ""
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PedefTheme.TextColor.secondary)

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PedefTheme.Semantic.error.opacity(0.8))
                    }
                    .transition(.opacity)
                } else {
                    Button {
                        withAnimation(PedefTheme.Animation.quick) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(PedefTheme.TextColor.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Content
            if isExpanded {
                if isEditing {
                    VStack(spacing: PedefTheme.Spacing.sm) {
                        TextEditor(text: $editText)
                            .font(PedefTheme.Typography.callout)
                            .frame(minHeight: 60)
                            .padding(PedefTheme.Spacing.xs)
                            .background(PedefTheme.Surface.primary)
                            .clipShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.xs))

                        HStack {
                            Button("Cancel") {
                                isEditing = false
                            }
                            .font(PedefTheme.Typography.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(PedefTheme.TextColor.secondary)

                            Spacer()

                            Button {
                                annotation.noteContent = editText.isEmpty ? nil : editText
                                annotation.modifiedDate = Date()
                                isEditing = false
                            } label: {
                                Text("Save")
                                    .font(PedefTheme.Typography.caption)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, PedefTheme.Spacing.md)
                                    .padding(.vertical, PedefTheme.Spacing.xxs)
                                    .background(PedefTheme.Brand.indigo, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.xs))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    // Show selected text if present
                    if let selectedText = annotation.selectedText, !selectedText.isEmpty {
                        HStack(alignment: .top, spacing: PedefTheme.Spacing.xs) {
                            Rectangle()
                                .fill(Color(hex: annotation.colorHex) ?? PedefTheme.Semantic.warning)
                                .frame(width: 2)

                            Text(selectedText)
                                .font(PedefTheme.Typography.caption)
                                .foregroundStyle(PedefTheme.TextColor.secondary)
                                .lineLimit(3)
                        }
                    }

                    // Note content
                    if let note = annotation.noteContent, !note.isEmpty {
                        Text(note)
                            .font(PedefTheme.Typography.callout)
                            .foregroundStyle(PedefTheme.TextColor.primary)
                            .textSelection(.enabled)
                    } else {
                        Text("Empty note")
                            .font(PedefTheme.Typography.caption)
                            .foregroundStyle(PedefTheme.TextColor.tertiary)
                            .italic()
                    }
                }
            }
        }
        .padding(PedefTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: PedefTheme.Radius.md)
                .fill(PedefTheme.Surface.elevated)
                .shadow(color: PedefTheme.Shadow.card.color, radius: PedefTheme.Shadow.card.radius, y: PedefTheme.Shadow.card.y)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: PedefTheme.Radius.md)
                .fill(Color(hex: annotation.colorHex) ?? PedefTheme.Semantic.warning)
                .frame(width: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: PedefTheme.Radius.md,
                        bottomLeadingRadius: PedefTheme.Radius.md,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
        }
        .onHover { hovering in
            withAnimation(PedefTheme.Animation.quick) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - New Sticky Note Card

struct NewStickyNoteCard: View {
    let pageIndex: Int
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var content = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PedefTheme.Spacing.sm) {
            HStack {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PedefTheme.Semantic.warning)

                Text("New note · Page \(pageIndex + 1)")
                    .font(PedefTheme.Typography.caption)
                    .foregroundStyle(PedefTheme.TextColor.secondary)

                Spacer()
            }

            TextEditor(text: $content)
                .font(PedefTheme.Typography.callout)
                .frame(minHeight: 60)
                .padding(PedefTheme.Spacing.xs)
                .background(PedefTheme.Surface.primary)
                .clipShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.xs))
                .overlay(
                    RoundedRectangle(cornerRadius: PedefTheme.Radius.xs)
                        .stroke(PedefTheme.Brand.indigo.opacity(0.3), lineWidth: 1)
                )
                .focused($isFocused)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .font(PedefTheme.Typography.caption)
                .buttonStyle(.plain)
                .foregroundStyle(PedefTheme.TextColor.secondary)

                Spacer()

                Button {
                    if !content.isEmpty {
                        onSave(content)
                    }
                } label: {
                    Text("Save")
                        .font(PedefTheme.Typography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, PedefTheme.Spacing.md)
                        .padding(.vertical, PedefTheme.Spacing.xxs)
                        .background(content.isEmpty ? PedefTheme.TextColor.tertiary : PedefTheme.Brand.indigo, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.xs))
                }
                .buttonStyle(.plain)
                .disabled(content.isEmpty)
            }
        }
        .padding(PedefTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: PedefTheme.Radius.md)
                .fill(PedefTheme.Surface.elevated)
                .shadow(color: PedefTheme.Shadow.card.color, radius: PedefTheme.Shadow.card.radius, y: PedefTheme.Shadow.card.y)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: PedefTheme.Radius.md,
                bottomLeadingRadius: PedefTheme.Radius.md,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(PedefTheme.Semantic.warning)
            .frame(width: 3)
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - Bookmarks Tab

struct BookmarksTabView: View {
    let bookmarks: [Annotation]
    let currentPage: Int
    @Bindable var paper: Paper
    var onNavigateToPage: ((Int) -> Void)?
    @Environment(\.modelContext) private var modelContext

    var isCurrentPageBookmarked: Bool {
        bookmarks.contains { $0.pageIndex == currentPage }
    }

    var body: some View {
        VStack(spacing: 0) {
            if bookmarks.isEmpty {
                AnnotationEmptyState(
                    icon: "bookmark",
                    title: "No Bookmarks",
                    message: "Tap the bookmark icon or use ⇧⌘B\nto bookmark the current page"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(bookmarks.sorted(by: { $0.pageIndex < $1.pageIndex })) { bookmark in
                            BookmarkRow(
                                bookmark: bookmark,
                                isCurrentPage: bookmark.pageIndex == currentPage,
                                onNavigate: { onNavigateToPage?(bookmark.pageIndex) },
                                onDelete: { removeBookmark(bookmark) },
                                onEditTitle: { title in
                                    bookmark.noteContent = title.isEmpty ? nil : title
                                    bookmark.modifiedDate = Date()
                                }
                            )
                        }
                    }
                    .padding(.vertical, PedefTheme.Spacing.xs)
                }
            }

            // Quick add/remove bookmark for current page
            Button {
                toggleBookmark()
            } label: {
                HStack(spacing: PedefTheme.Spacing.xs) {
                    Image(systemName: isCurrentPageBookmarked ? "bookmark.slash.fill" : "bookmark.fill")
                        .foregroundStyle(isCurrentPageBookmarked ? PedefTheme.Semantic.error : PedefTheme.Brand.indigo)
                    Text(isCurrentPageBookmarked ? "Remove Bookmark" : "Bookmark Page \(currentPage + 1)")
                        .font(PedefTheme.Typography.caption)
                        .foregroundStyle(isCurrentPageBookmarked ? PedefTheme.Semantic.error : PedefTheme.Brand.indigo)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PedefTheme.Spacing.sm)
                .background(
                    (isCurrentPageBookmarked ? PedefTheme.Semantic.error : PedefTheme.Brand.indigo).opacity(0.06)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleBookmark() {
        if let existing = bookmarks.first(where: { $0.pageIndex == currentPage }) {
            removeBookmark(existing)
        } else {
            let bookmark = Annotation(type: .bookmark, pageIndex: currentPage, bounds: .zero)
            bookmark.paper = paper
            paper.annotations.append(bookmark)
        }
    }

    private func removeBookmark(_ bookmark: Annotation) {
        paper.annotations.removeAll { $0.id == bookmark.id }
        modelContext.delete(bookmark)
    }
}

// MARK: - Bookmark Row

struct BookmarkRow: View {
    @Bindable var bookmark: Annotation
    let isCurrentPage: Bool
    let onNavigate: () -> Void
    let onDelete: () -> Void
    let onEditTitle: (String) -> Void

    @State private var isHovering = false
    @State private var isEditingTitle = false
    @State private var titleText = ""

    var body: some View {
        HStack(spacing: PedefTheme.Spacing.sm) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isCurrentPage ? PedefTheme.Brand.indigo : PedefTheme.TextColor.secondary)

            VStack(alignment: .leading, spacing: 2) {
                if isEditingTitle {
                    TextField("Bookmark title", text: $titleText)
                        .textFieldStyle(.plain)
                        .font(PedefTheme.Typography.callout)
                        .onSubmit {
                            onEditTitle(titleText)
                            isEditingTitle = false
                        }
                } else {
                    Text(bookmark.noteContent ?? "Page \(bookmark.pageIndex + 1)")
                        .font(PedefTheme.Typography.callout)
                        .foregroundStyle(PedefTheme.TextColor.primary)

                    Text(bookmark.createdDate, style: .relative)
                        .font(PedefTheme.Typography.caption2)
                        .foregroundStyle(PedefTheme.TextColor.tertiary)
                }
            }

            Spacer()

            if isHovering {
                HStack(spacing: PedefTheme.Spacing.xxs) {
                    Button {
                        titleText = bookmark.noteContent ?? ""
                        isEditingTitle = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PedefTheme.TextColor.secondary)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PedefTheme.Semantic.error.opacity(0.8))
                }
                .transition(.opacity)
            } else if isCurrentPage {
                Text("Current")
                    .font(PedefTheme.Typography.caption2)
                    .foregroundStyle(PedefTheme.Brand.indigo)
                    .padding(.horizontal, PedefTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(PedefTheme.Brand.indigo.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, PedefTheme.Spacing.lg)
        .padding(.vertical, PedefTheme.Spacing.sm)
        .background(isHovering ? PedefTheme.Surface.hover : (isCurrentPage ? PedefTheme.Brand.indigo.opacity(0.04) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            onNavigate()
        }
        .onHover { hovering in
            withAnimation(PedefTheme.Animation.quick) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Empty State

struct AnnotationEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: PedefTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(PedefTheme.TextColor.tertiary)

            Text(title)
                .font(PedefTheme.Typography.headline)
                .foregroundStyle(PedefTheme.TextColor.secondary)

            Text(message)
                .font(PedefTheme.Typography.caption)
                .foregroundStyle(PedefTheme.TextColor.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
