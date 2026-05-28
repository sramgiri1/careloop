import Foundation

// MARK: — Circles
extension APIClient {
    func fetchCircle(id: String) async throws -> CareCircle {
        try await get("/circles/\(id)")
    }

    func fetchEvents(circleId: String) async throws -> [CircleEvent] {
        try await get("/circles/\(circleId)/events")
    }

    func createCircle(name: String, recipientName: String, archiveAfterDays: Int = 7) async throws -> CareCircle {
        try await postAny("/circles", body: [
            "name": name,
            "recipientName": recipientName,
            "archiveAfterDays": archiveAfterDays
        ])
    }

    func fetchRecipients(circleId: String) async throws -> [CareRecipient] {
        try await get("/circles/\(circleId)/recipients")
    }

    func createRecipient(circleId: String, name: String, relationship: String?, notes: String? = nil, premiumIntent: String? = nil) async throws -> CareRecipient {
        var body: [String: Any] = [
            "name": name
        ]
        if let relationship { body["relationship"] = relationship }
        if let notes { body["notes"] = notes }
        if let premiumIntent { body["premiumIntent"] = premiumIntent }
        return try await postAny("/circles/\(circleId)/recipients", body: body)
    }

    func updateRecipient(
        circleId: String,
        recipientId: String,
        name: String,
        relationship: String?,
        notes: String? = nil,
        isPrimary: Bool? = nil
    ) async throws -> CareRecipient {
        var body: [String: Any] = [
            "name": name
        ]
        body["relationship"] = relationship.map { $0 as Any } ?? NSNull()
        body["notes"] = notes.map { $0 as Any } ?? NSNull()
        if let isPrimary {
            body["isPrimary"] = isPrimary
        }
        return try await patchAny("/circles/\(circleId)/recipients/\(recipientId)", body: body)
    }

    func deleteRecipient(circleId: String, recipientId: String) async throws {
        try await deleteVoid("/circles/\(circleId)/recipients/\(recipientId)")
    }

    func proxyActivateRecipient(
        circleId: String,
        recipientId: String,
        consentDocumentReference: String?,
        authorizationAttested: Bool
    ) async throws -> CareRecipient {
        var body: [String: Any] = ["authorizationAttested": authorizationAttested]
        if let consentDocumentReference {
            body["consentDocumentReference"] = consentDocumentReference
        }
        return try await postAny("/circles/\(circleId)/recipients/\(recipientId)/proxy-activate", body: body)
    }

    func syncRecipientPremium(
        circleId: String,
        recipientId: String,
        source: String = "APP_STORE",
        expiresAt: Date?,
        appleOriginalTransactionId: String?,
        appleProductId: String?
    ) async throws -> CareRecipient {
        var body: [String: Any] = [
            "source": source,
        ]
        if let expiresAt {
            body["expiresAt"] = ISO8601DateFormatter().string(from: expiresAt)
        }
        if let appleOriginalTransactionId {
            body["appleOriginalTransactionId"] = appleOriginalTransactionId
        }
        if let appleProductId {
            body["appleProductId"] = appleProductId
        }
        return try await putAny(
            "/circles/\(circleId)/recipients/\(recipientId)/entitlement",
            body: body
        )
    }

    func requestRecipientPremiumUpgrade(circleId: String, recipientId: String) async throws -> PremiumUpgradeRequest {
        try await postAny("/circles/\(circleId)/recipients/\(recipientId)/premium-requests", body: [:])
    }

    func fetchPremiumUpgradeRequests(circleId: String) async throws -> [PremiumUpgradeRequestSummary] {
        try await get("/circles/\(circleId)/premium-requests")
    }

    func reorderRecipients(circleId: String, recipientIds: [String], primaryRecipientId: String? = nil) async throws -> [CareRecipient] {
        var body: [String: Any] = [
            "recipientIds": recipientIds,
        ]
        if let primaryRecipientId {
            body["primaryRecipientId"] = primaryRecipientId
        }
        return try await postAny("/circles/\(circleId)/recipients/reorder", body: body)
    }

    func addMember(circleId: String) async throws -> CircleMember {
        try await post("/circles/\(circleId)/members", body: [String: String]())
    }

    func inviteMember(
        circleId: String,
        name: String,
        email: String,
        role: MemberRole,
        phone: String? = nil,
        recipientId: String? = nil
    ) async throws -> GroupInvitation {
        var body: [String: Any] = [
            "name": name,
            "email": email,
            "role": role.rawValue,
        ]
        if let phone { body["phone"] = phone }
        if let recipientId { body["recipientId"] = recipientId }
        return try await postAny("/circles/\(circleId)/members/invite", body: body)
    }

    func fetchInvitations(circleId: String, status: InvitationStatus = .pending) async throws -> [GroupInvitation] {
        try await get("/circles/\(circleId)/invitations?status=\(status.rawValue)")
    }

    func revokeInvitation(circleId: String, invitationId: String) async throws {
        try await deleteVoid("/circles/\(circleId)/invitations/\(invitationId)")
    }

    func resendInvitation(circleId: String, invitationId: String) async throws -> GroupInvitation {
        try await postAny("/circles/\(circleId)/invitations/\(invitationId)/resend", body: [:])
    }

    func acceptInvitation(invitationId: String) async throws -> CircleMember {
        try await post("/invitations/\(invitationId)/accept", body: [String: String]())
    }

    func declineInvitation(invitationId: String) async throws {
        _ = try await postAny("/invitations/\(invitationId)/decline", body: [String: String]()) as InvitationDeclineResult
    }

    func removeMember(circleId: String, memberId: String) async throws {
        try await deleteVoid("/circles/\(circleId)/members/\(memberId)")
    }

    func updateMemberRole(circleId: String, memberId: String, role: MemberRole) async throws -> CircleMember {
        try await patch("/circles/\(circleId)/members/\(memberId)/role", body: ["role": role.rawValue])
    }

    func fetchRecipientAccess(circleId: String, memberId: String) async throws -> [RecipientAccessSummary] {
        try await get("/circles/\(circleId)/members/\(memberId)/recipient-access")
    }

    func grantRecipientAccess(circleId: String, memberId: String, recipientId: String) async throws {
        try await putAnyVoid(
            "/circles/\(circleId)/members/\(memberId)/recipient-access/\(recipientId)",
            body: [:]
        )
    }

    func revokeRecipientAccess(circleId: String, memberId: String, recipientId: String) async throws {
        try await deleteVoid("/circles/\(circleId)/members/\(memberId)/recipient-access/\(recipientId)")
    }
}

// MARK: — Tasks
extension APIClient {
    func fetchTasks(circleId: String) async throws -> [CareTask] {
        try await get("/circles/\(circleId)/tasks")
    }

    func createTask(circleId: String, title: String, notes: String?, dueAt: Date?,
                    priority: TaskPriority, assigneeId: String?,
                    recipientId: String?,
                    recurrence: TaskRecurrence?) async throws -> CareTask {
        var body: [String: Any] = [
            "title": title,
            "priority": priority.rawValue,
        ]
        body["notes"] = notes.map { $0 as Any } ?? NSNull()
        body["assigneeId"] = assigneeId.map { $0 as Any } ?? NSNull()
        body["recipientId"] = recipientId.map { $0 as Any } ?? NSNull()
        if let due = dueAt {
            body["dueAt"] = ISO8601DateFormatter().string(from: due)
        }
        body["recurrence"] = recurrencePayload(from: recurrence)
        return try await postAny("/circles/\(circleId)/tasks", body: body)
    }

    func updateTaskStatus(circleId: String, taskId: String, status: TaskStatus) async throws -> CareTask {
        try await patch("/circles/\(circleId)/tasks/\(taskId)", body: ["status": status.rawValue])
    }

    func updateTask(circleId: String, taskId: String,
                    title: String, notes: String?, dueAt: Date?,
                    priority: TaskPriority, status: TaskStatus, canAssign: Bool, assigneeId: String?,
                    recipientId: String?,
                    recurrence: TaskRecurrence?,
                    seriesScope: TaskSeriesScope = .occurrence) async throws -> CareTask {
        var body: [String: Any] = [
            "title":    title,
            "priority": priority.rawValue,
            "status":   status.rawValue,
            "seriesScope": seriesScope.rawValue,
        ]
        body["notes"] = notes.map { $0 as Any } ?? NSNull()
        body["dueAt"]  = dueAt.map { ISO8601DateFormatter().string(from: $0) as Any } ?? NSNull()
        body["recurrence"] = recurrencePayload(from: recurrence)
        body["recipientId"] = recipientId.map { $0 as Any } ?? NSNull()
        if canAssign { body["assigneeId"] = assigneeId.map { $0 as Any } ?? NSNull() }
        return try await patchAny("/circles/\(circleId)/tasks/\(taskId)", body: body)
    }

    func deleteTask(circleId: String, taskId: String) async throws {
        try await deleteVoid("/circles/\(circleId)/tasks/\(taskId)")
    }

    func snoozeReminder(circleId: String, taskId: String, minutes: Int) async throws -> ReminderSnoozeResult {
        try await post("/circles/\(circleId)/tasks/\(taskId)/reminder/snooze", body: ["minutes": minutes])
    }

    func fetchComments(circleId: String, taskId: String) async throws -> [TaskComment] {
        try await get("/circles/\(circleId)/tasks/\(taskId)/comments")
    }

    func postComment(circleId: String, taskId: String, body: String) async throws -> TaskComment {
        try await post("/circles/\(circleId)/tasks/\(taskId)/comments", body: ["body": body])
    }

    func deleteComment(circleId: String, taskId: String, commentId: String) async throws {
        try await deleteVoid("/circles/\(circleId)/tasks/\(taskId)/comments/\(commentId)")
    }
}

private func recurrencePayload(from recurrence: TaskRecurrence?) -> [String: Any] {
    guard let recurrence else {
        return ["frequency": TaskRecurrenceFrequency.none.rawValue]
    }

    var payload: [String: Any] = [
        "frequency": recurrence.frequency.rawValue,
    ]
    if let interval = recurrence.interval {
        payload["interval"] = interval
    }
    if !recurrence.weekdays.isEmpty {
        payload["weekdays"] = recurrence.weekdays
    }
    if let endsAt = recurrence.endsAt {
        payload["endsAt"] = ISO8601DateFormatter().string(from: endsAt)
    }
    return payload
}

// MARK: — Circles (admin mutations)
extension APIClient {
    func deleteCircle(id: String) async throws {
        try await deleteVoid("/circles/\(id)")
    }

    func leaveCircle(circleId: String) async throws {
        try await deleteVoid("/circles/\(circleId)/members/me")
    }

    func updateCircle(id: String, name: String?, recipientName: String?, archiveAfterDays: Int? = nil) async throws -> CareCircle {
        var body: [String: Any] = [:]
        if let n = name          { body["name"]          = n }
        if let r = recipientName { body["recipientName"] = r }
        if let d = archiveAfterDays { body["archiveAfterDays"] = d }
        return try await patchAny("/circles/\(id)", body: body)
    }

    func fetchCompletionInsights(circleId: String, days: Int = 7, recipientId: String? = nil) async throws -> CircleCompletionInsights {
        var path = "/circles/\(circleId)/insights/completion?days=\(days)"
        if let recipientId, !recipientId.isEmpty {
            path += "&recipientId=\(recipientId)"
        }
        return try await get(path)
    }
}

// MARK: — Users
extension APIClient {
    func signUp(
        email: String,
        name: String,
        password: String,
        phone: String?,
        acceptedTerms: Bool,
        termsVersion: String
    ) async throws -> AuthResult {
        var body: [String: Any] = [
            "email": email,
            "name": name,
            "password": password,
            "acceptedTerms": acceptedTerms,
            "termsVersion": termsVersion
        ]
        if let phone {
            body["phone"] = phone
        }
        return try await postAny("/auth/signup", body: body)
    }

    func logIn(email: String, password: String) async throws -> AuthResult {
        try await post("/auth/login", body: [
            "email": email,
            "password": password
        ])
    }

    func socialAuth(
        provider: AuthProvider,
        idToken: String?,
        accessToken: String?,
        providerUserId: String?,
        email: String?,
        name: String?,
        acceptedTerms: Bool = false,
        termsVersion: String? = nil
    ) async throws -> AuthResult {
        var body: [String: Any] = [
            "provider": provider.apiValue,
            "acceptedTerms": acceptedTerms,
        ]
        if let idToken { body["idToken"] = idToken }
        if let accessToken { body["accessToken"] = accessToken }
        if let providerUserId { body["providerUserId"] = providerUserId }
        if let email { body["email"] = email }
        if let name { body["name"] = name }
        if let termsVersion { body["termsVersion"] = termsVersion }
        return try await postAny("/auth/social", body: body)
    }

    func requestPasswordReset(email: String) async throws -> ForgotPasswordRequestResult {
        try await post("/auth/forgot-password/request", body: ["email": email])
    }

    func verifyPasswordResetCode(email: String, code: String) async throws -> ForgotPasswordVerifyResult {
        try await post("/auth/forgot-password/verify", body: ["email": email, "code": code])
    }

    func resetPassword(email: String, code: String, password: String) async throws -> ForgotPasswordResetResult {
        try await post("/auth/forgot-password/reset", body: [
            "email": email,
            "code": code,
            "password": password
        ])
    }

    func createUser(email: String, name: String, phone: String?) async throws -> CareUser {
        try await post("/users", body: ["email": email, "name": name, "phone": phone])
    }

    func fetchCurrentUser() async throws -> CareUser {
        try await get("/users/me")
    }

    func fetchUser(id: String) async throws -> CareUser {
        try await get("/users/\(id)")
    }

    func fetchUserByEmail(_ email: String) async throws -> CareUser {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return try await get("/users/by-email?email=\(encoded)")
    }

    func updateTimezone(userId: String, timezone: String) async throws -> CareUser {
        try await patch("/users/\(userId)/timezone", body: ["timezone": timezone])
    }

    func updatePushToken(userId: String, pushToken: String) async throws -> CareUser {
        try await patch("/users/\(userId)/push-token", body: ["pushToken": pushToken])
    }

    func updateNotificationPreferences(
        userId: String,
        notifAssignments: Bool? = nil,
        notifEscalations: Bool? = nil,
        notifDigest: Bool? = nil
    ) async throws -> CareUser {
        var body: [String: Any] = [:]
        if let v = notifAssignments { body["notifAssignments"] = v }
        if let v = notifEscalations { body["notifEscalations"] = v }
        if let v = notifDigest      { body["notifDigest"]      = v }
        return try await patchAny("/users/\(userId)/notification-preferences", body: body)
    }

    @discardableResult
    func logSession(userId: String, circleId: String) async throws -> LogResult {
        try await post("/users/\(userId)/session", body: ["circleId": circleId])
    }
}

struct LogResult: Decodable { let logged: Bool }
struct InvitationDeclineResult: Decodable { let declined: Bool }

enum TaskSeriesScope: String {
    case occurrence = "THIS_OCCURRENCE"
    case series = "SERIES"
}
