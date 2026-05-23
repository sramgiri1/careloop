import SwiftUI

struct NewTaskView: View {
    let circleId:   String
    let creatorId:  String
    let members:    [CircleMember]
    let recipients: [CareRecipient]
    let isAdmin:    Bool
    let onCreated:  (CareTask) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // MARK: – Shared fields
    @State private var title       = ""
    @State private var notes       = ""
    @State private var notesOpen   = false
    @State private var priority    = TaskPriority.normal
    @State private var assigneeId: String?
    @State private var recipientId: String

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
    @State private var freq            = TaskRecurrenceFrequency.daily
    @State private var customInterval  = 2
    @State private var weekdays        = Set<TaskWeekday>()
    @State private var recurrenceHasEnd = false
    @State private var endsAt          = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    // MARK: – Repeating start + time
    @State private var startDate           = Calendar.current.startOfDay(for: Date())
    @State private var startTime           = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var showStartCustom     = false
    @State private var showStartTimePicker = false

    @State private var loading = false
    @State private var error:  String?
    @State private var paywallRecipient: CareRecipient?
    @State private var upgradeRequestRecipientIds = Set<String>()

    init(circleId: String, creatorId: String, members: [CircleMember], recipients: [CareRecipient], isAdmin: Bool, onCreated: @escaping (CareTask) -> Void) {
        self.circleId   = circleId
        self.creatorId  = creatorId
        self.members    = members
        self.recipients = recipients
        self.isAdmin    = isAdmin
        self.onCreated  = onCreated
        let activeRecipients = TaskWorkflowPolicy.activeRecipients(recipients)
        let initialRecipient = activeRecipients.first ?? recipients.first
        _recipientId = State(initialValue: initialRecipient?.id ?? "")
        _assigneeId = State(initialValue: TaskWorkflowPolicy.defaultAssigneeId(
            for: initialRecipient,
            members: members,
            isOrganizer: isAdmin,
            currentUserId: creatorId
        ))
    }

    // MARK: – Design tokens
    private let teal = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let bg   = Color(uiColor: .systemGroupedBackground)
    private let card = Color(uiColor: .secondarySystemGroupedBackground)

    // MARK: – Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    titleCard
                    modeToggle

                    if taskMode == .once {
                        whenCard
                    } else {
                        if recurrenceLocked {
                            premiumLockCard
                        } else {
                            scheduleCard
                            startTimeCard
                            endsCard
                        }
                    }

                    if activeRecipients.count != 1 || activeRecipients.isEmpty { recipientCard }
                    priorityCard
                    if !activeRecipients.isEmpty && !availableAssignees.isEmpty { assigneeCard }
                    notesCard
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    Spacer(minLength: 32)
                }
                .padding(.top, 14)
                .padding(.horizontal, 16)
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if loading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Add") { Task { await save() } }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("new-task-submit-button")
                            .disabled(cannotSave)
                    }
                }
            }
            .onChange(of: freq)      { _ in seedWeekdayIfNeeded() }
            .onChange(of: startDate) { _ in seedWeekdayIfNeeded() }
            .onChange(of: recipientId) { _ in syncAssigneeSelection() }
            .sheet(item: $paywallRecipient) { recipient in
                PaywallView(circleId: circleId, recipient: recipient)
            }
        }
    }

    // MARK: – Title card

    private var titleCard: some View {
        TextField("Task title", text: $title)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier("new-task-title-field")
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
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
        .accessibilityIdentifier(mode == .once ? "task-mode-once-button" : "task-mode-repeating-button")
    }

    // MARK: – When card (one-time)

    private var whenCard: some View {
        CardShell {
            sectionLabel("When")

            // Quick-pick chips
            HStack(spacing: 8) {
                quickChip("None",     isOn: !hasDue) {
                    withAnimation { hasDue = false; showDueCustom = false }
                }
                quickChip("Today",    isOn: hasDue && !showDueCustom && Calendar.current.isDateInToday(dueDate)) {
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
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .padding(.horizontal, 6)
                        .tint(teal)
                }

                cardDivider
                expandableTimeRow(
                    time: $dueTime,
                    isExpanded: $showDueTimePicker,
                    label: "Time"
                )
            }
        }
    }

    // MARK: – Schedule card (repeating)

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
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    TaskWeekdayPicker(selection: $weekdays)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            if freq == .custom {
                cardDivider
                Stepper(value: $customInterval, in: 2...90) {
                    HStack {
                        Text("Interval")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                        Spacer()
                        Text("Every \(customInterval) days")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(teal)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .padding(.bottom, 2)
            }
        }
    }

    // MARK: – Start date + time card (repeating)

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
            .padding(.bottom, showStartCustom ? 0 : 0)

            if showStartCustom {
                cardDivider
                DatePicker("", selection: $startDate, in: today..., displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, 6)
                    .tint(teal)
            }

            cardDivider
            expandableTimeRow(
                time: $startTime,
                isExpanded: $showStartTimePicker,
                label: "Time of day"
            )
        }
    }

    // MARK: – Ends card (repeating)

    private var endsCard: some View {
        CardShell {
            sectionLabel("Ends")

            HStack(spacing: 8) {
                quickChip("Never",   isOn: !recurrenceHasEnd) {
                    withAnimation { recurrenceHasEnd = false }
                }
                quickChip("On date", isOn: recurrenceHasEnd) {
                    withAnimation { recurrenceHasEnd = true }
                }
            }
            .padding(.bottom, recurrenceHasEnd ? 0 : 14)

            if recurrenceHasEnd {
                cardDivider
                DatePicker("", selection: $endsAt, in: startDate..., displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, 6)
                    .tint(teal)
            }
        }
    }

    private var activeRecipients: [CareRecipient] {
        TaskWorkflowPolicy.activeRecipients(recipients)
    }

    private var selectedRecipientModel: CareRecipient? {
        recipients.first(where: { $0.id == recipientId }) ?? activeRecipients.first ?? recipients.first
    }

    private var selectedRecipientIsTaskable: Bool {
        selectedRecipientModel?.isActiveForTasks == true
    }

    private var availableAssignees: [CircleMember] {
        TaskWorkflowPolicy.eligibleAssigneeMembers(
            for: selectedRecipientModel,
            members: members,
            isOrganizer: isAdmin,
            currentUserId: creatorId
        )
    }

    private var recurrenceLocked: Bool {
        taskMode == .repeating && !ReceiverPremiumPolicy.supportsRecurringSchedules(for: selectedRecipientModel)
    }

    // MARK: – Care recipient card

    @ViewBuilder
    private var recipientCard: some View {
        if activeRecipients.isEmpty {
            CardShell {
                VStack(alignment: .leading, spacing: 8) {
                    Label(inactiveReceiverTitle, systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(inactiveReceiverDetail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    if isAdmin {
                        Text("Go to Care Receiver Management to send a direct invite or record proxy authorization.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(teal)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .accessibilityIdentifier("new-task-inactive-receiver-block")
        } else {
            CardShell {
                HStack {
                    Label("For", systemImage: "person.fill")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                    Spacer()
                    Picker("", selection: $recipientId) {
                        ForEach(activeRecipients) { r in
                            Text(r.name).tag(r.id)
                        }
                    }
                    .labelsHidden()
                    .tint(teal)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
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
                    .accessibilityIdentifier("task-recurring-upgrade-button")
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
        .accessibilityIdentifier("task-recurring-request-upgrade-button")
    }

    // MARK: – Priority card

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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                active
                                    ? AnyShapeStyle(priorityColor(p))
                                    : AnyShapeStyle(priorityColor(p).opacity(0.10)),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: – Assignee card

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
                .labelsHidden()
                .tint(teal)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    // MARK: – Notes card

    private var notesCard: some View {
        CardShell {
            Button {
                withAnimation(.spring(response: 0.28)) { notesOpen.toggle() }
            } label: {
                HStack {
                    Label(
                        notesOpen ? "Notes" : (notes.isEmpty ? "Add notes" : notes),
                        systemImage: "note.text"
                    )
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(notes.isEmpty && !notesOpen ? .secondary : .primary)
                    .lineLimit(1)
                    Spacer()
                    Image(systemName: notesOpen ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if notesOpen {
                cardDivider
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .font(.system(size: 15, design: .rounded))
                    .lineLimit(3...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Text("Don't include medical details — use titles like \"Doctor appointment\", not diagnoses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: – Reusable sub-components

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }

    private func quickChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
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
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                Text(active && date != nil ? date!.formatted(date: .abbreviated, time: .omitted) : "Custom")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
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
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(time.wrappedValue, style: .time)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(teal)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                DatePicker("", selection: time, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .tint(teal)
            }
        }
    }

    private var cardDivider: some View {
        Divider().padding(.horizontal, 16)
    }

    private func priorityColor(_ p: TaskPriority) -> Color {
        switch p {
        case .low:    return .green
        case .normal: return teal
        case .high:   return .orange
        case .urgent: return .red
        }
    }

    // MARK: – Date helpers

    private var today:    Date { Calendar.current.startOfDay(for: Date()) }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: today)! }

    // MARK: – Save logic

    private var cannotSave: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
            || loading
            || recipientId.isEmpty
            || !selectedRecipientIsTaskable
            || assigneeId == nil
            || recurrenceLocked
    }

    private var computedDueAt: Date? {
        switch taskMode {
        case .once:
            guard hasDue else { return nil }
            return Calendar.current.date(
                bySettingHour:   Calendar.current.component(.hour,   from: dueTime),
                minute:          Calendar.current.component(.minute, from: dueTime),
                second:          0,
                of: dueDate
            )
        case .repeating:
            return Calendar.current.date(
                bySettingHour:   Calendar.current.component(.hour,   from: startTime),
                minute:          Calendar.current.component(.minute, from: startTime),
                second:          0,
                of: startDate
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
        let currentIds = Set(availableAssignees.map(\.userId))
        if let assigneeId, currentIds.contains(assigneeId) {
            return
        }
        self.assigneeId = TaskWorkflowPolicy.defaultAssigneeId(
            for: selectedRecipientModel,
            members: members,
            isOrganizer: isAdmin,
            currentUserId: creatorId
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
            ?? "Select a premium care receiver to add repeating care routines."
    }

    private var inactiveReceiverTitle: String {
        if let recipient = selectedRecipientModel {
            return "Activate \(recipient.name) before creating tasks."
        }
        return "Activate a care receiver before creating tasks."
    }

    private var inactiveReceiverDetail: String {
        if let recipient = selectedRecipientModel {
            return "\(recipient.name) must accept a direct invite or be proxy-activated with recorded authorization before tasks can be created."
        }
        return "Tasks unlock after the care receiver accepts a direct invite or a Care Organizer records proxy authorization."
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

    private func save() async {
        loading = true
        do {
            let created = try await createTask()
            onCreated(created)
            dismiss()
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func createTask() async throws -> CareTask {
        if UITestScenario.current != nil {
            let created = makeUITestTask()
            appendUITestTask(created)
            return created
        }

        return try await APIClient.shared.createTask(
            circleId:    circleId,
            title:       title.trimmingCharacters(in: .whitespaces),
            notes:       notes.isEmpty ? nil : notes,
            dueAt:       computedDueAt,
            priority:    priority,
            assigneeId:  assigneeId,
            recipientId: recipientId.isEmpty ? nil : recipientId,
            recurrence:  computedRecurrence
        )
    }

    private func makeUITestTask() -> CareTask {
        let recurrence = computedRecurrence
        let selectedAssignee = members.first { $0.userId == assigneeId }?.user
        return CareTask(
            id: "ui-task-\(UUID().uuidString)",
            title: title.trimmingCharacters(in: .whitespaces),
            notes: notes.isEmpty ? nil : notes,
            dueAt: computedDueAt,
            status: .pending,
            priority: priority,
            recurrenceFrequency: recurrence?.frequency ?? .none,
            recurrenceInterval: recurrence?.interval,
            recurrenceWeekdays: recurrence?.weekdays ?? [],
            recurrenceEndsAt: recurrence?.endsAt,
            seriesId: recurrence == nil ? nil : "ui-series-\(UUID().uuidString)",
            completedAt: nil,
            archivedAt: nil,
            circleId: circleId,
            recipientId: recipientId.isEmpty ? nil : recipientId,
            recipient: selectedRecipientModel,
            creatorId: creatorId,
            assigneeId: assigneeId,
            assignee: selectedAssignee,
            capabilities: CareTaskCapabilities(
                canEdit: isAdmin,
                canDelete: isAdmin,
                canAssign: isAdmin,
                canChangeRecipient: isAdmin,
                canChangeStatus: true,
                canMarkDone: true,
                canSkip: true,
                canComment: true
            )
        )
    }

    private func appendUITestTask(_ task: CareTask) {
        guard var circle = appState.activeCircle else { return }
        var updatedTasks = circle.tasks ?? []
        updatedTasks.insert(task, at: 0)
        circle.tasks = updatedTasks
        appState.activeCircle = circle
    }
}

// MARK: – CardShell

private struct CardShell<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
