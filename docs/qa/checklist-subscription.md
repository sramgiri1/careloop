# CareLoop — Subscription System QA Checklist

**Status:** SENTINEL COMPLETE — all critical issues resolved, 34/34 unit tests green  
**Date:** 2026-05-01  
**Gate owner:** SENTINEL + AUDITOR  
**Scope:** StoreKit 2 subscription system, PaywallView, CircleListView premium UX

---

## Files delivered

| File | Description |
|------|-------------|
| `CareLoop/App/SubscriptionManager.swift` | StoreKit 2 `@MainActor ObservableObject` singleton |
| `CareLoop/Views/PaywallView.swift` | Dark-navy subscription paywall |
| `CareLoop/Views/Circles/CircleListView.swift` | Updated: premium badge, upgrade prompt, stat pills, AccountSheet callback |
| `CareLoopTests/SubscriptionManagerTests.swift` | Unit tests across StoreKit/product contracts and paywall disclosure text |
| `CareLoop/Configuration/CareLoop.storekit` | Local StoreKit configuration for simulator purchase testing |

---

## Auditor code review results

**Run:** `npm run skill auditor code.diff_review` + `code.lint` + `code.static_analysis` + `code.test_coverage`  
**Date:** 2026-05-01

### Issues found and resolved

| # | Severity | Issue | File | Resolution |
|---|----------|-------|------|------------|
| 1 | High | `latest!.purchaseDate` force-unwrap in `refreshEntitlements` | SubscriptionManager.swift | Replaced with `latest.map({ tx.purchaseDate > $0.purchaseDate }) ?? true` |
| 2 | Critical | AccountSheet "Upgrade to Premium" sets `@State var showPaywall` after `dismiss()` — view destroyed, state mutation is a no-op | CircleListView.swift | Moved `showPaywall` to parent `CircleListView`; AccountSheet now accepts `onUpgrade: (() -> Void)?` callback; callback fires after 350ms delay via `DispatchQueue.main.asyncAfter` |
| 3 | Medium | `@StateObject` used for singleton `SubscriptionManager` | CircleListView.swift, PaywallView.swift | Changed to `@ObservedObject` — correct pattern for a pre-existing singleton |
| 4 | Medium | Task priority `.background` on transaction observer | SubscriptionManager.swift | Changed to `.utility` — financial transaction observer must not run at lowest priority |
| 5 | Low | Misleading test name `test_userInitials_emptyName_returnsQuestionMark` asserts `""` | SubscriptionManagerTests.swift | Renamed to `test_userInitials_emptyName_returnsEmptyString`; added comment explaining `?` comes from nil-coalescing in `CircleListView.userInitials`, not the helper function |
| 6 | Low | Missing `@unknown default` on `Product.SubscriptionOffer.Period.Unit` switch | PaywallView.swift | Added `@unknown default: unit = "period"` |
| 7 | Critical | Unverified transactions in `observeTransactionUpdates` never call `tx.finish()` — StoreKit re-delivers indefinitely | SubscriptionManager.swift | Rewrote `if let tx = try? verified(result)` to full `switch result` with `tx.finish()` in both `.verified` and `.unverified` branches |

---

## Sentinel QA results

**Run:** `npm run skill sentinel qa.tests.execute` + `qa.simulator.run` + `qa.security.scan`  
**Date:** 2026-05-01

### Bugs found and resolved

| # | Severity | Bug | Resolution |
|---|----------|-----|------------|
| 1 | High | Double-tap on circle row triggers two concurrent `openCircle` calls | Added `guard loadingCircleId == nil` at top of `openCircle` |
| 2 | High | Double-tap on invite accept/decline triggers concurrent calls | Added `guard loadingInviteId == nil` at top of `acceptInvite` and `declineInvite` |
| 3 | High | Restore Purchases button not disabled during `isLoading` — concurrent `AppStore.sync()` possible | Added `.disabled(store.isLoading)` to Restore button |
| 4 | Critical | PaywallView shown from AccountSheet — sheet dismissed before `showPaywall = true` is set | Fixed by AccountSheet `onUpgrade` callback pattern (see Auditor issue #2) |
| 5 | Medium | Empty name string in `userInitials` returns `""` instead of `"?"` fallback | Fixed `CircleListView.userInitials` and `AccountSheet.initials` to return `raw.isEmpty ? "?" : raw` |
| 6 | Medium | Logo appears twice in CircleListView header (`style: .lockup` renders icon + wordmark, but asset already contains icon) | Changed to `style: .wordmark` |
| 7 | High | CTA button appears active during initial product load (products nil, `isLoading` false before init Task runs) | Set `isLoading = true` in SubscriptionManager `init`; PaywallView CTA uses `isProductLoading = store.isLoading \|\| (product == nil && store.storeError == nil)` |
| 8 | Medium | Paywall does not dismiss after successful purchase | Added `.onChange(of: store.isPremium) { if isPremium { dismiss() } }` |
| 9 | Low | Restore Purchases gave no user-visible feedback | Added `restoreMessage` published property; set to "Your subscription has been restored." or "No active subscription found on this Apple ID." after sync |

### Security scan

- No hardcoded secrets in subscription files
- No direct credit card or payment data collection — Apple handles all payment data via StoreKit
- No `eval`, `localhost` references, or debug-only code left in production paths

---

## Unit test results

**File:** `CareLoopTests/SubscriptionManagerTests.swift`  
**Total:** 34 tests | 0 failed

### Test classes

| Class | Tests | Coverage |
|-------|-------|----------|
| `SubscriptionManagerInitialStateTests` | 5 | `isPremium`, `activeTransaction`, `renewalDate`, `storeError`, `isLoading` defaults |
| `SubscriptionManagerProductIdTests` | 6 | Exact product ID values, distinct IDs, shared bundle prefix, correct suffixes |
| `SubscriptionManagerAccessorTests` | 8 | Nil-safety when products empty, `monthlyProduct`/`yearlyProduct` consistency, `product(yearly:)` routing |
| `PaywallDisclosureTextTests` | 6 | Auto-renewal language, cancel language, price+period in text, App Store mention, trial length, price-after-trial |
| `CircleListHeroTests` | 9 | Initials (single/full/three-word/empty), `recipientSubtitle` (0/1/2/3/4 recipients) |

### Key test cases

```swift
// App Store compliance — auto-renewal must be disclosed
func test_noOffer_containsAutoRenewalLanguage() { ... }

// StoreKit product ID contract — must match App Store Connect exactly
func test_monthlyProductId_isCorrect() {
    XCTAssertEqual(SubscriptionManager.monthlyID, "com.careloop.ios.premium.monthly")
}

// Nil-safety — no crash when StoreKit products haven't loaded
func test_monthlyProduct_nilSafeWhenProductsEmpty() {
    guard manager.products.isEmpty else { return }
    XCTAssertNil(manager.monthlyProduct)
}
```

---

## App Store compliance checklist

- [x] All payment data collected by Apple via StoreKit — no PCI scope
- [x] Disclosure text includes auto-renewal language ("Auto-renews unless cancelled at least 24 hours before the period ends")
- [x] Disclosure text includes cancel instructions ("Cancel anytime in App Store Settings › Subscriptions")
- [x] Disclosure text includes price from `product.displayPrice` (locale-aware, not hardcoded)
- [x] Disclosure text includes billing period
- [x] Trial disclosure shows trial length from `introductoryOffer.period` (not hardcoded)
- [x] Restore Purchases button present and functional
- [x] Unverified transactions are finished (StoreKit contract — prevents infinite re-delivery)
- [x] Privacy Policy and Terms of Use links in paywall footer
- [x] X (close) button with `accessibilityLabel("Close")`
- [x] No forbidden health claims in paywall copy
- [x] Local StoreKit config exists with monthly/yearly receiver Premium product IDs

## Local StoreKit configuration

Use this file in the Xcode scheme's StoreKit Configuration setting for simulator purchase tests:

```text
CareLoop/Configuration/CareLoop.storekit
```

Expected product IDs:

- `com.careloop.ios.premium.monthly`
- `com.careloop.ios.premium.yearly`

Local contract check:

```bash
npm run check:careloop-demo-readiness
```

External setup still required before production billing sign-off:

- Create the matching subscription group and product IDs in App Store Connect.
- Configure sandbox tester accounts.
- Validate purchase, restore, expiry, billing retry, and cancellation on a physical device or TestFlight build.

---

## Sign-off

| Gate | Owner | Status | Date |
|------|-------|--------|------|
| Code review (Auditor) | AUDITOR | PASS — all 7 issues resolved | 2026-05-01 |
| Unit tests (Sentinel) | SENTINEL | PASS — 34/34 green | 2026-05-01 |
| UX / bug review (Sentinel) | SENTINEL | PASS — all 9 bugs resolved | 2026-05-01 |
| App Store compliance | WARDEN | PASS — all checklist items satisfied | 2026-05-01 |
