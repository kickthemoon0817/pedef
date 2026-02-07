import SwiftUI
import SwiftData

/// View for managing all tags in the library
struct TagManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var tagService: TagService
    @EnvironmentObject private var historyService: HistoryService
    @EnvironmentObject private var errorReporter: ErrorReporter

    @State private var searchQuery = ""
    @State private var sortOrder: TagSortOrder = .name
    @State private var selectedTag: Tag?
    @State private var isEditingTag = false
    @State private var editTagName = ""
    @State private var editTagColor = ""
    @State private var showingDeleteConfirmation = false
    @State private var resultAlert: TagManagerAlert?

    enum TagSortOrder: String, CaseIterable {
        case name = "Name"
        case usage = "Usage"
        case recent = "Recent"
    }

    struct TagManagerAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isSuccess: Bool
    }

    private var sortedTags: [Tag] {
        let filtered = searchQuery.isEmpty
            ? tagService.allTags
            : tagService.searchTags(matching: searchQuery)

        switch sortOrder {
        case .name:
            return filtered.sorted { $0.name < $1.name }
        case .usage:
            return filtered.sorted { $0.usageCount > $1.usageCount }
        case .recent:
            return filtered.sorted { $0.createdDate > $1.createdDate }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if tagService.allTags.isEmpty {
                emptyStateView
            } else {
                tagListView
            }
        }
        .sheet(isPresented: $isEditingTag) {
            editTagSheet
        }
        .alert(item: $resultAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Delete Tag", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let tag = selectedTag {
                    deleteTag(tag)
                }
            }
        } message: {
            if let tag = selectedTag {
                Text("Are you sure you want to delete '\(tag.name)'? This will remove the tag from \(tag.papers.count) paper(s).")
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(spacing: PedefTheme.Spacing.md) {
            HStack {
                Text("Tags")
                    .font(PedefTheme.Typography.title3)
                    .foregroundStyle(PedefTheme.TextColor.primary)

                Text("\(tagService.allTags.count)")
                    .font(PedefTheme.Typography.caption)
                    .foregroundStyle(PedefTheme.TextColor.tertiary)
                    .padding(.horizontal, PedefTheme.Spacing.sm)
                    .padding(.vertical, PedefTheme.Spacing.xxxs)
                    .background(PedefTheme.Surface.hover, in: Capsule())

                Spacer()
            }

            HStack(spacing: PedefTheme.Spacing.md) {
                // Search
                PedefSearchField(text: $searchQuery, placeholder: "Search tags...")

                // Sort buttons
                HStack(spacing: 2) {
                    ForEach(TagSortOrder.allCases, id: \.self) { order in
                        Button {
                            withAnimation(PedefTheme.Animation.quick) {
                                sortOrder = order
                            }
                        } label: {
                            Text(order.rawValue)
                                .font(PedefTheme.Typography.caption)
                                .foregroundStyle(sortOrder == order ? PedefTheme.Brand.indigo : PedefTheme.TextColor.tertiary)
                                .padding(.horizontal, PedefTheme.Spacing.sm)
                                .padding(.vertical, PedefTheme.Spacing.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: PedefTheme.Radius.xs)
                                        .fill(sortOrder == order ? PedefTheme.Brand.indigo.opacity(0.12) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                .help("Sort tags")
            }
        }
        .padding(.horizontal, PedefTheme.Spacing.xl)
        .padding(.vertical, PedefTheme.Spacing.md)
        .background(PedefTheme.Surface.bar)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Tags Yet")
                .font(.headline)

            Text("Add tags to your papers to organize and find them easily.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested tags to get started:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(TagSuggestion.allCases.prefix(6), id: \.rawValue) { suggestion in
                        Button(action: { createSuggestedTag(suggestion) }) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: suggestion.color) ?? PedefTheme.Brand.indigo)
                                    .frame(width: 8, height: 8)
                                Text(suggestion.displayName)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: suggestion.color)?.opacity(0.5) ?? .gray, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: PedefTheme.Radius.lg)
                    .fill(PedefTheme.Surface.elevated)
            )
        }
        .padding(PedefTheme.Spacing.xxxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tagListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(sortedTags, id: \.id) { tag in
                    TagRowView(
                        tag: tag,
                        isSelected: selectedTag?.id == tag.id,
                        onTap: { selectedTag = tag },
                        onEdit: {
                            selectedTag = tag
                            editTagName = tag.name
                            editTagColor = tag.colorHex
                            isEditingTag = true
                        },
                        onDelete: {
                            selectedTag = tag
                            showingDeleteConfirmation = true
                        }
                    )
                }
            }
            .padding()
        }
    }

    private var editTagSheet: some View {
        VStack(spacing: PedefTheme.Spacing.xl) {
            Text("Edit Tag")
                .font(PedefTheme.Typography.headline)

            VStack(alignment: .leading, spacing: PedefTheme.Spacing.sm) {
                Text("Name")
                    .font(PedefTheme.Typography.caption)
                    .foregroundStyle(PedefTheme.TextColor.secondary)

                TextField("Tag name", text: $editTagName)
                    .textFieldStyle(.plain)
                    .font(PedefTheme.Typography.body)
                    .padding(PedefTheme.Spacing.sm)
                    .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: PedefTheme.Radius.sm)
                            .stroke(PedefTheme.Brand.indigo.opacity(0.5), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: PedefTheme.Spacing.sm) {
                Text("Color")
                    .font(PedefTheme.Typography.caption)
                    .foregroundStyle(PedefTheme.TextColor.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 8), count: 5), spacing: 8) {
                    ForEach(Tag.predefinedColors, id: \.self) { color in
                        Button(action: { editTagColor = color }) {
                            Circle()
                                .fill(Color(hex: color) ?? .gray)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(editTagColor == color ? PedefTheme.Brand.indigo : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Preview
            HStack {
                Text("Preview:")
                    .font(PedefTheme.Typography.caption)
                    .foregroundStyle(PedefTheme.TextColor.secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: editTagColor) ?? PedefTheme.Brand.indigo)
                        .frame(width: 8, height: 8)
                    Text(editTagName.isEmpty ? "tag name" : editTagName)
                        .font(PedefTheme.Typography.caption)
                }
                .padding(.horizontal, PedefTheme.Spacing.sm)
                .padding(.vertical, PedefTheme.Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: PedefTheme.Radius.pill)
                        .fill((Color(hex: editTagColor) ?? PedefTheme.Brand.indigo).opacity(0.15))
                )
            }

            HStack {
                Button("Cancel") {
                    isEditingTag = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(PedefTheme.TextColor.secondary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    saveTagEdits()
                } label: {
                    Text("Save")
                        .font(PedefTheme.Typography.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, PedefTheme.Spacing.lg)
                        .padding(.vertical, PedefTheme.Spacing.xs)
                        .background(editTagName.isEmpty ? PedefTheme.TextColor.tertiary : PedefTheme.Brand.indigo, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(editTagName.isEmpty)
            }
        }
        .padding(PedefTheme.Spacing.xxl)
        .frame(width: 300)
    }

    // MARK: - Actions

    private func createSuggestedTag(_ suggestion: TagSuggestion) {
        do {
            let tag = try tagService.createSuggestedTag(suggestion)
            historyService.recordAction(
                .createTag,
                details: [
                    "tagId": tag.id.uuidString,
                    "tagName": tag.name
                ]
            )
            resultAlert = TagManagerAlert(
                title: "Tag Created",
                message: "\"\(tag.name)\" is now available in your library.",
                isSuccess: true
            )
        } catch {
            errorReporter.report(error, title: "Tag Creation Failed")
        }
    }

    private func saveTagEdits() {
        guard let tag = selectedTag else { return }

        do {
            try tagService.updateTag(tag, name: editTagName, colorHex: editTagColor)
            historyService.recordAction(
                .updateTag,
                details: [
                    "tagId": tag.id.uuidString,
                    "tagName": editTagName
                ]
            )
            isEditingTag = false
            resultAlert = TagManagerAlert(
                title: "Tag Updated",
                message: "\"\(editTagName)\" has been updated.",
                isSuccess: true
            )
        } catch {
            errorReporter.report(error, title: "Tag Update Failed")
        }
    }

    private func deleteTag(_ tag: Tag) {
        do {
            let tagName = tag.name
            let tagId = tag.id.uuidString
            try tagService.deleteTag(tag)
            historyService.recordAction(
                .deleteTag,
                details: [
                    "tagId": tagId,
                    "tagName": tagName
                ]
            )
            selectedTag = nil
            resultAlert = TagManagerAlert(
                title: "Tag Deleted",
                message: "\"\(tagName)\" was removed from your library.",
                isSuccess: true
            )
        } catch {
            errorReporter.report(error, title: "Tag Deletion Failed")
        }
    }
}

// MARK: - Tag Row View

struct TagRowView: View {
    let tag: Tag
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            Circle()
                .fill(Color(hex: tag.colorHex) ?? PedefTheme.Brand.indigo)
                .frame(width: 12, height: 12)

            // Tag name
            Text(tag.name)
                .font(.body)

            Spacer()

            // Usage count
            HStack(spacing: 4) {
                Image(systemName: "doc.fill")
                    .font(.caption2)
                Text("\(tag.usageCount)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            // Actions (visible on hover)
            if isHovered {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Edit tag")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Delete tag")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: PedefTheme.Radius.md)
                .fill(isSelected ? PedefTheme.Brand.indigo.opacity(0.10) : (isHovered ? PedefTheme.Surface.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
