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

## Project Version Control

This repository uses Git for version control. Please follow these guidelines when contributing:

1. **Branching Strategy**: Use feature branches for new features and bug fixes. Name branches descriptively (e.g., `feature/add-user-authentication`, `bugfix/fix-login-error`). This is important to avoid conflicts between branches.
2. **Commit Messages**: Use conventional commit format `type(scope): description`, e.g. `feat(reader): add page capture` or `fix(ui): resolve contrast issue`.
3. **Pull Requests**: Submit pull requests for code reviews before merging changes into the main branch. Ensure that your code passes all tests and adheres to coding standards.
4. **Code Reviews**: Participate in code reviews to maintain code quality and share knowledge among team members.

## Build and Test
- Build: `xcodebuild -scheme Pedef -configuration Debug build -destination 'platform=macOS'`
- Test: `xcodebuild -scheme Pedef test -destination 'platform=macOS'` or `./scripts/run-tests.sh`

## CI and PR Workflow
- CI: `.github/workflows/ci.yml` runs SwiftLint (non-blocking), build, and test on PRs and main.
- PRs: follow the template at `.github/pull_request_template.md`.
- Verification: use automated commands only; avoid manual checks in agent workflows.

## Environment Variables
- `ANTHROPIC_API_KEY`: Claude API key
- `PEDEF_DEBUG_LOGGING`: enable verbose logging

## Agent Integration
Agents implement `PedefAgent` and operate with an `AgentContext` including current paper content, annotations, related papers, conversation history, and user preferences.

Available actions include adding annotations, creating notes, searching the archive, suggesting related papers, generating citations, and drafting text responses.
