import SwiftUI

struct LegalSection: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
}

enum CareLoopLegalDocument {
    static let termsVersion = "careloop-terms-2026-05-28"
    static let effectiveDate = "May 28, 2026"

    static let termsSections: [LegalSection] = [
        LegalSection(
            id: "service",
            title: "1. Care coordination service",
            body: "CareLoop helps invited family members and caregivers coordinate care circles, reminders, tasks, notes, and progress summaries. CareLoop is not an emergency response service and does not provide medical diagnosis, clinical advice, or treatment decisions."
        ),
        LegalSection(
            id: "emergency",
            title: "2. Emergencies and medical decisions",
            body: "If there is an emergency, call local emergency services immediately. Do not rely on CareLoop notifications, reminders, task status, or escalation messages for urgent care, clinical monitoring, medication safety, or time-critical intervention."
        ),
        LegalSection(
            id: "roles",
            title: "3. Roles and consent",
            body: "Care organizers are responsible for inviting the right people, assigning roles, and confirming they are authorized to coordinate care for a care receiver. Care receivers and authorized representatives can accept or decline invitations and should only share information they are comfortable using for coordination."
        ),
        LegalSection(
            id: "responsibility",
            title: "4. User responsibility",
            body: "You are responsible for the accuracy of the tasks, notes, schedules, and contact details you enter. Caregivers should confirm important instructions directly with the care receiver, organizer, or appropriate professional before acting on sensitive information."
        ),
        LegalSection(
            id: "privacy",
            title: "5. Privacy and data use",
            body: "CareLoop stores account, circle, invite, task, reminder, comment, and subscription information needed to operate the app. Avoid entering sensitive medical details unless they are necessary for coordination and you have permission to share them."
        ),
        LegalSection(
            id: "subscriptions",
            title: "6. Premium subscriptions",
            body: "Premium applies per care receiver. Purchases, renewals, cancellations, refunds, and trials are managed through the App Store or the payment provider shown at purchase time. If Premium expires, existing care history stays visible, but premium-only actions may lock."
        ),
        LegalSection(
            id: "acceptable-use",
            title: "7. Acceptable use",
            body: "Do not misuse CareLoop, attempt to access another user's care circle without permission, upload unlawful content, harass users, or use the app to make decisions that require licensed professional judgment."
        ),
        LegalSection(
            id: "changes",
            title: "8. Changes and contact",
            body: "CareLoop may update these terms as the product changes. Material updates may require renewed acceptance. For support or privacy questions, contact suchethram@gmail.com."
        ),
    ]
}

struct LegalTermsView: View {
    let showsAcceptanceAction: Bool
    let onAccept: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(showsAcceptanceAction: Bool = false, onAccept: @escaping () -> Void = {}) {
        self.showsAcceptanceAction = showsAcceptanceAction
        self.onAccept = onAccept
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.96, green: 0.97, blue: 0.99).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        ForEach(CareLoopLegalDocument.termsSections) { section in
                            sectionCard(section)
                        }

                        Text("Version \(CareLoopLegalDocument.termsVersion)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.45, green: 0.53, blue: 0.62))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                            .padding(.bottom, showsAcceptanceAction ? 92 : 28)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                }

                if showsAcceptanceAction {
                    VStack {
                        Spacer()
                        acceptanceButton
                    }
                    .ignoresSafeArea(.keyboard)
                }
            }
            .navigationTitle("Terms & Conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.10, green: 0.53, blue: 0.83))
                        .accessibilityIdentifier("terms-conditions-close-button")
                }
            }
        }
        .accessibilityIdentifier("terms-conditions-screen")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CareLoop Terms & Conditions")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.24))
                .fixedSize(horizontal: false, vertical: true)

            Text("Effective \(CareLoopLegalDocument.effectiveDate)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.10, green: 0.53, blue: 0.83))

            Text("Please review before creating an account. These terms explain what CareLoop is for, what it is not for, and how care-circle information should be handled.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.34, green: 0.42, blue: 0.53))
                .lineSpacing(4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color(red: 0.10, green: 0.53, blue: 0.83).opacity(0.08), radius: 16, x: 0, y: 8)
        )
    }

    private func sectionCard(_ section: LegalSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.24))

            Text(section.body)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.36, green: 0.44, blue: 0.55))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(red: 0.84, green: 0.89, blue: 0.94), lineWidth: 1)
        )
    }

    private var acceptanceButton: some View {
        Button {
            onAccept()
            dismiss()
        } label: {
            Text("OK, I agree")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.11, green: 0.76, blue: 0.72), Color(red: 0.10, green: 0.53, blue: 0.83)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color(red: 0.11, green: 0.76, blue: 0.72).opacity(0.22), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("terms-conditions-ok-button")
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
    }
}
