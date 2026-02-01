import SwiftUI

// MARK: - Tag Chip View

/// A compact tag representation with optional delete action
struct TagChipView: View {
    let tag: Tag
    var showDeleteButton: Bool = false
    var onDelete: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: tag.colorHex) ?? .accentColor)
                .frame(width: 8, height: 8)

            Text(tag.name)
                .font(.caption)
                .lineLimit(1)

            if showDeleteButton && isHovered {
                Button(action: { onDelete?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill((Color(hex: tag.colorHex) ?? .accentColor).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((Color(hex: tag.colorHex) ?? .accentColor).opacity(0.3), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Tag List View

/// Displays a collection of tags in a flowing layout
struct TagListView: View {
    let tags: [Tag]
    var showDeleteButtons: Bool = false
    var onTagTapped: ((Tag) -> Void)?
    var onDeleteTag: ((Tag) -> Void)?

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.id) { tag in
                TagChipView(
                    tag: tag,
                    showDeleteButton: showDeleteButtons,
                    onDelete: { onDeleteTag?(tag) }
                )
                .onTapGesture {
                    onTagTapped?(tag)
                }
            }
        }
    }
}

// MARK: - Tag Input View

/// A text field for adding new tags with autocomplete suggestions
struct TagInputView: View {
    @Binding var inputText: String
    let existingTags: [Tag]
    let onAddTag: (String) -> Void
    let onSelectTag: (Tag) -> Void

    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool

    private var filteredSuggestions: [Tag] {
        guard !inputText.isEmpty else { return [] }
        let query = inputText.lowercased()
        return existingTags.filter { $0.name.contains(query) }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextField("Add tag...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($isFocused)
                    .onSubmit {
                        if !inputText.isEmpty {
                            onAddTag(inputText)
                            inputText = ""
                        }
                    }
                    .onChange(of: inputText) { _, newValue in
                        showingSuggestions = !newValue.isEmpty && !filteredSuggestions.isEmpty
                    }

                if !inputText.isEmpty {
                    Button(action: { inputText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )

            if showingSuggestions {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredSuggestions, id: \.id) { tag in
                        Button(action: {
                            onSelectTag(tag)
                            inputText = ""
                            showingSuggestions = false
                        }) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: tag.colorHex) ?? .accentColor)
                                    .frame(width: 8, height: 8)
                                Text(tag.name)
                                    .font(.caption)
                                Spacer()
                                Text("\(tag.usageCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.1))
                                .opacity(0)
                        )
                    }
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                )
            }
        }
    }
}

// MARK: - Tag Suggestion Pills

/// Quick-add buttons for suggested tags
struct TagSuggestionPillsView: View {
    let suggestions: [TagSuggestion]
    let onSelect: (TagSuggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.rawValue) { suggestion in
                    Button(action: { onSelect(suggestion) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .bold))
                            Text(suggestion.displayName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: suggestion.color)?.opacity(0.5) ?? .gray, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: suggestion.color) ?? .accentColor)
                }
            }
        }
    }
}

// MARK: - Paper Tags Section

/// Complete tag management section for a paper
struct PaperTagsSection: View {
    let paper: Paper
    @ObservedObject var tagService: TagService
    @State private var newTagInput = ""
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.secondary)
                    Text("Tags")
                        .font(.headline)
                    Spacer()
                    Text("\(paper.tagObjects.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Current tags
                if paper.tagObjects.isEmpty {
                    Text("No tags added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    TagListView(
                        tags: paper.sortedTags,
                        showDeleteButtons: true,
                        onDeleteTag: { tag in
                            try? tagService.removeTag(tag, from: paper)
                        }
                    )
                }

                // Tag input
                TagInputView(
                    inputText: $newTagInput,
                    existingTags: tagService.allTags.filter { tag in
                        !paper.tagObjects.contains(where: { $0.id == tag.id })
                    },
                    onAddTag: { name in
                        _ = try? tagService.addNewTag(named: name, to: paper)
                    },
                    onSelectTag: { tag in
                        try? tagService.addTag(tag, to: paper)
                    }
                )

                // Suggestions
                let suggestions = tagService.suggestedTags(for: paper)
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggestions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        TagSuggestionPillsView(suggestions: Array(suggestions.prefix(5))) { suggestion in
                            if let tag = try? tagService.createSuggestedTag(suggestion) {
                                try? tagService.addTag(tag, to: paper)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Flow Layout

/// A layout that flows items horizontally and wraps to new lines
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

