import Foundation

struct CareTask: Identifiable, Codable, Hashable {
    static func == (lhs: CareTask, rhs: CareTask) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.notes == rhs.notes &&
        lhs.dueAt == rhs.dueAt &&
        lhs.status == rhs.status &&
        lhs.priority == rhs.priority &&
        lhs.recurrenceFrequency == rhs.recurrenceFrequency &&
        lhs.recurrenceInterval == rhs.recurrenceInterval &&
        lhs.recurrenceWeekdays == rhs.recurrenceWeekdays &&
        lhs.recurrenceEndsAt == rhs.recurrenceEndsAt &&
        lhs.seriesId == rhs.seriesId &&
        lhs.completedAt == rhs.completedAt &&
        lhs.archivedAt == rhs.archivedAt &&
        lhs.circleId == rhs.circleId &&
        lhs.recipientId == rhs.recipientId &&
        lhs.recipient == rhs.recipient &&
        lhs.creatorId == rhs.creatorId &&
        lhs.assigneeId == rhs.assigneeId &&
        lhs.capabilities == rhs.capabilities &&
        lhs.assignee?.id == rhs.assignee?.id &&
        lhs.assignee?.name == rhs.assignee?.name &&
        lhs.assignee?.email == rhs.assignee?.email &&
        lhs.assignee?.phone == rhs.assignee?.phone &&
        lhs.assignee?.pushToken == rhs.assignee?.pushToken &&
        lhs.assignee?.timezone == rhs.assignee?.timezone &&
        lhs.completedBy?.id == rhs.completedBy?.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(notes)
        hasher.combine(dueAt)
        hasher.combine(status)
        hasher.combine(priority)
        hasher.combine(recurrenceFrequency)
        hasher.combine(recurrenceInterval)
        hasher.combine(recurrenceWeekdays)
        hasher.combine(recurrenceEndsAt)
        hasher.combine(seriesId)
        hasher.combine(completedAt)
        hasher.combine(archivedAt)
        hasher.combine(circleId)
        hasher.combine(recipientId)
        hasher.combine(recipient)
        hasher.combine(creatorId)
        hasher.combine(assigneeId)
        hasher.combine(capabilities)
        hasher.combine(assignee?.id)
        hasher.combine(assignee?.name)
        hasher.combine(assignee?.email)
        hasher.combine(assignee?.phone)
        hasher.combine(assignee?.pushToken)
        hasher.combine(assignee?.timezone)
        hasher.combine(completedBy?.id)
    }

    let id: String
    let title: String
    let notes: String?
    let dueAt: Date?
    var status: TaskStatus
    let priority: TaskPriority
    let recurrenceFrequency: TaskRecurrenceFrequency
    let recurrenceInterval: Int?
    let recurrenceWeekdays: [String]
    let recurrenceEndsAt: Date?
    let seriesId: String?
    let completedAt: Date?
    let completedById: String?
    let completedBy: CareUser?
    let archivedAt: Date?
    let circleId: String
    let recipientId: String?
    let recipient: CareRecipient?
    let creatorId: String
    let assigneeId: String?
    var assignee: CareUser?
    let capabilities: CareTaskCapabilities?

    init(
        id: String,
        title: String,
        notes: String?,
        dueAt: Date?,
        status: TaskStatus,
        priority: TaskPriority,
        recurrenceFrequency: TaskRecurrenceFrequency = .none,
        recurrenceInterval: Int? = nil,
        recurrenceWeekdays: [String] = [],
        recurrenceEndsAt: Date? = nil,
        seriesId: String? = nil,
        completedAt: Date?,
        completedById: String? = nil,
        completedBy: CareUser? = nil,
        archivedAt: Date?,
        circleId: String,
        recipientId: String? = nil,
        recipient: CareRecipient? = nil,
        creatorId: String,
        assigneeId: String?,
        assignee: CareUser?,
        capabilities: CareTaskCapabilities? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.status = status
        self.priority = priority
        self.recurrenceFrequency = recurrenceFrequency
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceWeekdays = recurrenceWeekdays
        self.recurrenceEndsAt = recurrenceEndsAt
        self.seriesId = seriesId
        self.completedAt = completedAt
        self.completedById = completedById
        self.completedBy = completedBy
        self.archivedAt = archivedAt
        self.circleId = circleId
        self.recipientId = recipientId
        self.recipient = recipient
        self.creatorId = creatorId
        self.assigneeId = assigneeId
        self.assignee = assignee
        self.capabilities = capabilities
    }

    var isOverdue: Bool {
        guard let due = dueAt else { return false }
        return due < Date() && status == .pending
    }

    var recurrence: TaskRecurrence? {
        guard recurrenceFrequency != .none else { return nil }
        return TaskRecurrence(
            frequency: recurrenceFrequency,
            interval: recurrenceInterval,
            weekdays: recurrenceWeekdays,
            endsAt: recurrenceEndsAt
        )
    }

    var canToggleCompletion: Bool {
        TaskWorkflowPolicy.canToggleFromList(self)
    }

    func withUpdatedStatus(_ nextStatus: TaskStatus, completedAt: Date?, completedBy: CareUser?) -> CareTask {
        CareTask(
            id: id,
            title: title,
            notes: notes,
            dueAt: dueAt,
            status: nextStatus,
            priority: priority,
            recurrenceFrequency: recurrenceFrequency,
            recurrenceInterval: recurrenceInterval,
            recurrenceWeekdays: recurrenceWeekdays,
            recurrenceEndsAt: recurrenceEndsAt,
            seriesId: seriesId,
            completedAt: completedAt,
            completedById: completedBy?.id,
            completedBy: completedBy,
            archivedAt: archivedAt,
            circleId: circleId,
            recipientId: recipientId,
            recipient: recipient,
            creatorId: creatorId,
            assigneeId: assigneeId,
            assignee: assignee,
            capabilities: capabilities
        )
    }
}

struct CareTaskCapabilities: Codable, Hashable {
    let canEdit: Bool
    let canDelete: Bool
    let canAssign: Bool
    let canChangeRecipient: Bool
    let canChangeStatus: Bool
    let canMarkDone: Bool
    let canSkip: Bool
    let canComment: Bool
}

struct ReminderSnoozeResult: Codable, Hashable {
    let id: String
    let taskId: String
    let scheduledAt: Date
    let sentAt: Date?
    let snoozedUntil: Date?
    let snoozeCount: Int
    let escalationDueAt: Date?
    let status: ReminderStatus
    let escalatedAt: Date?
}

enum ReminderStatus: String, Codable, Hashable {
    case pending = "PENDING"
    case snoozed = "SNOOZED"
    case sent = "SENT"
    case failed = "FAILED"
    case escalated = "ESCALATED"
    case cancelled = "CANCELLED"
}

struct TaskComment: Identifiable, Codable, Equatable {
    let id: String
    let body: String
    let createdAt: Date
    let authorId: String
    let author: CommentAuthor?

    static func == (lhs: TaskComment, rhs: TaskComment) -> Bool {
        lhs.id == rhs.id && lhs.body == rhs.body
    }
}

struct CommentAuthor: Codable, Equatable {
    let id: String
    let name: String
}

struct TaskRecurrence: Codable, Hashable {
    let frequency: TaskRecurrenceFrequency
    let interval: Int?
    let weekdays: [String]
    let endsAt: Date?

    var summary: String {
        switch frequency {
        case .none:
            return "Does not repeat"
        case .daily:
            return intervalValue == 1 ? "Daily" : "Every \(intervalValue) days"
        case .weekly:
            if !normalizedWeekdays.isEmpty {
                let weekdayLabels = normalizedWeekdays.map(\.summaryLabel).joined(separator: ", ")
                return intervalValue == 1
                    ? "Every week on \(weekdayLabels)"
                    : "Every \(intervalValue) weeks on \(weekdayLabels)"
            }
            return intervalValue == 1 ? "Weekly" : "Every \(intervalValue) weeks"
        case .monthly:
            return intervalValue == 1 ? "Monthly" : "Every \(intervalValue) months"
        case .custom:
            return "Every \(intervalValue) days"
        }
    }

    var normalizedWeekdays: [TaskWeekday] {
        weekdays
            .compactMap(TaskWeekday.init(rawValue:))
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var intervalValue: Int {
        max(1, interval ?? 1)
    }
}

enum TaskWeekday: String, Codable, CaseIterable, Hashable, Identifiable {
    case sun = "SUN"
    case mon = "MON"
    case tue = "TUE"
    case wed = "WED"
    case thu = "THU"
    case fri = "FRI"
    case sat = "SAT"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .sun: return 0
        case .mon: return 1
        case .tue: return 2
        case .wed: return 3
        case .thu: return 4
        case .fri: return 5
        case .sat: return 6
        }
    }

    var pillLabel: String {
        switch self {
        case .sun: return "S"
        case .mon: return "M"
        case .tue: return "T"
        case .wed: return "W"
        case .thu: return "T"
        case .fri: return "F"
        case .sat: return "S"
        }
    }

    var summaryLabel: String {
        switch self {
        case .sun: return "Sun"
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        }
    }

    var fullLabel: String {
        switch self {
        case .sun: return "Sunday"
        case .mon: return "Monday"
        case .tue: return "Tuesday"
        case .wed: return "Wednesday"
        case .thu: return "Thursday"
        case .fri: return "Friday"
        case .sat: return "Saturday"
        }
    }

    static func from(date: Date, calendar: Calendar = .current) -> TaskWeekday {
        switch calendar.component(.weekday, from: date) {
        case 1: return .sun
        case 2: return .mon
        case 3: return .tue
        case 4: return .wed
        case 5: return .thu
        case 6: return .fri
        default: return .sat
        }
    }
}

enum TaskStatus: String, Codable {
    case pending    = "PENDING"
    case inProgress = "IN_PROGRESS"
    case done       = "DONE"
    case skipped    = "SKIPPED"

    var label: String {
        switch self {
        case .pending:    return "Pending"
        case .inProgress: return "In Progress"
        case .done:       return "Done"
        case .skipped:    return "Skipped"
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable {
    case low    = "LOW"
    case normal = "NORMAL"
    case high   = "HIGH"
    case urgent = "URGENT"

    var label: String { rawValue.capitalized }
}

enum TaskRecurrenceFrequency: String, Codable, CaseIterable {
    case none = "NONE"
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case custom = "CUSTOM"

    var label: String {
        switch self {
        case .none:
            return "Does not repeat"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .custom:
            return "Custom"
        }
    }
}
