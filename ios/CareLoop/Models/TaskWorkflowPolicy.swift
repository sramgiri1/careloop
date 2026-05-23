import Foundation

struct TaskDetailPermissions: Equatable {
    let canEdit: Bool
    let canDelete: Bool
    let canAssign: Bool
    let canChangeRecipient: Bool
    let canChangeStatus: Bool
    let canMarkDone: Bool
    let canSkip: Bool
    let canComment: Bool
    let canSnoozeReminder: Bool
}

enum TaskDetailDisplayState: Equatable {
    case pending
    case inProgress
    case overdue
    case escalated
    case done
    case skipped

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .overdue: return "Overdue"
        case .escalated: return "Escalated"
        case .done: return "Done"
        case .skipped: return "Skipped"
        }
    }

    var isClosed: Bool {
        self == .done || self == .skipped
    }
}

struct TaskDetailPresentation: Equatable {
    let displayState: TaskDetailDisplayState
    let permissions: TaskDetailPermissions
    let blockedReason: String?
    let recurrenceBlockReason: String?
}

enum TaskWorkflowPolicy {
    static let escalationGraceInterval: TimeInterval = 15 * 60

    static func activeRecipients(_ recipients: [CareRecipient]) -> [CareRecipient] {
        recipients.filter(\.isActiveForTasks)
    }

    static func eligibleAssigneeMembers(
        for recipient: CareRecipient?,
        members: [CircleMember],
        isOrganizer: Bool,
        currentUserId: String
    ) -> [CircleMember] {
        let allowedIds: Set<String>
        if isOrganizer {
            allowedIds = Set(members.map(\.userId))
        } else {
            allowedIds = Set(recipient?.eligibleAssigneeIds ?? [currentUserId])
        }

        return members
            .filter { allowedIds.contains($0.userId) }
            .sorted { lhs, rhs in
                let leftRank = assigneeSortRank(member: lhs, recipient: recipient, currentUserId: currentUserId)
                let rightRank = assigneeSortRank(member: rhs, recipient: recipient, currentUserId: currentUserId)
                if leftRank != rightRank { return leftRank < rightRank }
                let leftName = lhs.user?.name ?? lhs.userId
                let rightName = rhs.user?.name ?? rhs.userId
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            }
    }

    static func defaultAssigneeId(
        for recipient: CareRecipient?,
        members: [CircleMember],
        isOrganizer: Bool,
        currentUserId: String
    ) -> String? {
        let eligible = eligibleAssigneeMembers(
            for: recipient,
            members: members,
            isOrganizer: isOrganizer,
            currentUserId: currentUserId
        )
        if eligible.contains(where: { $0.userId == currentUserId }) {
            return currentUserId
        }
        if let receiverUserId = recipient?.receiverUserId,
           eligible.contains(where: { $0.userId == receiverUserId }) {
            return receiverUserId
        }
        return eligible.first?.userId
    }

    static func canToggleFromList(_ task: CareTask) -> Bool {
        if task.status == .done || task.status == .skipped {
            return task.capabilities?.canChangeStatus ?? false
        }
        return task.capabilities?.canMarkDone ?? false
    }

    static func detailPresentation(
        for task: CareTask,
        currentUserId: String,
        role: MemberRole,
        selectedRecipient: CareRecipient?,
        statusOverride: TaskStatus? = nil,
        now: Date = Date()
    ) -> TaskDetailPresentation {
        let status = statusOverride ?? task.status
        let isOrganizer = role == .admin
        let isReceiver = role == .recipient
        let isOwn = task.creatorId == currentUserId
        let isAssignee = task.assigneeId == currentUserId
        let capabilities = task.capabilities
        let canEdit = capabilities?.canEdit ?? (isOrganizer || isOwn)
        let canDelete = capabilities?.canDelete ?? canEdit
        let canAssign = capabilities?.canAssign ?? isOrganizer
        let canChangeRecipient = capabilities?.canChangeRecipient ?? canEdit
        let canChangeStatus = capabilities?.canChangeStatus ?? !isReceiver
        let canMarkDone = capabilities?.canMarkDone ?? (isOrganizer || isOwn || isAssignee)
        let canSkip = status.isOpen && (capabilities?.canSkip ?? (isOrganizer || isOwn))
        let canComment = capabilities?.canComment ?? true
        let canSnoozeReminder = task.dueAt != nil
            && status.isOpen
            && (isOrganizer || isAssignee || isOwn)

        return TaskDetailPresentation(
            displayState: detailDisplayState(for: task, status: status, now: now),
            permissions: TaskDetailPermissions(
                canEdit: canEdit,
                canDelete: canDelete,
                canAssign: canAssign,
                canChangeRecipient: canChangeRecipient,
                canChangeStatus: canChangeStatus,
                canMarkDone: canMarkDone,
                canSkip: canSkip,
                canComment: canComment,
                canSnoozeReminder: canSnoozeReminder
            ),
            blockedReason: taskBlockedReason(for: selectedRecipient),
            recurrenceBlockReason: recurrenceBlockReason(for: task, selectedRecipient: selectedRecipient)
        )
    }

    static func detailDisplayState(
        for task: CareTask,
        status: TaskStatus? = nil,
        now: Date = Date()
    ) -> TaskDetailDisplayState {
        switch status ?? task.status {
        case .done:
            return .done
        case .skipped:
            return .skipped
        case .inProgress:
            return .inProgress
        case .pending:
            guard let dueAt = task.dueAt, dueAt < now else { return .pending }
            if now.timeIntervalSince(dueAt) >= escalationGraceInterval {
                return .escalated
            }
            return .overdue
        }
    }

    private static func assigneeSortRank(
        member: CircleMember,
        recipient: CareRecipient?,
        currentUserId: String
    ) -> Int {
        if member.userId == currentUserId { return 0 }
        if member.userId == recipient?.receiverUserId { return 1 }
        if member.role == .admin { return 2 }
        return 3
    }

    private static func taskBlockedReason(for recipient: CareRecipient?) -> String? {
        guard let recipient, !recipient.isActiveForTasks else { return nil }
        return "\(recipient.name) must accept the invite or be proxy activated before new task actions are available."
    }

    private static func recurrenceBlockReason(for task: CareTask, selectedRecipient: CareRecipient?) -> String? {
        guard task.recurrenceFrequency != .none else { return nil }
        guard !ReceiverPremiumPolicy.supportsRecurringSchedules(for: selectedRecipient) else { return nil }
        let name = selectedRecipient?.name ?? "this care receiver"
        return "Recurring tasks require Premium for \(name)."
    }
}

private extension TaskStatus {
    var isOpen: Bool {
        self != .done && self != .skipped
    }
}
