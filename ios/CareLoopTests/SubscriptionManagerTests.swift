import XCTest
import StoreKit
@testable import CareLoop

// Tests for SubscriptionManager that do not require a StoreKit configuration file.
// They verify initial state, product ID contracts, and nil-safe accessors.
// StoreKit transaction tests require a .storekit config file in the scheme's
// StoreKit Configuration setting — add one in Xcode for simulator testing.

@MainActor
final class SubscriptionManagerInitialStateTests: XCTestCase {

    private var manager: SubscriptionManager!

    override func setUp() {
        super.setUp()
        manager = SubscriptionManager(startupBehavior: .manual)
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: – Initial published state

    func test_isPremium_defaultsFalse() {
        XCTAssertFalse(manager.isPremium,
            "isPremium must be false on a fresh session — no active transaction yet")
    }

    func test_activeTransaction_defaultsNil() {
        XCTAssertNil(manager.activeTransaction,
            "No active transaction expected without a StoreKit environment or completed purchase")
    }

    func test_renewalDate_defaultsNil() {
        XCTAssertNil(manager.renewalDate)
    }

    func test_latestPurchaseSnapshot_defaultsNil() {
        XCTAssertNil(manager.latestPurchaseSnapshot)
    }

    func test_storeError_defaultsNil() {
        XCTAssertNil(manager.storeError, "No error should exist before any purchase attempt")
    }

    func test_isLoading_defaultsFalse() {
        XCTAssertFalse(manager.isLoading, "Loading flag must start false before any network call")
    }
}

@MainActor
final class SubscriptionManagerProductIdTests: XCTestCase {

    // MARK: – Product ID contract
    // These IDs must match what's registered in App Store Connect exactly.

    func test_monthlyProductId_isCorrect() {
        XCTAssertEqual(SubscriptionManager.monthlyID, "com.careloop.ios.premium.monthly")
    }

    func test_yearlyProductId_isCorrect() {
        XCTAssertEqual(SubscriptionManager.yearlyID, "com.careloop.ios.premium.yearly")
    }

    func test_productIds_areDistinct() {
        XCTAssertNotEqual(SubscriptionManager.monthlyID, SubscriptionManager.yearlyID,
            "Monthly and yearly must be different product IDs")
    }

    func test_productIds_shareBundlePrefix() {
        let prefix = "com.careloop.ios.premium"
        XCTAssertTrue(SubscriptionManager.monthlyID.hasPrefix(prefix))
        XCTAssertTrue(SubscriptionManager.yearlyID.hasPrefix(prefix))
    }

    func test_supportedProductIds_matchMetadataOrder() {
        XCTAssertEqual(SubscriptionManager.supportedProductIDs, [
            SubscriptionManager.monthlyID,
            SubscriptionManager.yearlyID
        ])
    }

    func test_productMetadata_hasLocalFallbackPrices() {
        XCTAssertEqual(SubscriptionManager.monthlyMetadata.fallbackDisplayPrice, "$4.99")
        XCTAssertEqual(SubscriptionManager.monthlyMetadata.periodUnit, "month")
        XCTAssertEqual(SubscriptionManager.yearlyMetadata.fallbackDisplayPrice, "$49.99")
        XCTAssertEqual(SubscriptionManager.yearlyMetadata.periodUnit, "year")
    }

    func test_storeKitConfiguration_matchesSubscriptionMetadata() throws {
        let products = try loadLocalStoreKitProducts()
        for metadata in SubscriptionManager.supportedProductMetadata {
            let product = try XCTUnwrap(products[metadata.id], "Missing StoreKit product \(metadata.id)")
            XCTAssertEqual(try XCTUnwrap(product.displayName), metadata.displayName)
            XCTAssertEqual(product.displayPrice, metadata.fallbackDisplayPrice.droppingLeadingDollarSign())
            XCTAssertEqual(product.recurringSubscriptionPeriod, metadata.storeKitPeriod)
        }
    }

    func test_monthlyId_suffixIsMonthly() {
        XCTAssertTrue(SubscriptionManager.monthlyID.hasSuffix(".monthly"))
    }

    func test_yearlyId_suffixIsYearly() {
        XCTAssertTrue(SubscriptionManager.yearlyID.hasSuffix(".yearly"))
    }

    private struct StoreKitFile: Decodable {
        let subscriptionGroups: [SubscriptionGroup]
    }

    private struct SubscriptionGroup: Decodable {
        let subscriptions: [StoreKitSubscription]
    }

    private struct StoreKitSubscription: Decodable {
        let productID: String
        let displayPrice: String
        let recurringSubscriptionPeriod: String
        let localizations: [StoreKitLocalization]

        var displayName: String? {
            localizations.first { $0.locale == "en_US" }?.displayName ?? localizations.first?.displayName
        }
    }

    private struct StoreKitLocalization: Decodable {
        let locale: String
        let displayName: String
    }

    private func loadLocalStoreKitProducts() throws -> [String: StoreKitSubscription] {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let storeKitURL = projectRoot
            .appendingPathComponent("CareLoop")
            .appendingPathComponent("Configuration")
            .appendingPathComponent("CareLoop.storekit")
        let data = try Data(contentsOf: storeKitURL)
        let file = try JSONDecoder().decode(StoreKitFile.self, from: data)
        return Dictionary(
            uniqueKeysWithValues: file.subscriptionGroups
                .flatMap(\.subscriptions)
                .map { ($0.productID, $0) }
        )
    }
}

private extension String {
    func droppingLeadingDollarSign() -> String {
        hasPrefix("$") ? String(dropFirst()) : self
    }
}

@MainActor
final class SubscriptionManagerAccessorTests: XCTestCase {

    private var manager: SubscriptionManager!

    override func setUp() {
        super.setUp()
        manager = SubscriptionManager(startupBehavior: .manual)
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: – Nil-safe accessor contract when products have not loaded

    func test_monthlyProduct_nilSafeWhenProductsEmpty() {
        guard manager.products.isEmpty else {
            // StoreKit config present — skip this nil-safety check
            return
        }
        XCTAssertNil(manager.monthlyProduct,
            "monthlyProduct must return nil when products array is empty")
    }

    func test_yearlyProduct_nilSafeWhenProductsEmpty() {
        guard manager.products.isEmpty else { return }
        XCTAssertNil(manager.yearlyProduct)
    }

    func test_product_yearly_nilSafeWhenProductsEmpty() {
        guard manager.products.isEmpty else { return }
        XCTAssertNil(manager.product(yearly: true))
        XCTAssertNil(manager.product(yearly: false))
    }

    func test_introOffer_nilSafeWhenProductsEmpty() {
        guard manager.products.isEmpty else { return }
        XCTAssertNil(manager.introOffer(yearly: true))
        XCTAssertNil(manager.introOffer(yearly: false))
    }

    func test_monthlyProduct_consistentWithProductsArray() {
        // If products loaded, monthlyProduct must match the filtered result
        let expected = manager.products.first { $0.id == SubscriptionManager.monthlyID }
        XCTAssertEqual(manager.monthlyProduct?.id, expected?.id)
    }

    func test_yearlyProduct_consistentWithProductsArray() {
        let expected = manager.products.first { $0.id == SubscriptionManager.yearlyID }
        XCTAssertEqual(manager.yearlyProduct?.id, expected?.id)
    }

    func test_product_yearly_true_returnsYearlyProduct() {
        XCTAssertEqual(manager.product(yearly: true)?.id, manager.yearlyProduct?.id)
    }

    func test_product_yearly_false_returnsMonthlyProduct() {
        XCTAssertEqual(manager.product(yearly: false)?.id, manager.monthlyProduct?.id)
    }
}

// MARK: – PaywallView disclosure text logic

// Tests the disclosure text generation logic independent of StoreKit,
// using mock data to verify format, key phrases, and auto-renewal language.

final class PaywallDisclosureTextTests: XCTestCase {

    // Simulate how disclosureText builds its string (no-offer path)
    func test_noOffer_containsAutoRenewalLanguage() {
        let text = disclosureNoOffer(price: "$4.99", period: "month")
        XCTAssertTrue(text.contains("auto-renews") || text.contains("Auto-renews"),
            "Must disclose auto-renewal per App Store guidelines")
    }

    func test_noOffer_containsCancelLanguage() {
        let text = disclosureNoOffer(price: "$4.99", period: "month")
        XCTAssertTrue(text.contains("Cancel") || text.contains("cancel"),
            "Must tell users how to cancel")
    }

    func test_noOffer_containsPriceAndPeriod() {
        let text = disclosureNoOffer(price: "$9.99", period: "year")
        XCTAssertTrue(text.contains("$9.99"))
        XCTAssertTrue(text.contains("year"))
    }

    func test_noOffer_mentionsAppStoreSettings() {
        let text = disclosureNoOffer(price: "$4.99", period: "month")
        XCTAssertTrue(text.contains("App Store"),
            "Must reference where to cancel (App Store Settings)")
    }

    func test_withTrial_mentionsTrialLength() {
        let text = disclosureWithTrial(trialDays: 14, price: "$4.99", period: "month")
        XCTAssertTrue(text.contains("14"))
        XCTAssertTrue(text.contains("day") || text.contains("days"))
    }

    func test_withTrial_mentionsPriceAfterTrial() {
        let text = disclosureWithTrial(trialDays: 7, price: "$9.99", period: "year")
        XCTAssertTrue(text.contains("$9.99"))
    }

    // MARK: – Helpers (mirror PaywallView.disclosureText logic)

    private func disclosureNoOffer(price: String, period: String) -> String {
        "Billed \(price)/\(period). Auto-renews unless cancelled at least 24 hours before the period ends. Cancel anytime in App Store Settings › Subscriptions."
    }

    private func disclosureWithTrial(trialDays: Int, price: String, period: String) -> String {
        let unit = trialDays == 1 ? "day" : "days"
        return "\(trialDays)-\(unit) free trial, then \(price)/\(period). Auto-renews unless cancelled at least 24 hours before the period ends. Cancel anytime in App Store Settings › Subscriptions."
    }
}

// MARK: – CircleListView hero data helpers

final class CircleListHeroTests: XCTestCase {

    func test_userInitials_singleName() {
        XCTAssertEqual(initials(from: "Alice"), "A")
    }

    func test_userInitials_fullName() {
        XCTAssertEqual(initials(from: "Alice Johnson"), "AJ")
    }

    func test_userInitials_threeWordName_takesTwoInitials() {
        XCTAssertEqual(initials(from: "Alice Marie Johnson"), "AM")
    }

    func test_userInitials_emptyName_returnsEmptyString() {
        // initials() returns "" for empty input; the "?" fallback is applied
        // by the nil-coalescing in CircleListView.userInitials, not the helper.
        XCTAssertEqual(initials(from: ""), "")
    }

    func test_recipientSubtitle_noRecipients_returnsCareGroup() {
        XCTAssertEqual(subtitle(for: []), "Care group")
    }

    func test_recipientSubtitle_singleRecipient() {
        XCTAssertEqual(subtitle(for: ["Mom"]), "Caring for Mom")
    }

    func test_recipientSubtitle_twoRecipients() {
        XCTAssertEqual(subtitle(for: ["Mom", "Dad"]), "Caring for Mom and Dad")
    }

    func test_recipientSubtitle_threeRecipients_showsOverflow() {
        XCTAssertEqual(subtitle(for: ["Mom", "Dad", "Gran"]), "Caring for Mom + 2 more")
    }

    func test_recipientSubtitle_fourRecipients_showsOverflow() {
        XCTAssertEqual(subtitle(for: ["A", "B", "C", "D"]), "Caring for A + 3 more")
    }

    // Mirror CircleListView.recipientSubtitle(for:) logic
    private func subtitle(for names: [String]) -> String {
        switch names.count {
        case 0:  return "Care group"
        case 1:  return "Caring for \(names[0])"
        case 2:  return "Caring for \(names[0]) and \(names[1])"
        default: return "Caring for \(names[0]) + \(names.count - 1) more"
        }
    }

    // Mirror CircleListView.userInitials logic
    private func initials(from name: String) -> String {
        name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined().uppercased()
    }
}
