# AGENTS Guide for Pedef

This guide summarizes the project context and conventions for automated agents working in this repo.

## Project Overview
Pedef is a native macOS PDF reader and knowledge archive for academic research. The app supports PDF reading, annotations, library management, action history, and AI-assisted features.

## Tech Stack
- Platform: macOS 14+
- Language: Swift 6.2+ (Swift Language Mode 5)
- UI: SwiftUI with AppKit integrations where needed
- PDF: PDFKit
- Persistence: SwiftData
- AI: Claude via SwiftAnthropic v2.2.0
- Markdown: swift-markdown-ui v2.4.1
- Security: KeychainAccess v4.2.2
- Build: Swift Package Manager / Xcode 15+

## Repo Layout
- App/: app entry point and lifecycle
- Core/: Models, Services, Agents
- Features/: UI grouped by domain (Reader, Library, History, Agent)
- Shared/: reusable components, extensions, utilities
- Resources/: assets, colors, localizations
- Tests/: unit, integration, UI tests

## Key Features
- PDF reader with navigation, outline, zoom, progress
- Annotation system (highlights, notes, drawings, bookmarks)
- Library management (collections, tags, search, dedup)
- Action history with replay and analytics
- AI agents for summaries, citations, Q&A, research assistance

## Development Conventions
- Follow Swift API Design Guidelines
- Prefer value types where appropriate
- Use async/await for async work
- Document public APIs with DocC comments
- Maintain accessible UI (VoiceOver, keyboard nav, contrast)
- Avoid large refactors when making focused fixes

## Build and Test
- Build: `xcodebuild -scheme Pedef -configuration Debug build`
- Test: `xcodebuild -scheme Pedef test`

## Environment Variables
- `ANTHROPIC_API_KEY`: Claude API key
- `PEDEF_DEBUG_LOGGING`: enable verbose logging

## Agent Integration
Agents implement `PedefAgent` and operate with an `AgentContext` including current paper content, annotations, related papers, conversation history, and user preferences.

Available actions include adding annotations, creating notes, searching the archive, suggesting related papers, generating citations, and drafting text responses.
