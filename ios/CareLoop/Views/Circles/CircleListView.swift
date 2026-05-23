import SwiftUI

// MARK: — Circle list

struct CircleListView: View {
    @EnvironmentObject private var appState: AppState

    @State private var loadingCircleId: String?
    @State private var loadingInviteId: String?
    @State private var error: String?
    @State private var circleSheetMode: CircleSheetMode? = nil
    @State private var showAccount = false

    private var memberships: [CircleMembership] { appState.circleMemberships }
    private var pendingInvites: [GroupInvitation] { appState.currentUser?.pendingInvites ?? [] }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.95, green: 0.97, blue: 1.00).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        header.padding(.horizontal, 22).padding(.top, 14)

                        titleBlock.padding(.horizontal, 22).padding(.top, 30)

                        if memberships.isEmpty && pendingInvites.isEmpty {
                            WelcomeCardsView(
                                onCreateCircle: { error = nil; circleSheetMode = .create },
                                onJoinCircle:   { error = nil; circleSheetMode = .join }
                            )
                            .padding(.horizontal, 22)
                            .padding(.top, 16)
                        }

                        if !memberships.isEmpty {
                            circlesSection.padding(.top, 26)
                        }

                        if !pendingInvites.isEmpty {
                            invitesSection.padding(.top, 22)
                        }

                        if !memberships.isEmpty {
                            directoryActionsSection
                                .padding(.horizontal, 22)
                                .padding(.top, 14)
                                .padding(.bottom, 44)
                        } else {
                            Spacer(minLength: 40)
                        }

                        if let error {
                            Text(error)
                                .font(.footnote).foregroundStyle(.red)
                                .padding(.horizontal, 22).padding(.bottom, 16)
                        }
                    }
                }
                .refreshable {
                    do { try await appState.refreshMemberships() }
                    catch let loadError { error = loadError.localizedDescription }
                }
                .accessibilityIdentifier("circle-directory-screen")
            }
            .navigationBarHidden(true)
            .sheet(item: $circleSheetMode) { mode in
                JoinCircleView(dismissOnSuccess: true, startInCreateMode: mode.startInCreateMode)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showAccount) {
                AccountSheet().environmentObject(appState)
            }
        }
    }

    // MARK: — Header

    private var header: some View {
        HStack(alignment: .center) {
            CareLoopBrandView(style: .wordmark, surface: .light, wordmarkHeight: 17)
            Spacer()
            Button { showAccount = true } label: { avatarView }
                .accessibilityLabel("Account")
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Text(userInitials)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
    }

    private var userInitials: String {
        let raw = (appState.currentUser?.name ?? "")
            .split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined().uppercased()
        return raw.isEmpty ? "?" : raw
    }

    // MARK: — Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let firstName = appState.currentUser?.name
                .split(separator: " ").first.map(String.init) {
                Text("Hi, \(firstName)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.13, green: 0.56, blue: 0.87))
            }
            Text("Your Care Circles")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.22))
            Text("Choose a care circle to continue.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.44, green: 0.52, blue: 0.64))

            if !memberships.isEmpty {
                HStack(spacing: 8) {
                    statPill("\(memberships.count)", label: memberships.count == 1 ? "care circle" : "care circles", icon: "circle.grid.2x2.fill")
                    if !pendingInvites.isEmpty {
                        statPill("\(pendingInvites.count)", label: pendingInvites.count == 1 ? "invite" : "invites", icon: "envelope.fill")
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statPill(_ count: String, label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text("\(count) \(label)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Color(red: 0.35, green: 0.43, blue: 0.56))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color(red: 0.88, green: 0.93, blue: 0.99)))
    }

    // MARK: — Circles

    private var circlesSection: some View {
        VStack(spacing: 10) {
            ForEach(memberships) { membership in
                let circle = membership.circle ?? CareCircle(
                    id: membership.circleId, name: "Care Circle", recipientName: "Family"
                )
                Button { Task { await openCircle(circle.id) } } label: {
                    circleCard(circle: circle, role: membership.role)
                }
                .buttonStyle(.plain)
                .disabled(loadingCircleId != nil || loadingInviteId != nil)
            }
        }
        .padding(.horizontal, 22)
    }

    @ViewBuilder
    private func circleCard(circle: CareCircle, role: MemberRole) -> some View {
        let isActive  = circle.id == appState.rememberedCircleId
        let isLoading = loadingCircleId == circle.id

        HStack(spacing: 14) {
            // Gradient icon
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image("CareLoopIcon")
                    .resizable().scaledToFit().padding(10)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(circle.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.22))
                    .lineLimit(1)

                Text(recipientSubtitle(for: circle, role: role))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.44, green: 0.52, blue: 0.64))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    if isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.07, green: 0.68, blue: 0.48))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color(red: 0.87, green: 0.97, blue: 0.93)))
                    }
                    rolePill(role)
                }
            }

            Spacer(minLength: 8)

            if isLoading {
                ProgressView().scaleEffect(0.75)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.65, green: 0.74, blue: 0.88))
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .shadow(
                    color: Color(red: 0.13, green: 0.22, blue: 0.45)
                        .opacity(isActive ? 0.11 : 0.06),
                    radius: isActive ? 14 : 8, x: 0, y: 3
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isActive ? Color(red: 0.13, green: 0.56, blue: 0.87).opacity(0.18) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }

    // MARK: — Pending invites

    private var invitesSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Pending Invites")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.44, green: 0.52, blue: 0.64))
                    .textCase(.uppercase).tracking(0.4)
                ZStack {
                    Circle().fill(Color(red: 0.98, green: 0.42, blue: 0.32))
                    Text("\(pendingInvites.count)")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
                Spacer()
            }
            .padding(.horizontal, 22)

            ForEach(pendingInvites) { invite in
                inviteCard(invite).padding(.horizontal, 22)
            }
        }
    }

    @ViewBuilder
    private func inviteCard(_ invite: GroupInvitation) -> some View {
        let isRecipientInvite = invite.role == .recipient
        let rose = Color(red: 0.85, green: 0.30, blue: 0.50)
        let amber = Color(red: 0.96, green: 0.63, blue: 0.28)
        let accentColor = isRecipientInvite ? rose : amber

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isRecipientInvite
                              ? Color(red: 0.99, green: 0.91, blue: 0.94)
                              : Color(red: 0.99, green: 0.96, blue: 0.91))
                    Image(systemName: isRecipientInvite ? "heart.circle.fill" : "envelope.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(invite.circle.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.22))
                    let inviteSubtitle: String = {
                        if isRecipientInvite { return "Your care is organized in this circle" }
                        if invite.role == .member { return "Receiver access is granted after you join." }
                        let s = invite.circle.recipientDisplaySummary
                        return s.isEmpty ? "Care circle" : s
                    }()
                    Text(inviteSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary).lineLimit(1)
                    if let by = invite.invitedBy {
                        Text("From \(by.name)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let expirationSummary = invite.expirationSummary {
                        Text(expirationSummary)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(expirationSummary == "Expired" ? .red : .orange)
                    }
                }
                Spacer()
                rolePill(invite.role)
            }

            HStack(spacing: 10) {
                Button { Task { await accept(invite) } } label: {
                    Group {
                        if loadingInviteId == invite.id {
                            ProgressView().tint(.white)
                        } else {
                            Text("Accept")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.13, green: 0.56, blue: 0.87)))
                    .foregroundStyle(.white)
                }
                .disabled(loadingInviteId != nil || loadingCircleId != nil || !invite.canRespond)
                .accessibilityIdentifier("circle-list-invite-accept-\(invite.id)")

                Button { Task { await decline(invite) } } label: {
                    Text("Decline")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.92, green: 0.95, blue: 0.99)))
                        .foregroundStyle(Color(red: 0.35, green: 0.43, blue: 0.56))
                }
                .disabled(loadingInviteId != nil || loadingCircleId != nil || !invite.canRespond)
                .accessibilityIdentifier("circle-list-invite-decline-\(invite.id)")
            }

            if let responseUnavailableReason = invite.responseUnavailableReason {
                Text(responseUnavailableReason)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .shadow(color: Color(red: 0.13, green: 0.22, blue: 0.45).opacity(0.06), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accentColor.opacity(0.22), lineWidth: 1.5)
        )
    }

    // MARK: — Directory actions

    private var directoryActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next Step")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.44, green: 0.52, blue: 0.64))
                .textCase(.uppercase)
                .tracking(0.4)

            Button {
                error = nil
                circleSheetMode = .create
            } label: {
                actionCard(
                    title: "Create a Care Circle",
                    subtitle: "Start a new family care workspace",
                    icon: "plus",
                    accent: Color(red: 0.13, green: 0.56, blue: 0.87),
                    fill: Color(red: 0.88, green: 0.95, blue: 1.0)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("create-circle-button")

            Button {
                error = nil
                circleSheetMode = .join
            } label: {
                actionCard(
                    title: "Join a Care Circle",
                    subtitle: "Use an invite or Care Circle code",
                    icon: "person.badge.plus",
                    accent: Color(red: 0.16, green: 0.60, blue: 0.55),
                    fill: Color(red: 0.89, green: 0.97, blue: 0.95)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("join-circle-button")
        }
    }

    private func actionCard(title: String, subtitle: String, icon: String, accent: Color, fill: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(fill).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.22))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.44, green: 0.52, blue: 0.64))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.65, green: 0.74, blue: 0.88))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
                .shadow(color: Color(red: 0.13, green: 0.22, blue: 0.45).opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: — Shared

    @ViewBuilder
    private func rolePill(_ role: MemberRole) -> some View {
        let (label, fg, bg): (String, Color, Color) = {
            switch role {
            case .admin:
                return ("Care Organizer", Color(red: 0.13, green: 0.56, blue: 0.87), Color(red: 0.88, green: 0.95, blue: 1.0))
            case .member:
                return ("Caregiver", Color(red: 0.35, green: 0.43, blue: 0.56), Color(red: 0.92, green: 0.95, blue: 0.99))
            case .recipient:
                return ("Care Receiver", Color(red: 0.85, green: 0.30, blue: 0.50), Color(red: 0.99, green: 0.91, blue: 0.94))
            }
        }()
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(fg)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(bg))
    }

    private func recipientSubtitle(for circle: CareCircle, role: MemberRole) -> String {
        if role == .recipient { return "This care circle is organized for your care" }
        let names = circle.recipientNames
        switch names.count {
        case 0:  return "Invite care receivers to get started"
        case 1:  return "Caring for \(names[0])"
        case 2:  return "Caring for \(names[0]) and \(names[1])"
        default: return "Caring for \(names[0]) + \(names.count - 1) more"
        }
    }

    // MARK: — Actions

    private func openCircle(_ circleId: String) async {
        guard loadingCircleId == nil else { return }
        loadingCircleId = circleId; error = nil
        defer { loadingCircleId = nil }
        do { try await appState.activateCircle(id: circleId) }
        catch { self.error = error.localizedDescription }
    }

    private func accept(_ invite: GroupInvitation) async {
        guard appState.currentUser != nil, loadingInviteId == nil else { return }
        loadingInviteId = invite.id; error = nil
        defer { loadingInviteId = nil }
        do {
            if UITestScenario.current != nil {
                var acceptedCircle = invite.circle
                if invite.role == .member {
                    let currentUser = appState.currentUser
                    acceptedCircle = CareCircle(
                        id: acceptedCircle.id,
                        name: acceptedCircle.name,
                        recipientName: "",
                        archiveAfterDays: acceptedCircle.archiveAfterDays,
                        members: acceptedCircle.members,
                        recipients: acceptedCircle.recipients,
                        tasks: acceptedCircle.tasks
                    )
                    acceptedCircle.recipients = []
                    acceptedCircle.tasks = []
                    acceptedCircle.members = (acceptedCircle.members ?? []).filter { $0.role == .admin }
                    if let currentUser {
                        acceptedCircle.members?.append(
                            CircleMember(
                                id: "cm-\(invite.id)",
                                role: invite.role,
                                userId: currentUser.id,
                                user: currentUser
                            )
                        )
                    }
                }
                appState.currentUser?.pendingInvites?.removeAll { $0.id == invite.id }
                appState.currentUser?.memberships = [
                    CircleMembership(id: "cm-\(invite.id)", circleId: acceptedCircle.id, role: invite.role, circle: acceptedCircle)
                ]
                appState.attachCircle(acceptedCircle)
                return
            }
            _ = try await APIClient.shared.acceptInvitation(invitationId: invite.id)
            try await appState.refreshMemberships()
        } catch { self.error = error.localizedDescription }
    }

    private func decline(_ invite: GroupInvitation) async {
        guard appState.currentUser != nil, loadingInviteId == nil else { return }
        loadingInviteId = invite.id; error = nil
        defer { loadingInviteId = nil }
        do {
            if UITestScenario.current != nil {
                appState.currentUser?.pendingInvites?.removeAll { $0.id == invite.id }
                appState.uiTestInvitations.removeAll { $0.id == invite.id }
                return
            }
            try await APIClient.shared.declineInvitation(invitationId: invite.id)
            try await appState.refreshMemberships()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: — Sheet mode

private enum CircleSheetMode: Identifiable {
    case create, join
    var id: Self { self }
    var startInCreateMode: Bool? {
        switch self {
        case .create: return true
        case .join:   return false
        }
    }
}

// MARK: — Account sheet

struct AccountSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                            Text(initials)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 52, height: 52)

                        if let user = appState.currentUser {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.name)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                Text(user.email)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                if let user = appState.currentUser {
                    Section("Profile") {
                        LabeledContent("Name",  value: user.name)
                        LabeledContent("Email", value: user.email)
                    }
                }

                Section("Premium") {
                    if let snapshot = subscriptions.latestPurchaseSnapshot {
                        HStack {
                            Label("App Store Subscription", systemImage: "crown.fill")
                                .foregroundStyle(Color(red: 0.55, green: 0.22, blue: 0.97))
                            Spacer()
                            Text("Connected")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.07, green: 0.68, blue: 0.48))
                        }
                        if let renewal = snapshot.expirationDate {
                            LabeledContent("Renews", value: renewal, format: .dateTime.month().day().year())
                        }
                        Text("Premium access is managed per care receiver. Active purchases are synced when a Care Organizer upgrades a specific receiver.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Manage Subscription") {
                            subscriptions.openSubscriptionManagement()
                        }
                        .foregroundStyle(Color(red: 0.13, green: 0.56, blue: 0.87))
                    } else {
                        Text("Premium is unlocked one care receiver at a time from inside a Care Circle.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appState.signOut()
                        }
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var initials: String {
        let raw = (appState.currentUser?.name ?? "")
            .split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined().uppercased()
        return raw.isEmpty ? "?" : raw
    }
}
