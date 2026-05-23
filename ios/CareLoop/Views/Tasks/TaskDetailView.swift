import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var task: CareTask
    let onUpdate: (CareTask) -> Void
    let onDelete: () -> Void

    // MARK: – Shared fields (mirrors NewTaskView)
    @State private var title      = ""
    @State private var notes      = ""
    @State private var notesOpen  = false
    @State private var priority   = TaskPriority.normal
    @State private var assigneeId: String?
    @State private var recipientId = ""

    // MARK: – Task mode
    private enum TaskMode { case once, repeating }
    @State private var taskMode: TaskMode = .once

    // MARK: – One-time due
    @State private var hasDue            = false
    @State private var dueDate           = Calendar.current.startOfDay(for: Date())
    @State private var dueTime           = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var showDueCustom     = false
    @State private var showDueTimePicker = false

    // MARK: – Repeating schedule
    @State private var freq             = TaskRecurrenceFrequency.daily
    @State private var customInterval   = 2
    @State private var weekdays         = Set<TaskWeekday>()
    @State private var recurrenceHasEnd = false
    @State private var endsAt           = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    // MARK: – Repeating start + time
    @State private var startDate           = Calendar.current.startOfDay(for: Date())
    @State private var startTime           = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var showStartCustom     = false
    @State private var showStartTimePicker = false

    // MARK: – Status + meta
    @State private var status = TaskStatus.pending
    @State private var loading              = false
    @State private var error:               String?
    @State private var isEditing            = false
    @State private var showDeleteAlert      = false
    @State private var showSeriesScopeDialog = false
    @State private var paywallRecipient: CareRecipient?
    @State private var upgradeRequestRecipientIds = Set<String>()
    @State private var snoozingMinutes: Int?
    @State private var snoozeMessage: String?
    @State private var showComments = false

    init(task: CareTask, onUpdate: @escaping (CareTask) -> Void, onDelete: @escaping () -> Void) {
        _task       = State(initialValue: task)
        self.onUpdate = onUpdate
        self.onDelete = onDelete

        let existingDue = task.dueAt ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        let calDate     = Calendar.current.startOfDay(for: existingDue)
        let isRepeating = task.recurrence != nil
        let existingFreq = task.recurrence?.frequency ?? .daily
        let safeFreq    = existingFreq == .none ? .daily : existingFreq

        _title           = State(initialValue: task.title)
        _notes           = State(initialValue: task.notes ?? "")
        _notesOpen       = State(initialValue: !(task.notes ?? "").isEmpty)
        _priority        = State(initialValue: task.priority)
        _assigneeId      = State(initialValue: task.assigneeId)
        _recipientId     = State(initialValue: task.recipientId ?? "")
        _taskMode        = State(initialValue: isRepeating ? .repeating : .once)
        _status          = State(initialValue: task.status)

        // One-time
        _hasDue          = State(initialValue: task.dueAt != nil && !isRepeating)
        _dueDate         = State(initialValue: calDate)
        _dueTime         = State(initialValue: existingDue)
        _showDueCustom   = State(initialValue: {
            guard task.dueAt != nil, !isRepeating else { return false }
            return !Calendar.current.isDateInToday(calDate) && !Calendar.current.isDateInTomorrow(calDate)
        }())

        // Repeating
        _freq            = State(initialValue: safeFreq)
        _customInterval  = State(initialValue: max(2, task.recurrence?.interval ?? 2))
        _weekdays        = State(initialValue: Set(task.recurrence?.normalizedWeekdays ?? []))
        _recurrenceHasEnd = State(initialValue: task.recurrence?.endsAt != nil)
        _endsAt          = State(initialValue: task.recurrence?.endsAt ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
        _startDate       = State(initialValue: calDate)
        _startTime       = State(initialValue: existingDue)
        _showStartCustom = State(initialValue: {
            guard isRepeating else { return false }
            return !Calendar.current.isDateInToday(calDate) && !Calendar.current.isDateInTomorrow(calDate)
        }())
    }

    // MARK: – Permissions
    private var userId:   String { appState.currentUser?.id ?? "" }
    private var circleId: String { appState.activeCircle?.id ?? "" }
    private var isAdmin:  Bool   { appState.userRole == .admin }
    private var detailPresentation: TaskDetailPresentation {
        TaskWorkflowPolicy.detailPresentation(
            for: task,
            currentUserId: userId,
            role: appState.userRole,
            selectedRecipient: selectedRecipientModel,
            statusOverride: status
        )
    }
    private var canEdit:  Bool   { detailPresentation.permissions.canEdit }
    private var canChangeStatus: Bool { detailPresentation.permissions.canChangeStatus }
    private var canAssign: Bool { detailPresentation.permissions.canAssign }
    private var canChangeRecipient: Bool { detailPresentation.permissions.canChangeRecipient }
    private var canDelete: Bool { detailPresentation.permissions.canDelete }
    private var canSkip: Bool { detailPresentation.permissions.canSkip }
    private var canSnoozeReminder: Bool { detailPresentation.permissions.canSnoozeReminder }

    private var activeRecipients: [CareRecipient] {
        TaskWorkflowPolicy.activeRecipients(appState.activeCircle?.recipients ?? [])
    }

    private var selectedRecipientModel: CareRecipient? {
        let recipients = appState.activeCircle?.recipients ?? []
        return recipients.first(where: { $0.id == recipientId })
            ?? task.recipient
            ?? activeRecipients.first
    }

    private var recurrenceLocked: Bool {
        taskMode == .repeating && !ReceiverPremiumPolicy.supportsRecurringSchedules(for: selectedRecipientModel)
    }

    private var availableAssignees: [CircleMember] {
        TaskWorkflowPolicy.eligibleAssigneeMembers(
            for: selectedRecipientModel,
            members: appState.activeCircle?.members ?? [],
            isOrganizer: isAdmin,
            currentUserId: userId
        )
    }

    // MARK: – Design tokens (mirrors NewTaskView)
    private let teal = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let bg   = Color(uiColor: .systemGroupedBackground)
    private let card = Color(uiColor: .secondarySystemGroupedBackground)

    // MARK: – Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                titleCard
                if isTaskBlocked {
                    blockedTaskCard
                } else if shouldShowUrgencyCard {
                    urgencyCard
                }
                modeToggle.disabled(!canEditContent)

                if taskMode == .once {
                    whenCard.disabled(!canEditContent)
                } else {
                    if recurrenceLocked {
                        premiumLockCard
                    } else {
                        scheduleCard.disabled(!canEditContent)
                        startTimeCard.disabled(!canEditContent)
                        endsCard.disabled(!canEditContent)
                    }
                }

                if !isTaskBlocked && canSnoozeReminder {
                    snoozeCard
                }

                if !isTaskBlocked && canChangeStatus { statusCard }

                if activeRecipients.count != 1 || activeRecipients.isEmpty {
                    recipientCard.disabled(!(canChangeRecipient && isEditing))
                }
                priorityCard.disabled(!canEditContent)
                if canAssign && !availableAssignees.isEmpty {
                    assigneeCard.disabled(!isEditing)
                }
                notesCard.disabled(!canEditContent)

                if !isTaskBlocked && detailPresentation.permissions.canComment {
                    commentsLink
                }

                if !isTaskBlocked && canDelete { deleteButton }

                if let error {
                    Text(error)
                        .font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                Spacer(minLength: 32)
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("task-detail-screen")
        .background(bg.ignoresSafeArea())
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if loading {
                    ProgressView().scaleEffect(0.8)
                } else if isEditing || hasStatusChange {
                    Button("Save") { handleSaveTapped() }
                        .fontWeight(.semibold)
                        .disabled(cannotSave)
                        .accessibilityIdentifier("task-detail-save-button")
                } else if canEdit && !isTaskBlocked {
                    Button("Edit") { isEditing = true }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("task-detail-edit-button")
                } else {
                    EmptyView()
                }
            }
        }
        .onChange(of: freq)      { _ in seedWeekdayIfNeeded() }
        .onChange(of: startDate) { _ in seedWeekdayIfNeeded() }
        .onChange(of: recipientId) { _ in syncAssigneeSelection() }
        .sheet(item: $paywallRecipient) { recipient in
            PaywallView(circleId: circleId, recipient: recipient)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showComments) {
            NavigationStack {
                TaskCommentsView(task: task).environmentObject(appState)
            }
        }
        .alert("Delete this task?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await performDelete() } }
        } message: {
            Text("This removes the task from the care circle.")
        }
        .confirmationDialog(
            "Apply changes to",
            isPresented: $showSeriesScopeDialog,
            titleVisibility: .visible
        ) {
            Button("This occurrence only") { Task { await save(seriesScope: .occurrence) } }
            Button("Whole series")          { Task { await save(seriesScope: .series) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Update only this task occurrence, or apply changes to the whole recurring series.")
        }
    }

    // MARK: – Title card

    private var titleCard: some View {
        TextField("Task title", text: $title)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(!canEditContent)
            .accessibilityIdentifier("task-detail-title-field")
    }

    private var blockedTaskCard: some View {
        CardShell {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Task actions are blocked")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(detailPresentation.blockedReason ?? "This task cannot be changed right now.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier("task-detail-blocked-card")
    }

    private var urgencyCard: some View {
        CardShell {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: urgencyIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(urgencyColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(urgencyTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(urgencyMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier("task-detail-urgency-card")
    }

    // MARK: – Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.once,      icon: "calendar.badge.checkmark", label: "One-time")
            modeButton(.repeating, icon: "arrow.clockwise",          label: "Repeating")
        }
        .padding(4)
        .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func modeButton(_ mode: TaskMode, icon: String, label: String) -> some View {
        let active = taskMode == mode
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { taskMode = mode }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(label).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? .white : .secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(
                active
                    ? AnyShapeStyle(LinearGradient(
                        colors: [teal, Color(red: 0.13, green: 0.56, blue: 0.87)],
                        startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: – When card (one-time) — mirrors NewTaskView exactly

    private var whenCard: some View {
        CardShell {
            sectionLabel("When")
            HStack(spacing: 8) {
                quickChip("None",    isOn: !hasDue) {
                    withAnimation { hasDue = false; showDueCustom = false }
                }
                quickChip("Today",   isOn: hasDue && !showDueCustom && Calendar.current.isDateInToday(dueDate)) {
                    withAnimation { hasDue = true; showDueCustom = false; dueDate = today }
                }
                quickChip("Tomorrow", isOn: hasDue && !showDueCustom && Calendar.current.isDateInTomorrow(dueDate)) {
                    withAnimation { hasDue = true; showDueCustom = false; dueDate = tomorrow }
                }
                customDateChip(active: showDueCustom, date: hasDue ? dueDate : nil) {
                    withAnimation { hasDue = true; showDueCustom.toggle() }
                }
            }
            .padding(.bottom, hasDue ? 0 : 14)

            if hasDue {
                if showDueCustom {
                    cardDivider
                    DatePicker("", selection: $dueDate, displayedComponents: [.date])
                        .labelsHidden().datePickerStyle(.graphical)
                        .padding(.horizontal, 6).tint(teal)
                }
                cardDivider
                expandableTimeRow(time: $dueTime, isExpanded: $showDueTimePicker, label: "Time")
            }
        }
    }

    private var snoozeCard: some View {
        CardShell {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.clock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(teal)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Need more time?")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(snoozeMessage ?? "Snooze this reminder and delay escalation.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("snooze-status-message")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            HStack(spacing: 8) {
                snoozeButton(label: "15 min", minutes: 15)
                snoozeButton(label: "1 hour", minutes: 60)
                snoozeButton(label: "Tomorrow", minutes: 1440)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func snoozeButton(label: String, minutes: Int) -> some View {
        Button {
            Task { await snoozeReminder(minutes: minutes) }
        } label: {
            HStack(spacing: 6) {
                if snoozingMinutes == minutes {
                    ProgressView().scaleEffect(0.75)
                }
                Text(label)
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(teal, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(snoozingMinutes != nil)
        .accessibilityIdentifier("snooze-\(minutes)-button")
    }

    // MARK: – Schedule card (repeating) — mirrors NewTaskView

    private var scheduleCard: some View {
        CardShell {
            sectionLabel("Repeats")
            HStack(spacing: 8) {
                ForEach([TaskRecurrenceFrequency.daily, .weekly, .monthly, .custom], id: \.self) { f in
                    let labels: [TaskRecurrenceFrequency: String] = [
                        .daily: "Daily", .weekly: "Weekly", .monthly: "Monthly", .custom: "Custom"
                    ]
                    quickChip(labels[f] ?? f.label, isOn: freq == f) {
                        withAnimation(.spring(response: 0.28)) { freq = f }
                    }
                }
            }
            .padding(.bottom, freq == .weekly || freq == .custom ? 0 : 14)
            if freq == .weekly {
                cardDivider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Days of week")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary).textCase(.uppercase).tracking(0.4)
                    TaskWeekdayPicker(selection: $weekdays)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            if freq == .custom {
                cardDivider
                Stepper(value: $customInterval, in: 2...90) {
                    HStack {
                        Text("Interval").font(.system(size: 15, weight: .medium, design: .rounded))
                        Spacer()
                        Text("Every \(customInterval) days")
                            .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(teal)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 13).padding(.bottom, 2)
            }
        }
    }

    // MARK: – Start date + time card (repeating) — mirrors NewTaskView

    private var startTimeCard: some View {
        CardShell {
            sectionLabel("Starts on")
            HStack(spacing: 8) {
                quickChip("Today",    isOn: !showStartCustom && Calendar.current.isDateInToday(startDate)) {
                    withAnimation { showStartCustom = false; startDate = today }
                }
                quickChip("Tomorrow", isOn: !showStartCustom && Calendar.current.isDateInTomorrow(startDate)) {
                    withAnimation { showStartCustom = false; startDate = tomorrow }
                }
                customDateChip(active: showStartCustom, date: showStartCustom ? startDate : nil) {
                    withAnimation { showStartCustom.toggle() }
                }
            }
            if showStartCustom {
                cardDivider
                DatePicker("", selection: $startDate, in: Date()..., displayedComponents: [.date])
                    .labelsHidden().datePickerStyle(.graphical).padding(.horizontal, 6).tint(teal)
            }
            cardDivider
            expandableTimeRow(time: $startTime, isExpanded: $showStartTimePicker, label: "Time of day")
        }
    }

    // MARK: – Ends card (repeating) — mirrors NewTaskView

    private var endsCard: some View {
        CardShell {
            sectionLabel("Ends")
            HStack(spacing: 8) {
                quickChip("Never",   isOn: !recurrenceHasEnd) { withAnimation { recurrenceHasEnd = false } }
                quickChip("On date", isOn: recurrenceHasEnd)  { withAnimation { recurrenceHasEnd = true } }
            }
            .padding(.bottom, recurrenceHasEnd ? 0 : 14)
            if recurrenceHasEnd {
                cardDivider
                DatePicker("", selection: $endsAt, in: startDate..., displayedComponents: [.date])
                    .labelsHidden().datePickerStyle(.graphical).padding(.horizontal, 6).tint(teal)
            }
        }
    }

    // MARK: – Status card (TaskDetailView-only)

    private var statusCard: some View {
        CardShell {
            sectionLabel("Status")
            HStack(spacing: 8) {
                statusChip(.pending,    icon: "circle",                 color: Color(uiColor: .tertiaryLabel))
                statusChip(.inProgress, icon: "circle.dotted",          color: Color(red: 0.13, green: 0.56, blue: 0.87))
                statusChip(.done,       icon: "checkmark.circle.fill",  color: Color(red: 0.12, green: 0.68, blue: 0.49))
                if canSkip {
                    statusChip(.skipped, icon: "forward.circle.fill",   color: .orange)
                }
            }
            .padding(.bottom, status == .done && task.completedBy != nil ? 6 : 14)
            if status == .done, let doer = task.completedBy?.name {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Completed by \(doer)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Color(red: 0.12, green: 0.68, blue: 0.49))
                .padding(.bottom, 14)
            }
        }
    }

    private func statusChip(_ s: TaskStatus, icon: String, color: Color) -> some View {
        let active = status == s
        return Button { withAnimation { status = s } } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(s.label).font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? .white : color)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                active ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.10)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task-detail-status-\(s.rawValue.lowercased())")
        .accessibilityValue(active ? "Selected" : "Not selected")
    }

    // MARK: – Recipient card

    @ViewBuilder
    private var recipientCard: some View {
        if !activeRecipients.isEmpty {
            CardShell {
                HStack {
                    Label("For", systemImage: "person.fill")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                    Spacer()
                    Picker("", selection: $recipientId) {
                        ForEach(activeRecipients) { r in Text(r.name).tag(r.id) }
                    }
                    .labelsHidden().tint(teal)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
        }
    }

    private var premiumLockCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Repeating Schedules")
                VStack(alignment: .leading, spacing: 8) {
                    Text(lockedRecurringTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(lockedRecurringDetail)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, selectedRecipientModel != nil ? 0 : 14)

                if isAdmin, let recipient = selectedRecipientModel {
                    Button {
                        paywallRecipient = recipient
                    } label: {
                        Label("Unlock Premium for \(recipient.name)", systemImage: "crown.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.55, green: 0.22, blue: 0.97))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .accessibilityIdentifier("task-detail-recurring-upgrade-button")
                } else if let recipient = selectedRecipientModel {
                    caregiverUpgradeRequestButton(for: recipient)
                }
            }
        }
    }

    private func caregiverUpgradeRequestButton(for recipient: CareRecipient) -> some View {
        Button {
            Task { await requestUpgrade(for: recipient) }
        } label: {
            Label(upgradeRequestRecipientIds.contains(recipient.id) ? "Request sent" : "Ask organizer to upgrade", systemImage: "paperplane.fill")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(teal)
        .disabled(upgradeRequestRecipientIds.contains(recipient.id))
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .accessibilityIdentifier("task-detail-recurring-request-upgrade-button")
    }

    // MARK: – Priority card — mirrors NewTaskView

    private var priorityCard: some View {
        CardShell {
            sectionLabel("Priority")
            HStack(spacing: 8) {
                ForEach(TaskPriority.allCases, id: \.self) { p in
                    let active = priority == p
                    Button { withAnimation { priority = p } } label: {
                        Text(p.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(active ? .white : priorityColor(p))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(
                                active ? AnyShapeStyle(priorityColor(p)) : AnyShapeStyle(priorityColor(p).opacity(0.10)),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: – Assignee card — mirrors NewTaskView

    private var assigneeCard: some View {
        CardShell {
            HStack {
                Label("Assign to", systemImage: "person.2.fill")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                Spacer()
                Picker("", selection: Binding(
                    get: { assigneeId ?? "" },
                    set: { assigneeId = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(availableAssignees) { m in
                        Text(m.role == .recipient
                             ? "\(m.user?.name ?? "Unknown") (Care Receiver)"
                             : m.user?.name ?? "Unknown")
                            .tag(m.userId)
                    }
                }
                .labelsHidden().tint(teal)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
    }

    // MARK: – Notes card — mirrors NewTaskView

    private var notesCard: some View {
        CardShell {
            Button {
                withAnimation(.spring(response: 0.28)) { notesOpen.toggle() }
            } label: {
                HStack {
                    Label(notesOpen ? "Notes" : (notes.isEmpty ? "Add notes" : notes),
                          systemImage: "note.text")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(notes.isEmpty && !notesOpen ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: notesOpen ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            if notesOpen {
                cardDivider
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .font(.system(size: 15, design: .rounded)).lineLimit(3...6)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                Text("Don't include medical details — use titles like \"Doctor appointment\", not diagnoses.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }

    // MARK: – Comments link

    private var commentsLink: some View {
        Button {
            showComments = true
        } label: {
            HStack {
                Label("Comments", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(teal)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task-detail-comments-link")
    }

    // MARK: – Delete button

    private var deleteButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            Label("Delete Task", systemImage: "trash")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .accessibilityIdentifier("task-detail-delete-button")
    }

    // MARK: – Reusable sub-components (matches NewTaskView)

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary).textCase(.uppercase).tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private func quickChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? .white : .secondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(
                    isOn ? AnyShapeStyle(teal) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func customDateChip(active: Bool, date: Date?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                Text(active && date != nil ? date!.formatted(date: .abbreviated, time: .omitted) : "Custom")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? .white : .secondary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(
                active ? AnyShapeStyle(teal) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func expandableTimeRow(time: Binding<Date>, isExpanded: Binding<Bool>, label: String) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28)) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack {
                    Label(label, systemImage: "clock")
                        .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(.primary)
                    Spacer()
                    Text(time.wrappedValue, style: .time)
                        .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(teal)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            if isExpanded.wrappedValue {
                DatePicker("", selection: time, displayedComponents: [.hourAndMinute])
                    .labelsHidden().datePickerStyle(.wheel)
                    .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.bottom, 6).tint(teal)
            }
        }
    }

    private var cardDivider: some View { Divider().padding(.horizontal, 16) }

    private func priorityColor(_ p: TaskPriority) -> Color {
        switch p {
        case .low:    return .green
        case .normal: return teal
        case .high:   return .orange
        case .urgent: return .red
        }
    }

    private var today:    Date { Calendar.current.startOfDay(for: Date()) }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: today)! }

    // MARK: – Save logic

    private var cannotSave: Bool {
        loading
        || isTaskBlocked
        || (isEditing && (
            title.trimmingCharacters(in: .whitespaces).isEmpty
            || recipientId.isEmpty
            || (canAssign && assigneeId == nil)
            || recurrenceLocked
        ))
    }

    private var computedDueAt: Date? {
        switch taskMode {
        case .once:
            guard hasDue else { return nil }
            return Calendar.current.date(
                bySettingHour:   Calendar.current.component(.hour,   from: dueTime),
                minute:          Calendar.current.component(.minute, from: dueTime),
                second:          0, of: dueDate
            )
        case .repeating:
            return Calendar.current.date(
                bySettingHour:   Calendar.current.component(.hour,   from: startTime),
                minute:          Calendar.current.component(.minute, from: startTime),
                second:          0, of: startDate
            )
        }
    }

    private var computedRecurrence: TaskRecurrence? {
        guard taskMode == .repeating else { return nil }
        let resolvedWeekdays = freq == .weekly ? normalizedWeekdays : []
        let resolvedInterval = freq == .custom  ? customInterval    : 1
        return TaskRecurrence(
            frequency: freq,
            interval:  resolvedInterval,
            weekdays:  resolvedWeekdays,
            endsAt:    recurrenceHasEnd ? endsAt : nil
        )
    }

    private var normalizedWeekdays: [String] {
        let sorted = weekdays.sorted { $0.sortOrder < $1.sortOrder }
        if !sorted.isEmpty { return sorted.map(\.rawValue) }
        return [TaskWeekday.from(date: startDate).rawValue]
    }

    private func seedWeekdayIfNeeded() {
        guard taskMode == .repeating, freq == .weekly, weekdays.isEmpty else { return }
        weekdays = [TaskWeekday.from(date: startDate)]
    }

    private func syncAssigneeSelection() {
        guard canAssign else { return }
        let currentIds = Set(availableAssignees.map(\.userId))
        if let assigneeId, currentIds.contains(assigneeId) {
            return
        }
        self.assigneeId = TaskWorkflowPolicy.defaultAssigneeId(
            for: selectedRecipientModel,
            members: appState.activeCircle?.members ?? [],
            isOrganizer: isAdmin,
            currentUserId: userId
        )
    }

    private var lockedRecurringTitle: String {
        if let recipient = selectedRecipientModel {
            return "Recurring schedules are premium for \(recipient.name)"
        }
        return "Recurring schedules require premium"
    }

    private var lockedRecurringDetail: String {
        selectedRecipientModel?.premiumStatusDetail
            ?? "Select a premium care receiver to keep repeating routines enabled."
    }

    private func requestUpgrade(for recipient: CareRecipient) async {
        if UITestScenario.current != nil {
            upgradeRequestRecipientIds.insert(recipient.id)
            return
        }
        do {
            _ = try await APIClient.shared.requestRecipientPremiumUpgrade(circleId: circleId, recipientId: recipient.id)
            upgradeRequestRecipientIds.insert(recipient.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var hasChanges: Bool {
        title != task.title
        || notes != (task.notes ?? "")
        || computedDueAt != task.dueAt
        || priority != task.priority
        || assigneeId != task.assigneeId
        || recipientId != (task.recipientId ?? "")
        || computedRecurrence != task.recurrence
    }

    private var hasStatusChange: Bool {
        status != task.status
    }

    private var canEditContent: Bool {
        canEdit && isEditing && !isTaskBlocked
    }

    private var isTaskBlocked: Bool {
        detailPresentation.blockedReason != nil
    }

    private var shouldShowUrgencyCard: Bool {
        detailPresentation.displayState == .overdue || detailPresentation.displayState == .escalated
    }

    private var urgencyIcon: String {
        detailPresentation.displayState == .escalated ? "exclamationmark.octagon.fill" : "clock.badge.exclamationmark.fill"
    }

    private var urgencyColor: Color {
        detailPresentation.displayState == .escalated ? .red : .orange
    }

    private var urgencyTitle: String {
        detailPresentation.displayState == .escalated ? "Escalation active" : "Task is overdue"
    }

    private var urgencyMessage: String {
        switch detailPresentation.displayState {
        case .escalated:
            return "This task passed the escalation window. Mark it done, snooze it, or reassign it so the care team has a clear next step."
        case .overdue:
            return "This task is overdue but still inside the escalation window. Complete or snooze it before it escalates."
        default:
            return ""
        }
    }

    private var shouldPromptForSeriesScope: Bool {
        task.recurrence != nil && hasChanges && status == task.status
    }

    private func handleSaveTapped() {
        if shouldPromptForSeriesScope { showSeriesScopeDialog = true; return }
        Task { await save() }
    }

    private func save(seriesScope: TaskSeriesScope = .occurrence) async {
        loading = true; error = nil
        do {
            let updated = try await updateTask(seriesScope: seriesScope)
            task = updated; onUpdate(updated); dismiss()
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func updateTask(seriesScope: TaskSeriesScope) async throws -> CareTask {
        if UITestScenario.current != nil {
            return updateUITestTask()
        }

        return try await APIClient.shared.updateTask(
            circleId:    circleId,
            taskId:      task.id,
            title:       title.trimmingCharacters(in: .whitespaces),
            notes:       notes.isEmpty ? nil : notes,
            dueAt:       computedDueAt,
            priority:    priority,
            status:      status,
            canAssign:   canAssign,
            assigneeId:  assigneeId,
            recipientId: recipientId.isEmpty ? nil : recipientId,
            recurrence:  computedRecurrence,
            seriesScope: seriesScope
        )
    }

    private func updateUITestTask() -> CareTask {
        var updated = CareTask(
            id: task.id,
            title: title.trimmingCharacters(in: .whitespaces),
            notes: notes.isEmpty ? nil : notes,
            dueAt: computedDueAt,
            status: status,
            priority: priority,
            recurrenceFrequency: computedRecurrence?.frequency ?? .none,
            recurrenceInterval: computedRecurrence?.interval,
            recurrenceWeekdays: computedRecurrence?.weekdays ?? [],
            recurrenceEndsAt: computedRecurrence?.endsAt,
            seriesId: computedRecurrence == nil ? nil : task.seriesId,
            completedAt: status == .done ? Date() : nil,
            completedById: status == .done ? appState.currentUser?.id : nil,
            completedBy: status == .done ? appState.currentUser : nil,
            archivedAt: task.archivedAt,
            circleId: task.circleId,
            recipientId: recipientId.isEmpty ? nil : recipientId,
            recipient: selectedRecipientModel,
            creatorId: task.creatorId,
            assigneeId: assigneeId,
            assignee: availableAssignees.first { $0.userId == assigneeId }?.user ?? task.assignee,
            capabilities: task.capabilities
        )

        if status != .done {
            updated = updated.withUpdatedStatus(status, completedAt: nil, completedBy: nil)
        }

        if var circle = appState.activeCircle {
            circle.tasks = (circle.tasks ?? []).map { $0.id == updated.id ? updated : $0 }
            appState.activeCircle = circle
        }

        return updated
    }

    private func snoozeReminder(minutes: Int) async {
        snoozingMinutes = minutes
        error = nil
        defer { snoozingMinutes = nil }

        if UITestScenario.current != nil {
            let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
            snoozeMessage = snoozeStatusMessage(until: until)
            return
        }

        do {
            let result = try await APIClient.shared.snoozeReminder(circleId: circleId, taskId: task.id, minutes: minutes)
            if let until = result.snoozedUntil {
                snoozeMessage = snoozeStatusMessage(until: until)
            } else {
                snoozeMessage = "Snoozed for \(snoozeLabel(minutes: minutes))."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func snoozeLabel(minutes: Int) -> String {
        switch minutes {
        case 15: return "15 minutes"
        case 60: return "1 hour"
        case 1440: return "tomorrow"
        default: return "\(minutes) minutes"
        }
    }

    private func snoozeStatusMessage(until: Date) -> String {
        "Reminder rescheduled until \(until.formatted(date: .omitted, time: .shortened)). Escalation is paused until then."
    }

    private func performDelete() async {
        loading = true
        do {
            if UITestScenario.current != nil {
                deleteUITestTask()
            } else {
                try await APIClient.shared.deleteTask(circleId: circleId, taskId: task.id)
            }
            onDelete(); dismiss()
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func deleteUITestTask() {
        guard var circle = appState.activeCircle else { return }
        circle.tasks = (circle.tasks ?? []).filter { $0.id != task.id }
        appState.activeCircle = circle
    }
}

// MARK: – CardShell (local copy — avoids cross-file private access)
private struct CardShell<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
