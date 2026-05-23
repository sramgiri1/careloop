import SwiftUI
import Charts

struct AdminInsightsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedPeriod = 7
    @State private var selectedRecipientId = "all"
    @State private var insights: CircleCompletionInsights?
    @State private var loading = true
    @State private var error: String?
    @State private var paywallRecipient: CareRecipient?

    private let periodOptions = [7, 14, 30]

    private var canUpgrade: Bool { appState.userRole == .admin }
    private var canLoadAllInsights: Bool {
        ReceiverPremiumPolicy.allVisibleRecipientsSupportInsights(in: appState.activeCircle)
    }
    private var selectedRecipient: CareRecipient? {
        recipientOptions.first(where: { $0.id == selectedRecipientId })
    }
    private var lockedInsightRecipients: [CareRecipient] {
        recipientOptions.filter { !ReceiverPremiumPolicy.supportsInsights(for: $0) }
    }
    private var premiumInsightRecipients: [CareRecipient] {
        recipientOptions.filter { ReceiverPremiumPolicy.supportsInsights(for: $0) }
    }

    var body: some View {
        List {
            if let circle = appState.activeCircle {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(circle.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(circle.recipientDisplaySummary.isEmpty
                             ? "Task completion overview for this circle."
                             : "Completion insight for \(circle.recipientDisplaySummary)'s care group.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Window") {
                Picker("Window", selection: $selectedPeriod) {
                    ForEach(periodOptions, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)
            }

            if recipientOptions.count > 1 {
                Section("Recipient") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            recipientChip(id: "all", title: "All recipients", locked: !canLoadAllInsights)
                            ForEach(recipientOptions) { recipient in
                                recipientChip(
                                    id: recipient.id,
                                    title: recipient.name,
                                    locked: !ReceiverPremiumPolicy.supportsInsights(for: recipient)
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            if loading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if shouldShowPremiumLock {
                Section("Insights Locked") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(lockTitle)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text(lockDetail)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        insightUpgradeValuePreview()
                            .accessibilityIdentifier("insights-upgrade-value-preview")
                        if selectedRecipientId == "all", let firstPremium = premiumInsightRecipients.first {
                            Button {
                                selectedRecipientId = firstPremium.id
                            } label: {
                                Label("View reports for \(firstPremium.name)", systemImage: "chart.bar.fill")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("insights-view-premium-recipient-button")
                        }
                        if canUpgrade {
                            if let lockedRecipient {
                                upgradeButton(for: lockedRecipient)
                                    .accessibilityIdentifier("insights-upgrade-button")
                            } else if selectedRecipientId == "all" {
                                ForEach(lockedInsightRecipients) { recipient in
                                    upgradeButton(for: recipient)
                                        .accessibilityIdentifier("insights-upgrade-button-\(recipient.id)")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            } else if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            } else if let insights {
                Section("Overview") {
                    insightCard(title: "Completed", value: "\(insights.totals.completed)", tint: Color(red: 0.12, green: 0.68, blue: 0.49))
                    insightCard(title: "Active", value: "\(insights.totals.active)", tint: Color(red: 0.13, green: 0.56, blue: 0.87))
                    insightCard(title: "Overdue", value: "\(insights.totals.overdue)", tint: insights.totals.overdue > 0 ? .red : .secondary)
                }

                Section("Adherence") {
                    adherenceSummary(insights.adherence)
                        .accessibilityIdentifier("insights-adherence-summary")
                }

                Section("Missed trend") {
                    missedTrend(insights.taskTrendByDay)
                        .accessibilityIdentifier("insights-missed-trend")
                }

                Section("Completed by day") {
                    Chart(insights.completedByDay) { day in
                        BarMark(
                            x: .value("Day", day.shortLabel),
                            y: .value("Completed", day.count)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(6)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 220)

                    if insights.completedByDay.allSatisfy({ $0.count == 0 }) {
                        Text("No completed tasks in this window yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Top caregivers") {
                    if insights.topCaregivers.isEmpty {
                        Text("No completions recorded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(insights.topCaregivers) { caregiver in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(caregiver.name)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Text(caregiver.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(caregiver.completedCount)")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.13, green: 0.56, blue: 0.87))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !insights.caregiverLoad.isEmpty {
                    Section("Caregiver load") {
                        ForEach(insights.caregiverLoad) { caregiver in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(caregiver.name)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                        Text(caregiver.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(caregiver.loadSummaryLabel)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(caregiver.overdueAssignedCount > 0 ? .red : Color(red: 0.13, green: 0.56, blue: 0.87))
                                }
                                HStack {
                                    insightMini(label: "Done", value: caregiver.completedCount, tint: Color(red: 0.12, green: 0.68, blue: 0.49))
                                    insightMini(label: "Active", value: caregiver.activeAssignedCount, tint: Color(red: 0.13, green: 0.56, blue: 0.87))
                                    insightMini(label: "Total", value: caregiver.totalAssignedCount, tint: .secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if insights.escalationSummary.totalEscalated > 0 {
                    Section("Escalation response") {
                        escalationSummary(insights.escalationSummary)
                            .accessibilityIdentifier("insights-escalation-summary")
                    }
                }

                if !insights.recipientBreakdown.isEmpty {
                    Section("By recipient") {
                        ForEach(insights.recipientBreakdown) { recipient in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(recipient.name)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                HStack {
                                    insightMini(label: "Done", value: recipient.completed, tint: Color(red: 0.12, green: 0.68, blue: 0.49))
                                    insightMini(label: "Active", value: recipient.active, tint: Color(red: 0.13, green: 0.56, blue: 0.87))
                                    insightMini(label: "Overdue", value: recipient.overdue, tint: recipient.overdue > 0 ? .red : .secondary)
                                }
                                adherenceInline(recipient.adherence)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Completion Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            alignSelectionToPremiumScope()
            await loadInsights()
        }
        .onChange(of: selectedPeriod) { _ in
            Task { await loadInsights() }
        }
        .onChange(of: selectedRecipientId) { _ in
            Task { await loadInsights() }
        }
        .sheet(item: $paywallRecipient) { recipient in
            PaywallView(circleId: appState.activeCircle?.id ?? "", recipient: recipient)
                .environmentObject(appState)
        }
        .careLoopBrandBanner()
    }

    private var recipientOptions: [CareRecipient] {
        appState.activeCircle?.recipients ?? []
    }

    private var lockedRecipient: CareRecipient? {
        guard selectedRecipientId != "all" else { return nil }
        return selectedRecipient
    }

    private var shouldShowPremiumLock: Bool {
        if selectedRecipientId == "all" {
            return !canLoadAllInsights
        }
        return !ReceiverPremiumPolicy.supportsInsights(for: selectedRecipient)
    }

    private var lockTitle: String {
        if let lockedRecipient {
            return "Premium is required for \(lockedRecipient.name)"
        }
        return "Upgrade locked care receivers"
    }

    private var lockDetail: String {
        if let lockedRecipient {
            return lockedRecipient.premiumStatusDetail
        }
        if lockedInsightRecipients.isEmpty {
            return "Completion insights stay inside premium care receiver scopes. Select a premium receiver to continue."
        }
        return "All-recipient insights require every visible care receiver to have Premium. Upgrade locked receivers, or view one premium receiver now."
    }

    @ViewBuilder
    private func insightCard(title: String, value: String, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func insightMini(label: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func adherenceSummary(_ adherence: AdherenceInsightSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                adherenceMetric(title: "Completed", value: adherence.completionRateLabel, tint: Color(red: 0.12, green: 0.68, blue: 0.49))
                adherenceMetric(title: "On time", value: adherence.onTimeRateLabel, tint: Color(red: 0.13, green: 0.56, blue: 0.87))
            }
            Text(adherence.summaryLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                adherencePill(label: "Due", value: adherence.scheduled, tint: .secondary)
                adherencePill(label: "Late", value: adherence.late, tint: adherence.late > 0 ? .orange : .secondary)
                adherencePill(label: "Missed", value: adherence.missed, tint: adherence.missed > 0 ? .red : .secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func adherenceInline(_ adherence: AdherenceInsightSummary) -> some View {
        Text("Adherence \(adherence.completionRateLabel) · On time \(adherence.onTimeRateLabel)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("recipient-adherence-\(adherence.scheduled)-due")
    }

    @ViewBuilder
    private func adherenceMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func adherencePill(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text("\(value)")
                .fontWeight(.bold)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule(style: .continuous))
    }

    @ViewBuilder
    private func missedTrend(_ days: [TaskTrendDay]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.shortLabel),
                    y: .value("Due", day.due)
                )
                .foregroundStyle(Color(red: 0.78, green: 0.84, blue: 0.90))
                BarMark(
                    x: .value("Day", day.shortLabel),
                    y: .value("Missed", day.missed)
                )
                .foregroundStyle(day.needsAttention ? .red : Color(red: 0.12, green: 0.68, blue: 0.49))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)

            Text(trendSummary(days))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func trendSummary(_ days: [TaskTrendDay]) -> String {
        let missed = days.reduce(0) { $0 + $1.missed }
        let due = days.reduce(0) { $0 + $1.due }
        if due == 0 {
            return "No due tasks in this window yet."
        }
        if missed == 0 {
            return "No missed tasks in this window."
        }
        return "\(missed) of \(due) due tasks were missed in this window."
    }

    @ViewBuilder
    private func insightUpgradeValuePreview() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Premium reports unlock")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            premiumValueRow("Adherence rates by care receiver")
            premiumValueRow("Missed-task trends and escalation response timing")
            premiumValueRow("Caregiver load balance without exposing private notes")
        }
        .padding(12)
        .background(Color(red: 0.96, green: 0.92, blue: 1.0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func premiumValueRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.seal.fill")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.32, green: 0.18, blue: 0.62))
    }

    @ViewBuilder
    private func upgradeButton(for recipient: CareRecipient) -> some View {
        Button {
            paywallRecipient = recipient
        } label: {
            Label("Unlock Premium for \(recipient.name)", systemImage: "crown.fill")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.55, green: 0.22, blue: 0.97))
    }

    @ViewBuilder
    private func escalationSummary(_ summary: EscalationInsightSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                escalationMetric(title: "Escalated", value: summary.totalLabel, tint: .red)
                escalationMetric(title: "Response", value: summary.averageResponseLabel, tint: Color(red: 0.13, green: 0.56, blue: 0.87))
            }

            ForEach(summary.recent.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.taskTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text([item.recipientName, item.responseLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func escalationMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func recipientChip(id: String, title: String, locked: Bool) -> some View {
        let isSelected = selectedRecipientId == id
        Button {
            selectedRecipientId = id
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                }
            }
                .foregroundStyle(isSelected ? .white : Color(red: 0.23, green: 0.33, blue: 0.44))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                            ? LinearGradient(
                                colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [Color.white],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(red: 0.84, green: 0.89, blue: 0.94), lineWidth: isSelected ? 0 : 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func loadInsights() async {
        guard let circleId = appState.activeCircle?.id else {
            loading = false
            insights = nil
            return
        }

        guard !shouldShowPremiumLock else {
            loading = false
            insights = nil
            error = nil
            return
        }

        loading = true
        error = nil
        do {
            if UITestScenario.current != nil, let seededInsights = appState.uiTestCompletionInsights {
                insights = seededInsights
            } else {
                insights = try await APIClient.shared.fetchCompletionInsights(
                    circleId: circleId,
                    days: selectedPeriod,
                    recipientId: selectedRecipientId == "all" ? nil : selectedRecipientId
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func alignSelectionToPremiumScope() {
        if selectedRecipientId == "all", !canLoadAllInsights, let firstPremium = recipientOptions.first(where: \.premium.capabilities.canUseInsights) {
            selectedRecipientId = firstPremium.id
        }
    }
}
