import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  activationForAcceptedReceiver,
  activationForProxyReceiver,
  canCreateTasksForReceiver,
  isCareReceiverActive,
  normalizeReceiverActivationStatus,
} from "../src/lib/receiver-state.js";
import {
  canCreateTaskForReceiver,
  canEditTask,
  canViewReceiver,
  canViewTask,
} from "../src/lib/access.js";
import {
  isReceiverPremium,
  maxCaregiversForReceiver,
  receiverEntitlementCapabilities,
  receiverEntitlementSummary,
} from "../src/lib/entitlements.js";

const now = new Date("2026-05-16T12:00:00.000Z");

describe("receiver activation foundation", () => {
  test("draft and invited receivers are not active for task creation", () => {
    assert.equal(isCareReceiverActive({ activationStatus: "DRAFT" }), false);
    assert.equal(isCareReceiverActive({ activationStatus: "INVITED" }), false);
    assert.equal(canCreateTasksForReceiver({ activationStatus: "DRAFT" }), false);
  });

  test("accepted and proxy-active receivers allow task creation", () => {
    assert.equal(canCreateTasksForReceiver({ activationStatus: "ACTIVE" }), true);
    assert.equal(canCreateTasksForReceiver({ activationStatus: "PROXY_ACTIVE" }), true);
  });

  test("activation status normalization rejects unknown states", () => {
    assert.equal(normalizeReceiverActivationStatus("active"), "ACTIVE");
    assert.throws(() => normalizeReceiverActivationStatus("UNKNOWN"), /Invalid care receiver activation status/);
  });

  test("accepted receiver activation records account ownership", () => {
    assert.deepEqual(activationForAcceptedReceiver("receiver-1", now), {
      activationStatus: "ACTIVE",
      activatedAt: now,
      receiverUserId: "receiver-1",
    });
  });

  test("proxy receiver activation records consent attestation", () => {
    assert.deepEqual(
      activationForProxyReceiver({ attestedById: "admin-1", documentReference: "external-doc-42" }, now),
      {
        activationStatus: "PROXY_ACTIVE",
        activatedAt: now,
        consentAttestedAt: now,
        consentAttestedById: "admin-1",
        proxyAuthorizedById: "admin-1",
        consentDocumentReference: "external-doc-42",
      },
    );
  });
});

describe("receiver-scoped access foundation", () => {
  const organizer = { id: "m-admin", role: "ADMIN", userId: "admin-1", circleId: "circle-1" };
  const caregiver = { id: "m-caregiver", role: "MEMBER", userId: "caregiver-1", circleId: "circle-1" };
  const receiverMember = { id: "m-receiver", role: "RECIPIENT", userId: "receiver-1", circleId: "circle-1" };
  const receiver = {
    id: "receiver-profile-1",
    circleId: "circle-1",
    receiverUserId: "receiver-1",
    activationStatus: "ACTIVE",
  };
  const activeAccess = { recipientId: receiver.id, memberId: caregiver.id, revokedAt: null };
  const revokedAccess = { recipientId: receiver.id, memberId: caregiver.id, revokedAt: now };

  test("organizers can view and create work for every receiver in their circle", () => {
    assert.equal(canViewReceiver({ member: organizer, userId: organizer.userId, receiver }), true);
    assert.equal(canCreateTaskForReceiver({ member: organizer, receiver }), true);
  });

  test("caregivers need an active receiver access grant", () => {
    assert.equal(canViewReceiver({ member: caregiver, userId: caregiver.userId, receiver }), false);
    assert.equal(canViewReceiver({ member: caregiver, userId: caregiver.userId, receiver, accessGrant: revokedAccess }), false);
    assert.equal(canViewReceiver({ member: caregiver, userId: caregiver.userId, receiver, accessGrant: activeAccess }), true);
  });

  test("care receivers can view only their own receiver profile", () => {
    assert.equal(canViewReceiver({ member: receiverMember, userId: "receiver-1", receiver }), true);
    assert.equal(canViewReceiver({ member: receiverMember, userId: "other-receiver", receiver }), false);
  });

  test("caregivers see their own tasks and receiver-assigned tasks, not other caregiver tasks", () => {
    const ownTask = { circleId: "circle-1", recipientId: receiver.id, assigneeId: "caregiver-1" };
    const receiverTask = { circleId: "circle-1", recipientId: receiver.id, assigneeId: "receiver-1" };
    const otherCaregiverTask = { circleId: "circle-1", recipientId: receiver.id, assigneeId: "caregiver-2" };

    assert.equal(canViewTask({ member: caregiver, userId: "caregiver-1", task: ownTask, receiver, accessGrant: activeAccess }), true);
    assert.equal(canViewTask({ member: caregiver, userId: "caregiver-1", task: receiverTask, receiver, accessGrant: activeAccess }), true);
    assert.equal(canViewTask({ member: caregiver, userId: "caregiver-1", task: otherCaregiverTask, receiver, accessGrant: activeAccess }), false);
  });

  test("care receivers see only tasks assigned directly to them", () => {
    const receiverTask = { circleId: "circle-1", recipientId: receiver.id, assigneeId: "receiver-1" };
    const caregiverTask = { circleId: "circle-1", recipientId: receiver.id, assigneeId: "caregiver-1" };

    assert.equal(canViewTask({ member: receiverMember, userId: "receiver-1", task: receiverTask, receiver }), true);
    assert.equal(canViewTask({ member: receiverMember, userId: "receiver-1", task: caregiverTask, receiver }), false);
  });

  test("task editing is limited to organizers or the task creator", () => {
    const task = { circleId: "circle-1", creatorId: "caregiver-1" };

    assert.equal(canEditTask({ member: organizer, userId: "admin-1", task }), true);
    assert.equal(canEditTask({ member: caregiver, userId: "caregiver-1", task }), true);
    assert.equal(canEditTask({ member: caregiver, userId: "caregiver-2", task }), false);
    assert.equal(canEditTask({ member: receiverMember, userId: "receiver-1", task }), false);
  });
});

describe("receiver-scoped entitlement foundation", () => {
  test("active unexpired entitlement unlocks receiver-scoped premium", () => {
    const entitlement = {
      status: "ACTIVE",
      expiresAt: new Date("2026-05-17T12:00:00.000Z"),
    };
    assert.equal(isReceiverPremium(entitlement, now), true);
    assert.deepEqual(receiverEntitlementCapabilities(entitlement, now), {
      hasPremium: true,
      canUseAdvancedReminders: true,
      canUseInsights: true,
      canUseUnlimitedCaregivers: true,
      canUseAdvancedCoordination: true,
    });
  });

  test("missing, expired, or revoked entitlements stay free", () => {
    assert.equal(isReceiverPremium(null, now), false);
    assert.equal(isReceiverPremium({ status: "ACTIVE", expiresAt: new Date("2026-05-15T12:00:00.000Z") }, now), false);
    assert.equal(isReceiverPremium({ status: "REVOKED", expiresAt: null }, now), false);
  });

  test("entitlement summary exposes premium state and capability metadata", () => {
    const summary = receiverEntitlementSummary({
      status: "ACTIVE",
      source: "APP_STORE",
      startsAt: new Date("2026-05-01T00:00:00.000Z"),
      expiresAt: new Date("2026-06-01T00:00:00.000Z"),
      appleOriginalTransactionId: "otx-1",
      appleProductId: "com.careloop.ios.premium.monthly",
    }, now);

    assert.equal(summary.hasPremium, true);
    assert.equal(summary.source, "APP_STORE");
    assert.equal(summary.appleProductId, "com.careloop.ios.premium.monthly");
    assert.equal(summary.capabilities.canUseInsights, true);
  });

  test("free receivers keep a single caregiver access limit", () => {
    assert.equal(maxCaregiversForReceiver(null, now), 1);
    assert.equal(maxCaregiversForReceiver({ status: "ACTIVE", expiresAt: new Date("2026-06-01T00:00:00.000Z") }, now), null);
  });
});
