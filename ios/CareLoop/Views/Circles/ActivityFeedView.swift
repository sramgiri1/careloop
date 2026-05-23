import SwiftUI

struct ActivityFeedView: View {
    @EnvironmentObject private var appState: AppState

    @State private var events:  [CircleEvent] = []
    @State private var insights: CircleCompletionInsights?
    @State private var loading  = true
    @State private var error:   String?

    private let mid  = Color(red: 0.43, green: 0.50, blue: 0.60)
    private let dark = Color(red: 0.10, green: 0.16, blue: 0.24)
    private let bg   = Color(red: 0.95, green: 0.96, blue: 0.99)
    private let teal = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let blue = Color(red: 0.13, green: 0.56, blue: 0.87)
    private let green = Color(red: 0.12, green: 0.68, blue: 0.49)

    private var role: MemberRole { appState.userRole }
    private var isCaregiver: Bool { role == .member }

    private var visibleEvents: [CircleEvent] {
        events.filter { $0.isVisible(to: role) }
    }

    private var grouped: [(String, [CircleEvent])] {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        // Sort descending so newest section appears first
        let sorted = visibleEvents.sorted { $0.createdAt > $1.createdAt }
        var result: [(String, [CircleEvent])] = []
        var seen: [String: Int] = [:]
        for event in sorted {
            let key = Calendar.current.isDateInToday(event.createdAt)     ? "Today"
                    : Calendar.current.isDateInYesterday(event.createdAt) ? "Yesterday"
                    : fmt.string(from: event.createdAt)
            if let idx = seen[key] {
                result[idx].1.append(event)
            } else {
                seen[key] = result.count
                result.append((key, [event]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleEvents.isEmpty && !(isCaregiver && insights != nil) {
                    emptyState
                } else {
                    List {
                        if isCaregiver, let insights {
                            progressOverviewSection(insights)
                            if !insights.recipientBreakdown.isEmpty {
                                progressByReceiverSection(insights)
                            }
                        }
                        ForEach(grouped, id: \.0) { section, sectionEvents in
                            Section(section) {
                                ForEach(sectionEvents) { event in
                                    eventRow(event)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier(isCaregiver ? "receiver-progress-screen" : "activity-screen")
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(isCaregiver ? "Receiver Progress" : "Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .background(bg.ignoresSafeArea())
            .task { await load() }
        }
        .careLoopBrandBanner()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(mid)
            Text("No activity yet")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(dark)
            Text(isCaregiver ? "Receiver progress updates will appear here once care work begins." : "Actions taken in this circle will appear here.")
                .font(.system(size: 14))
                .foregroundStyle(mid)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func eventRow(_ event: CircleEvent) -> some View {
        let c = event.feedIconColor
        let iconColor = Color(red: c.red, green: c.green, blue: c.blue)
        let description = event.feedDescription(for: role)
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: event.feedIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(description)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(dark)
                    .lineLimit(2)
                Text(timeLabel(event.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(mid)
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday at \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private func progressOverviewSection(_ insights: CircleCompletionInsights) -> some View {
        Section("Overview") {
            HStack(spacing: 12) {
                progressCard(title: "Completed", value: "\(insights.totals.completed)", tint: green)
                progressCard(title: "Active", value: "\(insights.totals.active)", tint: blue)
                progressCard(title: "Overdue", value: "\(insights.totals.overdue)", tint: insights.totals.overdue > 0 ? .red : teal)
            }
            .padding(.vertical, 4)
            Text("Adherence \(insights.adherence.completionRateLabel) · On time \(insights.adherence.onTimeRateLabel)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(mid)
                .accessibilityIdentifier("activity-adherence-summary")
        }
    }

    @ViewBuilder
    private func progressByReceiverSection(_ insights: CircleCompletionInsights) -> some View {
        Section("By care receiver") {
            ForEach(insights.recipientBreakdown) { recipient in
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipient.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(dark)
                    HStack(spacing: 16) {
                        summaryPill(label: "Done", value: recipient.completed, tint: green)
                        summaryPill(label: "Active", value: recipient.active, tint: blue)
                        summaryPill(label: "Overdue", value: recipient.overdue, tint: recipient.overdue > 0 ? .red : teal)
                    }
                    Text("Adherence \(recipient.adherence.completionRateLabel)")
                        .font(.caption)
                        .foregroundStyle(mid)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func progressCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(mid)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func summaryPill(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(mid)
            Text("\(value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
    }

    private func load() async {
        if UITestScenario.current != nil {
            events = appState.uiTestEvents
            insights = isCaregiver ? appState.uiTestCompletionInsights : nil
            loading = false
            error = nil
            return
        }

        guard let circleId = appState.activeCircle?.id else {
            loading = false
            return
        }
        loading = true
        error = nil
        do {
            async let fetchedEvents = APIClient.shared.fetchEvents(circleId: circleId)
            async let fetchedInsights: CircleCompletionInsights? = isCaregiver
                ? APIClient.shared.fetchCompletionInsights(circleId: circleId)
                : nil
            events = try await fetchedEvents
            insights = try await fetchedInsights
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
