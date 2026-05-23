import SwiftUI
import Combine

extension Notification.Name {
    static let careLoopPushTokenRegistered = Notification.Name("CareLoopPushTokenRegistered")
    static let careLoopPushTaskOpened = Notification.Name("CareLoopPushTaskOpened")
}

@MainActor
final class AppState: ObservableObject {
    private enum SessionKeys {
        static let user = "careloop.userId"
        static let circle = "careloop.circleId"
    }

    @Published var currentUser: CareUser?
    @Published var activeCircle: CareCircle?
    @Published var pendingTaskId: String?
    @Published var pendingTaskCircleId: String?
    @Published var shouldPromptNewTask = false

    var uiTestInvitations: [GroupInvitation] = []
    var uiTestRecipientAccessByMemberId: [String: [RecipientAccessSummary]] = [:]
    var uiTestPremiumUpgradeRequests: [PremiumUpgradeRequestSummary] = []
    var uiTestEvents: [CircleEvent] = []
    var uiTestCompletionInsights: CircleCompletionInsights?

    private var cancellables: Set<AnyCancellable> = []
    private var pendingPushToken: String?
    #if DEBUG
    private let launchSession: DemoLaunchSession?
    #endif

    init(shouldRestoreSession: Bool = true) {
        #if DEBUG
        self.launchSession = nil
        #endif
        configure(shouldRestoreSession: shouldRestoreSession)
    }

    #if DEBUG
    init(shouldRestoreSession: Bool = true, launchSession: DemoLaunchSession?) {
        self.launchSession = launchSession
        configure(shouldRestoreSession: shouldRestoreSession)
    }
    #endif

    private func configure(shouldRestoreSession: Bool) {
        NotificationCenter.default.publisher(for: .careLoopPushTokenRegistered)
            .compactMap { $0.object as? String }
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                self?.handlePushToken(token)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .careLoopPushTaskOpened)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handlePushTaskOpened(notification.object)
            }
            .store(in: &cancellables)

        #if DEBUG
        if let launchSession {
            APIClient.shared.setAccessToken(launchSession.accessToken)
            persistSession(userId: nil, circleId: launchSession.circleId)
        }
        #endif

        if shouldRestoreSession {
            Task { await restoreSession() }
        }
    }

    var circleMemberships: [CircleMembership] {
        let activeCircleId = activeCircle?.id
        return (currentUser?.memberships ?? []).sorted { lhs, rhs in
            if lhs.circleId == activeCircleId { return true }
            if rhs.circleId == activeCircleId { return false }
            let leftName = lhs.circle?.name ?? lhs.circleId
            let rightName = rhs.circle?.name ?? rhs.circleId
            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        }
    }

    var userRole: MemberRole {
        guard let userId = currentUser?.id,
              let members = activeCircle?.members
        else { return .member }
        return members.first(where: { $0.userId == userId })?.role ?? .member
    }

    var rememberedCircleId: String? {
        storedCircleId
    }

    func signIn(user: CareUser, circle: CareCircle) {
        let resolvedUser = mergedUser(user, with: circle)
        currentUser = resolvedUser
        activeCircle = circle
        persistSession(userId: user.id, circleId: circle.id)
        Task { await flushPendingPushTokenIfNeeded() }
    }

    func signIn(user: CareUser, circle: CareCircle?) {
        let rememberedCircleId = circle?.id ?? resolvedCircleId(from: user, preferredCircleId: storedCircleId)
        currentUser = mergedUser(user, with: nil)
        activeCircle = circle
        persistSession(userId: user.id, circleId: rememberedCircleId)
        Task { await flushPendingPushTokenIfNeeded() }
    }

    func attachCircle(_ circle: CareCircle) {
        currentUser = currentUser.map { mergedUser($0, with: circle) }
        activeCircle = circle
        persistSession(userId: currentUser?.id, circleId: circle.id)
    }

    func attachCircle(_ circle: CareCircle, promptNewTask: Bool) {
        attachCircle(circle)
        shouldPromptNewTask = promptNewTask
    }

    func activateCircle(id: String, promptNewTask: Bool = false) async throws {
        try await refreshCurrentUser(preferredCircleId: id, promptNewTask: promptNewTask)
    }

    func refreshCurrentUser(
        preferredCircleId: String? = nil,
        promptNewTask: Bool = false,
        selectCircle: Bool = true
    ) async throws {
        let user = try await APIClient.shared.fetchCurrentUser()
        let targetCircleId = resolvedCircleId(from: user, preferredCircleId: preferredCircleId)
        let selectedCircle = selectCircle
            ? try await resolvedActiveCircle(from: user, preferredCircleId: targetCircleId)
            : nil

        currentUser = mergedUser(user, with: selectedCircle)
        activeCircle = selectedCircle
        shouldPromptNewTask = promptNewTask
        persistSession(userId: user.id, circleId: targetCircleId)
        await flushPendingPushTokenIfNeeded()
    }

    func refreshMemberships() async throws {
        try await refreshCurrentUser(preferredCircleId: storedCircleId, selectCircle: false)
    }

    func clearActiveCircleSelection() {
        let rememberedCircleId = activeCircle?.id ?? storedCircleId
        activeCircle = nil
        shouldPromptNewTask = false
        persistSession(userId: currentUser?.id, circleId: rememberedCircleId)
    }

    func signOut() {
        APIClient.shared.revokeCurrentAccessTokenForSignOut()
        currentUser  = nil
        activeCircle = nil
        shouldPromptNewTask = false
        Self.resetPersistedSession()
    }

    static func resetPersistedSession() {
        APIClient.shared.clearAccessToken()
        UserDefaults.standard.removeObject(forKey: SessionKeys.user)
        UserDefaults.standard.removeObject(forKey: SessionKeys.circle)
    }

    private func restoreSession() async {
        guard APIClient.shared.hasAccessToken else { return }
        do {
            #if DEBUG
            if let launchSession, launchSession.autoActivateCircle {
                try await refreshCurrentUser(
                    preferredCircleId: launchSession.circleId,
                    selectCircle: true
                )
                return
            }
            #endif

            let user = try await APIClient.shared.fetchCurrentUser()
            let rememberedCircleId = resolvedCircleId(from: user, preferredCircleId: storedCircleId)
            currentUser = mergedUser(user, with: nil)
            activeCircle = nil
            persistSession(userId: user.id, circleId: rememberedCircleId)
            await flushPendingPushTokenIfNeeded()
        } catch { signOut() }
    }

    func consumePendingTask() {
        pendingTaskId = nil
        pendingTaskCircleId = nil
    }

    func consumeNewTaskPrompt() {
        shouldPromptNewTask = false
    }

    private func handlePushToken(_ token: String) {
        pendingPushToken = token
        Task { await flushPendingPushTokenIfNeeded() }
    }

    private func handlePushTaskOpened(_ object: Any?) {
        if let taskId = object as? String {
            pendingTaskId = taskId
            pendingTaskCircleId = nil
            return
        }
        guard let payload = object as? [String: String],
              let taskId = payload["taskId"]
        else { return }
        pendingTaskId = taskId
        pendingTaskCircleId = payload["circleId"]
    }

    private var storedCircleId: String? {
        UserDefaults.standard.string(forKey: SessionKeys.circle)
    }

    private func persistSession(userId: String?, circleId: String?) {
        if let userId {
            UserDefaults.standard.set(userId, forKey: SessionKeys.user)
        } else {
            UserDefaults.standard.removeObject(forKey: SessionKeys.user)
        }

        if let circleId {
            UserDefaults.standard.set(circleId, forKey: SessionKeys.circle)
        } else {
            UserDefaults.standard.removeObject(forKey: SessionKeys.circle)
        }
    }

    private func resolvedCircleId(from user: CareUser, preferredCircleId: String?) -> String? {
        let membershipIds = Set((user.memberships ?? []).map(\.circleId))
        if let preferredCircleId, membershipIds.contains(preferredCircleId) {
            return preferredCircleId
        }
        if let activeId = activeCircle?.id, membershipIds.contains(activeId) {
            return activeId
        }
        if let storedCircleId, membershipIds.contains(storedCircleId) {
            return storedCircleId
        }
        return user.memberships?.first?.circleId
    }

    private func resolvedMembershipCircle(from user: CareUser, preferredCircleId: String?) -> CareCircle? {
        guard let circleId = resolvedCircleId(from: user, preferredCircleId: preferredCircleId) else {
            return nil
        }
        return user.memberships?.first(where: { $0.circleId == circleId })?.circle
    }

    private func resolvedActiveCircle(from user: CareUser, preferredCircleId: String?) async throws -> CareCircle? {
        guard let circleId = resolvedCircleId(from: user, preferredCircleId: preferredCircleId) else {
            return nil
        }

        if let fetched = try? await APIClient.shared.fetchCircle(id: circleId) {
            return fetched
        }

        return user.memberships?.first(where: { $0.circleId == circleId })?.circle
    }

    private func mergedUser(_ user: CareUser, with circle: CareCircle?) -> CareUser {
        guard let circle else { return user }
        var updated = user
        updated.memberships = updated.memberships?.map { membership in
            guard membership.circleId == circle.id else { return membership }
            var membership = membership
            membership.circle = circle
            return membership
        }
        return updated
    }

    private func flushPendingPushTokenIfNeeded() async {
        guard let token = pendingPushToken,
              let userId = currentUser?.id else { return }
        do {
            currentUser = try await APIClient.shared.updatePushToken(userId: userId, pushToken: token)
            pendingPushToken = nil
        } catch {
            // Keep the token cached; the next session restore or sign-in will retry.
        }
    }
}
