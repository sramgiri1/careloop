import Foundation

struct ReceiverDashboardSummary: Identifiable, Equatable {
    let recipient: CareRecipient
    let openCount: Int
    let overdueCount: Int
    let completedCount: Int
    let supportingCaregiverCount: Int
    let nextDueAt: Date?
    let nextTaskTitle: String?

    var id: String { recipient.id }
}

enum CircleHomePolicy {
    static func activeRecipients(in circle: CareCircle) -> [CareRecipient] {
        circle.orderedRecipients.filter(\.isActiveForTasks)
    }

    static func receiverSummaries(in circle: CareCircle, tasks: [CareTask]) -> [ReceiverDashboardSummary] {
        circle.orderedRecipients.map { recipient in
            let recipientTasks = tasks.filter { $0.recipientId == recipient.id }
            let openTasks = recipientTasks.filter { !$0.isClosed }
            let nextTask = nextDueTask(in: openTasks)
            let supportingCaregiverCount = (circle.members ?? []).filter { member in
                member.role != .recipient && recipient.eligibleAssigneeIds.contains(member.userId)
            }.count

            return ReceiverDashboardSummary(
                recipient: recipient,
                openCount: openTasks.filter { !$0.isOverdue }.count,
                overdueCount: openTasks.filter(\.isOverdue).count,
                completedCount: recipientTasks.filter(\.isClosed).count,
                supportingCaregiverCount: supportingCaregiverCount,
                nextDueAt: nextTask?.dueAt,
                nextTaskTitle: nextTask?.title
            )
        }
    }

    static func nextDueTask(in tasks: [CareTask]) -> CareTask? {
        sortedOpenTasks(tasks).first
    }

    static func remainingOpenTasks(after taskId: String?, in tasks: [CareTask], limit: Int) -> [CareTask] {
        let ordered = sortedOpenTasks(tasks)
        guard let taskId else {
            return Array(ordered.prefix(limit))
        }
        return Array(ordered.filter { $0.id != taskId }.prefix(limit))
    }

    static func dueTodayCount(in tasks: [CareTask]) -> Int {
        let calendar = Calendar.current
        return tasks.filter { task in
            guard !task.isClosed, let dueAt = task.dueAt else { return false }
            return calendar.isDateInToday(dueAt)
        }.count
    }

    private static func sortedOpenTasks(_ tasks: [CareTask]) -> [CareTask] {
        tasks
            .filter { !$0.isClosed }
            .sorted { lhs, rhs in
                switch (lhs.dueAt, rhs.dueAt) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
    }
}

private extension CareTask {
    var isClosed: Bool {
        status == .done || status == .skipped
    }
}
