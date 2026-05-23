import SwiftUI

struct MemberListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showInvite = false
    @State private var loadingMemberId: String?
    @State private var error: String?
    @State private var pendingInvitations: [GroupInvitation] = []
    @State private var recipientAccessByMemberId: [String: [RecipientAccessSummary]] = [:]
    @State private var selectedCaregiverForAccess: CircleMember?

    private let blue = Color(red: 0.13, green: 0.56, blue: 0.87)
    private let teal = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let rose = Color(red: 0.85, green: 0.30, blue: 0.50)
    private let dark = Color(red: 0.10, green: 0.16, blue: 0.24)
    private let mid = Color(red: 0.43, green: 0.50, blue: 0.60)
    private let bg = Color(red: 0.95, green: 0.96, blue: 0.99)

    private var members: [CircleMember] {
        (appState.activeCircle?.members ?? []).sorted { lhs, rhs in
            let leftName = lhs.user?.name ?? lhs.userId
            let rightName = rhs.user?.name ?? rhs.userId
            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        }
    }

    private var organizers: [CircleMember] { members.filter { $0.role == .admin } }
    private var caregivers: [CircleMember] { members.filter { $0.role == .member } }
    private var receiverAccounts: [CircleMember] { members.filter { $0.role == .recipient } }
    private var nonReceiverPendingInvites: [GroupInvitation] {
        pendingInvitations.filter { $0.role != .recipient }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    heroCard

                    if appState.userRole == .admin && !nonReceiverPendingInvites.isEmpty {
                        pendingInvitesSection
                    }

                    organizersSection
                    caregiversSection

                    if !receiverAccounts.isEmpty {
                        receiverAccountsSection
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle("People & Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if appState.userRole == .admin {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            error = nil
                            showInvite = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        .accessibilityIdentifier("invite-caregiver-button")
                    }
                    if let circle = appState.activeCircle {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(
                                item: "Join \(circle.name) on CareLoop.\nCare Circle code: \(circle.id)",
                                subject: Text("Join my Care Circle")
                            ) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showInvite, onDismiss: {
                Task {
                    await refreshData()
                    if let id = appState.activeCircle?.id {
                        try? await appState.activateCircle(id: id)
                    }
                }
            }) {
                InviteMemberView()
                    .environmentObject(appState)
            }
            .sheet(item: $selectedCaregiverForAccess, onDismiss: {
                Task { await loadRecipientAccess() }
            }) { caregiver in
                CaregiverAccessView(
                    member: caregiver,
                    initialAccess: recipientAccessByMemberId[caregiver.id] ?? []
                )
                .environmentObject(appState)
            }
            .task { await refreshData() }
            .refreshable {
                if let id = appState.activeCircle?.id {
                    try? await appState.activateCircle(id: id)
                }
                await refreshData()
            }
        }
        .accessibilityIdentifier("people-access-screen")
        .careLoopBrandBanner()
    }

    private var heroCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [blue.opacity(0.18), teal.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "person.2.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(blue)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Care team visibility")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                Text("Caregivers join with no receiver access by default. Care Organizers grant support scope explicitly.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
    }

    private var pendingInvitesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Pending Invitations", icon: "envelope.fill", color: Color.orange)

            VStack(spacing: 12) {
                ForEach(nonReceiverPendingInvites) { invite in
                    infoCard(title: invite.name, subtitle: invite.email, body: inviteCopy(invite)) {
                        if loadingMemberId == invite.id {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            VStack(spacing: 8) {
                                Button("Resend") {
                                    Task { await resend(invite) }
                                }
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .accessibilityIdentifier("pending-invite-resend-\(invite.id)")

                                Button("Revoke", role: .destructive) {
                                    Task { await revoke(invite) }
                                }
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .accessibilityIdentifier("pending-invite-revoke-\(invite.id)")
                            }
                        }
                    }
                }
            }
        }
    }

    private var organizersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Care Organizers", icon: "star.fill", color: blue)

            VStack(spacing: 12) {
                ForEach(organizers) { member in
                    infoCard(
                        title: member.user?.name ?? "Care Organizer",
                        subtitle: member.user?.email ?? "Circle-wide coordinator",
                        body: "Full visibility across every care receiver, task, insight, and settings surface."
                    ) {
                        HStack(spacing: 10) {
                            roleBadge(member.role)
                            if canManage(member) {
                                Menu {
                                    Button("Make Caregiver") {
                                        Task { await updateRole(member, role: .member) }
                                    }
                                    Button("Remove", role: .destructive) {
                                        Task { await remove(member) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var caregiversSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Caregivers", icon: "hands.and.sparkles.fill", color: teal)

            if caregivers.isEmpty {
                emptyCard(title: "No caregivers yet", body: "Invite a caregiver to help with tasks, reminders, and receiver-specific support.")
            } else {
                VStack(spacing: 12) {
                    ForEach(caregivers) { member in
                        infoCard(
                            title: member.user?.name ?? "Caregiver",
                            subtitle: member.user?.email ?? "Caregiver",
                            body: caregiverAccessSummary(for: member)
                        ) {
                            HStack(spacing: 10) {
                                roleBadge(member.role)
                                if appState.userRole == .admin {
                                    Button("Manage Access") {
                                        selectedCaregiverForAccess = member
                                    }
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(blue)
                                    .accessibilityIdentifier("manage-access-\(member.id)")

                                    Menu {
                                        Button("Manage Receiver Access") {
                                            selectedCaregiverForAccess = member
                                        }
                                        Button("Make Care Organizer") {
                                            Task { await updateRole(member, role: .admin) }
                                        }
                                        Button("Remove", role: .destructive) {
                                            Task { await remove(member) }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityIdentifier("caregiver-actions-\(member.id)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var receiverAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Care Receiver Accounts", icon: "heart.fill", color: rose)

            VStack(spacing: 12) {
                ForEach(receiverAccounts) { member in
                    infoCard(
                        title: member.user?.name ?? "Care Receiver",
                        subtitle: member.user?.email ?? "Linked account",
                        body: receiverAccountCopy(for: member)
                    ) {
                        roleBadge(member.role)
                    }
                }
            }
        }
    }

    private func infoCard<Accessory: View>(
        title: String,
        subtitle: String,
        body: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                Text(body)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(dark)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
            accessory()
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func emptyCard(title: String, body: String) -> some View {
        infoCard(title: title, subtitle: "", body: body) {
            EmptyView()
        }
    }

    private func sectionLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.7)
        }
        .foregroundStyle(color)
    }

    private func roleBadge(_ role: MemberRole) -> some View {
        let color: Color = {
            switch role {
            case .admin: return blue
            case .member: return teal
            case .recipient: return rose
            }
        }()

        return Text(role.displayLabel)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func canManage(_ member: CircleMember) -> Bool {
        guard appState.userRole == .admin,
              let currentUserId = appState.currentUser?.id else { return false }
        return member.userId != currentUserId
    }

    private func inviteCopy(_ invite: GroupInvitation) -> String {
        let suffix = invite.expirationSummary.map { " \($0)." } ?? ""
        switch invite.role {
        case .admin:
            return "Will join as a Care Organizer with full-circle visibility.\(suffix)"
        case .member:
            return "Will join as a Caregiver. Receiver access is granted separately after they join.\(suffix)"
        case .recipient:
            return "Will join as a Care Receiver.\(suffix)"
        }
    }

    private func caregiverAccessSummary(for member: CircleMember) -> String {
        let summaries = recipientAccessByMemberId[member.id] ?? []
        let granted = summaries.filter(\.hasAccess)
        if summaries.isEmpty {
            return "No care receiver access yet. Assign support scope before they can coordinate care."
        }
        if granted.isEmpty {
            return "No care receiver access yet. Assign support scope before they can coordinate care."
        }
        if granted.count == 1, let first = granted.first {
            return "Supporting \(first.name) only."
        }
        let names = granted.map(\.name)
        return "Supporting \(names.prefix(2).joined(separator: " and "))\(granted.count > 2 ? " + \(granted.count - 2) more" : "")."
    }

    private func receiverAccountCopy(for member: CircleMember) -> String {
        if let recipient = (appState.activeCircle?.recipients ?? []).first(where: { $0.receiverUserId == member.userId }) {
            return recipient.activationStatusDetail
        }
        return "Linked to this Care Circle for direct task reminders."
    }

    private func refreshData() async {
        await loadInvitations()
        await loadRecipientAccess()
    }

    private func loadInvitations() async {
        guard appState.userRole == .admin else {
            pendingInvitations = []
            return
        }

        if UITestScenario.current != nil {
            pendingInvitations = appState.uiTestInvitations
            return
        }

        guard let circleId = appState.activeCircle?.id else {
            pendingInvitations = []
            return
        }

        do {
            pendingInvitations = try await APIClient.shared.fetchInvitations(circleId: circleId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadRecipientAccess() async {
        guard appState.userRole == .admin else {
            recipientAccessByMemberId = [:]
            return
        }

        if UITestScenario.current != nil {
            recipientAccessByMemberId = appState.uiTestRecipientAccessByMemberId
            return
        }

        guard let circleId = appState.activeCircle?.id else {
            recipientAccessByMemberId = [:]
            return
        }

        var accessMap: [String: [RecipientAccessSummary]] = [:]
        for caregiver in caregivers {
            do {
                accessMap[caregiver.id] = try await APIClient.shared.fetchRecipientAccess(circleId: circleId, memberId: caregiver.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
        recipientAccessByMemberId = accessMap
    }

    private func remove(_ member: CircleMember) async {
        guard let circleId = appState.activeCircle?.id else { return }

        loadingMemberId = member.id
        error = nil
        defer { loadingMemberId = nil }

        do {
            try await APIClient.shared.removeMember(circleId: circleId, memberId: member.id)
            try await appState.activateCircle(id: circleId)
            await refreshData()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func updateRole(_ member: CircleMember, role: MemberRole) async {
        guard let circleId = appState.activeCircle?.id else { return }

        loadingMemberId = member.id
        error = nil
        defer { loadingMemberId = nil }

        do {
            _ = try await APIClient.shared.updateMemberRole(circleId: circleId, memberId: member.id, role: role)
            try await appState.activateCircle(id: circleId)
            await refreshData()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func revoke(_ invite: GroupInvitation) async {
        guard let circleId = appState.activeCircle?.id else { return }

        loadingMemberId = invite.id
        error = nil
        defer { loadingMemberId = nil }

        do {
            if UITestScenario.current != nil {
                pendingInvitations.removeAll { $0.id == invite.id }
                appState.uiTestInvitations.removeAll { $0.id == invite.id }
                return
            }
            try await APIClient.shared.revokeInvitation(circleId: circleId, invitationId: invite.id)
            await refreshData()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resend(_ invite: GroupInvitation) async {
        guard let circleId = appState.activeCircle?.id else { return }

        loadingMemberId = invite.id
        error = nil
        defer { loadingMemberId = nil }

        do {
            if UITestScenario.current != nil {
                let refreshed = invite.replacingExpiration(Date().addingTimeInterval(14 * 24 * 60 * 60))
                pendingInvitations.replace(invite, with: refreshed)
                appState.uiTestInvitations.replace(invite, with: refreshed)
                return
            }
            _ = try await APIClient.shared.resendInvitation(circleId: circleId, invitationId: invite.id)
            await refreshData()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct CaregiverAccessView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let member: CircleMember
    @State private var access: [RecipientAccessSummary]
    @State private var loadingRecipientId: String?
    @State private var error: String?

    init(member: CircleMember, initialAccess: [RecipientAccessSummary]) {
        self.member = member
        _access = State(initialValue: initialAccess)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose which care receivers \(member.user?.name ?? "this caregiver") can support. They will only see receiver-specific tasks and progress inside the receivers you grant.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Receiver Access") {
                    if access.isEmpty {
                        Text("No care receivers available yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(access.enumerated()), id: \.element.id) { index, summary in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: toggleBinding(for: index)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(summary.name)
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        Text(summary.activationStatus.label)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(loadingRecipientId == summary.recipientId)
                                .accessibilityIdentifier("access-toggle-\(summary.recipientId)")

                                if loadingRecipientId == summary.recipientId {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(member.user?.name ?? "Receiver Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("caregiver-access-done")
                }
            }
        }
        .accessibilityIdentifier("caregiver-access-screen")
    }

    private func toggleBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { access[index].hasAccess },
            set: { newValue in
                Task { await setAccess(newValue, for: index) }
            }
        )
    }

    private func setAccess(_ hasAccess: Bool, for index: Int) async {
        guard let circleId = appState.activeCircle?.id else { return }
        let summary = access[index]
        loadingRecipientId = summary.recipientId
        error = nil
        defer { loadingRecipientId = nil }

        do {
            if UITestScenario.current != nil {
                access[index] = RecipientAccessSummary(
                    recipientId: summary.recipientId,
                    name: summary.name,
                    activationStatus: summary.activationStatus,
                    hasAccess: hasAccess,
                    grantedAt: hasAccess ? Date() : nil
                )
                appState.uiTestRecipientAccessByMemberId[member.id] = access
                return
            }

            if hasAccess {
                try await APIClient.shared.grantRecipientAccess(circleId: circleId, memberId: member.id, recipientId: summary.recipientId)
            } else {
                try await APIClient.shared.revokeRecipientAccess(circleId: circleId, memberId: member.id, recipientId: summary.recipientId)
            }

            access = try await APIClient.shared.fetchRecipientAccess(circleId: circleId, memberId: member.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct InviteMemberView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var role: MemberRole = .member
    @State private var confirmedAdult = false
    @State private var loading = false
    @State private var error: String?

    private var canInvite: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidEmail(email) &&
        confirmedAdult &&
        !loading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite Support Person") {
                    TextField("Full name", text: $name)
                        .accessibilityIdentifier("invite-caregiver-name-field")
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("invite-caregiver-email-field")
                    Picker("Role", selection: $role) {
                        Text(MemberRole.member.displayLabel).tag(MemberRole.member)
                        Text(MemberRole.admin.displayLabel).tag(MemberRole.admin)
                    }
                    .pickerStyle(.segmented)
                    Text(roleInviteDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: $confirmedAdult) {
                        Text("I confirm this person is 18 years or older")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .accessibilityIdentifier("invite-caregiver-adult-toggle")
                } footer: {
                    Text("CareLoop is for adults only. Invite flows for minors will be supported in a future update.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Invite Caregiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") {
                        Task { await sendInvite() }
                    }
                    .accessibilityIdentifier("invite-caregiver-submit-button")
                    .disabled(!canInvite)
                }
            }
        }
    }

    private func sendInvite() async {
        guard let circleId = appState.activeCircle?.id else { return }
        loading = true
        error = nil
        do {
            _ = try await APIClient.shared.inviteMember(
                circleId: circleId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                role: role
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }

    private var roleInviteDescription: String {
        switch role {
        case .admin:
            return "Care Organizer: full-circle visibility, people management, and settings control."
        case .member:
            return "Caregiver: can create, assign, and complete tasks inside the receiver scope you grant."
        case .recipient:
            return "Use Care Receiver invites from the Care Receiver Management screen."
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".")
    }
}
