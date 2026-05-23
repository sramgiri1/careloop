export const RECEIVER_ACTIVATION_STATUS = Object.freeze({
  DRAFT: "DRAFT",
  INVITED: "INVITED",
  ACTIVE: "ACTIVE",
  PROXY_ACTIVE: "PROXY_ACTIVE",
});

const ACTIVE_STATUSES = new Set([
  RECEIVER_ACTIVATION_STATUS.ACTIVE,
  RECEIVER_ACTIVATION_STATUS.PROXY_ACTIVE,
]);

export function normalizeReceiverActivationStatus(value) {
  const status = String(value ?? RECEIVER_ACTIVATION_STATUS.DRAFT).toUpperCase();
  if (!Object.hasOwn(RECEIVER_ACTIVATION_STATUS, status)) {
    throw new Error("Invalid care receiver activation status");
  }
  return status;
}

export function isCareReceiverActive(receiver) {
  return ACTIVE_STATUSES.has(normalizeReceiverActivationStatus(receiver?.activationStatus));
}

export function canCreateTasksForReceiver(receiver) {
  return isCareReceiverActive(receiver);
}

export function activationForAcceptedReceiver(userId, now = new Date()) {
  if (!userId) throw new Error("receiver userId is required");
  return {
    activationStatus: RECEIVER_ACTIVATION_STATUS.ACTIVE,
    activatedAt: now,
    receiverUserId: userId,
  };
}

export function activationForProxyReceiver({ attestedById, documentReference = null }, now = new Date()) {
  if (!attestedById) throw new Error("consent attester is required");
  return {
    activationStatus: RECEIVER_ACTIVATION_STATUS.PROXY_ACTIVE,
    activatedAt: now,
    consentAttestedAt: now,
    consentAttestedById: attestedById,
    proxyAuthorizedById: attestedById,
    consentDocumentReference: documentReference,
  };
}
