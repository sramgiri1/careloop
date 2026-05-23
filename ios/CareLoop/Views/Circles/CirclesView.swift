import SwiftUI

struct CirclesView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("askedForPush") private var askedForPush = false

    @State private var tasks:              [CareTask] = []
    @State private var loading             = true
    @State private var error:              String?
    @State private var showNewTask         = false
    @State private var showMembers         = false
    @State private var showSettings        = false
    @State private var showPermissionSheet = false
    @State private var selectedTask:       CareTask?
    @State private var highlightedTaskId:  String?
    @State private var selectedRecipient   = "all"

    // MARK: – Design tokens
    private let teal  = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let blue  = Color(red: 0.13, green: 0.56, blue: 0.87)
    private let dark  = Color(red: 0.10, green: 0.16, blue: 0.24)
    private let bg    = Color(red: 0.95, green: 0.96, blue: 0.99)
    private let green = Color(red: 0.12, green: 0.68, blue: 0.49)

    var body: some View {
        if appState.userRole == .recipient {
            RecipientBoardView()
                .environmentObject(appState)
                .careLoopBrandBanner()
        } else {
            mainBoard
        }
    }

    // MARK: – Main board (admin + member)

    private var mainBoard: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    boardScrollView
                }
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle(appState.activeCircle?.name ?? "Care Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { boardToolbar }
            .navigationDestination(isPresented: Binding(
                get: { selectedTask != nil },
                set: { if !$0 { selectedTask = nil } }
            )) {
                if let task = selectedTask {
                    TaskDetailView(
                        task:     task,
                        onUpdate: { updateInList($0) },
                        onDelete: { removeFromList(task) }
                    )
                    .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showNewTask, onDismiss: { Task { await loadTasks() } }) {
                if let circle = appState.activeCircle, let user = appState.currentUser {
                    NewTaskView(
                        circleId:   circle.id,
                        creatorId:  user.id,
                        members:    circle.members ?? [],
                        recipients: circle.recipients ?? [],
                        isAdmin:    appState.userRole == .admin,
                        onCreated:  { created in
                            tasks.insert(created, at: 0)
                            if created.dueAt != nil && !askedForPush && UITestScenario.current == nil {
                                showPermissionSheet = true
                            }
                        }
                    )
                    .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showMembers) {
                MemberListView().environmentObject(appState)
            }
            .sheet(isPresented: $showSettings) {
                if let circle = appState.activeCircle {
                    CircleSettingsView(circle: circle).environmentObject(appState)
                }
            }
            .sheet(isPresented: $showPermissionSheet) {
                NotificationPermissionView { _ in askedForPush = true }
            }
        }
        .careLoopBrandBanner()
        .task { await loadTasks() }
        .onAppear {
            if appState.shouldPromptNewTask {
                showNewTask = true
                appState.consumeNewTaskPrompt()
            }
        }
        .onChange(of: appState.shouldPromptNewTask) { shouldPrompt in
            if shouldPrompt { showNewTask = true; appState.consumeNewTaskPrompt() }
        }
        .onChange(of: appState.pendingTaskId) { _ in syncDeepLink() }
        .onChange(of: tasks) { _ in syncDeepLink() }
        .onChange(of: appState.activeCircle?.id) { _ in
            selectedRecipient = "all"
            Task { await loadTasks() }
        }
    }

    // MARK: – Toolbar

    @ToolbarContentBuilder
    private var boardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 16) {
                Button { showMembers = true } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityIdentifier("task-board-people-access-button")
                if appState.userRole == .admin {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("task-board-settings-button")
                }
                Button { appState.clearActiveCircleSelection() } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .accessibilityIdentifier("task-board-back-to-dashboard-button")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showNewTask = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityIdentifier("add-task-button")
        }
    }

    // MARK: – Board scroll view

    private var boardScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    circleHeaderCard
                        .padding(.horizontal, 16)

                    if multipleRecipients {
                        recipientFilterRow
                            .padding(.horizontal, 16)
                    }

                    if let err = error {
                        Text(err)
                            .font(.footnote).foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }

                    boardSection("Overdue",  tasks: overdueSection,  color: .red)
                    boardSection("Today",    tasks: todaySection,     color: teal)
                    boardSection("Upcoming", tasks: upcomingSection,  color: blue)
                    boardSection("Anytime",  tasks: noDateSection,    color: Color(red: 0.43, green: 0.50, blue: 0.60))
                    boardSection("Completed", tasks: completedSection, color: green)

                    if allEmpty {
                        emptyStateView
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .accessibilityIdentifier("task-board-screen")
            .refreshable { await loadTasks() }
            .onChange(of: highlightedTaskId) { id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    highlightedTaskId = nil
                }
            }
        }
    }

    // MARK: – Circle header card

    private var circleHeaderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [teal, blue],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image("CareLoopIcon")
                    .resizable().scaledToFit().padding(10)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(appState.activeCircle?.name ?? "Care Circle")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                if let subtitle = circleSubtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            let role = appState.userRole
            Text(role.displayLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(role == .admin ? blue : Color(red: 0.23, green: 0.33, blue: 0.44))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    Capsule().fill(role == .admin
                        ? Color(red: 0.88, green: 0.95, blue: 1.0)
                        : Color(red: 0.93, green: 0.95, blue: 0.98))
                )
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var circleSubtitle: String? {
        guard let circle = appState.activeCircle else { return nil }
        let names = circle.recipientNames
        switch names.count {
        case 0: return nil
        case 1: return "Caring for \(names[0])"
        case 2: return "Caring for \(names[0]) and \(names[1])"
        default: return "Caring for \(names[0]) + \(names.count - 1) more"
        }
    }

    // MARK: – Recipient filter row

    private var multipleRecipients: Bool {
        (appState.activeCircle?.recipients ?? []).count > 1
    }

    private var recipientFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(id: "all", label: "All")
                ForEach(appState.activeCircle?.recipients ?? []) { r in
                    filterChip(id: r.id, label: r.name)
                }
            }
        }
    }

    private func filterChip(id: String, label: String) -> some View {
        let active = selectedRecipient == id
        return Button { selectedRecipient = id } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(active ? .white : Color(red: 0.23, green: 0.33, blue: 0.44))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    Group {
                        if active {
                            LinearGradient(colors: [teal, blue], startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.white
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(red: 0.84, green: 0.89, blue: 0.95), lineWidth: active ? 0 : 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: – Board sections

    @ViewBuilder
    private func boardSection(_ title: String, tasks: [CareTask], color: Color) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title, count: tasks.count, color: color)
                    .padding(.horizontal, 16)
                ForEach(tasks) { task in
                    taskCard(task)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .tracking(0.7)
            Text("· \(count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color.opacity(0.65))
            Spacer()
        }
    }

    // MARK: – Task card

    private func taskCard(_ task: CareTask) -> some View {
        Button { selectedTask = task } label: {
            TaskRowView(task: task, onToggle: { Task { await toggle(task) } })
        }
        .buttonStyle(.plain)
        .id(task.id)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.85, green: 0.30, blue: 0.50), lineWidth: 2)
                .opacity(highlightedTaskId == task.id ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: highlightedTaskId)
        )
        .contextMenu { contextMenuItems(for: task) }
        .accessibilityIdentifier("task-card-\(task.id)")
        .accessibilityValue(task.status.label)
    }

    @ViewBuilder
    private func contextMenuItems(for task: CareTask) -> some View {
        Button { selectedTask = task } label: {
            Label(canEdit(task) ? "Edit task" : "View task",
                  systemImage: canEdit(task) ? "pencil" : "eye")
        }

        if canSkip(task) {
            Button { Task { await setStatus(task, .skipped) } } label: {
                Label("Skip task", systemImage: "forward.fill")
            }
        }

        if task.status == .done || task.status == .skipped {
            Button { Task { await setStatus(task, .pending) } } label: {
                Label("Mark as pending", systemImage: "arrow.uturn.backward")
            }
        }

        if canAssign(task) && task.assigneeId != nil {
            Button { selectedTask = task } label: {
                Label("Reassign", systemImage: "person.2.badge.gearshape")
            }
        }

        if canDelete(task) {
            Divider()
            Button(role: .destructive) { Task { await deleteTask(task) } } label: {
                Label("Delete task", systemImage: "trash")
            }
        }
    }

    // MARK: – Empty state

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.trianglebadge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(teal.opacity(0.5))
            Text("No tasks yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(dark)
            Text("Tap + to add the first task for this care circle.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: – Task data sections

    private var filteredTasks: [CareTask] {
        guard selectedRecipient != "all" else { return tasks }
        return tasks.filter { $0.recipientId == selectedRecipient }
    }

    private var activeTasks: [CareTask] {
        filteredTasks.filter { $0.status != .done && $0.status != .skipped }
    }

    private var overdueSection: [CareTask] {
        activeTasks
            .filter { $0.isOverdue }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var todaySection: [CareTask] {
        activeTasks
            .filter { task in
                guard let d = task.dueAt else { return false }
                return Calendar.current.isDateInToday(d) && !task.isOverdue
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var upcomingSection: [CareTask] {
        activeTasks
            .filter { task in
                guard let d = task.dueAt else { return false }
                return d > Date() && !Calendar.current.isDateInToday(d)
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var noDateSection: [CareTask] {
        activeTasks
            .filter { $0.dueAt == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var completedSection: [CareTask] {
        filteredTasks
            .filter { $0.status == .done || $0.status == .skipped }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var allEmpty: Bool {
        overdueSection.isEmpty && todaySection.isEmpty &&
        upcomingSection.isEmpty && noDateSection.isEmpty && completedSection.isEmpty
    }

    // MARK: – Role-based permissions

    private var userId:  String { appState.currentUser?.id ?? "" }
    private var isAdmin: Bool   { appState.userRole == .admin }

    private func canEdit(_ task: CareTask) -> Bool {
        detailPresentation(for: task).permissions.canEdit
    }

    private func canSkip(_ task: CareTask) -> Bool {
        detailPresentation(for: task).permissions.canSkip
    }

    private func canAssign(_ task: CareTask) -> Bool {
        detailPresentation(for: task).permissions.canAssign
    }

    private func canDelete(_ task: CareTask) -> Bool {
        detailPresentation(for: task).permissions.canDelete
    }

    private func detailPresentation(for task: CareTask) -> TaskDetailPresentation {
        TaskWorkflowPolicy.detailPresentation(
            for: task,
            currentUserId: userId,
            role: appState.userRole,
            selectedRecipient: taskRecipient(for: task)
        )
    }

    private func taskRecipient(for task: CareTask) -> CareRecipient? {
        if let recipient = task.recipient { return recipient }
        return appState.activeCircle?.recipients?.first(where: { $0.id == task.recipientId })
    }

    // MARK: – Data operations

    private func loadTasks() async {
        if let seededTasks = appState.activeCircle?.tasks, UITestScenario.current != nil {
            tasks = seededTasks
            loading = false
            error = nil
            return
        }
        guard let circleId = appState.activeCircle?.id else {
            tasks = []; loading = false; return
        }
        loading = true; error = nil
        do { tasks = try await APIClient.shared.fetchTasks(circleId: circleId) }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func toggle(_ task: CareTask) async {
        guard let circleId = appState.activeCircle?.id else { return }
        guard task.canToggleCompletion else { return }
        let next: TaskStatus = task.status == .done ? .pending : .done
        if UITestScenario.current != nil {
            applyUITestTaskStatus(task, next)
            return
        }
        if let updated = try? await APIClient.shared.updateTaskStatus(
            circleId: circleId, taskId: task.id, status: next
        ) { updateInList(updated) }
    }

    private func setStatus(_ task: CareTask, _ status: TaskStatus) async {
        guard let circleId = appState.activeCircle?.id else { return }
        if let updated = try? await APIClient.shared.updateTaskStatus(
            circleId: circleId, taskId: task.id, status: status
        ) { updateInList(updated) }
    }

    private func deleteTask(_ task: CareTask) async {
        guard let circleId = appState.activeCircle?.id else { return }
        try? await APIClient.shared.deleteTask(circleId: circleId, taskId: task.id)
        removeFromList(task)
    }

    private func updateInList(_ task: CareTask) {
        tasks = tasks.map { $0.id == task.id ? task : $0 }
    }

    private func applyUITestTaskStatus(_ task: CareTask, _ status: TaskStatus) {
        let updated = task.withUpdatedStatus(
            status,
            completedAt: status == .done ? Date() : nil,
            completedBy: status == .done ? appState.currentUser : nil
        )
        tasks = tasks.map { $0.id == task.id ? updated : $0 }

        if status == .done, let nextOccurrence = makeNextUITestOccurrence(after: updated) {
            tasks.insert(nextOccurrence, at: 0)
        }

        if var circle = appState.activeCircle {
            circle.tasks = tasks
            appState.activeCircle = circle
        }
    }

    private func makeNextUITestOccurrence(after task: CareTask) -> CareTask? {
        guard let recurrence = task.recurrence,
              let dueAt = task.dueAt,
              let nextDueAt = nextDueDate(after: dueAt, recurrence: recurrence)
        else { return nil }

        return CareTask(
            id: "ui-task-\(UUID().uuidString)",
            title: task.title,
            notes: task.notes,
            dueAt: nextDueAt,
            status: .pending,
            priority: task.priority,
            recurrenceFrequency: task.recurrenceFrequency,
            recurrenceInterval: task.recurrenceInterval,
            recurrenceWeekdays: task.recurrenceWeekdays,
            recurrenceEndsAt: task.recurrenceEndsAt,
            seriesId: task.seriesId ?? "ui-series-\(UUID().uuidString)",
            completedAt: nil,
            archivedAt: nil,
            circleId: task.circleId,
            recipientId: task.recipientId,
            recipient: task.recipient,
            creatorId: task.creatorId,
            assigneeId: task.assigneeId,
            assignee: task.assignee,
            capabilities: task.capabilities
        )
    }

    private func nextDueDate(after date: Date, recurrence: TaskRecurrence) -> Date? {
        let calendar = Calendar.current
        let interval = max(1, recurrence.interval ?? 1)
        switch recurrence.frequency {
        case .daily, .custom:
            return calendar.date(byAdding: .day, value: interval, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: interval, to: date)
        case .none:
            return nil
        }
    }

    private func removeFromList(_ task: CareTask) {
        tasks.removeAll { $0.id == task.id }
    }

    private func syncDeepLink() {
        guard let id = appState.pendingTaskId,
              appState.pendingTaskCircleId == nil || appState.pendingTaskCircleId == appState.activeCircle?.id,
              let task = tasks.first(where: { $0.id == id }) else { return }
        if multipleRecipients, let recipientId = task.recipientId {
            selectedRecipient = recipientId
        }
        highlightedTaskId = task.id
        appState.consumePendingTask()
    }
}
