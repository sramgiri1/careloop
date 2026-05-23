import SwiftUI

struct RecipientManagementView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateRecipient = false
    @State private var showAddReceiverUpgradeGate = false
    @State private var addReceiverUsesPremiumIntent = false
    @State private var editingRecipient: CareRecipient?
    @State private var invitingRecipient: CareRecipient?
    @State private var proxyRecipient: CareRecipient?
    @State private var activationDecisionRecipient: CareRecipient?
    @State private var removalRecipient: CareRecipient?
    @State private var paywallRecipient: CareRecipient?
    @State private var managementRecipient: CareRecipient?
    @State private var loadingRecipientId: String?
    @State private var loadingInviteId: String?
    @State private var error: String?
    @State private var pendingInvites: [GroupInvitation] = []
    @State private var upgradeRequests: [PremiumUpgradeRequestSummary] = []

    private let rose = Color(red: 0.85, green: 0.30, blue: 0.50)
    private let blue = Color(red: 0.13, green: 0.56, blue: 0.87)
    private let teal = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let dark = Color(red: 0.10, green: 0.16, blue: 0.24)
    private let mid = Color(red: 0.43, green: 0.50, blue: 0.60)
    private let bg = Color(red: 0.95, green: 0.96, blue: 0.99)

    private var recipients: [CareRecipient] {
        appState.activeCircle?.orderedRecipients ?? []
    }

    private var firstPremiumRecipient: CareRecipient? {
        recipients.first(where: \.hasPremium)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    infoBanner
                        .padding(.horizontal, 20)

                    if let firstPremiumRecipient {
                        Button {
                            managementRecipient = firstPremiumRecipient
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color(red: 0.55, green: 0.22, blue: 0.97))
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color(red: 0.55, green: 0.22, blue: 0.97).opacity(0.12)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Manage Premium")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(dark)
                                    Text("\(firstPremiumRecipient.name)'s receiver-specific plan")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(mid)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(mid.opacity(0.65))
                            }
                            .padding(16)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("manage-premium-top-button")
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                            .accessibilityIdentifier("recipient-management-error")
                    }

                    if !upgradeRequests.isEmpty {
                        upgradeRequestSection
                            .padding(.horizontal, 20)
                    }

                    if !pendingInvites.isEmpty {
                        pendingSection
                            .padding(.horizontal, 20)
                    }

                    if !recipients.isEmpty {
                        recipientsSection
                            .padding(.horizontal, 20)
                    }

                    if recipients.isEmpty && pendingInvites.isEmpty {
                        emptyState
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 20)
            }
            .accessibilityIdentifier("receiver-management-scroll")
            .background(bg.ignoresSafeArea())
            .navigationTitle("Care Receiver Management")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startAddRecipient()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("add-care-receiver-button")
                }
            }
            .sheet(isPresented: $showCreateRecipient, onDismiss: { Task { await refreshData() } }) {
                RecipientEditorSheet(title: "Add Care Receiver") { name, relationship, notes, inviteEmail in
                    try await createRecipient(name: name, relationship: relationship, notes: notes, inviteEmail: inviteEmail)
                }
                .environmentObject(appState)
            }
            .confirmationDialog(
                "Premium is required to add another care receiver",
                isPresented: $showAddReceiverUpgradeGate,
                titleVisibility: .visible
            ) {
                Button("Upgrade and add receiver") {
                    addReceiverUsesPremiumIntent = true
                    showCreateRecipient = true
                }
                Button("Cancel", role: .cancel) {
                    addReceiverUsesPremiumIntent = false
                }
            } message: {
                Text("Your free plan includes one care receiver. Upgrade before adding another receiver to this Care Circle.")
            }
            .sheet(item: $editingRecipient, onDismiss: { Task { await refreshData() } }) { recipient in
                RecipientEditorSheet(title: "Edit Care Receiver", recipient: recipient) { name, relationship, notes, _ in
                    try await updateRecipient(recipient, name: name, relationship: relationship, notes: notes)
                }
                .environmentObject(appState)
            }
            .sheet(item: $invitingRecipient, onDismiss: { Task { await refreshData() } }) { recipient in
                RecipientInviteSheet(recipient: recipient) { email in
                    try await sendInvite(for: recipient, email: email)
                }
                .environmentObject(appState)
            }
            .sheet(item: $activationDecisionRecipient) { recipient in
                ReceiverActivationDecisionSheet(
                    recipient: recipient,
                    onChooseDirectInvite: { showDirectInvite(for: recipient) },
                    onChooseProxyActivation: { showProxyActivation(for: recipient) }
                )
            }
            .sheet(item: $proxyRecipient, onDismiss: { Task { await refreshData() } }) { recipient in
                ProxyActivationSheet(recipient: recipient) { consentDocumentReference, authorizationAttested in
                    try await proxyActivate(
                        recipient,
                        consentDocumentReference: consentDocumentReference,
                        authorizationAttested: authorizationAttested
                    )
                }
                .environmentObject(appState)
            }
            .sheet(item: $paywallRecipient) { recipient in
                PaywallView(circleId: appState.activeCircle?.id ?? "", recipient: recipient)
                    .environmentObject(appState)
            }
            .sheet(item: $managementRecipient) { recipient in
                ReceiverPremiumManagementView(
                    circleId: appState.activeCircle?.id ?? "",
                    recipient: recipient
                )
            }
            .confirmationDialog(
                "Remove \(removalRecipient?.name ?? "care receiver")?",
                isPresented: Binding(
                    get: { removalRecipient != nil },
                    set: { if !$0 { removalRecipient = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Care Receiver", role: .destructive) {
                    guard let recipient = removalRecipient else { return }
                    removalRecipient = nil
                    Task { await removeRecipient(recipient) }
                }
                Button("Cancel", role: .cancel) {
                    removalRecipient = nil
                }
            } message: {
                Text("Only unused care receiver profiles can be removed. Move or archive their tasks first, and every circle must keep at least one receiver.")
            }
            .task { await refreshData() }
            .refreshable {
                if let id = appState.activeCircle?.id {
                    try? await appState.activateCircle(id: id)
                }
                await refreshData()
            }
        }
        .accessibilityIdentifier("receiver-management-screen")
        .careLoopBrandBanner()
    }

    private var infoBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rose.opacity(0.10))
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(rose)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("Activation controls task access")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                Text("Care tasks stay blocked until a care receiver joins directly or is proxy-activated with recorded consent.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Pending Invites", icon: "envelope.fill", color: Color.orange)

            VStack(spacing: 0) {
                ForEach(Array(pendingInvites.enumerated()), id: \.element.id) { index, invite in
                    pendingRow(invite)
                    if index < pendingInvites.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
    }

    private var upgradeRequestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Upgrade Requests", icon: "paperplane.fill", color: Color(red: 0.55, green: 0.22, blue: 0.97))

            VStack(spacing: 0) {
                ForEach(Array(upgradeRequests.enumerated()), id: \.element.id) { index, request in
                    upgradeRequestRow(request)
                    if index < upgradeRequests.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
    }

    private func upgradeRequestRow(_ request: PremiumUpgradeRequestSummary) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.55, green: 0.22, blue: 0.97).opacity(0.12))
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.22, blue: 0.97))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(request.requestCount) \(request.requestCount == 1 ? "caregiver" : "caregivers") requested Premium for \(request.recipientName)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                if let latestRequesterName = request.latestRequesterName {
                    Text("Latest request from \(latestRequesterName).")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(mid)
                }
                Text("Review the receiver plan below. This request does not start a purchase.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier("premium-request-\(request.recipientId)")
    }

    private func pendingRow(_ invite: GroupInvitation) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                Image(systemName: "clock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.orange)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(invite.recipient?.name ?? invite.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(dark)
                Text(invite.email)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                Text("Waiting for direct acceptance before tasks can begin.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                if let expirationSummary = invite.expirationSummary {
                    Text(expirationSummary)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(expirationSummary == "Expired" ? .red : .orange)
                }
            }

            Spacer()

            if loadingInviteId == invite.id {
                ProgressView().scaleEffect(0.8)
            } else {
                VStack(spacing: 8) {
                    Button {
                        Task { await resendInvite(invite) }
                    } label: {
                        Text("Resend")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recipient-invite-resend-\(invite.id)")

                    Button(role: .destructive) {
                        Task { await revokeInvite(invite) }
                    } label: {
                        Text("Revoke")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recipient-invite-revoke-\(invite.id)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var recipientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Care Receivers", icon: "heart.fill", color: rose)

            VStack(spacing: 12) {
                ForEach(Array(recipients.enumerated()), id: \.element.id) { index, recipient in
                    recipientCard(recipient, index: index)
                }
            }
        }
    }

    private func recipientCard(_ recipient: CareRecipient, index: Int) -> some View {
        let statusColor = color(for: recipient.activationStatus)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(statusColor.opacity(0.10))
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(recipient.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(dark)
                        if recipient.isPrimary {
                            chip("Primary", tint: blue)
                        }
                    }
                    if let relationship = recipient.relationship, !relationship.isEmpty {
                        Text(relationship)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(mid)
                    }
                    Text(recipient.activationStatusDetail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(mid)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recipient.premiumStatusDetail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(recipient.hasPremium ? teal : mid)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        premiumStatusIcon(for: recipient)
                        Text(recipient.premiumPlanSummaryLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(recipient.hasPremium ? Color(red: 0.55, green: 0.22, blue: 0.97) : mid)
                        if recipient.hasPremium {
                            Button("Manage") {
                                managementRecipient = recipient
                            }
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(Color(red: 0.55, green: 0.22, blue: 0.97))
                            .accessibilityIdentifier("recipient-manage-plan-\(recipient.id)")
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    chip(recipient.activationStatus.label, tint: statusColor)
                    if loadingRecipientId == recipient.id {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Menu {
                            Button("Edit Details") {
                                editingRecipient = recipient
                            }
                            if !recipient.hasPremium {
                                Button("Unlock Premium") {
                                    paywallRecipient = recipient
                                }
                            } else {
                                Button("Manage Premium") {
                                    managementRecipient = recipient
                                }
                            }
                            if !recipient.isPrimary {
                                Button("Make Primary") {
                                    Task { await setPrimary(recipient) }
                                }
                            }
                            if index > 0 {
                                Button("Move Earlier") {
                                    Task { await moveRecipient(recipient, direction: -1) }
                                }
                            }
                            if index < recipients.count - 1 {
                                Button("Move Later") {
                                    Task { await moveRecipient(recipient, direction: 1) }
                                }
                            }
                            if canChooseActivationPath(for: recipient) {
                                Button("Activation Options") {
                                    activationDecisionRecipient = recipient
                                }
                            }
                            Button("Remove", role: .destructive) {
                                removalRecipient = recipient
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("recipient-actions-\(recipient.id)")
                        }
                        .accessibilityIdentifier("recipient-actions-menu-\(recipient.id)")
                    }
                }
            }

            if let notes = recipient.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(dark)
                    .padding(.top, 2)
            }

            if canChooseActivationPath(for: recipient) {
                Button {
                    activationDecisionRecipient = recipient
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                        Text("Choose activation path")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(teal)
                .accessibilityIdentifier("recipient-activation-path-\(recipient.id)")
                .padding(.top, 6)
            }

            if !recipient.hasPremium {
                Button {
                    paywallRecipient = recipient
                } label: {
                    Label("Upgrade \(recipient.name)", systemImage: "crown.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.55, green: 0.22, blue: 0.97))
                .accessibilityIdentifier("recipient-upgrade-\(recipient.id)")
            } else {
                Button {
                    managementRecipient = recipient
                } label: {
                    Label("Manage \(recipient.name) plan", systemImage: "gearshape.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.55, green: 0.22, blue: 0.97))
                .accessibilityIdentifier("recipient-manage-plan-footer-\(recipient.id)")
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .accessibilityIdentifier("recipient-card-\(recipient.id)")
    }

    private func canChooseActivationPath(for recipient: CareRecipient) -> Bool {
        recipient.activationStatus != .proxyActive && (recipient.receiverUserId == nil || !recipient.isActiveForTasks)
    }

    private func premiumStatusIcon(for recipient: CareRecipient) -> some View {
        Image(systemName: recipient.premiumStatusIconName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(recipient.hasPremium ? Color(red: 0.55, green: 0.22, blue: 0.97) : mid)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill((recipient.hasPremium ? Color(red: 0.55, green: 0.22, blue: 0.97) : mid).opacity(0.11))
            )
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(false)
            .accessibilityLabel(recipient.premiumStatusAccessibilityLabel)
            .accessibilityIdentifier("recipient-plan-badge-\(recipient.id)")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(rose.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "heart.circle")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(rose)
            }
            VStack(spacing: 6) {
                Text("No care receivers yet")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                Text("Add a draft profile or send an invite. Tasks stay blocked until the care receiver becomes active or proxy-active.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                    .multilineTextAlignment(.center)
            }
            Button {
                startAddRecipient()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Care Receiver")
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [rose, Color(red: 0.95, green: 0.55, blue: 0.30)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func startAddRecipient() {
        error = nil
        addReceiverUsesPremiumIntent = false
        if recipients.isEmpty {
            showCreateRecipient = true
        } else {
            showAddReceiverUpgradeGate = true
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

    private func chip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private func color(for status: CareReceiverActivationStatus) -> Color {
        switch status {
        case .draft: return mid
        case .invited: return Color.orange
        case .active: return Color(red: 0.07, green: 0.68, blue: 0.48)
        case .proxyActive: return teal
        }
    }

    private func refreshData() async {
        await loadPendingInvites()
        await loadUpgradeRequests()
    }

    private func loadPendingInvites() async {
        guard let circleId = appState.activeCircle?.id else { return }
        if UITestScenario.current != nil {
            pendingInvites = appState.uiTestInvitations.filter { $0.role == .recipient }
            return
        }
        do {
            let all = try await APIClient.shared.fetchInvitations(circleId: circleId)
            pendingInvites = all.filter { $0.role == .recipient }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadUpgradeRequests() async {
        guard let circleId = appState.activeCircle?.id else { return }
        if UITestScenario.current != nil {
            upgradeRequests = appState.uiTestPremiumUpgradeRequests
            return
        }
        do {
            upgradeRequests = try await APIClient.shared.fetchPremiumUpgradeRequests(circleId: circleId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createRecipient(name: String, relationship: String?, notes: String?, inviteEmail: String?) async throws {
        guard let circleId = appState.activeCircle?.id else { return }
        if UITestScenario.current != nil {
            var circle = appState.activeCircle
            let existingRecipients = circle?.recipients ?? []
            let created = CareRecipient(
                id: "ui-recipient-\(existingRecipients.count + 1)",
                name: name,
                relationship: relationship,
                notes: notes,
                isPrimary: existingRecipients.isEmpty,
                sortOrder: existingRecipients.count,
                activationStatus: inviteEmail?.isEmpty == false ? .invited : .draft,
                premium: .free
            )
            circle?.recipients = existingRecipients + [created]
            if let circle {
                appState.attachCircle(circle)
            }
            addReceiverUsesPremiumIntent = false
            return
        }
        let created = try await APIClient.shared.createRecipient(
            circleId: circleId,
            name: name,
            relationship: relationship,
            notes: notes,
            premiumIntent: addReceiverUsesPremiumIntent ? "ADD_RECEIVER" : nil
        )
        addReceiverUsesPremiumIntent = false
        if let inviteEmail, !inviteEmail.isEmpty {
            _ = try await APIClient.shared.inviteMember(
                circleId: circleId,
                name: created.name,
                email: inviteEmail,
                role: .recipient,
                recipientId: created.id
            )
        }
        try await appState.activateCircle(id: circleId)
        await loadPendingInvites()
    }

    private func updateRecipient(_ recipient: CareRecipient, name: String, relationship: String?, notes: String?) async throws {
        guard let circleId = appState.activeCircle?.id else { return }
        if UITestScenario.current != nil {
            var circle = appState.activeCircle
            let currentRecipients = circle?.recipients ?? []
            circle?.recipients = currentRecipients.map { current in
                guard current.id == recipient.id else { return current }
                return copyRecipient(
                    current,
                    name: name,
                    relationship: .some(relationship),
                    notes: .some(notes),
                    isPrimary: current.isPrimary
                )
            }
            if let circle {
                appState.attachCircle(circle)
            }
            return
        }
        _ = try await APIClient.shared.updateRecipient(
            circleId: circleId,
            recipientId: recipient.id,
            name: name,
            relationship: relationship,
            notes: notes,
            isPrimary: recipient.isPrimary ? true : nil
        )
        try await appState.activateCircle(id: circleId)
    }

    private func sendInvite(for recipient: CareRecipient, email: String) async throws {
        guard let circleId = appState.activeCircle?.id else { return }
        if UITestScenario.current != nil {
            guard var circle = appState.activeCircle else { return }
            let currentRecipients = circle.recipients ?? []
            circle.recipients = currentRecipients.map { current in
                guard current.id == recipient.id else { return current }
                return copyRecipient(current, activationStatus: .invited)
            }
            let invite = GroupInvitation(
                id: "ui-recipient-invite-\(recipient.id)",
                email: email,
                name: recipient.name,
                role: .recipient,
                status: .pending,
                expiresAt: Date().addingTimeInterval(14 * 24 * 60 * 60),
                circle: circle,
                recipient: recipient,
                invitedBy: appState.currentUser.map { InvitationSender(id: $0.id, name: $0.name, email: $0.email) }
            )
            appState.uiTestInvitations.append(invite)
            pendingInvites.append(invite)
            appState.attachCircle(circle)
            return
        }
        _ = try await APIClient.shared.inviteMember(
            circleId: circleId,
            name: recipient.name,
            email: email,
            role: .recipient,
            recipientId: recipient.id
        )
        try await appState.activateCircle(id: circleId)
        await loadPendingInvites()
    }

    private func proxyActivate(
        _ recipient: CareRecipient,
        consentDocumentReference: String?,
        authorizationAttested: Bool
    ) async throws {
        guard let circleId = appState.activeCircle?.id else { return }
        if UITestScenario.current != nil {
            guard authorizationAttested else {
                throw APIError.httpError(400, "Proxy activation requires explicit authorization attestation")
            }
            var circle = appState.activeCircle
            let currentRecipients = circle?.recipients ?? []
            circle?.recipients = currentRecipients.map { current in
                guard current.id == recipient.id else { return current }
                return copyRecipient(current, activationStatus: .proxyActive)
            }
            if let circle {
                appState.attachCircle(circle)
            }
            return
        }
        _ = try await APIClient.shared.proxyActivateRecipient(
            circleId: circleId,
            recipientId: recipient.id,
            consentDocumentReference: consentDocumentReference,
            authorizationAttested: authorizationAttested
        )
        try await appState.activateCircle(id: circleId)
        await loadPendingInvites()
    }

    private func showDirectInvite(for recipient: CareRecipient) {
        activationDecisionRecipient = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            invitingRecipient = recipient
        }
    }

    private func showProxyActivation(for recipient: CareRecipient) {
        activationDecisionRecipient = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            proxyRecipient = recipient
        }
    }

    private func setPrimary(_ recipient: CareRecipient) async {
        guard let circleId = appState.activeCircle?.id else { return }
        loadingRecipientId = recipient.id
        error = nil
        defer { loadingRecipientId = nil }

        do {
            if UITestScenario.current != nil {
                var circle = appState.activeCircle
                let currentRecipients = circle?.recipients ?? []
                circle?.recipients = currentRecipients.map { current in
                    copyRecipient(
                        current,
                        isPrimary: current.id == recipient.id,
                        sortOrder: current.sortOrder
                    )
                }
                if let circle {
                    appState.attachCircle(circle)
                }
                return
            }
            _ = try await APIClient.shared.updateRecipient(
                circleId: circleId,
                recipientId: recipient.id,
                name: recipient.name,
                relationship: recipient.relationship,
                notes: recipient.notes,
                isPrimary: true
            )
            try await appState.activateCircle(id: circleId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func moveRecipient(_ recipient: CareRecipient, direction: Int) async {
        guard let circleId = appState.activeCircle?.id,
              let currentIndex = recipients.firstIndex(where: { $0.id == recipient.id })
        else { return }

        let nextIndex = currentIndex + direction
        guard recipients.indices.contains(nextIndex) else { return }

        loadingRecipientId = recipient.id
        error = nil
        defer { loadingRecipientId = nil }

        var reorderedIds = recipients.map(\.id)
        reorderedIds.swapAt(currentIndex, nextIndex)

        do {
            if UITestScenario.current != nil {
                var circle = appState.activeCircle
                circle?.recipients = reorderedIds.enumerated().compactMap { index, recipientId in
                    guard let current = recipients.first(where: { $0.id == recipientId }) else { return nil }
                    return copyRecipient(
                        current,
                        sortOrder: index,
                        preservePrimary: true
                    )
                }
                if let circle {
                    appState.attachCircle(circle)
                }
                return
            }
            _ = try await APIClient.shared.reorderRecipients(
                circleId: circleId,
                recipientIds: reorderedIds,
                primaryRecipientId: recipients.first(where: \.isPrimary)?.id
            )
            try await appState.activateCircle(id: circleId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func revokeInvite(_ invite: GroupInvitation) async {
        guard let circleId = appState.activeCircle?.id else { return }
        loadingInviteId = invite.id
        error = nil
        defer { loadingInviteId = nil }

        do {
            if UITestScenario.current != nil {
                pendingInvites.removeAll { $0.id == invite.id }
                appState.uiTestInvitations.removeAll { $0.id == invite.id }
                return
            }
            try await APIClient.shared.revokeInvitation(circleId: circleId, invitationId: invite.id)
            try await appState.activateCircle(id: circleId)
            await loadPendingInvites()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resendInvite(_ invite: GroupInvitation) async {
        guard let circleId = appState.activeCircle?.id else { return }
        loadingInviteId = invite.id
        error = nil
        defer { loadingInviteId = nil }

        do {
            if UITestScenario.current != nil {
                let refreshed = invite.replacingExpiration(Date().addingTimeInterval(14 * 24 * 60 * 60))
                pendingInvites.replace(invite, with: refreshed)
                appState.uiTestInvitations.replace(invite, with: refreshed)
                return
            }
            _ = try await APIClient.shared.resendInvitation(circleId: circleId, invitationId: invite.id)
            try await appState.activateCircle(id: circleId)
            await loadPendingInvites()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func removeRecipient(_ recipient: CareRecipient) async {
        guard let circleId = appState.activeCircle?.id else { return }
        loadingRecipientId = recipient.id
        error = nil
        defer { loadingRecipientId = nil }

        do {
            if UITestScenario.current != nil {
                var circle = appState.activeCircle
                let remainingRecipients = circle?.recipients?.filter { $0.id != recipient.id } ?? []
                if remainingRecipients.isEmpty {
                    error = "Every circle must keep at least one care recipient."
                    return
                }

                let hasActiveTasks = (circle?.tasks ?? []).contains { task in
                    task.recipientId == recipient.id && task.archivedAt == nil
                }
                if hasActiveTasks {
                    error = "Move or archive this recipient's tasks before removing them."
                    return
                }

                circle?.recipients?.removeAll { $0.id == recipient.id }
                if let remaining = circle?.recipients, !remaining.contains(where: \.isPrimary), let first = remaining.first {
                    circle?.recipients = remaining.map { current in
                        copyRecipient(
                            current,
                            isPrimary: current.id == first.id,
                            sortOrder: current.sortOrder
                        )
                    }
                }
                if let circle {
                    appState.attachCircle(circle)
                }
                return
            }
            try await APIClient.shared.deleteRecipient(circleId: circleId, recipientId: recipient.id)
            try await appState.activateCircle(id: circleId)
            await loadPendingInvites()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func copyRecipient(
        _ recipient: CareRecipient,
        name: String? = nil,
        relationship: String?? = nil,
        notes: String?? = nil,
        activationStatus: CareReceiverActivationStatus? = nil,
        isPrimary: Bool? = nil,
        sortOrder: Int? = nil,
        preservePrimary: Bool = false
    ) -> CareRecipient {
        CareRecipient(
            id: recipient.id,
            name: name ?? recipient.name,
            relationship: relationship ?? recipient.relationship,
            notes: notes ?? recipient.notes,
            isPrimary: preservePrimary ? recipient.isPrimary : (isPrimary ?? recipient.isPrimary),
            sortOrder: sortOrder ?? recipient.sortOrder,
            activationStatus: activationStatus ?? recipient.activationStatus,
            receiverUserId: recipient.receiverUserId,
            eligibleAssigneeIds: recipient.eligibleAssigneeIds,
            premium: recipient.premium
        )
    }
}

private struct RecipientEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let recipient: CareRecipient?
    let onSave: (String, String?, String?, String?) async throws -> Void

    @State private var name = ""
    @State private var relationship = ""
    @State private var notes = ""
    @State private var inviteEmail = ""
    @State private var loading = false
    @State private var error: String?

    init(title: String, recipient: CareRecipient? = nil, onSave: @escaping (String, String?, String?, String?) async throws -> Void) {
        self.title = title
        self.recipient = recipient
        self.onSave = onSave
        _name = State(initialValue: recipient?.name ?? "")
        _relationship = State(initialValue: recipient?.relationship ?? "")
        _notes = State(initialValue: recipient?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("recipient-editor-name-field")
                    TextField("Relationship", text: $relationship)
                        .accessibilityIdentifier("recipient-editor-relationship-field")
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("recipient-editor-notes-field")
                }

                if recipient == nil {
                    Section("Invite Now (Optional)") {
                        TextField("Email address", text: $inviteEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("recipient-editor-invite-email-field")
                        Text("Leave email blank to create a draft receiver profile first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(recipient == nil ? "Add" : "Save") {
                        Task { await save() }
                    }
                    .accessibilityIdentifier(recipient == nil ? "recipient-editor-add-button" : "recipient-editor-save-button")
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
                }
            }
        }
    }

    private func save() async {
        loading = true
        error = nil
        do {
            let normalizedRelationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedInvite = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            try await onSave(
                name.trimmingCharacters(in: .whitespacesAndNewlines),
                normalizedRelationship.isEmpty ? nil : normalizedRelationship,
                normalizedNotes.isEmpty ? nil : normalizedNotes,
                normalizedInvite.isEmpty ? nil : normalizedInvite
            )
            await MainActor.run {
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }
}

private struct ReceiverActivationDecisionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let recipient: CareRecipient
    let onChooseDirectInvite: () -> Void
    let onChooseProxyActivation: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    activationChoice(
                        title: recipient.activationStatus == .invited ? "Continue direct invite" : "Invite \(recipient.name) directly",
                        subtitle: "Best when \(recipient.name) can create or use their own account. Tasks unlock only after they accept.",
                        icon: "envelope.fill",
                        tint: Color(red: 0.13, green: 0.56, blue: 0.87),
                        identifier: "recipient-activation-choice-invite-\(recipient.id)",
                        action: onChooseDirectInvite
                    )

                    activationChoice(
                        title: "Record proxy authorization",
                        subtitle: "Use only when an authorized person has consent to coordinate care for \(recipient.name).",
                        icon: "checkmark.seal.fill",
                        tint: Color(red: 0.16, green: 0.80, blue: 0.72),
                        identifier: "recipient-activation-choice-proxy-\(recipient.id)",
                        action: onChooseProxyActivation
                    )
                } header: {
                    Text("Choose activation path")
                } footer: {
                    Text("The path determines who can unlock tasks. Direct invite links the receiver to their own account; proxy activation records organizer attestation.")
                }
            }
            .navigationTitle("Activate \(recipient.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("recipient-activation-decision-screen")
    }

    private func activationChoice(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(tint.opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier(identifier)
    }
}

private struct RecipientInviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let recipient: CareRecipient
    let onSend: (String) async throws -> Void

    @State private var email = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite \(recipient.name)") {
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("recipient-invite-email-field")
                    Text("They need to accept the invite before tasks can begin, unless a Care Organizer records proxy authorization.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Send Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await send() }
                    }
                    .accessibilityIdentifier("recipient-invite-send-button")
                    .disabled(!email.contains("@") || loading)
                }
            }
        }
    }

    private func send() async {
        loading = true
        error = nil
        do {
            try await onSend(email.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }
}

private struct ProxyActivationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let recipient: CareRecipient
    let onActivate: (String?, Bool) async throws -> Void

    @State private var documentReference = ""
    @State private var authorizationAttested = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Proxy Activation") {
                    Text("Use this only when a Care Organizer has consent and/or external authorization to coordinate care on behalf of \(recipient.name).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Authorization reference (optional)", text: $documentReference)
                        .accessibilityIdentifier("recipient-proxy-consent-field")
                    Toggle(
                        "I confirm I am authorized to coordinate care for \(recipient.name) and agree to CareLoop's consent terms.",
                        isOn: $authorizationAttested
                    )
                    .accessibilityIdentifier("recipient-proxy-attestation-toggle")
                    Text("Do not enter medical details here. Use a short document or family authorization reference only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Proxy Activate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Activate") {
                        Task { await activate() }
                    }
                    .accessibilityIdentifier("recipient-proxy-activate-button")
                    .disabled(loading || !authorizationAttested)
                }
            }
        }
    }

    private func activate() async {
        loading = true
        error = nil
        do {
            let normalizedReference = documentReference.trimmingCharacters(in: .whitespacesAndNewlines)
            try await onActivate(normalizedReference.isEmpty ? nil : normalizedReference, authorizationAttested)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }
}
