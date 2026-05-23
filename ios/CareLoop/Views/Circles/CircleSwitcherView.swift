import SwiftUI

struct CircleSwitcherView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var loadingCircleId: String?
    @State private var loadingInviteId: String?
    @State private var error: String?
    @State private var showJoinCreate = false
    @State private var initialCircleId: String?

    var body: some View {
        NavigationStack {
            List {
                if let activeCircle = appState.activeCircle {
                    Section("Current Circle") {
                        circleRow(
                            circleId: activeCircle.id,
                            title: activeCircle.name,
                            subtitle: activeCircle.recipientDisplaySummary,
                            role: appState.userRole,
                            isActive: true,
                            action: nil
                        )
                    }
                }

                if !otherMemberships.isEmpty {
                    Section("Other Circles") {
                        ForEach(otherMemberships) { membership in
                            let circle = membership.circle ?? CareCircle(
                                id: membership.circleId,
                                name: "Care Circle",
                                recipientName: "Family"
                            )
                            circleRow(
                                circleId: circle.id,
                                title: circle.name,
                                subtitle: circle.recipientDisplaySummary,
                                role: membership.role,
                                isActive: false
                            ) {
                                Task { await switchCircle(circle.id) }
                            }
                            .disabled(loadingCircleId != nil)
                        }
                    }
                }

                if appState.circleMemberships.isEmpty {
                    Section {
                        Text("You are not a member of any circles yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !pendingInvites.isEmpty {
                    Section("Pending Invites") {
                        ForEach(pendingInvites) { invite in
                            pendingInviteRow(invite)
                        }
                    }
                }

                Section {
                    Button {
                        error = nil
                        showJoinCreate = true
                    } label: {
                        Label("Join or Create Another Circle", systemImage: "plus.circle")
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
            .navigationTitle("Your Circles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showJoinCreate, onDismiss: {
                if appState.activeCircle?.id != initialCircleId {
                    dismiss()
                }
            }) {
                JoinCircleView(dismissOnSuccess: true)
                    .environmentObject(appState)
            }
        }
        .onAppear {
            initialCircleId = appState.activeCircle?.id
        }
    }

    private var otherMemberships: [CircleMembership] {
        appState.circleMemberships.filter { $0.circleId != appState.activeCircle?.id }
    }

    private var pendingInvites: [GroupInvitation] {
        appState.currentUser?.pendingInvites ?? []
    }

    @ViewBuilder
    private func circleRow(
        circleId: String,
        title: String,
        subtitle: String,
        role: MemberRole,
        isActive: Bool,
        action: (() -> Void)?
    ) -> some View {
        let label = HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image("CareLoopIcon")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.10, green: 0.16, blue: 0.24))
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(role == .admin ? "Admin" : "Member")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(role == .admin ? Color(red: 0.13, green: 0.56, blue: 0.87) : Color(red: 0.23, green: 0.33, blue: 0.44))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(role == .admin ? Color(red: 0.88, green: 0.95, blue: 1.0) : Color(red: 0.93, green: 0.95, blue: 0.98))
                    )
                if loadingCircleId == circleId {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.68, blue: 0.49))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)

        if let action {
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private func switchCircle(_ circleId: String) async {
        loadingCircleId = circleId
        error = nil
        do {
            try await appState.activateCircle(id: circleId)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        loadingCircleId = nil
    }

    @ViewBuilder
    private func pendingInviteRow(_ invite: GroupInvitation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invite.circle.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(invite.circle.recipientDisplaySummary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let invitedBy = invite.invitedBy {
                        Text("Invited by \(invitedBy.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                roleBadge(invite.role)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await accept(invite) }
                } label: {
                    if loadingInviteId == invite.id {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Accept")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.13, green: 0.56, blue: 0.87))
                .disabled(loadingInviteId != nil || loadingCircleId != nil || !invite.canRespond)
                .accessibilityIdentifier("circle-switcher-invite-accept-\(invite.id)")

                Button("Decline") {
                    Task { await decline(invite) }
                }
                .buttonStyle(.bordered)
                .disabled(loadingInviteId != nil || loadingCircleId != nil || !invite.canRespond)
                .accessibilityIdentifier("circle-switcher-invite-decline-\(invite.id)")
            }

            if let responseUnavailableReason = invite.responseUnavailableReason {
                Text(responseUnavailableReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func accept(_ invite: GroupInvitation) async {
        guard appState.currentUser != nil else { return }
        loadingInviteId = invite.id
        error = nil
        defer { loadingInviteId = nil }

        do {
            _ = try await APIClient.shared.acceptInvitation(invitationId: invite.id)
            try await appState.activateCircle(id: invite.circle.id)
            dismiss()
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

    @ViewBuilder
    private func roleBadge(_ role: MemberRole) -> some View {
        Text(role == .admin ? "Admin" : "Member")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(role == .admin ? Color(red: 0.13, green: 0.56, blue: 0.87) : Color(red: 0.23, green: 0.33, blue: 0.44))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(role == .admin ? Color(red: 0.88, green: 0.95, blue: 1.0) : Color(red: 0.93, green: 0.95, blue: 0.98))
            )
    }
}
