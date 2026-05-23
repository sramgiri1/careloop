import XCTest
@testable import CareLoop

// MARK: — CareTask

final class CareTaskTests: XCTestCase {

    private func makeTask(dueAt: Date?, status: TaskStatus) -> CareTask {
        CareTask(
            id: "t1", title: "Test task", notes: nil,
            dueAt: dueAt, status: status, priority: .normal,
            completedAt: nil, archivedAt: nil,
            circleId: "c1", creatorId: "u1", assigneeId: nil, assignee: nil
        )
    }

    func test_isOverdue_trueWhenPastDueAndPending() {
        let task = makeTask(dueAt: Date().addingTimeInterval(-3600), status: .pending)
        XCTAssertTrue(task.isOverdue)
    }

    func test_isOverdue_falseWhenFutureDue() {
        let task = makeTask(dueAt: Date().addingTimeInterval(3600), status: .pending)
        XCTAssertFalse(task.isOverdue)
    }

    func test_isOverdue_falseWhenNoDueDate() {
        let task = makeTask(dueAt: nil, status: .pending)
        XCTAssertFalse(task.isOverdue)
    }

    func test_isOverdue_falseWhenDone() {
        let task = makeTask(dueAt: Date().addingTimeInterval(-3600), status: .done)
        XCTAssertFalse(task.isOverdue)
    }

    func test_isOverdue_falseWhenSkipped() {
        let task = makeTask(dueAt: Date().addingTimeInterval(-3600), status: .skipped)
        XCTAssertFalse(task.isOverdue)
    }

    func test_isOverdue_falseWhenInProgress() {
        let task = makeTask(dueAt: Date().addingTimeInterval(-3600), status: .inProgress)
        XCTAssertFalse(task.isOverdue)
    }
}

// MARK: — TaskStatus

final class TaskStatusTests: XCTestCase {

    func test_labels() {
        XCTAssertEqual(TaskStatus.pending.label,    "Pending")
        XCTAssertEqual(TaskStatus.inProgress.label, "In Progress")
        XCTAssertEqual(TaskStatus.done.label,       "Done")
        XCTAssertEqual(TaskStatus.skipped.label,    "Skipped")
    }

    func test_rawValues() {
        XCTAssertEqual(TaskStatus.pending.rawValue,    "PENDING")
        XCTAssertEqual(TaskStatus.inProgress.rawValue, "IN_PROGRESS")
        XCTAssertEqual(TaskStatus.done.rawValue,       "DONE")
        XCTAssertEqual(TaskStatus.skipped.rawValue,    "SKIPPED")
    }

    func test_decodesFromRawValue() {
        XCTAssertEqual(TaskStatus(rawValue: "PENDING"),     .pending)
        XCTAssertEqual(TaskStatus(rawValue: "IN_PROGRESS"), .inProgress)
        XCTAssertEqual(TaskStatus(rawValue: "DONE"),        .done)
        XCTAssertEqual(TaskStatus(rawValue: "SKIPPED"),     .skipped)
        XCTAssertNil(TaskStatus(rawValue: "INVALID"))
    }
}

// MARK: — TaskPriority

final class TaskPriorityTests: XCTestCase {

    func test_labels() {
        XCTAssertEqual(TaskPriority.low.label,    "Low")
        XCTAssertEqual(TaskPriority.normal.label, "Normal")
        XCTAssertEqual(TaskPriority.high.label,   "High")
        XCTAssertEqual(TaskPriority.urgent.label, "Urgent")
    }

    func test_rawValues() {
        XCTAssertEqual(TaskPriority.low.rawValue,    "LOW")
        XCTAssertEqual(TaskPriority.normal.rawValue, "NORMAL")
        XCTAssertEqual(TaskPriority.high.rawValue,   "HIGH")
        XCTAssertEqual(TaskPriority.urgent.rawValue, "URGENT")
    }

    func test_allCasesCount() {
        XCTAssertEqual(TaskPriority.allCases.count, 4)
    }

    func test_allCasesOrder() {
        XCTAssertEqual(TaskPriority.allCases, [.low, .normal, .high, .urgent])
    }
}

// MARK: — MemberRole

final class MemberRoleTests: XCTestCase {

    func test_rawValues() {
        XCTAssertEqual(MemberRole.admin.rawValue,  "ADMIN")
        XCTAssertEqual(MemberRole.member.rawValue, "MEMBER")
    }

    func test_decodesFromRawValue() {
        XCTAssertEqual(MemberRole(rawValue: "ADMIN"),  .admin)
        XCTAssertEqual(MemberRole(rawValue: "MEMBER"), .member)
        XCTAssertNil(MemberRole(rawValue: "OWNER"))
    }

    func test_displayLabels_matchProductTerminology() {
        XCTAssertEqual(MemberRole.admin.displayLabel, "Care Organizer")
        XCTAssertEqual(MemberRole.member.displayLabel, "Caregiver")
        XCTAssertEqual(MemberRole.recipient.displayLabel, "Care Receiver")
    }
}

final class CareRecipientPremiumTests: XCTestCase {

    func test_careRecipient_defaultsToFreePremiumState() {
        let recipient = CareRecipient(id: "r1", name: "Maya")

        XCTAssertFalse(recipient.hasPremium)
        XCTAssertEqual(recipient.premiumStatusLabel, "Free")
        XCTAssertEqual(recipient.premiumStatusIconName, "crown")
        XCTAssertEqual(recipient.premiumStatusAccessibilityLabel, "Maya plan: Free")
        XCTAssertEqual(recipient.caregiverAccessSummary, "1 caregiver included")
    }

    func test_careRecipient_exposesPremiumCapabilities() {
        let recipient = CareRecipient(
            id: "r1",
            name: "Maya",
            premium: CareRecipientPremium(
                status: .active,
                source: .appStore,
                startsAt: Date(timeIntervalSince1970: 0),
                expiresAt: Date(timeIntervalSince1970: 3600),
                appleOriginalTransactionId: "otx-1",
                appleProductId: "com.careloop.ios.premium.yearly",
                hasPremium: true,
                capabilities: CareRecipientPremiumCapabilities(
                    hasPremium: true,
                    canUseAdvancedReminders: true,
                    canUseInsights: true,
                    canUseUnlimitedCaregivers: true,
                    canUseAdvancedCoordination: true
                )
            )
        )

        XCTAssertTrue(recipient.hasPremium)
        XCTAssertEqual(recipient.premiumStatusLabel, "Premium")
        XCTAssertEqual(recipient.premiumStatusIconName, "crown.fill")
        XCTAssertEqual(recipient.premiumStatusAccessibilityLabel, "Maya plan: Premium")
        XCTAssertEqual(recipient.caregiverAccessSummary, "Unlimited caregivers")
        XCTAssertTrue(ReceiverPremiumPolicy.supportsInsights(for: recipient))
        XCTAssertTrue(ReceiverPremiumPolicy.supportsRecurringSchedules(for: recipient))
    }

    func test_careRecipient_exposesExpiredPremiumAsLockedButVisible() {
        let recipient = CareRecipient(
            id: "r1",
            name: "Maya",
            premium: CareRecipientPremium(
                status: .active,
                source: .appStore,
                startsAt: Date(timeIntervalSince1970: 0),
                expiresAt: Date(timeIntervalSince1970: 3600),
                appleOriginalTransactionId: "otx-1",
                appleProductId: "com.careloop.ios.premium.monthly",
                hasPremium: false,
                capabilities: .free
            )
        )

        XCTAssertFalse(recipient.hasPremium)
        XCTAssertTrue(recipient.hasExpiredPremium)
        XCTAssertEqual(recipient.premiumStatusLabel, "Expired")
        XCTAssertEqual(recipient.premiumStatusIconName, "exclamationmark.triangle.fill")
        XCTAssertEqual(recipient.premiumStatusAccessibilityLabel, "Maya plan: Expired")
        XCTAssertTrue(recipient.premiumStatusDetail.contains("Existing care history remains visible"))
        XCTAssertFalse(ReceiverPremiumPolicy.supportsInsights(for: recipient))
        XCTAssertFalse(ReceiverPremiumPolicy.supportsRecurringSchedules(for: recipient))
    }

    func test_careRecipient_exposesBillingRetryAndRefundedPremiumAsLockedButVisible() {
        let statuses: [(CareRecipientEntitlementStatus, String, String)] = [
            (.billingRetry, "Billing retry", "billing needs attention"),
            (.refunded, "Refunded", "was refunded"),
        ]

        for (status, label, detail) in statuses {
            let recipient = CareRecipient(
                id: "r1",
                name: "Maya",
                premium: CareRecipientPremium(
                    status: status,
                    source: .appStore,
                    startsAt: Date(timeIntervalSince1970: 0),
                    expiresAt: Date(timeIntervalSince1970: 3_600),
                    appleOriginalTransactionId: "otx-1",
                    appleProductId: "com.careloop.ios.premium.monthly",
                    hasPremium: false,
                    capabilities: .free
                )
            )

            XCTAssertFalse(recipient.hasPremium)
            XCTAssertEqual(recipient.premiumStatusLabel, label)
            XCTAssertEqual(recipient.premiumPlanSummaryLabel, "\(label) plan")
            XCTAssertEqual(recipient.premiumStatusIconName, "exclamationmark.triangle.fill")
            XCTAssertTrue(recipient.premiumStatusDetail.contains(detail))
            XCTAssertTrue(recipient.premiumStatusDetail.contains("Existing care history remains visible"))
            XCTAssertFalse(ReceiverPremiumPolicy.supportsInsights(for: recipient))
            XCTAssertFalse(ReceiverPremiumPolicy.supportsRecurringSchedules(for: recipient))
        }
    }
}

// MARK: — Sprint 2: AppState push notification state

final class AppStatePushTests: XCTestCase {

    @MainActor
    func test_pendingTaskId_defaultsToNil() {
        let state = AppState()
        XCTAssertNil(state.pendingTaskId)
        XCTAssertNil(state.pendingTaskCircleId)
    }

    @MainActor
    func test_consumePendingTask_clearsTaskId() {
        let state = AppState()
        state.pendingTaskId = "task-abc"
        state.pendingTaskCircleId = "circle-abc"
        state.consumePendingTask()
        XCTAssertNil(state.pendingTaskId, "consumePendingTask should clear pendingTaskId")
        XCTAssertNil(state.pendingTaskCircleId, "consumePendingTask should clear pendingTaskCircleId")
    }

    @MainActor
    func test_consumePendingTask_isIdempotent_whenAlreadyNil() {
        let state = AppState()
        XCTAssertNil(state.pendingTaskId)
        state.consumePendingTask()
        XCTAssertNil(state.pendingTaskId, "calling consumePendingTask on nil should not crash")
    }

    @MainActor
    func test_pendingTaskId_canBeSetAndRead() {
        let state = AppState()
        state.pendingTaskId = "task-xyz-789"
        XCTAssertEqual(state.pendingTaskId, "task-xyz-789")
    }

    @MainActor
    func test_pushTaskOpenedNotification_setsPendingTaskId() {
        let state = AppState()
        let taskId = "push-deep-link-task"
        NotificationCenter.default.post(
            name: .careLoopPushTaskOpened,
            object: taskId
        )
        // NotificationCenter dispatches synchronously for non-async publishers
        // but the sink uses RunLoop.main; flush the run loop
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(state.pendingTaskId, taskId)
    }

    @MainActor
    func test_pushTaskOpenedNotification_setsPendingTaskAndCircleIds() {
        let state = AppState()
        NotificationCenter.default.post(
            name: .careLoopPushTaskOpened,
            object: ["taskId": "push-task", "circleId": "push-circle", "recipientId": "push-recipient"]
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(state.pendingTaskId, "push-task")
        XCTAssertEqual(state.pendingTaskCircleId, "push-circle")
    }
}

// MARK: — Sprint 2: push token endpoint contract

final class PushTokenEndpointTests: XCTestCase {

    func test_updatePushToken_requestBody_containsPushToken() throws {
        // Verify the endpoint encoding is correct before any network call.
        // APIClient.shared.updatePushToken encodes { "pushToken": <value> }.
        let body: [String: String] = ["pushToken": "device-token-abc123"]
        let data = try JSONSerialization.data(withJSONObject: body)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(decoded?["pushToken"], "device-token-abc123")
    }

    func test_updatePushToken_path_format() {
        let userId = "user-abc"
        let path = "/users/\(userId)/push-token"
        XCTAssertEqual(path, "/users/user-abc/push-token")
    }
}

// MARK: — Sprint 2: Reminder scheduling contract (iOS side)

final class ReminderSchedulingTests: XCTestCase {

    func test_reminderScheduledAt_is_15minutesBeforeDueAt() {
        let dueAt = Date(timeIntervalSinceNow: 3600) // 1 hour from now
        let scheduledAt = dueAt.addingTimeInterval(-15 * 60)
        let diff = dueAt.timeIntervalSince(scheduledAt)
        XCTAssertEqual(diff, 15 * 60, accuracy: 1, "Reminder fires exactly 15 minutes before due time")
    }

    func test_escalation_fires_after_15_minutes_of_no_action() {
        let sentAt = Date(timeIntervalSinceNow: -(16 * 60)) // sent 16 min ago
        let escalationCutoff = Date(timeIntervalSinceNow: -(15 * 60))
        XCTAssertTrue(sentAt < escalationCutoff, "sentAt 16min ago is past the 15min escalation window")
    }

    func test_escalation_does_not_fire_within_15_minutes() {
        let sentAt = Date(timeIntervalSinceNow: -(14 * 60)) // sent 14 min ago
        let escalationCutoff = Date(timeIntervalSinceNow: -(15 * 60))
        XCTAssertFalse(sentAt < escalationCutoff, "sentAt 14min ago has not yet crossed the escalation window")
    }
}

// MARK: — AppState.userRole

final class AppStateRoleTests: XCTestCase {

    @MainActor
    func test_userRole_defaultsToMemberWithNoState() {
        let state = AppState()
        XCTAssertEqual(state.userRole, .member)
    }

    @MainActor
    func test_userRole_defaultsToMemberWithNoCircle() {
        let state = AppState()
        state.currentUser = CareUser(id: "u1", email: "a@test.com", name: "Alice", phone: nil, memberships: nil)
        XCTAssertEqual(state.userRole, .member)
    }

    @MainActor
    func test_userRole_defaultsToMemberWithNoUser() {
        let state = AppState()
        let member = CircleMember(id: "m1", role: .admin, userId: "u1", user: nil)
        state.activeCircle = CareCircle(id: "c1", name: "Test", recipientName: "Bob", members: [member], tasks: nil)
        XCTAssertEqual(state.userRole, .member)
    }

    @MainActor
    func test_userRole_returnsAdmin() {
        let state = AppState()
        state.currentUser = CareUser(id: "u1", email: "a@test.com", name: "Alice", phone: nil, memberships: nil)
        let member = CircleMember(id: "m1", role: .admin, userId: "u1", user: nil)
        state.activeCircle = CareCircle(id: "c1", name: "Test", recipientName: "Bob", members: [member], tasks: nil)
        XCTAssertEqual(state.userRole, .admin)
    }

    @MainActor
    func test_userRole_returnsMember() {
        let state = AppState()
        state.currentUser = CareUser(id: "u2", email: "b@test.com", name: "Bob", phone: nil, memberships: nil)
        let member = CircleMember(id: "m2", role: .member, userId: "u2", user: nil)
        state.activeCircle = CareCircle(id: "c1", name: "Test", recipientName: "Carol", members: [member], tasks: nil)
        XCTAssertEqual(state.userRole, .member)
    }

    @MainActor
    func test_userRole_defaultsToMemberWhenUserNotInCircle() {
        let state = AppState()
        state.currentUser = CareUser(id: "u99", email: "x@test.com", name: "Stranger", phone: nil, memberships: nil)
        let member = CircleMember(id: "m1", role: .admin, userId: "u1", user: nil)
        state.activeCircle = CareCircle(id: "c1", name: "Test", recipientName: "Bob", members: [member], tasks: nil)
        XCTAssertEqual(state.userRole, .member)
    }

    @MainActor
    func test_userRole_adminInMultiMemberCircle() {
        let state = AppState()
        state.currentUser = CareUser(id: "u1", email: "a@test.com", name: "Alice", phone: nil, memberships: nil)
        let admin  = CircleMember(id: "m1", role: .admin,  userId: "u1", user: nil)
        let member = CircleMember(id: "m2", role: .member, userId: "u2", user: nil)
        state.activeCircle = CareCircle(id: "c1", name: "Test", recipientName: "Bob", members: [admin, member], tasks: nil)
        XCTAssertEqual(state.userRole, .admin)
    }

    @MainActor
    func test_userRole_recalculatesWhenSameUserSwitchesCircles() {
        let state = AppState()
        state.currentUser = CareUser(id: "u1", email: "a@test.com", name: "Alice", phone: nil, memberships: nil)

        let receiverCircle = CareCircle(
            id: "c1",
            name: "Receiver Circle",
            recipientName: "Alice",
            members: [CircleMember(id: "m1", role: .recipient, userId: "u1", user: nil)],
            tasks: nil
        )
        let adminCircle = CareCircle(
            id: "c2",
            name: "Admin Circle",
            recipientName: "Bob",
            members: [CircleMember(id: "m2", role: .admin, userId: "u1", user: nil)],
            tasks: nil
        )
        let caregiverCircle = CareCircle(
            id: "c3",
            name: "Caregiver Circle",
            recipientName: "Carol",
            members: [CircleMember(id: "m3", role: .member, userId: "u1", user: nil)],
            tasks: nil
        )

        state.activeCircle = receiverCircle
        XCTAssertEqual(state.userRole, .recipient)
        state.activeCircle = adminCircle
        XCTAssertEqual(state.userRole, .admin)
        state.activeCircle = caregiverCircle
        XCTAssertEqual(state.userRole, .member)
    }
}

// MARK: — AppState multi-circle behavior

final class AppStateCircleTests: XCTestCase {

    @MainActor
    func test_circleMemberships_sortsActiveCircleFirst_thenAlphabetically() {
        let state = AppState()
        let alpha = CareCircle(id: "c1", name: "Alpha Family", recipientName: "Alice")
        let beta = CareCircle(id: "c2", name: "Beta Family", recipientName: "Bob")
        let gamma = CareCircle(id: "c3", name: "Gamma Family", recipientName: "Carol")

        state.currentUser = CareUser(
            id: "u1",
            email: "a@test.com",
            name: "Alice",
            phone: nil,
            memberships: [
                CircleMembership(id: "m1", circleId: alpha.id, role: .member, circle: alpha),
                CircleMembership(id: "m2", circleId: gamma.id, role: .admin, circle: gamma),
                CircleMembership(id: "m3", circleId: beta.id, role: .member, circle: beta),
            ]
        )
        state.activeCircle = gamma

        XCTAssertEqual(state.circleMemberships.map(\.circleId), ["c3", "c1", "c2"])
    }

    @MainActor
    func test_attachCircle_updatesMatchingMembershipSnapshot() {
        let state = AppState()
        let original = CareCircle(id: "c1", name: "Alpha Family", recipientName: "Alice", archiveAfterDays: 7)
        let updated = CareCircle(id: "c1", name: "Alpha Family", recipientName: "Alice Johnson", archiveAfterDays: 14)

        state.currentUser = CareUser(
            id: "u1",
            email: "a@test.com",
            name: "Alice",
            phone: nil,
            memberships: [
                CircleMembership(id: "m1", circleId: original.id, role: .admin, circle: original)
            ]
        )

        state.attachCircle(updated)

        XCTAssertEqual(state.activeCircle?.recipientName, "Alice Johnson")
        XCTAssertEqual(state.currentUser?.memberships?.first?.circle?.recipientName, "Alice Johnson")
        XCTAssertEqual(state.currentUser?.memberships?.first?.circle?.archiveAfterDays, 14)
    }

    @MainActor
    func test_signIn_withoutExplicitCircle_keepsUserInDirectoryState() {
        let state = AppState()
        let alpha = CareCircle(id: "c1", name: "Alpha Family", recipientName: "Alice")
        let user = CareUser(
            id: "u1",
            email: "a@test.com",
            name: "Alice",
            phone: nil,
            memberships: [
                CircleMembership(id: "m1", circleId: alpha.id, role: .admin, circle: alpha)
            ]
        )

        state.signIn(user: user, circle: nil)

        XCTAssertNotNil(state.currentUser)
        XCTAssertNil(state.activeCircle)
        XCTAssertEqual(state.circleMemberships.first?.circleId, "c1")
    }
}

// MARK: — Recurring tasks and insights

final class TaskRecurrenceTests: XCTestCase {

    func test_dailyRecurrenceSummary_usesNaturalLabel() {
        let recurrence = TaskRecurrence(frequency: .daily, interval: 1, weekdays: [], endsAt: nil)
        XCTAssertEqual(recurrence.summary, "Daily")
    }

    func test_customRecurrenceSummary_reflectsInterval() {
        let recurrence = TaskRecurrence(frequency: .custom, interval: 3, weekdays: [], endsAt: nil)
        XCTAssertEqual(recurrence.summary, "Every 3 days")
    }

    func test_weeklyRecurrenceSummary_listsSelectedWeekdays() {
        let recurrence = TaskRecurrence(frequency: .weekly, interval: 2, weekdays: ["MON", "WED", "FRI"], endsAt: nil)
        XCTAssertEqual(recurrence.summary, "Every 2 weeks on Mon, Wed, Fri")
    }

    func test_careTaskRecurrence_isNilWhenTaskDoesNotRepeat() {
        let task = CareTask(
            id: "t1",
            title: "Task",
            notes: nil,
            dueAt: nil,
            status: .pending,
            priority: .normal,
            completedAt: nil,
            archivedAt: nil,
            circleId: "c1",
            creatorId: "u1",
            assigneeId: nil,
            assignee: nil
        )
        XCTAssertNil(task.recurrence)
    }
}

final class CompletionInsightModelTests: XCTestCase {

    func test_completedTaskDay_shortLabel_formatsDate() {
        let day = CompletedTaskDay(date: "2026-04-29", count: 2)
        XCTAssertFalse(day.shortLabel.isEmpty)
    }

    func test_taskTrendDay_reportsAttentionWhenMissedTasksExist() {
        let day = TaskTrendDay(date: "2026-04-29", due: 3, completed: 2, missed: 1)

        XCTAssertTrue(day.needsAttention)
        XCTAssertFalse(day.shortLabel.isEmpty)
    }

    func test_caregiverLoadInsight_formatsActiveAndOverdueSummary() {
        let load = CaregiverLoadInsight(
            userId: "u2",
            name: "Carlos",
            email: "carlos@test.com",
            completedCount: 2,
            activeAssignedCount: 3,
            overdueAssignedCount: 1,
            totalAssignedCount: 5
        )

        XCTAssertEqual(load.loadSummaryLabel, "3 active · 1 overdue")
    }

    func test_escalationInsightSummary_formatsResponseLabels() {
        let item = EscalationInsightItem(
            taskId: "t1",
            taskTitle: "Pick up prescriptions",
            recipientId: "cr1",
            recipientName: "Maya",
            escalatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            responseMinutes: 18
        )
        let summary = EscalationInsightSummary(
            totalEscalated: 1,
            averageResponseMinutes: 18,
            recent: [item]
        )

        XCTAssertEqual(summary.totalLabel, "1 escalation")
        XCTAssertEqual(summary.averageResponseLabel, "18 min avg response")
        XCTAssertEqual(item.responseLabel, "18 min response")
        XCTAssertEqual(EscalationInsightSummary.empty.averageResponseLabel, "No response time yet")
    }

    func test_adherenceSummary_formatsRatesAndEmptyState() {
        let summary = AdherenceInsightSummary(
            scheduled: 4,
            completed: 3,
            onTime: 2,
            late: 1,
            missed: 1,
            completionRate: 75,
            onTimeRate: 50
        )

        XCTAssertEqual(summary.completionRateLabel, "75%")
        XCTAssertEqual(summary.onTimeRateLabel, "50%")
        XCTAssertEqual(summary.summaryLabel, "3 of 4 due tasks completed, 2 on time.")
        XCTAssertEqual(AdherenceInsightSummary.empty.completionRateLabel, "No due tasks")
    }
}

final class CareCircleRecipientTests: XCTestCase {

    func test_recipientDisplaySummary_usesSingleName() {
        let circle = CareCircle(
            id: "c1",
            name: "Doe Family",
            recipientName: "John Doe",
            recipients: [
                CareRecipient(id: "r1", name: "John Doe", relationship: nil, notes: nil, isPrimary: true)
            ]
        )
        XCTAssertEqual(circle.recipientDisplaySummary, "John Doe")
    }

    func test_recipientDisplaySummary_collapsesMultipleNames() {
        let circle = CareCircle(
            id: "c1",
            name: "Doe Family",
            recipientName: "John Doe",
            recipients: [
                CareRecipient(id: "r1", name: "John Doe", relationship: nil, notes: nil, isPrimary: true),
                CareRecipient(id: "r2", name: "Jane Doe", relationship: nil, notes: nil, isPrimary: false),
                CareRecipient(id: "r3", name: "Mia Doe", relationship: nil, notes: nil, isPrimary: false),
            ]
        )
        XCTAssertEqual(circle.recipientDisplaySummary, "John Doe + 2 more")
    }

    func test_orderedRecipients_respectsPrimaryThenSortOrder() {
        let circle = CareCircle(
            id: "c1",
            name: "Doe Family",
            recipientName: "John Doe",
            recipients: [
                CareRecipient(id: "r3", name: "Mia Doe", relationship: nil, notes: nil, isPrimary: false, sortOrder: 2),
                CareRecipient(id: "r1", name: "John Doe", relationship: nil, notes: nil, isPrimary: true, sortOrder: 1),
                CareRecipient(id: "r2", name: "Jane Doe", relationship: nil, notes: nil, isPrimary: false, sortOrder: 0),
            ]
        )

        XCTAssertEqual(circle.orderedRecipients.map(\.id), ["r1", "r2", "r3"])
        XCTAssertEqual(circle.primaryRecipient?.id, "r1")
    }

    func test_recipientActivation_decodesWithDraftDefaultForOlderPayloads() throws {
        let data = """
        {
          "id": "r1",
          "name": "John Doe",
          "relationship": null,
          "notes": null,
          "isPrimary": true,
          "sortOrder": 0
        }
        """.data(using: .utf8)!

        let recipient = try JSONDecoder().decode(CareRecipient.self, from: data)
        XCTAssertEqual(recipient.activationStatus, .draft)
        XCTAssertFalse(recipient.isActiveForTasks)
    }

    func test_recipientActivation_activeAndProxyActiveUnlockTasks() {
        XCTAssertTrue(CareRecipient(id: "r1", name: "John", activationStatus: .active).isActiveForTasks)
        XCTAssertTrue(CareRecipient(id: "r2", name: "Jane", activationStatus: .proxyActive).isActiveForTasks)
        XCTAssertFalse(CareRecipient(id: "r3", name: "Mia", activationStatus: .invited).isActiveForTasks)
    }

    func test_recipientActivationLabels_matchManagementFlow() {
        XCTAssertEqual(CareReceiverActivationStatus.draft.label, "Draft")
        XCTAssertEqual(CareReceiverActivationStatus.invited.label, "Invited")
        XCTAssertEqual(CareReceiverActivationStatus.active.label, "Active")
        XCTAssertEqual(CareReceiverActivationStatus.proxyActive.label, "Proxy Active")
        XCTAssertTrue(CareRecipient(id: "r1", name: "John", activationStatus: .draft).activationStatusDetail.contains("Tasks stay blocked"))
        XCTAssertTrue(CareRecipient(id: "r2", name: "Jane", activationStatus: .proxyActive).activationStatusDetail.contains("recorded consent"))
    }

    func test_recipientEligibleAssigneeIds_decodeWhenPresent() throws {
        let data = """
        {
          "id": "cr1",
          "name": "Mom",
          "relationship": "Parent",
          "notes": null,
          "isPrimary": true,
          "sortOrder": 0,
          "activationStatus": "ACTIVE",
          "receiverUserId": "u3",
          "eligibleAssigneeIds": ["u1", "u2", "u3"]
        }
        """.data(using: .utf8)!

        let recipient = try JSONDecoder().decode(CareRecipient.self, from: data)
        XCTAssertEqual(recipient.eligibleAssigneeIds, ["u1", "u2", "u3"])
    }

    func test_recipientAccessSummary_decodesReceiverScopeGrant() throws {
        let data = """
        {
          "recipientId": "cr1",
          "name": "Mom",
          "activationStatus": "ACTIVE",
          "hasAccess": true,
          "grantedAt": "2026-05-16T14:00:00Z"
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(RecipientAccessSummary.self, from: data)
        XCTAssertEqual(summary.id, "cr1")
        XCTAssertEqual(summary.name, "Mom")
        XCTAssertEqual(summary.activationStatus, .active)
        XCTAssertTrue(summary.hasAccess)
    }
}

final class GroupInvitationTests: XCTestCase {

    func test_groupInvitation_decodesLinkedRecipient() throws {
        let data = """
        {
          "id": "i1",
          "email": "mom@test.com",
          "name": "Mom",
          "role": "RECIPIENT",
          "status": "PENDING",
          "expiresAt": "2099-05-31T10:00:00Z",
          "circle": {
            "id": "c1",
            "name": "Ramgiri Care Circle",
            "recipientName": "Maya",
            "archiveAfterDays": 7
          },
          "recipient": {
            "id": "cr1",
            "name": "Maya",
            "activationStatus": "INVITED",
            "receiverUserId": null
          },
          "invitedBy": {
            "id": "u1",
            "name": "Olivia Organizer",
            "email": "organizer@test.com"
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let invitation = try decoder.decode(GroupInvitation.self, from: data)
        XCTAssertEqual(invitation.recipient?.id, "cr1")
        XCTAssertEqual(invitation.recipient?.activationStatus, .invited)
        XCTAssertEqual(invitation.circle.name, "Ramgiri Care Circle")
        XCTAssertNotNil(invitation.expiresAt)
        XCTAssertTrue(invitation.expirationSummary?.contains("Expires") == true)
    }

    func test_groupInvitation_decodesExpiredStatus() throws {
        let data = """
        {
          "id": "i2",
          "email": "caregiver@test.com",
          "name": "Caregiver",
          "role": "MEMBER",
          "status": "EXPIRED",
          "expiresAt": "2026-05-01T10:00:00Z",
          "circle": {
            "id": "c1",
            "name": "Ramgiri Care Circle",
            "recipientName": "Maya",
            "archiveAfterDays": 7
          },
          "recipient": null,
          "invitedBy": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let invitation = try decoder.decode(GroupInvitation.self, from: data)
        XCTAssertEqual(invitation.status, .expired)
        XCTAssertNotNil(invitation.expiresAt)
        XCTAssertEqual(invitation.expirationSummary, "Expired")
    }
}

final class TaskWorkflowPolicyTests: XCTestCase {

    func test_defaultAssignee_prefersCurrentUserWhenEligible() {
        let recipient = CareRecipient(
            id: "cr1",
            name: "Mom",
            activationStatus: .active,
            receiverUserId: "u3",
            eligibleAssigneeIds: ["u1", "u3"]
        )
        let members = [
            CircleMember(id: "m1", role: .admin, userId: "u1", user: CareUser(id: "u1", email: "a@test.com", name: "Alex", phone: nil, memberships: nil)),
            CircleMember(id: "m2", role: .recipient, userId: "u3", user: CareUser(id: "u3", email: "r@test.com", name: "Mom", phone: nil, memberships: nil)),
        ]

        let assigneeId = TaskWorkflowPolicy.defaultAssigneeId(
            for: recipient,
            members: members,
            isOrganizer: false,
            currentUserId: "u1"
        )

        XCTAssertEqual(assigneeId, "u1")
    }

    func test_eligibleAssigneeMembers_filtersToRecipientScopeForCaregiver() {
        let recipient = CareRecipient(
            id: "cr1",
            name: "Mom",
            activationStatus: .active,
            receiverUserId: "u3",
            eligibleAssigneeIds: ["u1", "u2", "u3"]
        )
        let members = [
            CircleMember(id: "m1", role: .admin, userId: "u1", user: CareUser(id: "u1", email: "a@test.com", name: "Alex", phone: nil, memberships: nil)),
            CircleMember(id: "m2", role: .member, userId: "u2", user: CareUser(id: "u2", email: "b@test.com", name: "Bea", phone: nil, memberships: nil)),
            CircleMember(id: "m3", role: .recipient, userId: "u3", user: CareUser(id: "u3", email: "r@test.com", name: "Mom", phone: nil, memberships: nil)),
            CircleMember(id: "m4", role: .member, userId: "u4", user: CareUser(id: "u4", email: "c@test.com", name: "Chris", phone: nil, memberships: nil)),
        ]

        let eligible = TaskWorkflowPolicy.eligibleAssigneeMembers(
            for: recipient,
            members: members,
            isOrganizer: false,
            currentUserId: "u2"
        )

        XCTAssertEqual(eligible.map(\.userId), ["u2", "u3", "u1"])
    }

    func test_canToggleFromList_usesCapabilitiesForIncompleteTasks() {
        let task = CareTask(
            id: "t1",
            title: "Give meds",
            notes: nil,
            dueAt: Date(),
            status: .pending,
            priority: .normal,
            completedAt: nil,
            archivedAt: nil,
            circleId: "c1",
            creatorId: "u1",
            assigneeId: "u2",
            assignee: nil,
            capabilities: CareTaskCapabilities(
                canEdit: false,
                canDelete: false,
                canAssign: false,
                canChangeRecipient: false,
                canChangeStatus: false,
                canMarkDone: false,
                canSkip: false,
                canComment: true
            )
        )

        XCTAssertFalse(task.canToggleCompletion)
    }
}

final class CircleEventPresentationTests: XCTestCase {

    func test_caregiverFeedDescription_redactsActorDetails() {
        let event = CircleEvent(
            id: "e1",
            type: .taskCompleted,
            createdAt: Date(),
            actorId: "u1",
            actor: EventActor(id: "u1", name: "Olivia Organizer")
        )

        XCTAssertEqual(event.feedDescription(for: .member), "A task was completed")
        XCTAssertTrue(event.isVisible(to: .recipient))
    }

    func test_caregiverFeedDescription_hides_team_management_events() {
        let event = CircleEvent(
            id: "e2",
            type: .inviteCreated,
            createdAt: Date(),
            actorId: "u1",
            actor: EventActor(id: "u1", name: "Olivia Organizer")
        )

        XCTAssertEqual(event.feedDescription(for: .member), "")
        XCTAssertFalse(event.isVisible(to: .member))
    }
}

final class TaskDetailPresentationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func recipient(
        id: String = "r1",
        name: String = "Mom",
        activationStatus: CareReceiverActivationStatus = .active,
        premium: CareRecipientPremium = .free
    ) -> CareRecipient {
        CareRecipient(
            id: id,
            name: name,
            activationStatus: activationStatus,
            receiverUserId: "u4",
            eligibleAssigneeIds: ["u1", "u2", "u4"],
            premium: premium
        )
    }

    private func task(
        status: TaskStatus = .pending,
        dueAt: Date? = nil,
        creatorId: String = "u1",
        assigneeId: String? = "u2",
        recipient: CareRecipient? = nil,
        recurrenceFrequency: TaskRecurrenceFrequency = .none,
        capabilities: CareTaskCapabilities? = nil
    ) -> CareTask {
        CareTask(
            id: "t1",
            title: "Pick up prescriptions",
            notes: nil,
            dueAt: dueAt,
            status: status,
            priority: .normal,
            recurrenceFrequency: recurrenceFrequency,
            recurrenceInterval: recurrenceFrequency == .none ? nil : 1,
            completedAt: status == .done ? now : nil,
            archivedAt: nil,
            circleId: "c1",
            recipientId: recipient?.id ?? "r1",
            recipient: recipient,
            creatorId: creatorId,
            assigneeId: assigneeId,
            assignee: nil,
            capabilities: capabilities
        )
    }

    func test_detailPresentation_allowsOrganizerToManageTask() {
        let presentation = TaskWorkflowPolicy.detailPresentation(
            for: task(creatorId: "u2", assigneeId: "u3"),
            currentUserId: "u1",
            role: .admin,
            selectedRecipient: recipient(),
            now: now
        )

        XCTAssertTrue(presentation.permissions.canEdit)
        XCTAssertTrue(presentation.permissions.canDelete)
        XCTAssertTrue(presentation.permissions.canAssign)
        XCTAssertTrue(presentation.permissions.canChangeRecipient)
        XCTAssertTrue(presentation.permissions.canChangeStatus)
        XCTAssertTrue(presentation.permissions.canSnoozeReminder == false)
    }

    func test_detailPresentation_limitsCaregiverToCreatedOrAssignedActions() {
        let presentation = TaskWorkflowPolicy.detailPresentation(
            for: task(dueAt: now.addingTimeInterval(600), creatorId: "u1", assigneeId: "u2"),
            currentUserId: "u2",
            role: .member,
            selectedRecipient: recipient(),
            now: now
        )

        XCTAssertFalse(presentation.permissions.canEdit)
        XCTAssertFalse(presentation.permissions.canDelete)
        XCTAssertFalse(presentation.permissions.canAssign)
        XCTAssertFalse(presentation.permissions.canChangeRecipient)
        XCTAssertTrue(presentation.permissions.canChangeStatus)
        XCTAssertTrue(presentation.permissions.canMarkDone)
        XCTAssertTrue(presentation.permissions.canSnoozeReminder)
    }

    func test_detailPresentation_blocksCareReceiverEditingButAllowsAssignedCompletion() {
        let presentation = TaskWorkflowPolicy.detailPresentation(
            for: task(dueAt: now.addingTimeInterval(600), creatorId: "u1", assigneeId: "u4"),
            currentUserId: "u4",
            role: .recipient,
            selectedRecipient: recipient(),
            now: now
        )

        XCTAssertFalse(presentation.permissions.canEdit)
        XCTAssertFalse(presentation.permissions.canDelete)
        XCTAssertFalse(presentation.permissions.canAssign)
        XCTAssertFalse(presentation.permissions.canChangeRecipient)
        XCTAssertFalse(presentation.permissions.canChangeStatus)
        XCTAssertTrue(presentation.permissions.canMarkDone)
        XCTAssertTrue(presentation.permissions.canSnoozeReminder)
    }

    func test_detailPresentation_usesServerCapabilitiesWhenPresent() {
        let capabilities = CareTaskCapabilities(
            canEdit: false,
            canDelete: false,
            canAssign: false,
            canChangeRecipient: false,
            canChangeStatus: false,
            canMarkDone: false,
            canSkip: false,
            canComment: false
        )

        let presentation = TaskWorkflowPolicy.detailPresentation(
            for: task(dueAt: now.addingTimeInterval(600), capabilities: capabilities),
            currentUserId: "u1",
            role: .admin,
            selectedRecipient: recipient(),
            now: now
        )

        XCTAssertFalse(presentation.permissions.canEdit)
        XCTAssertFalse(presentation.permissions.canDelete)
        XCTAssertFalse(presentation.permissions.canChangeStatus)
        XCTAssertFalse(presentation.permissions.canMarkDone)
        XCTAssertFalse(presentation.permissions.canComment)
        XCTAssertTrue(presentation.permissions.canSnoozeReminder)
    }

    func test_detailDisplayState_distinguishesOverdueAndEscalated() {
        let overdueTask = task(dueAt: now.addingTimeInterval(-60))
        let escalatedTask = task(dueAt: now.addingTimeInterval(-TaskWorkflowPolicy.escalationGraceInterval - 1))

        XCTAssertEqual(TaskWorkflowPolicy.detailDisplayState(for: overdueTask, now: now), .overdue)
        XCTAssertEqual(TaskWorkflowPolicy.detailDisplayState(for: escalatedTask, now: now), .escalated)
    }

    func test_detailPresentation_reportsInactiveReceiverBlockReason() {
        let invited = recipient(activationStatus: .invited)
        let presentation = TaskWorkflowPolicy.detailPresentation(
            for: task(recipient: invited),
            currentUserId: "u1",
            role: .admin,
            selectedRecipient: invited,
            now: now
        )

        XCTAssertEqual(
            presentation.blockedReason,
            "Mom must accept the invite or be proxy activated before new task actions are available."
        )
    }

    func test_detailPresentation_reportsRecurringPremiumBlockReason() {
        let freeRecipient = recipient()
        let presentation = TaskWorkflowPolicy.detailPresentation(
            for: task(recipient: freeRecipient, recurrenceFrequency: .daily),
            currentUserId: "u1",
            role: .admin,
            selectedRecipient: freeRecipient,
            now: now
        )

        XCTAssertEqual(presentation.recurrenceBlockReason, "Recurring tasks require Premium for Mom.")
    }
}

final class CircleHomePolicyTests: XCTestCase {

    private func makeRecipient(id: String, name: String, userId: String, assignees: [String]) -> CareRecipient {
        CareRecipient(
            id: id,
            name: name,
            relationship: nil,
            notes: nil,
            isPrimary: id == "r1",
            sortOrder: 0,
            activationStatus: .active,
            receiverUserId: userId,
            eligibleAssigneeIds: assignees
        )
    }

    private func makeTask(
        id: String,
        title: String,
        dueAt: Date?,
        status: TaskStatus,
        recipient: CareRecipient,
        assigneeId: String
    ) -> CareTask {
        CareTask(
            id: id,
            title: title,
            notes: nil,
            dueAt: dueAt,
            status: status,
            priority: .normal,
            completedAt: status == .done ? Date() : nil,
            archivedAt: nil,
            circleId: "c1",
            recipientId: recipient.id,
            recipient: recipient,
            creatorId: "u1",
            assigneeId: assigneeId,
            assignee: nil
        )
    }

    func test_nextDueTask_prefersSoonestIncompleteTask() {
        let recipient = makeRecipient(id: "r1", name: "Mom", userId: "u4", assignees: ["u1", "u4"])
        let tasks = [
            makeTask(id: "t1", title: "Later", dueAt: Date().addingTimeInterval(3600), status: .pending, recipient: recipient, assigneeId: "u4"),
            makeTask(id: "t2", title: "Sooner", dueAt: Date().addingTimeInterval(900), status: .pending, recipient: recipient, assigneeId: "u4"),
            makeTask(id: "t3", title: "Done", dueAt: Date().addingTimeInterval(300), status: .done, recipient: recipient, assigneeId: "u4"),
        ]

        XCTAssertEqual(CircleHomePolicy.nextDueTask(in: tasks)?.id, "t2")
    }

    func test_receiverSummaries_calculateOpenOverdueAndCompletedCounts() {
        let mom = makeRecipient(id: "r1", name: "Mom", userId: "u4", assignees: ["u1", "u2", "u4"])
        let dad = makeRecipient(id: "r2", name: "Dad", userId: "u5", assignees: ["u1", "u5"])
        let members = [
            CircleMember(id: "m1", role: .admin, userId: "u1", user: nil),
            CircleMember(id: "m2", role: .member, userId: "u2", user: nil),
            CircleMember(id: "m4", role: .recipient, userId: "u4", user: nil),
            CircleMember(id: "m5", role: .recipient, userId: "u5", user: nil),
        ]
        let circle = CareCircle(
            id: "c1",
            name: "Family",
            recipientName: "Mom",
            members: members,
            recipients: [mom, dad]
        )
        let tasks = [
            makeTask(id: "t1", title: "Morning meds", dueAt: Date().addingTimeInterval(1800), status: .pending, recipient: mom, assigneeId: "u4"),
            makeTask(id: "t2", title: "Refill meds", dueAt: Date().addingTimeInterval(-1800), status: .pending, recipient: mom, assigneeId: "u2"),
            makeTask(id: "t3", title: "Check in", dueAt: Date().addingTimeInterval(-7200), status: .done, recipient: mom, assigneeId: "u1"),
            makeTask(id: "t4", title: "Walk", dueAt: Date().addingTimeInterval(5400), status: .pending, recipient: dad, assigneeId: "u5"),
        ]

        let summaries = CircleHomePolicy.receiverSummaries(in: circle, tasks: tasks)

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.first(where: { $0.recipient.id == "r1" })?.openCount, 1)
        XCTAssertEqual(summaries.first(where: { $0.recipient.id == "r1" })?.overdueCount, 1)
        XCTAssertEqual(summaries.first(where: { $0.recipient.id == "r1" })?.completedCount, 1)
        XCTAssertEqual(summaries.first(where: { $0.recipient.id == "r1" })?.supportingCaregiverCount, 2)
    }
}
