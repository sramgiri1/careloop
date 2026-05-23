import Foundation

#if DEBUG
enum UITestScenario: String {
    case circleDirectory = "circle-directory"
    case organizerHome = "organizer-home"
    case caregiverHome = "caregiver-home"
    case receiverHome = "receiver-home"
    case taskComments = "task-comments"
    case inactiveReceiverTask = "inactive-receiver-task"
    case recipientInvite = "recipient-invite"
    case caregiverInvite = "caregiver-invite"
    case inviteEdgeStates = "invite-edge-states"
    case premiumBillingStates = "premium-billing-states"

    private static let launchArgument = "-careloop-ui-scenario"
    private static let pendingTaskLaunchArgument = "-careloop-ui-pending-task"
    private static let pendingTaskCircleLaunchArgument = "-careloop-ui-pending-circle"

    static var current: UITestScenario? {
        #if DEBUG
        parse(ProcessInfo.processInfo.arguments)
        #else
        nil
        #endif
    }

    static func parse(_ arguments: [String]) -> UITestScenario? {
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return UITestScenario(rawValue: arguments[index + 1])
    }

    static func pendingTaskId(_ arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: pendingTaskLaunchArgument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    static func pendingTaskCircleId(_ arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: pendingTaskCircleLaunchArgument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

extension AppState {
    convenience init(uiTestScenario scenario: UITestScenario) {
        self.init(shouldRestoreSession: false)

        let fixture = UITestScenarioFixture.make(scenario)
        currentUser = fixture.user
        if scenario == .recipientInvite || scenario == .caregiverInvite || scenario == .inviteEdgeStates {
            currentUser?.pendingInvites = fixture.invitations
        }
        activeCircle = scenario == .circleDirectory || scenario == .recipientInvite || scenario == .caregiverInvite || scenario == .inviteEdgeStates ? nil : fixture.circle
        uiTestInvitations = fixture.invitations
        uiTestRecipientAccessByMemberId = fixture.recipientAccessByMemberId
        uiTestPremiumUpgradeRequests = fixture.premiumUpgradeRequests
        uiTestEvents = fixture.events
        uiTestCompletionInsights = fixture.completionInsights
        pendingTaskId = UITestScenario.pendingTaskId(ProcessInfo.processInfo.arguments) ?? fixture.pendingTaskId
        pendingTaskCircleId = UITestScenario.pendingTaskCircleId(ProcessInfo.processInfo.arguments)
        shouldPromptNewTask = false
    }
}

private struct UITestScenarioFixture {
    let user: CareUser
    let circle: CareCircle
    let invitations: [GroupInvitation]
    let recipientAccessByMemberId: [String: [RecipientAccessSummary]]
    let premiumUpgradeRequests: [PremiumUpgradeRequestSummary]
    let events: [CircleEvent]
    let completionInsights: CircleCompletionInsights?
    let pendingTaskId: String?

    static func make(_ scenario: UITestScenario) -> UITestScenarioFixture {
        let organizer = CareUser(id: "u1", email: "organizer@careloop.test", name: "Olivia Organizer", phone: nil, memberships: nil)
        let caregiver = CareUser(id: "u2", email: "caregiver@careloop.test", name: "Carlos Caregiver", phone: nil, memberships: nil)
        let backupCaregiver = CareUser(id: "u3", email: "backup@careloop.test", name: "Bianca Backup", phone: nil, memberships: nil)
        let mom = CareUser(id: "u4", email: "mom@careloop.test", name: "Maya Receiver", phone: nil, memberships: nil)
        let dad = CareUser(id: "u5", email: "dad@careloop.test", name: "David Receiver", phone: nil, memberships: nil)
        let organizerActor = EventActor(id: organizer.id, name: organizer.name)
        let caregiverActor = EventActor(id: caregiver.id, name: caregiver.name)
        let premiumCapabilities = CareRecipientPremiumCapabilities(
            hasPremium: true,
            canUseAdvancedReminders: true,
            canUseInsights: true,
            canUseUnlimitedCaregivers: true,
            canUseAdvancedCoordination: true
        )

        let allMembers = [
            CircleMember(id: "m1", role: .admin, userId: organizer.id, user: organizer),
            CircleMember(id: "m2", role: .member, userId: caregiver.id, user: caregiver),
            CircleMember(id: "m3", role: .member, userId: backupCaregiver.id, user: backupCaregiver),
            CircleMember(id: "m4", role: .recipient, userId: mom.id, user: mom),
            CircleMember(id: "m5", role: .recipient, userId: dad.id, user: dad),
        ]

        let momRecipient = CareRecipient(
            id: "r1",
            name: "Maya",
            relationship: "Mom",
            notes: nil,
            isPrimary: true,
            sortOrder: 0,
            activationStatus: .active,
            receiverUserId: mom.id,
            eligibleAssigneeIds: [organizer.id, caregiver.id, backupCaregiver.id, mom.id],
            premium: CareRecipientPremium(
                status: .active,
                source: .appStore,
                startsAt: Date().addingTimeInterval(-14 * 24 * 60 * 60),
                expiresAt: Date().addingTimeInterval(14 * 24 * 60 * 60),
                appleOriginalTransactionId: "ui-premium-maya",
                appleProductId: "com.careloop.ios.premium.yearly",
                hasPremium: true,
                capabilities: premiumCapabilities
            )
        )
        let dadRecipient = CareRecipient(
            id: "r2",
            name: "David",
            relationship: "Dad",
            notes: nil,
            isPrimary: false,
            sortOrder: 1,
            activationStatus: .invited,
            receiverUserId: nil,
            eligibleAssigneeIds: [organizer.id, backupCaregiver.id],
            premium: .free
        )
        let billingRetryRecipient = CareRecipient(
            id: "r3",
            name: "Elena",
            relationship: "Aunt",
            notes: nil,
            isPrimary: false,
            sortOrder: 2,
            activationStatus: .active,
            receiverUserId: nil,
            eligibleAssigneeIds: [organizer.id, caregiver.id],
            premium: CareRecipientPremium(
                status: .billingRetry,
                source: .appStore,
                startsAt: Date().addingTimeInterval(-20 * 24 * 60 * 60),
                expiresAt: Date().addingTimeInterval(10 * 24 * 60 * 60),
                appleOriginalTransactionId: "ui-billing-retry-elena",
                appleProductId: "com.careloop.ios.premium.monthly",
                hasPremium: false,
                capabilities: .free
            )
        )
        let refundedRecipient = CareRecipient(
            id: "r4",
            name: "Robert",
            relationship: "Uncle",
            notes: nil,
            isPrimary: false,
            sortOrder: 3,
            activationStatus: .active,
            receiverUserId: nil,
            eligibleAssigneeIds: [organizer.id, caregiver.id],
            premium: CareRecipientPremium(
                status: .refunded,
                source: .appStore,
                startsAt: Date().addingTimeInterval(-20 * 24 * 60 * 60),
                expiresAt: Date().addingTimeInterval(10 * 24 * 60 * 60),
                appleOriginalTransactionId: "ui-refunded-robert",
                appleProductId: "com.careloop.ios.premium.monthly",
                hasPremium: false,
                capabilities: .free
            )
        )

        let organizerTasks = [
            CareTask(
                id: "t1",
                title: "Morning wellness check",
                notes: "Confirm breakfast and the morning routine.",
                dueAt: Date().addingTimeInterval(45 * 60),
                status: .pending,
                priority: .high,
                completedAt: nil,
                archivedAt: nil,
                circleId: "c1",
                recipientId: momRecipient.id,
                recipient: momRecipient,
                creatorId: organizer.id,
                assigneeId: mom.id,
                assignee: mom,
                capabilities: CareTaskCapabilities(canEdit: true, canDelete: true, canAssign: true, canChangeRecipient: true, canChangeStatus: true, canMarkDone: true, canSkip: true, canComment: true)
            ),
            CareTask(
                id: "t2",
                title: "Pick up prescriptions",
                notes: nil,
                dueAt: Date().addingTimeInterval(-30 * 60),
                status: .pending,
                priority: .urgent,
                completedAt: nil,
                archivedAt: nil,
                circleId: "c1",
                recipientId: momRecipient.id,
                recipient: momRecipient,
                creatorId: organizer.id,
                assigneeId: caregiver.id,
                assignee: caregiver,
                capabilities: CareTaskCapabilities(canEdit: true, canDelete: true, canAssign: true, canChangeRecipient: true, canChangeStatus: true, canMarkDone: true, canSkip: true, canComment: true)
            ),
            CareTask(
                id: "t3",
                title: "Evening walk check-in",
                notes: nil,
                dueAt: Date().addingTimeInterval(2 * 60 * 60),
                status: .pending,
                priority: .normal,
                completedAt: nil,
                archivedAt: nil,
                circleId: "c1",
                recipientId: momRecipient.id,
                recipient: momRecipient,
                creatorId: organizer.id,
                assigneeId: backupCaregiver.id,
                assignee: backupCaregiver,
                capabilities: CareTaskCapabilities(canEdit: true, canDelete: true, canAssign: true, canChangeRecipient: true, canChangeStatus: true, canMarkDone: true, canSkip: true, canComment: true)
            ),
            CareTask(
                id: "t4",
                title: "Evening check-in",
                notes: nil,
                dueAt: Date().addingTimeInterval(-3 * 60 * 60),
                status: .done,
                priority: .normal,
                completedAt: Date().addingTimeInterval(-90 * 60),
                archivedAt: nil,
                circleId: "c1",
                recipientId: momRecipient.id,
                recipient: momRecipient,
                creatorId: organizer.id,
                assigneeId: organizer.id,
                assignee: organizer,
                capabilities: CareTaskCapabilities(canEdit: true, canDelete: true, canAssign: true, canChangeRecipient: true, canChangeStatus: true, canMarkDone: true, canSkip: true, canComment: true)
            ),
            CareTask(
                id: "t7",
                title: "Set up Dad care plan",
                notes: nil,
                dueAt: Date().addingTimeInterval(4 * 60 * 60),
                status: .pending,
                priority: .normal,
                completedAt: nil,
                archivedAt: nil,
                circleId: "c1",
                recipientId: dadRecipient.id,
                recipient: dadRecipient,
                creatorId: organizer.id,
                assigneeId: organizer.id,
                assignee: organizer,
                capabilities: CareTaskCapabilities(canEdit: true, canDelete: true, canAssign: true, canChangeRecipient: true, canChangeStatus: true, canMarkDone: true, canSkip: true, canComment: true)
            ),
        ]

        switch scenario {
        case .circleDirectory, .recipientInvite, .caregiverInvite, .inviteEdgeStates:
            let circle = CareCircle(
                id: "c1",
                name: "Ramgiri Care Circle",
                recipientName: "Maya",
                members: allMembers,
                recipients: [momRecipient, dadRecipient],
                tasks: organizerTasks
            )
            let pendingInvites = [
                GroupInvitation(
                    id: "invite-caregiver",
                    email: "newcaregiver@careloop.test",
                    name: "Nina Caregiver",
                    role: .member,
                    status: .pending,
                    expiresAt: nil,
                    circle: circle,
                    recipient: nil,
                    invitedBy: InvitationSender(id: organizer.id, name: organizer.name, email: organizer.email)
                ),
                GroupInvitation(
                    id: "invite-receiver",
                    email: "dad@careloop.test",
                    name: "David Receiver",
                    role: .recipient,
                    status: .pending,
                    expiresAt: nil,
                    circle: circle,
                    recipient: dadRecipient,
                    invitedBy: InvitationSender(id: organizer.id, name: organizer.name, email: organizer.email)
                ),
            ]
            var user: CareUser
            let visibleInvites: [GroupInvitation]
            switch scenario {
            case .inviteEdgeStates:
                user = caregiver
                user.memberships = []
                visibleInvites = [
                    GroupInvitation(
                        id: "invite-expired",
                        email: caregiver.email,
                        name: caregiver.name,
                        role: .member,
                        status: .pending,
                        expiresAt: Date().addingTimeInterval(-60),
                        circle: circle,
                        recipient: nil,
                        invitedBy: InvitationSender(id: organizer.id, name: organizer.name, email: organizer.email)
                    ),
                    GroupInvitation(
                        id: "invite-declined",
                        email: caregiver.email,
                        name: caregiver.name,
                        role: .member,
                        status: .declined,
                        expiresAt: nil,
                        circle: circle,
                        recipient: nil,
                        invitedBy: InvitationSender(id: organizer.id, name: organizer.name, email: organizer.email)
                    ),
                    GroupInvitation(
                        id: "invite-revoked",
                        email: caregiver.email,
                        name: caregiver.name,
                        role: .member,
                        status: .revoked,
                        expiresAt: nil,
                        circle: circle,
                        recipient: nil,
                        invitedBy: InvitationSender(id: organizer.id, name: organizer.name, email: organizer.email)
                    ),
                ]
            case .recipientInvite:
                user = mom
                user.memberships = []
                visibleInvites = [pendingInvites[1]]
            case .caregiverInvite:
                user = caregiver
                user.memberships = []
                visibleInvites = [pendingInvites[0]]
            default:
                user = organizer
                user.memberships = [CircleMembership(id: "cm1", circleId: circle.id, role: .admin, circle: circle)]
                visibleInvites = pendingInvites
            }
            user.pendingInvites = visibleInvites.isEmpty ? nil : visibleInvites
            return UITestScenarioFixture(
                user: user,
                circle: circle,
                invitations: visibleInvites,
                recipientAccessByMemberId: [:],
                premiumUpgradeRequests: [],
                events: [],
                completionInsights: nil,
                pendingTaskId: nil
            )

        case .organizerHome, .taskComments, .inactiveReceiverTask, .premiumBillingStates:
            let fixtureRecipients: [CareRecipient]
            if scenario == .inactiveReceiverTask {
                fixtureRecipients = [dadRecipient]
            } else if scenario == .premiumBillingStates {
                fixtureRecipients = [momRecipient, dadRecipient, billingRetryRecipient, refundedRecipient]
            } else {
                fixtureRecipients = [momRecipient, dadRecipient]
            }
            let fixtureTasks = scenario == .inactiveReceiverTask ? [] : organizerTasks
            let circle = CareCircle(
                id: "c1",
                name: "Ramgiri Care Circle",
                recipientName: "Maya",
                members: allMembers,
                recipients: fixtureRecipients,
                tasks: fixtureTasks
            )
            let pendingInvites = [
                GroupInvitation(
                    id: "invite-caregiver",
                    email: "newcaregiver@careloop.test",
                    name: "Nina Caregiver",
                    role: .member,
                    status: .pending,
                    expiresAt: nil,
                    circle: circle,
                    recipient: nil,
                    invitedBy: InvitationSender(id: organizer.id, name: organizer.name, email: organizer.email)
                ),
                GroupInvitation(
                    id: "invite-receiver",
                    email: "dad@careloop.test",
                    name: "David Receiver",
                    role: .recipient,
                    status: .pending,
                    expiresAt: nil,
                    circle: circle,
                    recipient: dadRecipient,
                    invitedBy: InvitationSender(id: organizer.id, name: organizer.name, email: organizer.email)
                ),
            ]
            var user = organizer
            user.memberships = [CircleMembership(id: "cm1", circleId: circle.id, role: .admin, circle: circle)]
            return UITestScenarioFixture(
                user: user,
                circle: circle,
                invitations: pendingInvites,
                recipientAccessByMemberId: [
                    "m2": [
                        RecipientAccessSummary(
                            recipientId: momRecipient.id,
                            name: momRecipient.name,
                            activationStatus: momRecipient.activationStatus,
                            hasAccess: true,
                            grantedAt: Date().addingTimeInterval(-2 * 60 * 60)
                        ),
                        RecipientAccessSummary(
                            recipientId: dadRecipient.id,
                            name: dadRecipient.name,
                            activationStatus: dadRecipient.activationStatus,
                            hasAccess: false,
                            grantedAt: nil
                        ),
                    ],
                    "m3": [
                        RecipientAccessSummary(
                            recipientId: momRecipient.id,
                            name: momRecipient.name,
                            activationStatus: momRecipient.activationStatus,
                            hasAccess: true,
                            grantedAt: Date().addingTimeInterval(-60 * 60)
                        ),
                        RecipientAccessSummary(
                            recipientId: dadRecipient.id,
                            name: dadRecipient.name,
                            activationStatus: dadRecipient.activationStatus,
                            hasAccess: true,
                            grantedAt: Date().addingTimeInterval(-30 * 60)
                        ),
                    ],
                ],
                premiumUpgradeRequests: [
                    PremiumUpgradeRequestSummary(
                        recipientId: dadRecipient.id,
                        recipientName: dadRecipient.name,
                        requestCount: 2,
                        latestRequesterName: backupCaregiver.name,
                        latestRequesterId: backupCaregiver.id,
                        latestRequestedAt: Date().addingTimeInterval(-30 * 60)
                    ),
                ],
                events: [
                    CircleEvent(id: "e0", type: .reminderEscalated, createdAt: Date().addingTimeInterval(-20 * 60), actorId: organizer.id, actor: organizerActor),
                    CircleEvent(id: "e1", type: .taskCompleted, createdAt: Date().addingTimeInterval(-45 * 60), actorId: caregiver.id, actor: caregiverActor),
                    CircleEvent(id: "e2", type: .recipientUpdated, createdAt: Date().addingTimeInterval(-90 * 60), actorId: organizer.id, actor: organizerActor),
                    CircleEvent(id: "e3", type: .taskCreated, createdAt: Date().addingTimeInterval(-4 * 60 * 60), actorId: organizer.id, actor: organizerActor),
                ],
                completionInsights: CircleCompletionInsights(
                    periodDays: 7,
                    selectedRecipientId: nil,
                    completedByDay: [
                        CompletedTaskDay(date: "2026-05-14", count: 1),
                        CompletedTaskDay(date: "2026-05-15", count: 0),
                        CompletedTaskDay(date: "2026-05-16", count: 1),
                    ],
                    taskTrendByDay: [
                        TaskTrendDay(date: "2026-05-14", due: 2, completed: 1, missed: 1),
                        TaskTrendDay(date: "2026-05-15", due: 1, completed: 1, missed: 0),
                        TaskTrendDay(date: "2026-05-16", due: 1, completed: 1, missed: 0),
                    ],
                    topCaregivers: [
                        TopCaregiverInsight(userId: caregiver.id, name: caregiver.name, email: caregiver.email, completedCount: 1),
                    ],
                    caregiverLoad: [
                        CaregiverLoadInsight(
                            userId: caregiver.id,
                            name: caregiver.name,
                            email: caregiver.email,
                            completedCount: 1,
                            activeAssignedCount: 2,
                            overdueAssignedCount: 1,
                            totalAssignedCount: 4
                        ),
                        CaregiverLoadInsight(
                            userId: backupCaregiver.id,
                            name: backupCaregiver.name,
                            email: backupCaregiver.email,
                            completedCount: 0,
                            activeAssignedCount: 1,
                            overdueAssignedCount: 0,
                            totalAssignedCount: 1
                        ),
                    ],
                    escalationSummary: EscalationInsightSummary(
                        totalEscalated: 1,
                        averageResponseMinutes: 18,
                        recent: [
                            EscalationInsightItem(
                                taskId: "t3",
                                taskTitle: "Pick up prescriptions",
                                recipientId: momRecipient.id,
                                recipientName: momRecipient.name,
                                escalatedAt: Date().addingTimeInterval(-90 * 60),
                                responseMinutes: 18
                            ),
                        ]
                    ),
                    recipientBreakdown: [
                        RecipientCompletionInsight(
                            recipientId: momRecipient.id,
                            name: momRecipient.name,
                            completed: 1,
                            active: 2,
                            overdue: 1,
                            adherence: AdherenceInsightSummary(
                                scheduled: 4,
                                completed: 3,
                                onTime: 2,
                                late: 1,
                                missed: 1,
                                completionRate: 75,
                                onTimeRate: 50
                            )
                        ),
                        RecipientCompletionInsight(
                            recipientId: dadRecipient.id,
                            name: dadRecipient.name,
                            completed: 0,
                            active: 0,
                            overdue: 0,
                            adherence: .empty
                        ),
                    ],
                    adherence: AdherenceInsightSummary(
                        scheduled: 4,
                        completed: 3,
                        onTime: 2,
                        late: 1,
                        missed: 1,
                        completionRate: 75,
                        onTimeRate: 50
                    ),
                    totals: CompletionInsightTotals(completed: 1, active: 2, overdue: 1)
                ),
                pendingTaskId: nil
            )

        case .caregiverHome:
            let caregiverMomRecipient = CareRecipient(
                id: momRecipient.id,
                name: momRecipient.name,
                relationship: momRecipient.relationship,
                notes: momRecipient.notes,
                isPrimary: momRecipient.isPrimary,
                sortOrder: momRecipient.sortOrder,
                activationStatus: momRecipient.activationStatus,
                receiverUserId: momRecipient.receiverUserId,
                eligibleAssigneeIds: momRecipient.eligibleAssigneeIds,
                premium: .free
            )
            let visibleTasks = organizerTasks.filter { task in
                task.recipientId == momRecipient.id && (task.assigneeId == caregiver.id || task.assigneeId == mom.id || task.creatorId == caregiver.id)
            }
            let circle = CareCircle(
                id: "c1",
                name: "Ramgiri Care Circle",
                recipientName: "Maya",
                members: allMembers,
                recipients: [caregiverMomRecipient],
                tasks: visibleTasks
            )
            var user = caregiver
            user.memberships = [CircleMembership(id: "cm2", circleId: circle.id, role: .member, circle: circle)]
            return UITestScenarioFixture(
                user: user,
                circle: circle,
                invitations: [],
                recipientAccessByMemberId: [:],
                premiumUpgradeRequests: [],
                events: [
                    CircleEvent(id: "e4", type: .taskCompleted, createdAt: Date().addingTimeInterval(-30 * 60), actorId: organizer.id, actor: organizerActor),
                    CircleEvent(id: "e5", type: .taskUpdated, createdAt: Date().addingTimeInterval(-2 * 60 * 60), actorId: organizer.id, actor: organizerActor),
                ],
                completionInsights: CircleCompletionInsights(
                    periodDays: 7,
                    selectedRecipientId: nil,
                    completedByDay: [
                        CompletedTaskDay(date: "2026-05-14", count: 0),
                        CompletedTaskDay(date: "2026-05-15", count: 1),
                        CompletedTaskDay(date: "2026-05-16", count: 0),
                    ],
                    taskTrendByDay: [
                        TaskTrendDay(date: "2026-05-14", due: 1, completed: 0, missed: 1),
                        TaskTrendDay(date: "2026-05-15", due: 1, completed: 1, missed: 0),
                        TaskTrendDay(date: "2026-05-16", due: 1, completed: 1, missed: 0),
                    ],
                    topCaregivers: [],
                    caregiverLoad: [],
                    escalationSummary: .empty,
                    recipientBreakdown: [
                        RecipientCompletionInsight(
                            recipientId: momRecipient.id,
                            name: momRecipient.name,
                            completed: 1,
                            active: 2,
                            overdue: 1,
                            adherence: AdherenceInsightSummary(
                                scheduled: 3,
                                completed: 2,
                                onTime: 1,
                                late: 1,
                                missed: 1,
                                completionRate: 67,
                                onTimeRate: 33
                            )
                        ),
                    ],
                    adherence: AdherenceInsightSummary(
                        scheduled: 3,
                        completed: 2,
                        onTime: 1,
                        late: 1,
                        missed: 1,
                        completionRate: 67,
                        onTimeRate: 33
                    ),
                    totals: CompletionInsightTotals(completed: 1, active: 2, overdue: 1)
                ),
                pendingTaskId: nil
            )

        case .receiverHome:
            let receiverTasks = [
                CareTask(
                    id: "t5",
                    title: "Lunchtime hydration check",
                    notes: "Drink water after lunch and mark this done.",
                    dueAt: Date().addingTimeInterval(20 * 60),
                    status: .pending,
                    priority: .high,
                    completedAt: nil,
                    archivedAt: nil,
                    circleId: "c1",
                    recipientId: momRecipient.id,
                    recipient: momRecipient,
                    creatorId: organizer.id,
                    assigneeId: mom.id,
                    assignee: mom,
                    capabilities: CareTaskCapabilities(canEdit: false, canDelete: false, canAssign: false, canChangeRecipient: false, canChangeStatus: false, canMarkDone: true, canSkip: false, canComment: true)
                ),
                CareTask(
                    id: "t6",
                    title: "Drink water",
                    notes: nil,
                    dueAt: Date().addingTimeInterval(90 * 60),
                    status: .pending,
                    priority: .normal,
                    completedAt: nil,
                    archivedAt: nil,
                    circleId: "c1",
                    recipientId: momRecipient.id,
                    recipient: momRecipient,
                    creatorId: organizer.id,
                    assigneeId: mom.id,
                    assignee: mom,
                    capabilities: CareTaskCapabilities(canEdit: false, canDelete: false, canAssign: false, canChangeRecipient: false, canChangeStatus: false, canMarkDone: true, canSkip: false, canComment: true)
                ),
                CareTask(
                    id: "t8",
                    title: "Breakfast check-in",
                    notes: "Completed from a reminder earlier today.",
                    dueAt: Date().addingTimeInterval(-2 * 60 * 60),
                    status: .done,
                    priority: .normal,
                    completedAt: Date().addingTimeInterval(-90 * 60),
                    completedById: mom.id,
                    completedBy: mom,
                    archivedAt: nil,
                    circleId: "c1",
                    recipientId: momRecipient.id,
                    recipient: momRecipient,
                    creatorId: organizer.id,
                    assigneeId: mom.id,
                    assignee: mom,
                    capabilities: CareTaskCapabilities(canEdit: false, canDelete: false, canAssign: false, canChangeRecipient: false, canChangeStatus: false, canMarkDone: false, canSkip: false, canComment: true)
                ),
            ]
            let circle = CareCircle(
                id: "c1",
                name: "Ramgiri Care Circle",
                recipientName: "Maya",
                members: allMembers,
                recipients: [momRecipient],
                tasks: receiverTasks
            )
            var user = mom
            user.memberships = [CircleMembership(id: "cm3", circleId: circle.id, role: .recipient, circle: circle)]
            return UITestScenarioFixture(
                user: user,
                circle: circle,
                invitations: [],
                recipientAccessByMemberId: [:],
                premiumUpgradeRequests: [],
                events: [],
                completionInsights: nil,
                pendingTaskId: nil
            )
        }
    }
}
#else
enum UITestScenario {
    case taskComments

    static var current: UITestScenario? {
        nil
    }

    static func pendingTaskId(_ arguments: [String]) -> String? {
        nil
    }

    static func pendingTaskCircleId(_ arguments: [String]) -> String? {
        nil
    }
}
#endif
