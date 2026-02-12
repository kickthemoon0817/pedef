# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - 2026-02-13

### Added

#### Annotation Sidebar — Tabbed Design
- **Three-tab layout**: All Annotations, Notes, Bookmarks — each with its own view
- **Color filter bar**: Click color dots to filter highlights by color in the "All" tab
- **Type filter**: Filter by annotation type (highlight, underline, etc.) alongside color
- **Clear filters button**: One-click reset for all active filters

#### Comment Workflow
- **Quick add/edit/delete comments** via hover actions on annotation rows
- **Comment editor popover** with keyboard shortcuts (⌘Enter to save, Escape to cancel)
- **Clear comment button** in the editor for quick removal
- **Inline tag management**: Remove tags directly from annotation rows on hover

#### Highlight UX
- **Fast color switch**: Click the color dot on any annotation row to open an inline color picker
- **Color filter pills**: Filter all annotations by highlight color
- **Tag/label support**: Add tags with quick suggestions (important, question, todo, methodology, etc.)
- **Tag removal on hover**: Remove individual tags from annotations without opening a menu

#### Sticky Notes (Post-it)
- **Sticky note card UI**: Collapsible/expandable cards with colored left border
- **Notes panel**: Dedicated "Notes" tab showing all notes for the current document
- **New note creation**: "New Note on Page X" button at the bottom of the Notes tab
- **In-place editing**: Edit note content directly in the card
- **Context-aware notes**: Creating a note while text is selected captures the selection

#### Bookmark Improvements
- **One-tap bookmark toggle**: Header bookmark button shows filled/unfilled state for current page
- **Bookmark list**: Dedicated "Bookmarks" tab with all bookmarks sorted by page
- **Bookmark titles**: Editable titles for bookmarks (defaults to "Page N")
- **Current page indicator**: Shows "Current" badge for the current page's bookmark
- **Quick add/remove**: Bottom bar in Bookmarks tab for one-tap bookmark toggle
- **Jump-to-bookmark**: Click any bookmark to navigate to its page

#### Navigation
- **Click-to-navigate**: Clicking an annotation row in the sidebar jumps to its page
- **Page links**: "Page N" labels in annotation rows are clickable navigation links

### Changed
- Annotation sidebar refactored from monolithic view to focused, tabbed components
- Sidebar width increased from 300px to 320px ideal for better readability
- Annotation rows now show hover actions (edit, tag, delete) instead of relying solely on context menus
- Empty states have distinct messages per tab with relevant keyboard shortcuts

### Fixed
- Bookmark button now visually reflects current page bookmark state
- Annotation sidebar now properly excludes bookmarks from the main "All" list

### Technical
- New file: `Features/Reader/AnnotationSidebarView.swift` — all sidebar components
- Model extensions: `Annotation.isBookmark`, `Annotation.isNote`, `Paper.bookmarks`, `Paper.notes`, `Paper.isPageBookmarked(_:)`
- Added 10 new unit tests for annotation model operations
- Separated annotation sidebar from PDFReaderView.swift for maintainability
