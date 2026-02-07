import SwiftUI
import SwiftData

struct TimelineView: View {
    @EnvironmentObject private var historyService: HistoryService
    @State private var selectedDateRange: DateRange = .today
    @State private var selectedCategory: ActionCategory?
    @State private var expandedSessions: Set<UUID> = []

    enum DateRange: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case allTime = "All Time"

        var range: ClosedRange<Date> {
            let calendar = Calendar.current
            let now = Date()

            switch self {
            case .today:
                let start = calendar.startOfDay(for: now)
                return start...now
            case .yesterday:
                let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
                let end = calendar.startOfDay(for: now)
                return start...end
            case .thisWeek:
                let start = calendar.date(byAdding: .day, value: -7, to: now)!
                return start...now
            case .thisMonth:
                let start = calendar.date(byAdding: .month, value: -1, to: now)!
                return start...now
            case .allTime:
                let start = Date.distantPast
                return start...now
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Text("Activity")
                    .font(PedefTheme.Typography.title3)
                    .foregroundStyle(PedefTheme.TextColor.primary)

                Spacer()

                Button {
                    // Export history
                } label: {
                    HStack(spacing: PedefTheme.Spacing.xxs) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .medium))
                        Text("Export")
                            .font(PedefTheme.Typography.caption)
                    }
                    .foregroundStyle(PedefTheme.TextColor.secondary)
                    .padding(.horizontal, PedefTheme.Spacing.sm)
                    .padding(.vertical, PedefTheme.Spacing.xs)
                    .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
                }
                .buttonStyle(.plain)
                .help("Export History")
            }
            .padding(.horizontal, PedefTheme.Spacing.xl)
            .padding(.vertical, PedefTheme.Spacing.md)
            .background(PedefTheme.Surface.bar)

            // Filters
            TimelineFilters(
                selectedDateRange: $selectedDateRange,
                selectedCategory: $selectedCategory
            )

            Divider()

            // Stats Summary
            StatsSummaryView(stats: historyService.getOverallStats())

            Divider()

            // Timeline
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedActions.keys.sorted().reversed(), id: \.self) { date in
                        DaySection(
                            date: date,
                            actions: groupedActions[date] ?? [],
                            expandedSessions: $expandedSessions
                        )
                    }
                }
                .padding()
            }
        }
    }

    private var filteredActions: [ActionHistory] {
        var actions = historyService.getActions(inDateRange: selectedDateRange.range, limit: 500)
        if let category = selectedCategory {
            actions = actions.filter { $0.category == category }
        }
        return actions
    }

    private var groupedActions: [Date: [ActionHistory]] {
        let calendar = Calendar.current
        return Dictionary(grouping: filteredActions) { action in
            calendar.startOfDay(for: action.timestamp)
        }
    }
}

// MARK: - Filters

struct TimelineFilters: View {
    @Binding var selectedDateRange: TimelineView.DateRange
    @Binding var selectedCategory: ActionCategory?

    var body: some View {
        HStack(spacing: PedefTheme.Spacing.lg) {
            // Date range pills
            HStack(spacing: 2) {
                ForEach(TimelineView.DateRange.allCases, id: \.self) { range in
                    Button {
                        withAnimation(PedefTheme.Animation.quick) {
                            selectedDateRange = range
                        }
                    } label: {
                        Text(range.rawValue)
                            .font(PedefTheme.Typography.caption)
                            .foregroundStyle(selectedDateRange == range ? PedefTheme.Brand.indigo : PedefTheme.TextColor.tertiary)
                            .padding(.horizontal, PedefTheme.Spacing.sm)
                            .padding(.vertical, PedefTheme.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: PedefTheme.Radius.xs)
                                    .fill(selectedDateRange == range ? PedefTheme.Brand.indigo.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))

            // Category filter
            Menu {
                Button("All") { selectedCategory = nil }
                Divider()
                ForEach(ActionCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category.displayName, systemImage: category.systemImage)
                    }
                }
            } label: {
                HStack(spacing: PedefTheme.Spacing.xxs) {
                    Image(systemName: selectedCategory?.systemImage ?? "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .medium))
                    Text(selectedCategory?.displayName ?? "All")
                        .font(PedefTheme.Typography.caption)
                }
                .foregroundStyle(selectedCategory != nil ? PedefTheme.Brand.indigo : PedefTheme.TextColor.secondary)
                .padding(.horizontal, PedefTheme.Spacing.sm)
                .padding(.vertical, PedefTheme.Spacing.xs)
                .background(PedefTheme.Surface.hover, in: RoundedRectangle(cornerRadius: PedefTheme.Radius.sm))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
        .padding(.horizontal, PedefTheme.Spacing.xl)
        .padding(.vertical, PedefTheme.Spacing.md)
        .background(PedefTheme.Surface.bar)
    }
}

extension ActionCategory: CaseIterable {
    static var allCases: [ActionCategory] {
        [.reading, .annotation, .library, .agent, .session]
    }
}

// MARK: - Stats Summary

struct StatsSummaryView: View {
    let stats: OverallStats

    var body: some View {
        HStack(spacing: PedefTheme.Spacing.xxl) {
            StatItem(
                title: "Reading Time",
                value: stats.formattedReadingTime,
                icon: "clock"
            )

            StatItem(
                title: "Papers Read",
                value: "\(stats.papersRead)",
                icon: "doc.text"
            )

            StatItem(
                title: "Annotations",
                value: "\(stats.totalAnnotations)",
                icon: "highlighter"
            )

            StatItem(
                title: "Sessions",
                value: "\(stats.sessionsCount)",
                icon: "calendar"
            )
        }
        .padding()
        .background(PedefTheme.Surface.elevated)
        .pedefShadow(PedefTheme.Shadow.sm)
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: PedefTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(PedefTheme.Brand.indigo)

            Text(value)
                .font(PedefTheme.Typography.headline)

            Text(title)
                .font(PedefTheme.Typography.caption)
                .foregroundStyle(PedefTheme.TextColor.secondary)
        }
        .frame(minWidth: 80)
    }
}

// MARK: - Day Section

struct DaySection: View {
    let date: Date
    let actions: [ActionHistory]
    @Binding var expandedSessions: Set<UUID>

    private var groupedBySession: [UUID: [ActionHistory]] {
        Dictionary(grouping: actions) { $0.sessionId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            Text(date, style: .date)
                .font(.headline)
                .foregroundStyle(.secondary)

            // Sessions
            ForEach(groupedBySession.keys.sorted { lhs, rhs in
                let lhsFirst = groupedBySession[lhs]?.first?.timestamp ?? Date.distantPast
                let rhsFirst = groupedBySession[rhs]?.first?.timestamp ?? Date.distantPast
                return lhsFirst > rhsFirst
            }, id: \.self) { sessionId in
                SessionCard(
                    sessionId: sessionId,
                    actions: groupedBySession[sessionId] ?? [],
                    isExpanded: expandedSessions.contains(sessionId),
                    onToggle: {
                        if expandedSessions.contains(sessionId) {
                            expandedSessions.remove(sessionId)
                        } else {
                            expandedSessions.insert(sessionId)
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Session Card

struct SessionCard: View {
    let sessionId: UUID
    let actions: [ActionHistory]
    let isExpanded: Bool
    let onToggle: () -> Void

    private var startTime: Date {
        actions.last?.timestamp ?? Date()
    }

    private var endTime: Date {
        actions.first?.timestamp ?? Date()
    }

    private var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    private var papersOpened: Set<UUID> {
        Set(actions.compactMap(\.paperId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Session header
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(startTime, style: .time)
                        .font(.subheadline.weight(.medium))

                    Text("-")
                        .foregroundStyle(.secondary)

                    Text(endTime, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 12) {
                        Label("\(actions.count)", systemImage: "list.bullet")
                        Label("\(papersOpened.count)", systemImage: "doc.text")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Expanded actions
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(actions) { action in
                        ActionRow(action: action)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding()
        .background(PedefTheme.Surface.elevated)
        .clipShape(RoundedRectangle(cornerRadius: PedefTheme.Radius.md))
        .pedefShadow(PedefTheme.Shadow.card)
    }
}

// MARK: - Action Row

struct ActionRow: View {
    let action: ActionHistory

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: action.category.systemImage)
                .font(.caption)
                .foregroundStyle(categoryColor)
                .frame(width: 16)

            Text(action.actionType.displayName)
                .font(.caption)

            Spacer()

            Text(action.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var categoryColor: Color {
        switch action.category {
        case .reading: return PedefTheme.Brand.indigo
        case .annotation: return PedefTheme.Semantic.warning
        case .library: return PedefTheme.Semantic.success
        case .agent: return PedefTheme.Brand.purple
        case .session: return PedefTheme.TextColor.tertiary
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TimelineView()
            .environmentObject(HistoryService())
    }
}
