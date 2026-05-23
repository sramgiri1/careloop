export const RECEIVER_ENTITLEMENT_STATUS = Object.freeze({
  FREE: "FREE",
  ACTIVE: "ACTIVE",
  EXPIRED: "EXPIRED",
  REVOKED: "REVOKED",
  BILLING_RETRY: "BILLING_RETRY",
  REFUNDED: "REFUNDED",
});

export const RECEIVER_PREMIUM_LIMITS = Object.freeze({
  FREE_CAREGIVER_ACCESS: 1,
});

export const RECEIVER_PREMIUM_APP_STORE_PRODUCTS = Object.freeze({
  MONTHLY: "com.careloop.ios.premium.monthly",
  YEARLY: "com.careloop.ios.premium.yearly",
});

export const RECEIVER_PREMIUM_APP_STORE_PRODUCT_IDS = Object.freeze(
  Object.values(RECEIVER_PREMIUM_APP_STORE_PRODUCTS),
);

export function isSupportedReceiverPremiumProductId(productId) {
  return RECEIVER_PREMIUM_APP_STORE_PRODUCT_IDS.includes(productId);
}

export function isSupportedReceiverEntitlementStatus(status) {
  return Object.values(RECEIVER_ENTITLEMENT_STATUS).includes(status);
}

export function isReceiverPremium(entitlement, now = new Date()) {
  if (!entitlement || entitlement.status !== RECEIVER_ENTITLEMENT_STATUS.ACTIVE) {
    return false;
  }
  if (!entitlement.expiresAt) return true;
  return new Date(entitlement.expiresAt) > now;
}

export function receiverEntitlementCapabilities(entitlement, now = new Date()) {
  const premium = isReceiverPremium(entitlement, now);
  return {
    hasPremium: premium,
    canUseAdvancedReminders: premium,
    canUseInsights: premium,
    canUseUnlimitedCaregivers: premium,
    canUseAdvancedCoordination: premium,
  };
}

export function receiverEntitlementSummary(entitlement, now = new Date()) {
  const capabilities = receiverEntitlementCapabilities(entitlement, now);
  return {
    status: entitlement?.status ?? RECEIVER_ENTITLEMENT_STATUS.FREE,
    source: entitlement?.source ?? null,
    startsAt: entitlement?.startsAt ?? null,
    expiresAt: entitlement?.expiresAt ?? null,
    appleOriginalTransactionId: entitlement?.appleOriginalTransactionId ?? null,
    appleProductId: entitlement?.appleProductId ?? null,
    hasPremium: capabilities.hasPremium,
    capabilities,
  };
}

export function maxCaregiversForReceiver(entitlement, now = new Date()) {
  const capabilities = receiverEntitlementCapabilities(entitlement, now);
  return capabilities.canUseUnlimitedCaregivers
    ? null
    : RECEIVER_PREMIUM_LIMITS.FREE_CAREGIVER_ACCESS;
}
