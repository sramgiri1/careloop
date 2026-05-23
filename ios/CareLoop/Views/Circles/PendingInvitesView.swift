import SwiftUI

struct PendingInvitesView: View {
    @EnvironmentObject private var appState: AppState

    @State private var loadingInviteId: String?
    @State private var error: String?

    private var invites: [GroupInvitation] {
        appState.currentUser?.pendingInvites ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if invites.isEmpty {
                        Text("You have no pending invitations.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(invites) { invite in
                            inviteCard(invite)
                        }
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.99).ignoresSafeArea())
            .navigationTitle("Pending Invites")
            .navigationBarTitleDisplayMode(.inline)
            .careLoopBrandBanner()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You’ve been invited")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.10, green: 0.16, blue: 0.24))
            Text("Accept a CareLoop invitation to join an existing care group, or decline it and set up your own later.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.42, green: 0.51, blue: 0.62))
        }
    }

    @ViewBuilder
    private func inviteCard(_ invite: GroupInvitation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(invite.circle.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(invite.role == .recipient
                     ? "Your care is organized in this circle"
                     : invite.circle.recipientDisplaySummary)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let invitedBy = invite.invitedBy {
                Text("Invited by \(invitedBy.name) (\(invitedBy.email))")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let expirationSummary = invite.expirationSummary {
                Text(expirationSummary)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(expirationSummary == "Expired" ? .red : .orange)
            }

            HStack(spacing: 10) {
                roleBadge(invite.role)
                Text(invite.email)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await accept(invite) }
                } label: {
                    if loadingInviteId == invite.id {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        Text("Accept")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .disabled(loadingInviteId != nil || !invite.canRespond)
                .accessibilityIdentifier("pending-invite-accept-\(invite.id)")

                Button {
                    Task { await decline(invite) }
                } label: {
                    Text("Decline")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.28, green: 0.37, blue: 0.47))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(red: 0.84, green: 0.89, blue: 0.94), lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white)
                        )
                )
                .disabled(loadingInviteId != nil || !invite.canRespond)
                .accessibilityIdentifier("pending-invite-decline-\(invite.id)")
            }

            if let responseUnavailableReason = invite.responseUnavailableReason {
                Text(responseUnavailableReason)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    @ViewBuilder
    private func roleBadge(_ role: MemberRole) -> some View {
        let (label, fg, bg): (String, Color, Color) = {
            switch role {
            case .admin:
                return ("Admin access", Color(red: 0.13, green: 0.56, blue: 0.87), Color(red: 0.88, green: 0.95, blue: 1.0))
            case .member:
                return ("Member access", Color(red: 0.23, green: 0.33, blue: 0.44), Color(red: 0.93, green: 0.95, blue: 0.98))
            case .recipient:
                return ("Care Receiver", Color(red: 0.85, green: 0.30, blue: 0.50), Color(red: 0.99, green: 0.91, blue: 0.94))
            }
        }()
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(bg))
    }

    private func accept(_ invite: GroupInvitation) async {
        guard appState.currentUser != nil else { return }
        loadingInviteId = invite.id
        error = nil
        defer { loadingInviteId = nil }

        do {
            _ = try await APIClient.shared.acceptInvitation(invitationId: invite.id)
            try await appState.activateCircle(id: invite.circle.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func decline(_ invite: GroupInvitation) async {
        guard appState.currentUser != nil else { return }
        loadingInviteId = invite.id
        error = nil
        defer { loadingInviteId = nil }

        do {
            try await APIClient.shared.declineInvitation(invitationId: invite.id)
            try await appState.refreshCurrentUser()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
