import SwiftUI

struct CircleHomeView: View {
    @EnvironmentObject private var appState: AppState

    @State private var tasks: [CareTask] = []
    @State private var loading = true
    @State private var error: String?
    @State private var deepLinkToTaskBoard = false
    @State private var isCompletingNextTask = false
    @State private var paywallRecipient: CareRecipient?

    private let teal = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let blue = Color(red: 0.13, green: 0.56, blue: 0.87)
    private let green = Color(red: 0.12, green: 0.68, blue: 0.49)
    private let dark = Color(red: 0.10, green: 0.16, blue: 0.24)
    private let mid = Color(red: 0.43, green: 0.50, blue: 0.60)
    private let bg = Color(red: 0.95, green: 0.96, blue: 0.99)
    private let rose = Color(red: 0.85, green: 0.30, blue: 0.50)

    private let twoColumns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var role: MemberRole { appState.userRole }
    private var isOrganizer: Bool { role == .admin }
    private var isCaregiver: Bool { role == .member }
    private var isReceiver: Bool { role == .recipient }

    private var activeCircle: CareCircle? { appState.activeCircle }
    private var activeRecipients: [CareRecipient] {
        guard let circle = activeCircle else { return [] }
        return CircleHomePolicy.activeRecipients(in: circle)
    }
    private var receiverSummaries: [ReceiverDashboardSummary] {
        guard let circle = activeCircle else { return [] }
        return CircleHomePolicy.receiverSummaries(in: circle, tasks: tasks)
    }
    private var nextReceiverTask: CareTask? {
        CircleHomePolicy.nextDueTask(in: tasks)
    }
    private var laterReceiverTasks: [CareTask] {
        CircleHomePolicy.remainingOpenTasks(after: nextReceiverTask?.id, in: tasks, limit: 3)
    }
    private var upgradeRecipient: CareRecipient? {
        ReceiverPremiumPolicy.defaultPaywallRecipient(in: activeCircle)
    }
    private var receiverProfile: CareRecipient? {
        guard isReceiver, let userId = appState.currentUser?.id else { return nil }
        return activeCircle?.orderedRecipients.first { $0.receiverUserId == userId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                if let circle = activeCircle {
                    if isReceiver {
                        receiverHome(circle: circle)
                    } else {
                        dashboardHome(circle: circle)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(activeCircle?.name ?? "Care Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { appState.clearActiveCircleSelection() } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("circle-directory-button")
                }
            }
            .navigationDestination(isPresented: $deepLinkToTaskBoard) {
                if isReceiver {
                    RecipientBoardView().environmentObject(appState)
                } else {
                    CirclesView().environmentObject(appState)
                }
            }
            .sheet(item: $paywallRecipient) { recipient in
                PaywallView(circleId: activeCircle?.id ?? "", recipient: recipient)
                    .environmentObject(appState)
            }
            .task {
                await loadTasks()
                syncPendingTaskNavigation()
            }
            .onChange(of: appState.pendingTaskId) { _ in
                syncPendingTaskNavigation()
            }
            .onChange(of: appState.activeCircle?.id) { _ in
                Task {
                    await loadTasks()
                    syncPendingTaskNavigation()
                }
            }
            .refreshable {
                if let id = appState.activeCircle?.id, UITestScenario.current == nil {
                    try? await appState.activateCircle(id: id)
                }
                await loadTasks()
            }
        }
        .careLoopBrandBanner()
    }

    private func dashboardHome(circle: CareCircle) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                heroCard(circle: circle)
                statsRow(circle: circle)
                receiverSection
                actionsSection(circle: circle)
                previewSection
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 32)
            }
            .padding(18)
        }
        .accessibilityIdentifier(isOrganizer ? "organizer-dashboard" : "caregiver-dashboard")
    }

    private func receiverHome(circle: CareCircle) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                receiverHero(circle: circle)

                if loading {
                    homeShell {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 30)
                    }
                } else if let task = nextReceiverTask {
                    nextTaskCard(task)
                    if !laterReceiverTasks.isEmpty {
                        receiverTimelineSection
                    }
                } else {
                    receiverEmptyState
                }

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 32)
            }
            .padding(18)
        }
        .accessibilityIdentifier("care-receiver-home")
    }

    private func heroCard(circle: CareCircle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [roleGradientStart, roleGradientEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: roleIcon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(circle.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(dark)
                    Text(isOrganizer ? "Care Circle dashboard" : "Your caregiver dashboard")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(mid)
                }
                Spacer()
            }

            Text(circle.recipientDisplaySummary.isEmpty ? "This care circle is ready for coordination." : circle.recipientDisplaySummary)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(dark)

            HStack(spacing: 8) {
                roleBadge
                if let receiverProfile {
                    premiumStatusIcon(for: receiverProfile, accessibilityIdentifier: "receiver-home-plan-badge")
                }
                labelChip(
                    "\(activeRecipients.count) \(activeRecipients.count == 1 ? "care receiver" : "care receivers")",
                    icon: "heart.fill",
                    tint: rose,
                    fill: rose.opacity(0.08)
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
    }

    private func receiverHero(circle: CareCircle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [rose, Color(red: 0.95, green: 0.55, blue: 0.30)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(circle.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(dark)
                    Text("Your care plan for right now")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(mid)
                }
            }

            roleBadge
            if let receiverProfile {
                premiumStatusIcon(for: receiverProfile, accessibilityIdentifier: "receiver-home-plan-badge")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
    }

    private func statsRow(circle: CareCircle) -> some View {
        LazyVGrid(columns: twoColumns, spacing: 14) {
            if isOrganizer {
                statCard("Due soon", value: "\(openTaskCount)", icon: "checklist", tint: blue)
                statCard("Overdue", value: "\(overdueCount)", icon: "exclamationmark.circle.fill", tint: .red)
                statCard("Completed", value: "\(completedTaskCount)", icon: "checkmark.circle.fill", tint: green)
                statCard("Receivers", value: "\(activeRecipients.count)", icon: "heart.fill", tint: rose)
            } else {
                statCard("Due today", value: "\(CircleHomePolicy.dueTodayCount(in: tasks))", icon: "sun.max.fill", tint: blue)
                statCard("Assigned to me", value: "\(myAssignedCount)", icon: "person.badge.clock.fill", tint: teal)
                statCard("Overdue", value: "\(overdueCount)", icon: "exclamationmark.circle.fill", tint: .red)
                statCard("My receivers", value: "\(activeRecipients.count)", icon: "heart.fill", tint: rose)
            }
        }
    }

    private func statCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(mid)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var receiverSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Care Receivers")

            if receiverSummaries.isEmpty {
                homeShell {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No active care receivers yet")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(dark)
                        Text("A care receiver needs to be active before daily coordination can begin.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(mid)
                    }
                    .padding(18)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(receiverSummaries) { summary in
                        receiverCard(summary)
                    }
                }
            }
        }
    }

    private func receiverCard(_ summary: ReceiverDashboardSummary) -> some View {
        NavigationLink {
            CirclesView().environmentObject(appState)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(rose.opacity(summary.overdueCount > 0 ? 0.18 : 0.10))
                        Image(systemName: "heart.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(summary.overdueCount > 0 ? .red : rose)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.recipient.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(dark)
                        if let relationship = summary.recipient.relationship, !relationship.isEmpty {
                            Text(relationship)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(mid)
                        }
                        Text(summary.recipient.isActiveForTasks ? (summary.nextTaskTitle ?? "No open tasks right now") : "Tasks unlock after activation")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(mid)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        premiumStatusIcon(for: summary.recipient, accessibilityIdentifier: "receiver-plan-badge-\(summary.recipient.id)")
                        receiverCountChip("\(summary.openCount) open", tint: blue)
                        if summary.overdueCount > 0 {
                            receiverCountChip("\(summary.overdueCount) overdue", tint: .red)
                        }
                    }
                }

                HStack(spacing: 10) {
                    receiverMetric(title: "Completed", value: "\(summary.completedCount)", tint: green)
                    receiverMetric(title: "Support team", value: "\(summary.supportingCaregiverCount)", tint: teal)
                    if let nextDueAt = summary.nextDueAt {
                        receiverMetric(title: "Next", value: dueLabel(for: nextDueAt), tint: blue)
                    }
                }
            }
            .padding(18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("receiver-summary-\(summary.recipient.id)")
    }

    private func premiumStatusIcon(for recipient: CareRecipient, accessibilityIdentifier: String) -> some View {
        Image(systemName: recipient.premiumStatusIconName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(recipient.hasPremium ? Color(red: 0.55, green: 0.22, blue: 0.97) : mid)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill((recipient.hasPremium ? Color(red: 0.55, green: 0.22, blue: 0.97) : mid).opacity(0.11))
            )
            .accessibilityLabel(recipient.premiumStatusAccessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func receiverCountChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private func receiverMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(mid)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionsSection(circle: CareCircle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Quick Actions")

            featuredActionLink(
                title: isOrganizer ? "Task Board" : "My Task Board",
                subtitle: isOrganizer ? "Add, assign, and track care work across the circle" : "Track the work you own and the care tasks you support",
                icon: "checklist.checked",
                badge: overdueCount > 0 ? "\(overdueCount) overdue" : nil,
                badgeColor: .red,
                accessibilityIdentifier: isOrganizer ? "quick-action-task-board" : "quick-action-my-task-board"
            ) {
                CirclesView().environmentObject(appState)
            }

            LazyVGrid(columns: twoColumns, spacing: 14) {
                if isOrganizer {
                    secondaryActionLink(title: "Care Receivers", icon: "heart.text.square.fill", tint: rose, subtitle: "Manage active receivers", accessibilityIdentifier: "quick-action-care-receivers") {
                        RecipientManagementView().environmentObject(appState)
                    }
                    secondaryActionLink(title: "People & Access", icon: "person.2.fill", tint: blue, subtitle: "Invite and scope support", accessibilityIdentifier: "quick-action-people-access") {
                        MemberListView().environmentObject(appState)
                    }
                    secondaryActionLink(title: "Activity", icon: "clock.fill", tint: teal, subtitle: "Review care timeline", accessibilityIdentifier: "quick-action-activity") {
                        ActivityFeedView().environmentObject(appState)
                    }
                    if let upgradeRecipient {
                        secondaryActionButton(
                            title: "Unlock Premium",
                            icon: "crown.fill",
                            tint: Color(red: 0.55, green: 0.22, blue: 0.97),
                            subtitle: "Upgrade \(upgradeRecipient.name)'s workflow",
                            accessibilityIdentifier: "quick-action-upgrade-premium"
                        ) {
                            paywallRecipient = upgradeRecipient
                        }
                    }
                    secondaryActionLink(title: "Insights", icon: "chart.bar.fill", tint: green, subtitle: "See completion patterns", accessibilityIdentifier: "quick-action-insights") {
                        AdminInsightsView().environmentObject(appState)
                    }
                    secondaryActionLink(title: "Settings", icon: "gearshape.fill", tint: mid, subtitle: "Circle preferences", accessibilityIdentifier: "quick-action-settings") {
                        SettingsView().environmentObject(appState)
                    }
                } else {
                    secondaryActionLink(title: "Care Circle", icon: "person.2.fill", tint: blue, subtitle: "See your support team", accessibilityIdentifier: "quick-action-care-circle") {
                        MemberListView().environmentObject(appState)
                    }
                    secondaryActionLink(title: "Receiver Progress", icon: "clock.fill", tint: teal, subtitle: "Counts and updates without private assignments", accessibilityIdentifier: "quick-action-activity") {
                        ActivityFeedView().environmentObject(appState)
                    }
                    secondaryActionLink(title: "Settings", icon: "gearshape.fill", tint: mid, subtitle: "Circle preferences", accessibilityIdentifier: "quick-action-settings") {
                        SettingsView().environmentObject(appState)
                    }
                    if let circle = appState.activeCircle {
                        ShareLink(
                            item: "Join \(circle.name) on CareLoop!\nCare Circle code: \(circle.id)",
                            subject: Text("Join my Care Circle")
                        ) {
                            secondaryCard(title: "Share", icon: "square.and.arrow.up", tint: blue, subtitle: "Invite by message or link")
                        }
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("Next Up")
                Spacer()
                Button { deepLinkToTaskBoard = true } label: {
                    Text("Open task board")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(blue)
                }
                .accessibilityIdentifier("open-task-board-button")
            }

            if loading {
                homeShell {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 18)
                }
            } else if previewTasks.isEmpty {
                homeShell {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No upcoming tasks")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(dark)
                        Text("Use the task board to add the next step for this care circle.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(mid)
                    }
                    .padding(18)
                }
            } else {
                homeShell {
                    VStack(spacing: 0) {
                        ForEach(Array(previewTasks.enumerated()), id: \.element.id) { index, task in
                            previewRow(task)
                            if index < previewTasks.count - 1 {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                }
            }
        }
    }

    private func nextTaskCard(_ task: CareTask) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                labelChip("Next due task", icon: "clock.fill", tint: rose, fill: rose.opacity(0.10))
                if task.isOverdue {
                    labelChip("Overdue", icon: "exclamationmark.triangle.fill", tint: .red, fill: Color.red.opacity(0.10))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(task.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                Text(task.notes?.isEmpty == false ? task.notes! : "Your care team scheduled this task for you.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                if let dueAt = task.dueAt {
                    Text(dueLabel(for: dueAt))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(task.isOverdue ? .red : rose)
                }
            }

            VStack(spacing: 10) {
                Button {
                    Task { await markReceiverTaskDone(task) }
                } label: {
                    HStack {
                        if isCompletingNextTask {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(task.canToggleCompletion ? "Mark Complete" : "Open My Tasks")
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(task.canToggleCompletion ? rose : blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(isCompletingNextTask)
                .accessibilityIdentifier("receiver-next-task-primary")

                Button {
                    deepLinkToTaskBoard = true
                } label: {
                    Text("View All My Tasks")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .accessibilityIdentifier("receiver-open-all-tasks")
            }
        }
        .padding(22)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var receiverTimelineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Later Today")

            homeShell {
                VStack(spacing: 0) {
                    ForEach(Array(laterReceiverTasks.enumerated()), id: \.element.id) { index, task in
                        previewRow(task)
                        if index < laterReceiverTasks.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
        }
    }

    private var receiverEmptyState: some View {
        homeShell {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nothing is due right now")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                Text("When your care team schedules the next task, it will appear here first.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                Button {
                    deepLinkToTaskBoard = true
                } label: {
                    Text("Open My Task List")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(blue)
                        .padding(.top, 6)
                }
            }
            .padding(22)
        }
    }

    private var previewTasks: [CareTask] {
        let openTasks = tasks.filter { $0.status != .done && $0.status != .skipped }
        if isCaregiver {
            let myId = appState.currentUser?.id ?? ""
            let assigned = openTasks.filter { $0.assigneeId == myId }
            return CircleHomePolicy.remainingOpenTasks(after: nil, in: assigned.isEmpty ? openTasks : assigned, limit: 3)
        }
        return CircleHomePolicy.remainingOpenTasks(after: nil, in: openTasks, limit: 3)
    }

    private func previewRow(_ task: CareTask) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(task.isOverdue ? Color.red.opacity(0.12) : roleGradientStart.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: task.isOverdue ? "exclamationmark" : previewRowIcon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(task.isOverdue ? .red : roleGradientStart)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let recipient = task.recipient?.name {
                        Text(recipient)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(mid)
                        Text("·").foregroundStyle(.quaternary)
                    }
                    if let dueAt = task.dueAt {
                        Text(dueLabel(for: dueAt))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(task.isOverdue ? .red : mid)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
    }

    private func featuredActionLink<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        badge: String?,
        badgeColor: Color,
        accessibilityIdentifier: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            featuredCard(title: title, subtitle: subtitle, icon: icon, badge: badge, badgeColor: badgeColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func featuredCard(title: String, subtitle: String, icon: String, badge: String?, badgeColor: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [roleGradientStart.opacity(0.18), roleGradientEnd.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(roleGradientStart)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(dark)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeColor.opacity(0.10), in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
    }

    private func secondaryActionLink<Destination: View>(
        title: String,
        icon: String,
        tint: Color,
        subtitle: String,
        accessibilityIdentifier: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            secondaryCard(title: title, icon: icon, tint: tint, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func secondaryActionButton(
        title: String,
        icon: String,
        tint: Color,
        subtitle: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            secondaryCard(title: title, icon: icon, tint: tint, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func secondaryCard(title: String, icon: String, tint: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.10))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)

            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(dark)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(mid)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func homeShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(dark)
    }

    private var roleIcon: String {
        switch role {
        case .admin: return "star.fill"
        case .member: return "hands.and.sparkles.fill"
        case .recipient: return "heart.fill"
        }
    }

    private var roleGradientStart: Color {
        switch role {
        case .admin: return blue
        case .member: return teal
        case .recipient: return rose
        }
    }

    private var roleGradientEnd: Color {
        switch role {
        case .admin: return Color(red: 0.08, green: 0.40, blue: 0.75)
        case .member: return blue
        case .recipient: return Color(red: 0.95, green: 0.55, blue: 0.30)
        }
    }

    private var roleBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: roleIcon)
                .font(.system(size: 10, weight: .bold))
            Text(role.displayLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(roleGradientStart)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(roleGradientStart.opacity(0.10), in: Capsule())
    }

    private func labelChip(_ title: String, icon: String, tint: Color, fill: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(fill, in: Capsule())
    }

    private var previewRowIcon: String {
        isCaregiver ? "person.badge.clock.fill" : "checklist"
    }

    private var openTaskCount: Int {
        tasks.filter { $0.status != .done && $0.status != .skipped && !$0.isOverdue }.count
    }

    private var overdueCount: Int {
        tasks.filter(\.isOverdue).count
    }

    private var completedTaskCount: Int {
        tasks.filter { $0.status == .done || $0.status == .skipped }.count
    }

    private var myAssignedCount: Int {
        let myId = appState.currentUser?.id ?? ""
        return tasks.filter { $0.assigneeId == myId && $0.status != .done && $0.status != .skipped }.count
    }

    private func dueLabel(for date: Date) -> String {
        if date < Date() { return "Overdue" }
        if Calendar.current.isDateInToday(date) {
            return "Today · \(date.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func markReceiverTaskDone(_ task: CareTask) async {
        guard task.canToggleCompletion else {
            deepLinkToTaskBoard = true
            return
        }
        guard let circleId = appState.activeCircle?.id else { return }

        isCompletingNextTask = true
        defer { isCompletingNextTask = false }

        do {
            let updatedTask: CareTask
            if UITestScenario.current != nil {
                updatedTask = task.withUpdatedStatus(.done, completedAt: Date(), completedBy: appState.currentUser)
            } else {
                updatedTask = try await APIClient.shared.updateTaskStatus(circleId: circleId, taskId: task.id, status: .done)
            }
            applyTaskUpdate(updatedTask)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applyTaskUpdate(_ updatedTask: CareTask) {
        tasks = tasks.map { existing in
            existing.id == updatedTask.id ? updatedTask : existing
        }

        if var circle = appState.activeCircle {
            circle.tasks = tasks
            appState.attachCircle(circle)
        }
    }

    private func loadTasks() async {
        if let seededTasks = appState.activeCircle?.tasks, UITestScenario.current != nil {
            tasks = seededTasks
            loading = false
            error = nil
            return
        }

        guard let circleId = appState.activeCircle?.id else {
            tasks = []
            loading = false
            return
        }

        loading = true
        error = nil
        do {
            tasks = try await APIClient.shared.fetchTasks(circleId: circleId)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func syncPendingTaskNavigation() {
        guard appState.pendingTaskId != nil,
              appState.pendingTaskCircleId == nil || appState.pendingTaskCircleId == appState.activeCircle?.id,
              !deepLinkToTaskBoard
        else { return }
        deepLinkToTaskBoard = true
    }
}
