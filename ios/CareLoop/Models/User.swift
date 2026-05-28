import Foundation

struct CareUser: Identifiable, Codable {
    let id: String
    let email: String
    let name: String
    let phone: String?
    var pushToken: String?
    var timezone: String?
    var notifAssignments: Bool?
    var notifEscalations: Bool?
    var notifDigest: Bool?
    var termsAcceptedAt: Date?
    var termsAcceptedVersion: String?
    var memberships: [CircleMembership]?
    var pendingInvites: [GroupInvitation]?
}

struct AuthResult: Codable {
    let method: String
    let accessToken: String
    let user: CareUser
}

struct ForgotPasswordRequestResult: Codable {
    let sent: Bool
    let expiresInMinutes: Int
    let debugCode: String?
}

struct ForgotPasswordVerifyResult: Codable {
    let verified: Bool
}

struct ForgotPasswordResetResult: Codable {
    let reset: Bool
}

struct CircleMembership: Identifiable, Codable {
    let id: String
    let circleId: String
    let role: MemberRole
    var circle: CareCircle?
}

struct InvitationSender: Identifiable, Codable {
    let id: String
    let name: String
    let email: String
}

struct GroupInvitation: Identifiable, Codable {
    let id: String
    let email: String
    let name: String
    let role: MemberRole
    let status: InvitationStatus
    let expiresAt: Date?
    let circle: CareCircle
    let recipient: CareRecipient?
    let invitedBy: InvitationSender?
}

extension GroupInvitation {
    var canRespond: Bool {
        status == .pending && expirationSummary != "Expired"
    }

    var responseUnavailableReason: String? {
        if status != .pending {
            return "This invitation is \(status.rawValue.lowercased())."
        }
        if expirationSummary == "Expired" {
            return "This invitation expired. Ask the organizer to resend it."
        }
        return nil
    }

    var expirationSummary: String? {
        guard let expiresAt else { return nil }
        if status == .expired || Date() >= expiresAt {
            return "Expired"
        }
        return "Expires \(expiresAt.formatted(.dateTime.month().day().year()))"
    }

    func replacingExpiration(_ expiresAt: Date) -> GroupInvitation {
        GroupInvitation(
            id: id,
            email: email,
            name: name,
            role: role,
            status: status,
            expiresAt: expiresAt,
            circle: circle,
            recipient: recipient,
            invitedBy: invitedBy
        )
    }
}

extension Array where Element == GroupInvitation {
    mutating func replace(_ invitation: GroupInvitation, with replacement: GroupInvitation) {
        guard let index = firstIndex(where: { $0.id == invitation.id }) else { return }
        self[index] = replacement
    }
}

enum InvitationStatus: String, Codable {
    case pending = "PENDING"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case revoked = "REVOKED"
    case expired = "EXPIRED"
}
