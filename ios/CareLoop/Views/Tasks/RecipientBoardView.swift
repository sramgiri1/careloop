import SwiftUI

// Care board for users with the RECIPIENT role.
// Shows all circle tasks plus personal reminders. Recipients can mark their own assigned tasks done.
struct RecipientBoardView: View {
    @EnvironmentObject private var appState: AppState

    @State private var tasks:           [CareTask] = []
    @State private var loading          = true
    @State private var error:           String?
    @State private var highlightedTaskId: String?

    // MARK: – Design tokens
    private let teal  = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let blue  = Color(red: 0.13, green: 0.56, blue: 0.87)
    private let dark  = Color(red: 0.10, green: 0.16, blue: 0.24)
    private let mid   = Color(red: 0.43, green: 0.50, blue: 0.60)
    private let green = Color(red: 0.12, green: 0.68, blue: 0.49)
    private let bg    = Color(red: 0.95, green: 0.96, blue: 0.99)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 20) {
                        greetingHero
                            .padding(.horizontal, 16)

                        if let err = error {
                            Text(err)
                                .font(.footnote).foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        }

                        careSection("Today",      tasks: todayTasks,    icon: "sun.max.fill",    color: teal)
                        careSection("Coming up",  tasks: upcomingTasks, icon: "calendar",        color: blue)
                        careSection("Anytime",    tasks: anyTimeTasks,  icon: "infinity",        color: mid)
                        careSection("Done",       tasks: doneTasks,     icon: "checkmark.circle", color: green)

                        caregiverSection
                            .padding(.horizontal, 16)

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
            .background(bg.ignoresSafeArea())
            .accessibilityIdentifier("recipient-task-board-screen")
            .navigationTitle(appState.activeCircle?.name ?? "My Care")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { appState.clearActiveCircleSelection() } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            }
            .refreshable { await load() }
            .onChange(of: highlightedTaskId) { id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    highlightedTaskId = nil
                }
            }
        }
        } // ScrollViewReader
        .task { await load() }
        .onChange(of: appState.activeCircle?.id) { _ in Task { await load() } }
        .onChange(of: appState.pendingTaskId) { id in
            guard let id, highlightedTaskId == nil,
                  appState.pendingTaskCircleId == nil || appState.pendingTaskCircleId == appState.activeCircle?.id,
                  tasks.contains(where: { $0.id == id }) else { return }
            highlightedTaskId = id
            appState.consumePendingTask()
        }
        .onChange(of: tasks) { _ in
            guard let id = appState.pendingTaskId, highlightedTaskId == nil,
                  appState.pendingTaskCircleId == nil || appState.pendingTaskCircleId == appState.activeCircle?.id,
                  tasks.contains(where: { $0.id == id }) else { return }
            highlightedTaskId = id
            appState.consumePendingTask()
        }
    }

    // MARK: – Greeting hero

    private var greetingHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(timeGreeting), \(firstName)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(dark)

            Text(heroSubtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(mid)

            HStack(spacing: 10) {
                statPill("\(todayTasks.count) today", color: teal)
                statPill("\(caregivers.count) caregivers", color: blue)
                if !overdueCount.isEmpty {
                    statPill(overdueCount, color: .red)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var timeGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var firstName: String {
        appState.currentUser?.name.split(separator: " ").first.map(String.init)
            ?? appState.currentUser?.name
            ?? "there"
    }

    private var heroSubtitle: String {
        guard let circle = appState.activeCircle else { return "Your care is being taken care of." }
        let count = (circle.members ?? []).count
        return count <= 1
            ? "Your care team is looking out for you."
            : "You have \(count) people looking out for you."
    }

    private var overdueCount: String {
        let n = tasks.filter { $0.isOverdue }.count
        return n > 0 ? "\(n) overdue" : ""
    }

    private func statPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
    }

    // MARK: – Care section

    @ViewBuilder
    private func careSection(_ title: String, tasks: [CareTask], icon: String, color: Color) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.7)
                    Text("· \(tasks.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(color.opacity(0.65))
                    Spacer()
                }
                .foregroundStyle(color)
                .padding(.horizontal, 16)

                ForEach(tasks) { task in
                    recipientTaskRow(task)
                        .padding(.horizontal, 16)
                        .id(task.id)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(red: 0.85, green: 0.30, blue: 0.50), lineWidth: 2)
                                .opacity(highlightedTaskId == task.id ? 1 : 0)
                                .animation(.easeOut(duration: 0.3), value: highlightedTaskId)
                        )
                }
            }
        }
    }

    // MARK: – Recipient task row

    private func recipientTaskRow(_ task: CareTask) -> some View {
        let isMyTask = task.assigneeId == appState.currentUser?.id
        let canMarkDone = (task.capabilities?.canMarkDone ?? isMyTask)
            && task.status != .done
            && task.status != .skipped

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: taskStatusIcon(task))
                    .font(.system(size: 22))
                    .foregroundStyle(taskStatusColor(task))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(task.status == .done ? mid : dark)
                        .strikethrough(task.status == .done, color: mid)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if task.status == .done, let doer = task.completedBy?.name {
                            let first = doer.split(separator: " ").first.map(String.init) ?? doer
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                Text("Done by \(first)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(green)
                        } else if isMyTask {
                            HStack(spacing: 4) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 11))
                                Text("Your reminder")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.50))
                        } else if let assignee = task.assignee?.name {
                            let first = assignee.split(separator: " ").first.map(String.init) ?? assignee
                            caregiverLabel(first)
                        } else {
                            caregiverLabel("Unassigned")
                        }
                        if task.status != .done, let due = task.dueAt {
                            Text("·").foregroundStyle(.quaternary)
                            Text(recipientDueLabel(due))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(task.isOverdue ? .red : mid)
                        }
                    }
                }

                Spacer()

                if task.recurrence != nil {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(mid.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, canMarkDone ? 10 : 13)

            if canMarkDone {
                Button {
                    Task { await markDone(task) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("I've done this")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.50))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color(red: 0.85, green: 0.30, blue: 0.50).opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(task.status == .done ? 0.02 : 0.04), radius: 5, x: 0, y: 2)
    }

    private func markDone(_ task: CareTask) async {
        guard let circleId = appState.activeCircle?.id else { return }
        do {
            let updated = try await APIClient.shared.updateTaskStatus(
                circleId: circleId, taskId: task.id, status: .done
            )
            if let idx = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func caregiverLabel(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 11))
            Text(name)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(blue)
    }

    private func taskStatusIcon(_ task: CareTask) -> String {
        switch task.status {
        case .done:       return "checkmark.circle.fill"
        case .skipped:    return "forward.circle.fill"
        case .inProgress: return "circle.dotted"
        case .pending:    return task.isOverdue ? "exclamationmark.circle" : "circle"
        }
    }

    private func taskStatusColor(_ task: CareTask) -> Color {
        switch task.status {
        case .done:       return green
        case .skipped:    return .orange
        case .inProgress: return blue
        case .pending:    return task.isOverdue ? .red : Color(uiColor: .tertiaryLabel)
        }
    }

    private func recipientDueLabel(_ date: Date) -> String {
        if date < Date() { return "Overdue" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: – Caregivers section

    private var caregivers: [CircleMember] {
        (appState.activeCircle?.members ?? []).filter { $0.role != .recipient }
    }

    @ViewBuilder
    private var caregiverSection: some View {
        if !caregivers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("YOUR CARE TEAM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.7)
                    Spacer()
                }
                .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.50))

                VStack(spacing: 0) {
                    ForEach(Array(caregivers.enumerated()), id: \.element.id) { idx, member in
                        caregiverRow(member)
                        if idx < caregivers.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
            }
        }
    }

    private func caregiverRow(_ member: CircleMember) -> some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [teal.opacity(0.3), blue.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Text(initials(for: member.user?.name ?? "?"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(blue)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.user?.name ?? "Caregiver")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(dark)
                Text(member.role == .admin ? "Organiser" : "Caregiver")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
            }

            Spacer()

            let taskCount = tasks.filter {
                $0.assigneeId == member.userId &&
                $0.status != .done && $0.status != .skipped
            }.count
            if taskCount > 0 {
                Text("\(taskCount) task\(taskCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(teal)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(teal.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let raw = parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        return raw.isEmpty ? "?" : raw
    }

    // MARK: – Task bucketing

    private var todayTasks: [CareTask] {
        tasks
            .filter { task in
                guard task.status != .done, task.status != .skipped else { return false }
                guard let d = task.dueAt else { return false }
                return Calendar.current.isDateInToday(d)
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var upcomingTasks: [CareTask] {
        tasks
            .filter { task in
                guard task.status != .done, task.status != .skipped else { return false }
                guard let d = task.dueAt else { return false }
                return d > Date() && !Calendar.current.isDateInToday(d)
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var anyTimeTasks: [CareTask] {
        tasks
            .filter { $0.status != .done && $0.status != .skipped && $0.dueAt == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var doneTasks: [CareTask] {
        tasks
            .filter { $0.status == .done || $0.status == .skipped }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: – Data

    private func load() async {
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
}
