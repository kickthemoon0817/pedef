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
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Export history
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export History")
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
        HStack {
            Picker("Time Range", selection: $selectedDateRange) {
                ForEach(TimelineView.DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .frame(width: 120)

            Picker("Category", selection: $selectedCategory) {
                Text("All").tag(nil as ActionCategory?)
                ForEach(ActionCategory.allCases, id: \.self) { category in
                    Label(category.displayName, systemImage: category.systemImage)
                        .tag(category as ActionCategory?)
                }
            }
            .frame(width: 120)

            Spacer()
        }
        .padding()
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
        HStack(spacing: 24) {
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
        .background(Color.secondary.opacity(0.05))
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        case .reading: return .blue
        case .annotation: return .yellow
        case .library: return .green
        case .agent: return .purple
        case .session: return .gray
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
