import SwiftUI
import SwiftData

/// View for managing all tags in the library
struct TagManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var tagService: TagService
    @EnvironmentObject private var historyService: HistoryService

    @State private var searchQuery = ""
    @State private var sortOrder: TagSortOrder = .name
    @State private var selectedTag: Tag?
    @State private var isEditingTag = false
    @State private var editTagName = ""
    @State private var editTagColor = ""
    @State private var showingDeleteConfirmation = false

    enum TagSortOrder: String, CaseIterable {
        case name = "Name"
        case usage = "Usage"
        case recent = "Recent"
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
        VStack(spacing: 12) {
            HStack {
                Text("Tags")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(tagService.allTags.count) tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search tags...", text: $searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )

                // Sort picker
                Picker("Sort", selection: $sortOrder) {
                    ForEach(TagSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
        .padding()
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
                                    .fill(Color(hex: suggestion.color) ?? .accentColor)
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .padding(40)
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
        VStack(spacing: 20) {
            Text("Edit Tag")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Tag name", text: $editTagName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 8), count: 5), spacing: 8) {
                    ForEach(Tag.predefinedColors, id: \.self) { color in
                        Button(action: { editTagColor = color }) {
                            Circle()
                                .fill(Color(hex: color) ?? .gray)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: editTagColor == color ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Preview
            HStack {
                Text("Preview:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: editTagColor) ?? .accentColor)
                        .frame(width: 8, height: 8)
                    Text(editTagName.isEmpty ? "tag name" : editTagName)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill((Color(hex: editTagColor) ?? .accentColor).opacity(0.15))
                )
            }

            HStack {
                Button("Cancel") {
                    isEditingTag = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveTagEdits()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editTagName.isEmpty)
            }
        }
        .padding(24)
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
        } catch {
            print("Failed to create tag: \(error)")
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
        } catch {
            print("Failed to update tag: \(error)")
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
        } catch {
            print("Failed to delete tag: \(error)")
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
                .fill(Color(hex: tag.colorHex) ?? .accentColor)
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

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
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

