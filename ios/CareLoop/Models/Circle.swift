import Foundation

struct CareCircle: Identifiable, Codable {
    let id: String
    let name: String
    let recipientName: String
    let archiveAfterDays: Int
    var members: [CircleMember]?
    var recipients: [CareRecipient]?
    var tasks: [CareTask]?

    init(id: String, name: String, recipientName: String, archiveAfterDays: Int = 7, members: [CircleMember]? = nil, recipients: [CareRecipient]? = nil, tasks: [CareTask]? = nil) {
        self.id = id
        self.name = name
        self.recipientName = recipientName
        self.archiveAfterDays = archiveAfterDays
        self.members = members
        self.recipients = recipients
        self.tasks = tasks
    }

    var orderedRecipients: [CareRecipient] {
        (recipients ?? []).sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary && !rhs.isPrimary }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var primaryRecipient: CareRecipient? {
        orderedRecipients.first
    }

    var recipientDisplaySummary: String {
        let names = recipientNames
        switch names.count {
        case 0:  return ""
        case 1:  return names[0]
        case 2:  return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) + \(names.count - 1) more"
        }
    }

    var recipientNames: [String] {
        let explicit = orderedRecipients
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !explicit.isEmpty { return explicit }
        let fallback = recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [fallback]
    }
}

struct CareRecipient: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let relationship: String?
    let notes: String?
    let isPrimary: Bool
    let sortOrder: Int
    let activationStatus: CareReceiverActivationStatus
    let receiverUserId: String?
    let eligibleAssigneeIds: [String]
    let premium: CareRecipientPremium

    init(
        id: String,
        name: String,
        relationship: String? = nil,
        notes: String? = nil,
        isPrimary: Bool = false,
        sortOrder: Int = 0,
        activationStatus: CareReceiverActivationStatus = .draft,
        receiverUserId: String? = nil,
        eligibleAssigneeIds: [String] = [],
        premium: CareRecipientPremium = .free
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.notes = notes
        self.isPrimary = isPrimary
        self.sortOrder = sortOrder
        self.activationStatus = activationStatus
        self.receiverUserId = receiverUserId
        self.eligibleAssigneeIds = eligibleAssigneeIds
        self.premium = premium
    }

    var isActiveForTasks: Bool {
        activationStatus == .active || activationStatus == .proxyActive
    }

    var activationStatusLabel: String {
        switch activationStatus {
        case .draft: return "Draft"
        case .invited: return "Invited"
        case .active: return "Active"
        case .proxyActive: return "Proxy Active"
        }
    }

    var activationStatusDetail: String {
        switch activationStatus {
        case .draft:
            return "Profile created. Tasks stay blocked until they join or a proxy is authorized."
        case .invited:
            return "Invite sent. Tasks stay blocked until they join or a proxy is authorized."
        case .active:
            return "Joined and ready for direct task coordination."
        case .proxyActive:
            return "Activated by a Care Organizer with recorded consent."
        }
    }

    var hasPremium: Bool {
        premium.hasPremium
    }

    var hasExpiredPremium: Bool {
        if premium.status == .expired { return true }
        guard premium.status == .active, let expiresAt = premium.expiresAt else { return false }
        return expiresAt <= Date()
    }

    var premiumStatusLabel: String {
        if premium.hasPremium { return "Premium" }
        if premium.status == .revoked { return "Revoked" }
        if premium.status == .billingRetry { return "Billing retry" }
        if premium.status == .refunded { return "Refunded" }
        if hasExpiredPremium { return "Expired" }
        return "Free"
    }

    var premiumStatusIconName: String {
        if premium.hasPremium { return "crown.fill" }
        if premium.status == .revoked || premium.status == .billingRetry || premium.status == .refunded || hasExpiredPremium {
            return "exclamationmark.triangle.fill"
        }
        return "crown"
    }

    var premiumStatusAccessibilityLabel: String {
        "\(name) plan: \(premiumStatusLabel)"
    }

    var premiumStatusDetail: String {
        if premium.hasPremium {
            if let expiresAt = premium.expiresAt {
                return "Premium receiver features active until \(expiresAt.formatted(.dateTime.month().day().year()))."
            }
            return "Premium receiver features are active."
        }
        if premium.status == .revoked {
            return "Premium was revoked for this care receiver. Existing care history remains visible, but new premium actions are blocked."
        }
        if premium.status == .billingRetry {
            return "Premium billing needs attention for this care receiver. Existing care history remains visible, but new premium actions are blocked until billing recovers."
        }
        if premium.status == .refunded {
            return "Premium was refunded for this care receiver. Existing care history remains visible, but new premium actions are blocked."
        }
        if hasExpiredPremium {
            if let expiresAt = premium.expiresAt {
                return "Premium expired on \(expiresAt.formatted(.dateTime.month().day().year())). Existing care history remains visible, but new premium actions are blocked."
            }
            return "Premium expired for this care receiver. Existing care history remains visible, but new premium actions are blocked."
        }
        return "Basic tasks and reminders only. Upgrade this care receiver to unlock recurring schedules, insights, and unlimited caregivers."
    }

    var premiumPlanSummaryLabel: String {
        hasPremium ? "Premium plan active" : "\(premiumStatusLabel) plan"
    }

    var caregiverAccessSummary: String {
        premium.capabilities.canUseUnlimitedCaregivers
            ? "Unlimited caregivers"
            : "1 caregiver included"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case relationship
        case notes
        case isPrimary
        case sortOrder
        case activationStatus
        case receiverUserId
        case eligibleAssigneeIds
        case premium
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        relationship = try container.decodeIfPresent(String.self, forKey: .relationship)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        activationStatus = try container.decodeIfPresent(CareReceiverActivationStatus.self, forKey: .activationStatus) ?? .draft
        receiverUserId = try container.decodeIfPresent(String.self, forKey: .receiverUserId)
        eligibleAssigneeIds = try container.decodeIfPresent([String].self, forKey: .eligibleAssigneeIds) ?? []
        premium = try container.decodeIfPresent(CareRecipientPremium.self, forKey: .premium) ?? .free
    }
}

struct CareRecipientPremium: Codable, Hashable {
    let status: CareRecipientEntitlementStatus
    let source: CareRecipientEntitlementSource?
    let startsAt: Date?
    let expiresAt: Date?
    let appleOriginalTransactionId: String?
    let appleProductId: String?
    let hasPremium: Bool
    let capabilities: CareRecipientPremiumCapabilities

    static let free = CareRecipientPremium(
        status: .free,
        source: nil,
        startsAt: nil,
        expiresAt: nil,
        appleOriginalTransactionId: nil,
        appleProductId: nil,
        hasPremium: false,
        capabilities: .free
    )
}

struct CareRecipientPremiumCapabilities: Codable, Hashable {
    let hasPremium: Bool
    let canUseAdvancedReminders: Bool
    let canUseInsights: Bool
    let canUseUnlimitedCaregivers: Bool
    let canUseAdvancedCoordination: Bool

    static let free = CareRecipientPremiumCapabilities(
        hasPremium: false,
        canUseAdvancedReminders: false,
        canUseInsights: false,
        canUseUnlimitedCaregivers: false,
        canUseAdvancedCoordination: false
    )
}

struct PremiumUpgradeRequest: Identifiable, Codable, Hashable {
    let id: String
    let circleId: String
    let recipientId: String
    let requesterUserId: String
    let createdAt: Date?
}

struct PremiumUpgradeRequestSummary: Identifiable, Codable, Hashable {
    let recipientId: String
    let recipientName: String
    let requestCount: Int
    let latestRequesterName: String?
    let latestRequesterId: String?
    let latestRequestedAt: Date?

    var id: String { recipientId }
}

enum CareRecipientEntitlementStatus: String, Codable {
    case free = "FREE"
    case active = "ACTIVE"
    case expired = "EXPIRED"
    case revoked = "REVOKED"
    case billingRetry = "BILLING_RETRY"
    case refunded = "REFUNDED"
}

enum CareRecipientEntitlementSource: String, Codable {
    case appStore = "APP_STORE"
    case manual = "MANUAL"
}

enum ReceiverPremiumPolicy {
    static func premiumRecipients(in circle: CareCircle?) -> [CareRecipient] {
        guard let circle else { return [] }
        return circle.orderedRecipients.filter(\.hasPremium)
    }

    static func freeRecipients(in circle: CareCircle?) -> [CareRecipient] {
        guard let circle else { return [] }
        return circle.orderedRecipients.filter { !$0.hasPremium }
    }

    static func defaultPaywallRecipient(in circle: CareCircle?) -> CareRecipient? {
        guard let circle else { return nil }
        return freeRecipients(in: circle).first(where: \.isActiveForTasks)
            ?? freeRecipients(in: circle).first
            ?? circle.primaryRecipient
    }

    static func supportsInsights(for recipient: CareRecipient?) -> Bool {
        recipient?.premium.capabilities.canUseInsights == true
    }

    static func supportsRecurringSchedules(for recipient: CareRecipient?) -> Bool {
        recipient?.premium.capabilities.canUseAdvancedReminders == true
    }

    static func allVisibleRecipientsSupportInsights(in circle: CareCircle?) -> Bool {
        let recipients = circle?.orderedRecipients ?? []
        guard !recipients.isEmpty else { return false }
        return recipients.allSatisfy(\.premium.capabilities.canUseInsights)
    }

    static func upgradePromptTitle(for recipient: CareRecipient) -> String {
        "Unlock Premium for \(recipient.name)"
    }

    static func upgradePromptSubtitle(for recipient: CareRecipient) -> String {
        recipient.premiumStatusDetail
    }
}

enum CareReceiverActivationStatus: String, Codable, CaseIterable {
    case draft = "DRAFT"
    case invited = "INVITED"
    case active = "ACTIVE"
    case proxyActive = "PROXY_ACTIVE"

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .invited: return "Invited"
        case .active: return "Active"
        case .proxyActive: return "Proxy Active"
        }
    }
}

struct CircleMember: Identifiable, Codable {
    let id: String
    let role: MemberRole
    let userId: String
    var user: CareUser?
}

struct RecipientAccessSummary: Identifiable, Codable, Hashable {
    let recipientId: String
    let name: String
    let activationStatus: CareReceiverActivationStatus
    let hasAccess: Bool
    let grantedAt: Date?

    var id: String { recipientId }

    private enum CodingKeys: String, CodingKey {
        case recipientId
        case name
        case activationStatus
        case hasAccess
        case grantedAt
    }

    init(
        recipientId: String,
        name: String,
        activationStatus: CareReceiverActivationStatus,
        hasAccess: Bool,
        grantedAt: Date?
    ) {
        self.recipientId = recipientId
        self.name = name
        self.activationStatus = activationStatus
        self.hasAccess = hasAccess
        self.grantedAt = grantedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recipientId = try container.decode(String.self, forKey: .recipientId)
        name = try container.decode(String.self, forKey: .name)
        activationStatus = try container.decode(CareReceiverActivationStatus.self, forKey: .activationStatus)
        hasAccess = try container.decode(Bool.self, forKey: .hasAccess)

        if let grantedAtString = try container.decodeIfPresent(String.self, forKey: .grantedAt) {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]

            if let date = fractional.date(from: grantedAtString) ?? basic.date(from: grantedAtString) {
                grantedAt = date
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .grantedAt,
                    in: container,
                    debugDescription: "Cannot decode ISO8601 date: \(grantedAtString)"
                )
            }
        } else {
            grantedAt = nil
        }
    }
}

enum MemberRole: String, Codable, CaseIterable {
    case admin     = "ADMIN"
    case member    = "MEMBER"
    case recipient = "RECIPIENT"

    var displayLabel: String {
        switch self {
        case .admin:     return "Care Organizer"
        case .member:    return "Caregiver"
        case .recipient: return "Care Receiver"
        }
    }
}

struct CircleEvent: Identifiable, Codable {
    let id: String
    let type: CircleEventType
    let createdAt: Date
    let actorId: String?
    let actor: EventActor?

    var actorFirstName: String {
        guard let name = actor?.name else { return "Someone" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    var feedDescription: String {
        let who = actorFirstName
        switch type {
        case .circleCreated:        return "\(who) created this circle"
        case .taskCreated:          return "\(who) added a task"
        case .taskSeriesCreated:    return "\(who) added a recurring task"
        case .taskCompleted:        return "\(who) completed a task"
        case .taskUpdated:          return "\(who) updated a task"
        case .taskDeleted:          return "\(who) deleted a task"
        case .inviteCreated:        return "\(who) sent an invitation"
        case .inviteAccepted:       return "\(who) joined the circle"
        case .inviteDeclined:       return "\(who) declined an invitation"
        case .inviteRevoked:        return "\(who) revoked an invitation"
        case .recipientAdded:       return "\(who) added a care receiver"
        case .recipientUpdated:     return "\(who) updated care receiver info"
        case .recipientRemoved:     return "\(who) removed a care receiver"
        case .memberJoined:         return "\(who) joined via circle code"
        case .memberRemoved:        return "\(who) removed a member"
        case .memberRoleUpdated:    return "\(who) updated a member's role"
        case .reminderSent:        return "CareLoop sent a reminder"
        case .reminderEscalated:   return "CareLoop escalated a task"
        case .digestSent,
             .digestOpened,
             .appSession,
             .unknown:              return ""
        }
    }

    var isVisible: Bool { !feedDescription.isEmpty }

    func feedDescription(for viewerRole: MemberRole) -> String {
        if viewerRole == .admin {
            return feedDescription
        }

        switch type {
        case .taskCreated:
            return "A task was added"
        case .taskSeriesCreated:
            return "A recurring task was added"
        case .taskCompleted:
            return "A task was completed"
        case .taskUpdated:
            return "A task was updated"
        case .taskDeleted:
            return "A task was removed"
        case .recipientAdded:
            return "A care receiver was added"
        case .recipientUpdated:
            return "Care receiver details were updated"
        case .recipientRemoved:
            return "A care receiver was removed"
        case .reminderSent:
            return "A reminder was sent"
        case .reminderEscalated:
            return "A care task still needs attention"
        default:
            return ""
        }
    }

    func isVisible(to viewerRole: MemberRole) -> Bool {
        !feedDescription(for: viewerRole).isEmpty
    }

    var feedIcon: String {
        switch type {
        case .taskCreated, .taskSeriesCreated:  return "plus.circle.fill"
        case .taskCompleted:                    return "checkmark.circle.fill"
        case .taskUpdated:                      return "pencil.circle.fill"
        case .taskDeleted:                      return "trash.circle.fill"
        case .inviteCreated, .inviteAccepted,
             .inviteDeclined, .inviteRevoked,
             .memberJoined, .memberRemoved,
             .memberRoleUpdated:                return "person.circle.fill"
        case .recipientAdded, .recipientUpdated,
             .recipientRemoved:                 return "heart.circle.fill"
        case .circleCreated:                    return "star.circle.fill"
        case .reminderSent:                     return "bell.circle.fill"
        case .reminderEscalated:                return "exclamationmark.octagon.fill"
        default:                                return "circle.fill"
        }
    }

    var feedIconColor: (red: Double, green: Double, blue: Double) {
        switch type {
        case .taskCompleted:                    return (0.12, 0.68, 0.49)
        case .reminderEscalated:                return (0.85, 0.30, 0.30)
        case .reminderSent:                     return (0.13, 0.56, 0.87)
        case .taskDeleted:                      return (0.85, 0.30, 0.30)
        case .taskCreated, .taskSeriesCreated,
             .taskUpdated:                      return (0.13, 0.56, 0.87)
        case .inviteAccepted, .memberJoined:    return (0.16, 0.80, 0.72)
        case .recipientAdded, .recipientUpdated,
             .recipientRemoved:                 return (0.85, 0.30, 0.50)
        default:                                return (0.43, 0.50, 0.60)
        }
    }
}

struct EventActor: Codable {
    let id: String
    let name: String
}

enum CircleEventType: String, Codable {
    case circleCreated       = "CIRCLE_CREATED"
    case inviteCreated       = "INVITE_CREATED"
    case inviteAccepted      = "INVITE_ACCEPTED"
    case inviteDeclined      = "INVITE_DECLINED"
    case inviteRevoked       = "INVITE_REVOKED"
    case recipientAdded      = "RECIPIENT_ADDED"
    case recipientUpdated    = "RECIPIENT_UPDATED"
    case recipientRemoved    = "RECIPIENT_REMOVED"
    case taskCreated         = "TASK_CREATED"
    case taskSeriesCreated   = "TASK_SERIES_CREATED"
    case taskUpdated         = "TASK_UPDATED"
    case taskCompleted       = "TASK_COMPLETED"
    case taskDeleted         = "TASK_DELETED"
    case memberJoined        = "MEMBER_JOINED"
    case memberRemoved       = "MEMBER_REMOVED"
    case memberRoleUpdated   = "MEMBER_ROLE_UPDATED"
    case reminderSent        = "REMINDER_SENT"
    case reminderEscalated   = "REMINDER_ESCALATED"
    case digestSent          = "DIGEST_SENT"
    case digestOpened        = "DIGEST_OPENED"
    case appSession          = "APP_SESSION"
    case unknown = "__unknown__"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CircleEventType(rawValue: raw) ?? .unknown
    }
}
