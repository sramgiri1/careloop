import SwiftUI
import StoreKit

struct PaywallView: View {
    let circleId: String
    let recipient: CareRecipient

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SubscriptionManager.shared

    @State private var isYearly = true
    @State private var isSyncingEntitlement = false
    @State private var syncError: String?
    @State private var completion: PremiumPurchaseCompletion?
    @State private var showTermsAndConditions = false

    private var allowsSimulatedPremiumSync: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-careloop-ui-simulate-premium-sync")
        #else
        false
        #endif
    }

    private let features: [(icon: String, title: String)] = [
        ("arrow.clockwise", "Recurring routines for this care receiver"),
        ("chart.bar.fill", "Receiver-scoped completion insights"),
        ("person.3.fill", "Unlimited caregiver access"),
        ("bell.badge.fill", "Advanced coordination and reminders"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        if let completion {
                            successSection(completion)
                                .padding(.top, 34)
                                .padding(.horizontal, 22)
                                .padding(.bottom, 44)
                        } else {
                            heroSection
                                .padding(.top, 24)
                            featuresSection
                            planSelectorSection
                                .padding(.horizontal, 22)
                            ctaSection
                                .padding(.horizontal, 22)
                            footerSection
                                .padding(.horizontal, 22)
                                .padding(.bottom, 44)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("receiver-paywall-screen")
        .sheet(isPresented: $showTermsAndConditions) {
            LegalTermsView()
        }
    }

    private var background: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.04, green: 0.08, blue: 0.20), location: 0),
                .init(color: Color(red: 0.06, green: 0.14, blue: 0.30), location: 0.55),
                .init(color: Color(red: 0.04, green: 0.10, blue: 0.22), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)
                    .shadow(color: Color(red: 0.16, green: 0.80, blue: 0.72).opacity(0.50), radius: 22, x: 0, y: 6)
                Image(systemName: "crown.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text(ReceiverPremiumPolicy.upgradePromptTitle(for: recipient))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Premium applies only to \(recipient.name)’s care workflow inside this Care Circle.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: 8) {
                statusChip(title: recipient.name, tint: Color(red: 0.16, green: 0.80, blue: 0.72))
                statusChip(title: recipient.caregiverAccessSummary, tint: Color(red: 0.13, green: 0.56, blue: 0.87))
            }
        }
        .padding(.horizontal, 28)
    }

    private func statusChip(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.15)))
    }

    private var featuresSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.16, green: 0.80, blue: 0.72))
                        .frame(width: 24, alignment: .center)
                    Text(item.title)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(red: 0.16, green: 0.80, blue: 0.72).opacity(0.90))
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 24)

                if index < features.count - 1 {
                    Rectangle()
                        .fill(.white.opacity(0.07))
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    private var planSelectorSection: some View {
        VStack(spacing: 10) {
            Text("Choose a plan")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textCase(.uppercase)
                .tracking(0.6)

            HStack(spacing: 12) {
                planCard(yearly: false)
                planCard(yearly: true)
            }
        }
    }

    @ViewBuilder
    private func planCard(yearly: Bool) -> some View {
        let selected = isYearly == yearly
        let product = store.product(yearly: yearly)
        let metadata = store.metadata(yearly: yearly)
        let price = product?.displayPrice ?? metadata.fallbackDisplayPrice
        let period = "/ \(metadata.periodUnit)"

        Button { isYearly = yearly } label: {
            VStack(spacing: 6) {
                if yearly {
                    Text("Best Value")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? Color(red: 0.04, green: 0.08, blue: 0.20) : Color(red: 0.16, green: 0.80, blue: 0.72))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(selected ? Color(red: 0.16, green: 0.80, blue: 0.72) : Color(red: 0.16, green: 0.80, blue: 0.72).opacity(0.18)))
                } else {
                    Spacer().frame(height: 20)
                }

                Text(yearly ? "Yearly" : "Monthly")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? .white : .white.opacity(0.55))
                Text(price)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? .white : .white.opacity(0.70))
                Text(period)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? .white.opacity(0.65) : .white.opacity(0.35))
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        selected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.80, blue: 0.72).opacity(0.20),
                                    Color(red: 0.13, green: 0.56, blue: 0.87).opacity(0.20),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(Color.white.opacity(0.05))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        selected
                        ? Color(red: 0.16, green: 0.80, blue: 0.72).opacity(0.65)
                        : Color.white.opacity(0.10),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var ctaSection: some View {
        VStack(spacing: 12) {
            let product = store.product(yearly: isYearly)
            let hasOffer = store.introOffer(yearly: isYearly) != nil
            let ctaLabel = hasOffer ? "Start Free Trial" : "Unlock Premium"
            let isProductLoading = store.isLoading || isSyncingEntitlement || (product == nil && store.storeError == nil)

            Button {
                if let product {
                    Task { await purchaseAndSync(product) }
                }
            } label: {
                Group {
                    if isProductLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaLabel)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.80, blue: 0.72),
                                    Color(red: 0.13, green: 0.56, blue: 0.87),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(red: 0.16, green: 0.80, blue: 0.72).opacity(0.38), radius: 14, x: 0, y: 5)
                )
                .foregroundStyle(.white)
                .opacity(isProductLoading ? 0.75 : 1.0)
            }
            .disabled(isProductLoading || product == nil)

            if let syncError {
                Text(syncError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                    .multilineTextAlignment(.center)
            } else if let storeError = store.storeError {
                Text(storeError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 16) {
            Text(disclosureText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            if let msg = store.restoreMessage {
                Text(msg)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(store.isPremium ? Color(red: 0.16, green: 0.80, blue: 0.72) : .white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await restoreAndSync() }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(store.isLoading || isSyncingEntitlement ? 0.30 : 0.50))
                    .underline()
            }
            .disabled(store.isLoading || isSyncingEntitlement)

            HStack(spacing: 18) {
                Button("Terms of Use") {
                    showTermsAndConditions = true
                }
                .accessibilityIdentifier("paywall-terms-link-button")

                Button("Privacy Policy") {
                    showTermsAndConditions = true
                }
                .accessibilityIdentifier("paywall-privacy-link-button")
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.58))
            .buttonStyle(.plain)

            Text("Premium is managed per care receiver. Unlocking \(recipient.name) does not automatically upgrade other care receivers in this Care Circle.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.32))
                .multilineTextAlignment(.center)

            if UITestScenario.current != nil || allowsSimulatedPremiumSync {
                Button("Simulate Purchase Success") {
                    let productId = isYearly ? SubscriptionManager.yearlyID : SubscriptionManager.monthlyID
                    let expiresAt = Date().addingTimeInterval(isYearly ? 365 * 24 * 60 * 60 : 30 * 24 * 60 * 60)
                    if allowsSimulatedPremiumSync {
                        Task {
                            await syncEntitlement(
                                productId: productId,
                                originalTransactionId: "simulated-\(UUID().uuidString)",
                                expiresAt: expiresAt
                            )
                        }
                    } else {
                        showSuccess(
                            productId: productId,
                            expiresAt: expiresAt
                        )
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .accessibilityIdentifier("simulate-premium-success-button")
            }
        }
    }

    private func successSection(_ completion: PremiumPurchaseCompletion) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.16, green: 0.80, blue: 0.72).opacity(0.18))
                    .frame(width: 112, height: 112)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.80, blue: 0.72), Color(red: 0.13, green: 0.56, blue: 0.87)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 82, height: 82)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 9) {
                Text("Premium is active for \(recipient.name)")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Recurring routines, insights, unlimited caregivers, and advanced coordination are now unlocked only for this care receiver.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(red: 0.16, green: 0.80, blue: 0.72))
                        )
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("premium-success-continue-button")

                Button {
                    store.openSubscriptionManagement()
                } label: {
                    Text("Manage plan")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .accessibilityIdentifier("premium-success-manage-plan-button")
            }

            VStack(spacing: 10) {
                successRow(icon: "person.crop.circle.badge.checkmark", title: "Care receiver", value: recipient.name)
                successRow(icon: "crown.fill", title: "Plan scope", value: "Receiver-specific Premium")
                successRow(icon: "calendar.badge.clock", title: completion.renewalTitle, value: completion.renewalDetail)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )

            Text("Manage or cancel subscriptions in App Store Settings. CareLoop keeps existing care history visible if a plan expires.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.40))
                .multilineTextAlignment(.center)
        }
        .accessibilityIdentifier("premium-success-screen")
    }

    private func successRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.16, green: 0.80, blue: 0.72))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }
            Spacer()
        }
    }

    private var disclosureText: String {
        let product = store.product(yearly: isYearly)
        let metadata = store.metadata(yearly: isYearly)
        let price = product?.displayPrice ?? metadata.fallbackDisplayPrice
        let period = metadata.periodUnit

        if let offer = store.introOffer(yearly: isYearly) {
            let n = offer.period.value
            let unit: String
            switch offer.period.unit {
            case .day: unit = n == 1 ? "day" : "days"
            case .week: unit = n == 1 ? "week" : "weeks"
            case .month: unit = n == 1 ? "month" : "months"
            case .year: unit = n == 1 ? "year" : "years"
            @unknown default: unit = "period"
            }
            return "\(n)-\(unit) free trial, then \(price)/\(period). Auto-renews unless cancelled at least 24 hours before the period ends. Cancel anytime in App Store Settings › Subscriptions."
        }
        return "Billed \(price)/\(period). Auto-renews unless cancelled at least 24 hours before the period ends. Cancel anytime in App Store Settings › Subscriptions."
    }

    private func purchaseAndSync(_ product: Product) async {
        syncError = nil
        await store.purchase(product)
        await syncLatestPurchaseSnapshot()
    }

    private func restoreAndSync() async {
        syncError = nil
        await store.restorePurchases()
        await syncLatestPurchaseSnapshot()
    }

    private func syncLatestPurchaseSnapshot() async {
        guard let purchase = store.latestPurchaseSnapshot else { return }
        await syncEntitlement(purchase)
    }

    private func syncEntitlement(_ purchase: SubscriptionManager.PurchaseSnapshot) async {
        await syncEntitlement(
            productId: purchase.productId,
            originalTransactionId: String(purchase.originalTransactionId),
            expiresAt: purchase.expirationDate
        )
    }

    private func syncEntitlement(productId: String, originalTransactionId: String, expiresAt: Date?) async {
        isSyncingEntitlement = true
        defer { isSyncingEntitlement = false }

        do {
            try await ReceiverPremiumEntitlementSync.sync(
                circleId: circleId,
                recipient: recipient,
                productId: productId,
                originalTransactionId: originalTransactionId,
                expiresAt: expiresAt,
                appState: appState
            )
            showSuccess(productId: productId, expiresAt: expiresAt)
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func showSuccess(productId: String, expiresAt: Date?) {
        completion = PremiumPurchaseCompletion(productId: productId, expiresAt: expiresAt)
    }
}

@MainActor
private enum ReceiverPremiumEntitlementSync {
    static func sync(
        circleId: String,
        recipient: CareRecipient,
        purchase: SubscriptionManager.PurchaseSnapshot,
        appState: AppState
    ) async throws {
        try await sync(
            circleId: circleId,
            recipient: recipient,
            productId: purchase.productId,
            originalTransactionId: String(purchase.originalTransactionId),
            expiresAt: purchase.expirationDate,
            appState: appState
        )
    }

    static func sync(
        circleId: String,
        recipient: CareRecipient,
        productId: String,
        originalTransactionId: String,
        expiresAt: Date?,
        appState: AppState
    ) async throws {
        _ = try await APIClient.shared.syncRecipientPremium(
            circleId: circleId,
            recipientId: recipient.id,
            expiresAt: expiresAt,
            appleOriginalTransactionId: originalTransactionId,
            appleProductId: productId
        )
        try await appState.activateCircle(id: circleId)
    }
}

private struct PremiumPurchaseCompletion: Equatable {
    let productId: String
    let expiresAt: Date?

    var renewalTitle: String {
        expiresAt == nil ? "Plan status" : "Renews"
    }

    var renewalDetail: String {
        guard let expiresAt else { return "Active until cancelled" }
        return expiresAt.formatted(.dateTime.month().day().year())
    }
}

struct ReceiverPremiumManagementView: View {
    let circleId: String
    let recipient: CareRecipient

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SubscriptionManager.shared
    @State private var isSyncingEntitlement = false
    @State private var syncMessage: String?
    @State private var syncError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    statusCard
                    actionsCard
                    expiredPolicyCard
                }
                .padding(22)
            }
            .background(Color(red: 0.94, green: 0.97, blue: 1.0).ignoresSafeArea())
            .navigationTitle("Premium Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("receiver-premium-management-screen")
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 0.55, green: 0.22, blue: 0.97))
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color(red: 0.55, green: 0.22, blue: 0.97).opacity(0.12)))
            Text("Manage Premium for \(recipient.name)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.24))
                .multilineTextAlignment(.center)
            Text("Premium applies only to \(recipient.name)'s care workflow in this Care Circle.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.64))
                .multilineTextAlignment(.center)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(recipient.hasPremium ? "Premium active" : "Premium inactive", systemImage: recipient.hasPremium ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(recipient.hasPremium ? Color(red: 0.07, green: 0.63, blue: 0.52) : Color.orange)
            managementRow("Care receiver", recipient.name)
            managementRow("Product", recipient.premium.appleProductId ?? "Not synced")
            managementRow(recipient.hasPremium ? "Renews/expires" : "Status", premiumDateText)
            managementRow("Unlocked", "Recurring routines, insights, unlimited caregivers")
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button {
                store.openSubscriptionManagement()
            } label: {
                Label("Manage in App Store", systemImage: "arrow.up.forward.app.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.55, green: 0.22, blue: 0.97))
            .accessibilityIdentifier("manage-in-app-store-button")

            Button {
                Task { await restoreAndSync() }
            } label: {
                Text("Restore and sync purchase")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(store.isLoading || isSyncingEntitlement)
            .accessibilityIdentifier("restore-premium-purchase-button")

            if isSyncingEntitlement {
                ProgressView("Syncing entitlement...")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .accessibilityIdentifier("restore-premium-sync-progress")
            }

            if let syncError {
                Text(syncError)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.80, green: 0.20, blue: 0.20))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("restore-premium-sync-error")
            } else if let syncMessage {
                Text(syncMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.07, green: 0.63, blue: 0.52))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("restore-premium-sync-message")
            } else if let message = store.restoreMessage {
                Text(message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.64))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("restore-premium-message")
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    private var expiredPolicyCard: some View {
        Text("If Premium expires or billing fails, existing care history remains visible. Only new premium actions are blocked until the receiver is upgraded again.")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.64))
            .multilineTextAlignment(.center)
            .padding(16)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var premiumDateText: String {
        guard let expiresAt = recipient.premium.expiresAt else {
            return recipient.hasPremium ? "Active until cancelled" : recipient.premiumStatusLabel
        }
        return expiresAt.formatted(.dateTime.month().day().year())
    }

    private func managementRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.64))
            Spacer(minLength: 18)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.24))
                .multilineTextAlignment(.trailing)
        }
    }

    private func restoreAndSync() async {
        syncError = nil
        syncMessage = nil
        await store.restorePurchases()

        guard let purchase = store.latestPurchaseSnapshot else {
            return
        }

        isSyncingEntitlement = true
        defer { isSyncingEntitlement = false }

        do {
            try await ReceiverPremiumEntitlementSync.sync(
                circleId: circleId,
                recipient: recipient,
                purchase: purchase,
                appState: appState
            )
            syncMessage = "Restored purchase synced for \(recipient.name)."
        } catch {
            syncError = error.localizedDescription
        }
    }
}
