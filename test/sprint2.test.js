// Sprint 2 backend tests — push notifications, scheduler rules, route contracts
// Run: node --test test/sprint2.test.js

// Set env before any module-level reads (override shell env for isolation)
process.env.API_KEY            = "test-key";
process.env.AUTH_TOKEN_SECRET  = "test-auth-secret";
process.env.DISABLE_SCHEDULER = "true";
process.env.RESEND_API_KEY     = "";   // force simulated email mode
process.env.APNS_KEY_ID        = "";   // force simulated push mode
process.env.APNS_TEAM_ID       = "";
process.env.APNS_KEY            = "";
process.env.GOOGLE_CLIENT_ID    = "google-client";
process.env.GOOGLE_CLIENT_SECRET = "google-secret";
process.env.FACEBOOK_APP_ID     = "facebook-app";
process.env.FACEBOOK_APP_SECRET = "facebook-secret";
process.env.APPLE_SERVICE_ID    = "com.careloop.web";
process.env.APPLE_TEAM_ID       = "team123";
process.env.APPLE_KEY_ID        = "key123";
process.env.APPLE_PRIVATE_KEY   = "-----BEGIN PRIVATE KEY-----\\nTEST\\n-----END PRIVATE KEY-----";
process.env.PUBLIC_API_BASE_URL = "http://localhost:3000";

import { test, describe, before, after } from "node:test";
import assert from "node:assert/strict";

import { deliverTaskNotification, sendReminderNotifications, sendDailyDigest } from "../src/lib/push.js";
import { escalationUserIdsForTask } from "../src/lib/access.js";
import Fastify from "fastify";
import authPlugin    from "../src/plugins/auth.js";
import authRoutes    from "../src/routes/auth.js";
import usersRoute    from "../src/routes/users.js";
import circlesRoute  from "../src/routes/circles.js";
import tasksRoute    from "../src/routes/tasks.js";
import { createOAuthState, hashPassword, issueAccessToken, verifyOAuthState } from "../src/lib/auth.js";
import { processEscalations, processPendingReminders } from "../src/scheduler/index.js";

async function authHeaders(user = { id: "u1", email: "a@t.com", name: "Alice" }) {
  return {
    authorization: `Bearer ${await issueAccessToken(user)}`,
    "content-type": "application/json",
  };
}

const HDR = await authHeaders();

// ─── mock DB ─────────────────────────────────────────────────────────────────
function buildDb(seed = {}) {
  const S = {
    users:      [...(seed.users      || [])],
    identities: [...(seed.identities || [])],
    passwordResetCodes: [...(seed.passwordResetCodes || [])],
    circles:    [...(seed.circles    || [])],
    invitations: [...(seed.invitations || [])],
    recipients: [...(seed.recipients || (seed.circles || []).map((circle, index) => ({
      id: `cr${index + 1}`,
      circleId: circle.id,
      name: circle.recipientName,
      relationship: null,
      notes: null,
      isPrimary: true,
      sortOrder: 0,
      activationStatus: "ACTIVE",
      activatedAt: new Date(),
      receiverUserId: null,
      consentAttestedAt: null,
      consentAttestedById: null,
      proxyAuthorizedById: null,
      consentDocumentReference: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    })))],
    recipientEntitlements: [...(seed.recipientEntitlements || [])],
    recipientAccesses: [...(seed.recipientAccesses || [])],
    premiumUpgradeRequests: [...(seed.premiumUpgradeRequests || [])],
    members:    [...(seed.members    || [])],
    tasks:      [...(seed.tasks      || [])],
    taskComments: [...(seed.taskComments || [])],
    reminders:  [...(seed.reminders  || [])],
    events:     [...(seed.events     || [])],
  };

  const seededIds = [
    ...S.users.map((item) => item.id),
    ...S.identities.map((item) => item.id),
    ...S.passwordResetCodes.map((item) => item.id),
    ...S.circles.map((item) => item.id),
    ...S.invitations.map((item) => item.id),
    ...S.recipients.map((item) => item.id),
    ...S.recipientEntitlements.map((item) => item.id),
    ...S.recipientAccesses.map((item) => item.id),
    ...S.premiumUpgradeRequests.map((item) => item.id),
    ...S.members.map((item) => item.id),
    ...S.tasks.map((item) => item.id),
    ...S.taskComments.map((item) => item.id),
    ...S.reminders.map((item) => item.id),
    ...S.events.map((item) => item.id),
  ];
  let seq = seededIds.reduce((max, id) => {
    const match = String(id ?? "").match(/(\d+)$/);
    return match ? Math.max(max, Number(match[1])) : max;
  }, 0);
  const uid = (p) => `${p}${++seq}`;
  const orderItems = (items, orderBy) => {
    const orderings = Array.isArray(orderBy) ? orderBy : (orderBy ? [orderBy] : []);
    if (orderings.length === 0) return [...items];
    return [...items].sort((lhs, rhs) => {
      for (const ordering of orderings) {
        const [field, direction] = Object.entries(ordering)[0];
        const left = lhs[field];
        const right = rhs[field];
        if (left === right) continue;
        if (left === null || left === undefined) return 1;
        if (right === null || right === undefined) return -1;
        const comparison = left > right ? 1 : -1;
        return direction === "desc" ? -comparison : comparison;
      }
      return 0;
    });
  };
  const windowItems = (items, { cursor, skip, take } = {}) => {
    let next = [...items];
    if (cursor?.id) {
      const index = next.findIndex((item) => item.id === cursor.id);
      if (index >= 0) next = next.slice(index + (skip ?? 0));
    } else if (skip) {
      next = next.slice(skip);
    }
    if (typeof take === "number") next = next.slice(0, take);
    return next;
  };

  function userRepo(s) {
    return {
      findUnique: async ({ where, include }) => {
        const user = s.users.find((u) => (where.id ? u.id === where.id : u.email === where.email)) ?? null;
        if (!user || !include) return user;
        return {
          ...user,
          memberships: include.memberships
            ? s.members
                .filter((m) => m.userId === user.id)
                .map((m) => ({
                  ...m,
                  circle: include.memberships?.include?.circle
                    ? (s.circles.find((c) => c.id === m.circleId) ?? null)
                    : undefined,
                }))
            : undefined,
          identities: include.identities
            ? s.identities.filter((i) => i.userId === user.id)
            : undefined,
        };
      },
      findMany: async () => s.users,
      create: async ({ data: d }) => {
        if (s.users.some((u) => u.email === d.email)) {
          throw Object.assign(new Error("Unique"), { code: "P2002" });
        }
        const u = {
          id: uid("u"),
          createdAt: new Date(),
          updatedAt: new Date(),
          authVersion: 0,
          pushToken: null,
          timezone: null,
          phone: null,
          notifAssignments: true,
          notifEscalations: true,
          notifDigest: true,
          ...d,
        };
        s.users.push(u);
        return u;
      },
      update: async ({ where, data: d }) => {
        const u = s.users.find((x) => x.id === where.id);
        if (!u) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        const resolved = Object.fromEntries(Object.entries(d).map(([key, value]) => {
          if (value && typeof value === "object" && "increment" in value) {
            return [key, (u[key] ?? 0) + value.increment];
          }
          return [key, value];
        }));
        Object.assign(u, resolved, { updatedAt: new Date() });
        return u;
      },
    };
  }

  function authIdentityRepo(s) {
    return {
      findUnique: async ({ where }) => {
        const key = where.provider_providerUserId;
        if (!key) return null;
        return s.identities.find((i) => i.provider === key.provider && i.providerUserId === key.providerUserId) ?? null;
      },
      upsert: async ({ where, update, create }) => {
        const key = where.provider_providerUserId;
        const existing = s.identities.find((i) => i.provider === key.provider && i.providerUserId === key.providerUserId);
        if (existing) {
          Object.assign(existing, update, { updatedAt: new Date() });
          return existing;
        }
        const identity = { id: uid("ai"), createdAt: new Date(), updatedAt: new Date(), ...create };
        s.identities.push(identity);
        return identity;
      },
    };
  }

  function passwordResetCodeRepo(s) {
    return {
      create: async ({ data: d }) => {
        const record = { id: uid("pr"), createdAt: new Date(), consumedAt: null, ...d };
        s.passwordResetCodes.push(record);
        return record;
      },
      findFirst: async ({ where, orderBy }) => {
        let items = s.passwordResetCodes.filter((r) => {
          if (where.userId && r.userId !== where.userId) return false;
          if (where.consumedAt === null && r.consumedAt !== null) return false;
          if (where.expiresAt?.gt && !(r.expiresAt > where.expiresAt.gt)) return false;
          return true;
        });
        if (orderBy?.createdAt === "desc") {
          items = items.sort((a, b) => b.createdAt - a.createdAt);
        }
        return items[0] ?? null;
      },
      updateMany: async ({ where, data: d }) => {
        let count = 0;
        for (const record of s.passwordResetCodes) {
          if (where.userId && record.userId !== where.userId) continue;
          if (where.consumedAt === null && record.consumedAt !== null) continue;
          Object.assign(record, d);
          count += 1;
        }
        return { count };
      },
    };
  }

  function circleRepo(s) {
    function includeRecipient(recipient, include) {
      if (!include) return recipient;
      return {
        ...recipient,
        entitlement: include.entitlement
          ? (s.recipientEntitlements.find((item) => item.recipientId === recipient.id) ?? null)
          : undefined,
      };
    }

    return {
      create: async ({ data: d }) => {
        const c = { id: uid("c"), createdAt: new Date(), updatedAt: new Date(), archiveAfterDays: 7, ...d };
        s.circles.push(c);
        return c;
      },
      findMany: async ({ select } = {}) => {
        if (!select) return s.circles;
        return s.circles.map((circle) => {
          const picked = {};
          for (const key of Object.keys(select)) {
            if (select[key]) picked[key] = circle[key];
          }
          return picked;
        });
      },
      findUnique: async ({ where, include }) => {
        const c = s.circles.find((x) => x.id === where.id) ?? null;
        if (!c || !include) return c;
        return {
          ...c,
          members: include.members
            ? s.members
                .filter((m) => m.circleId === c.id)
                .map((m) => ({
                  ...m,
                  user: include.members?.include?.user
                    ? (s.users.find((u) => u.id === m.userId) ?? null)
                    : undefined,
                }))
            : undefined,
          recipients: include.recipients
            ? s.recipients
                .filter((recipient) => recipient.circleId === c.id)
                .sort((lhs, rhs) => {
                  if (lhs.isPrimary !== rhs.isPrimary) return lhs.isPrimary ? -1 : 1;
                  return lhs.createdAt - rhs.createdAt;
                })
                .map((recipient) => includeRecipient(
                  recipient,
                  typeof include.recipients === "object" ? include.recipients.include : undefined,
                ))
            : undefined,
          tasks: include.tasks ? s.tasks.filter((t) => t.circleId === c.id) : undefined,
        };
      },
      update: async ({ where, data: d, include }) => {
        const circle = s.circles.find((x) => x.id === where.id);
        if (!circle) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        Object.assign(circle, d, { updatedAt: new Date() });
        if (!include) return circle;
        return {
          ...circle,
          members: include.members
            ? s.members
                .filter((m) => m.circleId === circle.id)
                .map((m) => ({
                  ...m,
                  user: include.members?.include?.user
                    ? (s.users.find((u) => u.id === m.userId) ?? null)
                    : undefined,
                }))
            : undefined,
          recipients: include.recipients
            ? s.recipients
                .filter((recipient) => recipient.circleId === circle.id)
                .sort((lhs, rhs) => {
                  if (lhs.isPrimary !== rhs.isPrimary) return lhs.isPrimary ? -1 : 1;
                  return lhs.createdAt - rhs.createdAt;
                })
                .map((recipient) => includeRecipient(
                  recipient,
                  typeof include.recipients === "object" ? include.recipients.include : undefined,
                ))
            : undefined,
          tasks: include.tasks ? s.tasks.filter((t) => t.circleId === circle.id) : undefined,
        };
      },
      delete: async ({ where }) => {
        const index = s.circles.findIndex((circle) => circle.id === where.id);
        if (index === -1) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        const [deleted] = s.circles.splice(index, 1);
        s.members = s.members.filter((member) => member.circleId !== where.id);
        s.recipients = s.recipients.filter((recipient) => recipient.circleId !== where.id);
        s.recipientAccesses = s.recipientAccesses.filter((access) =>
          s.recipients.some((recipient) => recipient.id === access.recipientId),
        );
        s.premiumUpgradeRequests = s.premiumUpgradeRequests.filter((request) =>
          s.recipients.some((recipient) => recipient.id === request.recipientId),
        );
        s.tasks = s.tasks.filter((task) => task.circleId !== where.id);
        s.invitations = s.invitations.filter((invitation) => invitation.circleId !== where.id);
        s.events = s.events.filter((event) => event.circleId !== where.id);
        return deleted;
      },
    };
  }

  function invitationRepo(s) {
    function matchesInvitation(invitation, where = {}) {
      if (where.id && invitation.id !== where.id) return false;
      if (where.circleId && invitation.circleId !== where.circleId) return false;
      if (where.email && invitation.email !== where.email) return false;
      if (where.status && invitation.status !== where.status) return false;
      return true;
    }

    function includeInvitation(invitation, include) {
      if (!invitation) return null;
      if (!include) return { ...invitation };
      return {
        ...invitation,
        circle: include.circle ? (s.circles.find((circle) => circle.id === invitation.circleId) ?? null) : undefined,
        recipient: include.recipient ? (s.recipients.find((recipient) => recipient.id === invitation.recipientId) ?? null) : undefined,
        invitedBy: include.invitedBy ? (s.users.find((user) => user.id === invitation.invitedById) ?? null) : undefined,
      };
    }

    return {
      create: async ({ data: d }) => {
        const invitation = {
          id: uid("i"),
          status: "PENDING",
          acceptedAt: null,
          expiresAt: null,
          invitedById: null,
          acceptedById: null,
          createdAt: new Date(),
          updatedAt: new Date(),
          ...d,
        };
        s.invitations.push(invitation);
        return invitation;
      },
      findUnique: async ({ where, include }) =>
        includeInvitation(s.invitations.find((invitation) => invitation.id === where.id) ?? null, include),
      findFirst: async ({ where, include }) =>
        includeInvitation(s.invitations.find((invitation) => matchesInvitation(invitation, where)) ?? null, include),
      findMany: async ({ where, include, orderBy, cursor, skip, take } = {}) => {
        let items = s.invitations.filter((invitation) => matchesInvitation(invitation, where));
        items = orderItems(items, orderBy);
        items = windowItems(items, { cursor, skip, take });
        return items.map((invitation) => includeInvitation(invitation, include));
      },
      update: async ({ where, data: d, include }) => {
        const invitation = s.invitations.find((item) => item.id === where.id);
        if (!invitation) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        Object.assign(invitation, d, { updatedAt: new Date() });
        return includeInvitation(invitation, include);
      },
    };
  }

  function careRecipientRepo(s) {
    function includeRecipient(recipient, include) {
      if (!recipient) return null;
      if (!include) return recipient;
      return {
        ...recipient,
        entitlement: include.entitlement
          ? (s.recipientEntitlements.find((item) => item.recipientId === recipient.id) ?? null)
          : undefined,
      };
    }

    return {
      create: async ({ data: d }) => {
        const recipient = {
          id: uid("cr"),
          relationship: null,
          notes: null,
          isPrimary: false,
          sortOrder: 0,
          activationStatus: "DRAFT",
          activatedAt: null,
          receiverUserId: null,
          consentAttestedAt: null,
          consentAttestedById: null,
          proxyAuthorizedById: null,
          consentDocumentReference: null,
          createdAt: new Date(),
          updatedAt: new Date(),
          ...d,
        };
        s.recipients.push(recipient);
        return recipient;
      },
      findUnique: async ({ where, include } = {}) =>
        includeRecipient(s.recipients.find((recipient) => recipient.id === where.id) ?? null, include),
      findFirst: async ({ where, orderBy, include } = {}) => {
        let items = s.recipients.filter((recipient) => {
          if (where?.id && recipient.id !== where.id) return false;
          if (where?.circleId && recipient.circleId !== where.circleId) return false;
          return true;
        });
        if (orderBy) {
          const orderings = Array.isArray(orderBy) ? orderBy : [orderBy];
          items = items.sort((lhs, rhs) => {
            for (const ordering of orderings) {
              const [field, direction] = Object.entries(ordering)[0];
              const left = lhs[field];
              const right = rhs[field];
              if (left === right) continue;
              if (direction === "desc") return left > right ? -1 : 1;
              return left < right ? -1 : 1;
            }
            return 0;
          });
        }
        return includeRecipient(items[0] ?? null, include);
      },
      findMany: async ({ where, orderBy, include } = {}) => {
        let items = s.recipients.filter((recipient) => {
          if (where?.circleId && recipient.circleId !== where.circleId) return false;
          if (where?.id?.in && !where.id.in.includes(recipient.id)) return false;
          return true;
        });
        if (orderBy) {
          const orderings = Array.isArray(orderBy) ? orderBy : [orderBy];
          items = items.sort((lhs, rhs) => {
            for (const ordering of orderings) {
              const [field, direction] = Object.entries(ordering)[0];
              const left = lhs[field];
              const right = rhs[field];
              if (left === right) continue;
              if (direction === "desc") return left > right ? -1 : 1;
              return left < right ? -1 : 1;
            }
            return 0;
          });
        }
        return items.map((recipient) => includeRecipient(recipient, include));
      },
      count: async ({ where } = {}) =>
        s.recipients.filter((recipient) => {
          if (where?.circleId && recipient.circleId !== where.circleId) return false;
          return true;
        }).length,
      update: async ({ where, data: d }) => {
        const recipient = s.recipients.find((item) => item.id === where.id);
        if (!recipient) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        Object.assign(recipient, d, { updatedAt: new Date() });
        return recipient;
      },
      updateMany: async ({ where, data: d }) => {
        let count = 0;
        for (const recipient of s.recipients) {
          if (where?.circleId && recipient.circleId !== where.circleId) continue;
          Object.assign(recipient, d, { updatedAt: new Date() });
          count += 1;
        }
        return { count };
      },
      delete: async ({ where }) => {
        const index = s.recipients.findIndex((item) => item.id === where.id);
        if (index === -1) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        const [deleted] = s.recipients.splice(index, 1);
        return deleted;
      },
    };
  }

  function careRecipientAccessRepo(s) {
    return {
      create: async ({ data: d }) => {
        const access = {
          id: uid("cra"),
          grantedAt: new Date(),
          revokedAt: null,
          createdAt: new Date(),
          updatedAt: new Date(),
          grantedById: null,
          ...d,
        };
        s.recipientAccesses.push(access);
        return access;
      },
      findMany: async ({ where } = {}) =>
        s.recipientAccesses.filter((access) => {
          if (where?.recipientId && access.recipientId !== where.recipientId) return false;
          if (where?.memberId && access.memberId !== where.memberId) return false;
          if (where?.revokedAt === null && access.revokedAt !== null) return false;
          return true;
        }),
      count: async ({ where } = {}) =>
        s.recipientAccesses.filter((access) => {
          if (where?.recipientId && access.recipientId !== where.recipientId) return false;
          if (where?.memberId && access.memberId !== where.memberId) return false;
          if (where?.revokedAt === null && access.revokedAt !== null) return false;
          return true;
        }).length,
      update: async ({ where, data: d }) => {
        const access = s.recipientAccesses.find((item) => item.id === where.id);
        if (!access) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        Object.assign(access, d, { updatedAt: new Date() });
        return access;
      },
    };
  }

  function careRecipientEntitlementRepo(s) {
    return {
      findUnique: async ({ where }) =>
        s.recipientEntitlements.find((entitlement) =>
          where.id
            ? entitlement.id === where.id
            : entitlement.recipientId === where.recipientId,
        ) ?? null,
      create: async ({ data: d }) => {
        const entitlement = {
          id: uid("cre"),
          status: "FREE",
          source: null,
          startsAt: null,
          expiresAt: null,
          appleOriginalTransactionId: null,
          appleProductId: null,
          purchasedById: null,
          createdAt: new Date(),
          updatedAt: new Date(),
          ...d,
        };
        s.recipientEntitlements.push(entitlement);
        return entitlement;
      },
      update: async ({ where, data: d }) => {
        const entitlement = s.recipientEntitlements.find((item) =>
          where.id ? item.id === where.id : item.recipientId === where.recipientId,
        );
        if (!entitlement) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        Object.assign(entitlement, d, { updatedAt: new Date() });
        return entitlement;
      },
    };
  }

  function premiumUpgradeRequestRepo(s) {
    function includeRequest(request, include) {
      if (!request) return null;
      return {
        ...request,
        recipient: include?.recipient
          ? (s.recipients.find((recipient) => recipient.id === request.recipientId) ?? null)
          : undefined,
        requester: include?.requester
          ? (s.users.find((user) => user.id === request.requesterUserId) ?? null)
          : undefined,
      };
    }

    return {
      create: async ({ data: d, include }) => {
        if (s.premiumUpgradeRequests.some((request) =>
          request.recipientId === d.recipientId && request.requesterUserId === d.requesterUserId,
        )) {
          throw Object.assign(new Error("Unique"), { code: "P2002" });
        }
        const request = {
          id: uid("pur"),
          createdAt: new Date(),
          updatedAt: new Date(),
          ...d,
        };
        s.premiumUpgradeRequests.push(request);
        return includeRequest(request, include);
      },
      findMany: async ({ where, include, orderBy } = {}) => {
        let items = s.premiumUpgradeRequests.filter((request) => {
          if (where?.circleId && request.circleId !== where.circleId) return false;
          if (where?.recipientId && request.recipientId !== where.recipientId) return false;
          if (where?.createdAt?.gte && request.createdAt < where.createdAt.gte) return false;
          return true;
        });
        if (orderBy?.createdAt === "desc") {
          items = [...items].sort((lhs, rhs) => rhs.createdAt - lhs.createdAt);
        }
        return items.map((request) => includeRequest(request, include));
      },
    };
  }

  function memberRepo(s) {
    return {
      create: async ({ data: d }) => {
        if (s.members.some((m) => m.userId === d.userId && m.circleId === d.circleId)) {
          throw Object.assign(new Error("Unique"), { code: "P2002" });
        }
        const m = { id: uid("m"), joinedAt: new Date(), role: "MEMBER", ...d };
        s.members.push(m);
        return m;
      },
      findUnique: async ({ where, include }) => {
        const k = where.userId_circleId;
        const member = k
          ? s.members.find((m) => m.userId === k.userId && m.circleId === k.circleId) ?? null
          : where.id
            ? s.members.find((m) => m.id === where.id) ?? null
            : null;
        if (!member || !include?.user) return member;
        return {
          ...member,
          user: s.users.find((u) => u.id === member.userId) ?? null,
        };
      },
      findFirst: async ({ where }) =>
        s.members.find((m) => {
          if (where.userId && m.userId !== where.userId) return false;
          if (where.circleId && m.circleId !== where.circleId) return false;
          if (where.role && m.role !== where.role) return false;
          return true;
        }) ?? null,
      findMany: async ({ where, include } = {}) =>
        s.members
          .filter((member) => {
            if (where?.circleId && member.circleId !== where.circleId) return false;
            if (where?.role && member.role !== where.role) return false;
            return true;
          })
          .map((member) => {
            if (!include?.user) return member;
            return {
              ...member,
              user: s.users.find((user) => user.id === member.userId) ?? null,
            };
          }),
      count: async ({ where } = {}) =>
        s.members.filter((m) => {
          if (where?.userId && m.userId !== where.userId) return false;
          if (where?.circleId && m.circleId !== where.circleId) return false;
          if (where?.role && m.role !== where.role) return false;
          return true;
        }).length,
      delete: async ({ where }) => {
        const index = s.members.findIndex((m) => m.id === where.id);
        if (index === -1) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        const [deleted] = s.members.splice(index, 1);
        return deleted;
      },
      update: async ({ where, data: d }) => {
        const member = s.members.find((m) => m.id === where.id);
        if (!member) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        Object.assign(member, d);
        return member;
      },
    };
  }

  function taskRepo(s) {
    function matchesTaskWhere(task, where = {}) {
      if (where.OR && !where.OR.some((branch) => matchesTaskWhere(task, branch))) return false;
      if (where.id && task.id !== where.id) return false;
      if (where.circleId && task.circleId !== where.circleId) return false;
      if (where.recipientId && typeof where.recipientId === "string" && task.recipientId !== where.recipientId) return false;
      if (where.recipientId?.in && !where.recipientId.in.includes(task.recipientId)) return false;
      if (where.seriesId && task.seriesId !== where.seriesId) return false;
      if (where.assigneeId && typeof where.assigneeId === "string" && task.assigneeId !== where.assigneeId) return false;
      if (where.assigneeId?.in && !where.assigneeId.in.includes(task.assigneeId)) return false;
      if (where.creatorId && task.creatorId !== where.creatorId) return false;
      if (where.archivedAt === null && task.archivedAt !== null) return false;
      if (where.archivedAt?.not === null && task.archivedAt === null) return false;
      if (where.status && typeof where.status === "string" && task.status !== where.status) return false;
      if (where.status?.in && !where.status.in.includes(task.status)) return false;
      if (where.status?.not && task.status === where.status.not) return false;
      if (where.status?.notIn && where.status.notIn.includes(task.status)) return false;
      if (where.dueAt && where.dueAt instanceof Date && String(task.dueAt) !== String(where.dueAt)) return false;
      if (where.dueAt?.lt && !(task.dueAt && task.dueAt < where.dueAt.lt)) return false;
      if (where.dueAt?.lte && !(task.dueAt && task.dueAt <= where.dueAt.lte)) return false;
      if (where.dueAt?.gte && !(task.dueAt && task.dueAt >= where.dueAt.gte)) return false;
      if (where.dueAt?.not === null && task.dueAt === null) return false;
      if (where.completedAt?.lte && !(task.completedAt && task.completedAt <= where.completedAt.lte)) return false;
      if (where.completedAt?.gte && !(task.completedAt && task.completedAt >= where.completedAt.gte)) return false;
      return true;
    }

    function includeTask(task, include) {
      if (!task) return null;
      if (!include) return { ...task };
      return {
        ...task,
        assignee: include.assignee ? (s.users.find((u) => u.id === task.assigneeId) ?? null) : undefined,
        completedBy: include.completedBy ? (s.users.find((u) => u.id === task.completedById) ?? null) : undefined,
        recipient: include.recipient ? (s.recipients.find((recipient) => recipient.id === task.recipientId) ?? null) : undefined,
        circle: include.circle ? (s.circles.find((c) => c.id === task.circleId) ?? null) : undefined,
      };
    }

    return {
      create: async ({ data: d, include }) => {
        const t = {
          id: uid("t"),
          createdAt: new Date(),
          updatedAt: new Date(),
          status: "PENDING",
          notes: null,
          assigneeId: null,
          recurrenceFrequency: "NONE",
          recurrenceInterval: null,
          recurrenceWeekdays: [],
          recurrenceEndsAt: null,
          seriesId: null,
          completedAt: null,
          completedById: null,
          archivedAt: null,
          recipientId: null,
          ...d
        };
        s.tasks.push(t);
        return includeTask(t, include);
      },
      findMany:  async ({ where, include, orderBy, cursor, skip, take } = {}) =>
        windowItems(
          orderItems(
            s.tasks.filter((task) => matchesTaskWhere(task, where)),
            orderBy,
          ),
          { cursor, skip, take },
        ).map((task) => includeTask(task, include)),
      findFirst: async ({ where, include }) =>
        includeTask(s.tasks.find((task) => matchesTaskWhere(task, where)) ?? null, include),
      count: async ({ where } = {}) =>
        s.tasks.filter((task) => matchesTaskWhere(task, where)).length,
      update: async ({ where, data: d, include }) => {
        const task = s.tasks.find((t) => t.id === where.id);
        if (!task) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        Object.assign(task, d, { updatedAt: new Date() });
        return includeTask(task, include);
      },
      updateMany: async ({ where, data: d }) => {
        let count = 0;
        for (const task of s.tasks) {
          if (!matchesTaskWhere(task, where)) continue;
          Object.assign(task, d, { updatedAt: new Date() });
          count += 1;
        }
        return { count };
      },
      delete: async ({ where }) => {
        const index = s.tasks.findIndex((task) => task.id === where.id);
        if (index === -1) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        const [deleted] = s.tasks.splice(index, 1);
        return deleted;
      },
    };
  }

  function reminderRepo(s) {
    function matchesReminderWhere(reminder, where = {}) {
      if (where.taskId && reminder.taskId !== where.taskId) return false;
      if (where.status && typeof where.status === "string" && reminder.status !== where.status) return false;
      if (where.status?.in && !where.status.in.includes(reminder.status)) return false;
      if (where.scheduledAt?.lte && !(reminder.scheduledAt && reminder.scheduledAt <= where.scheduledAt.lte)) return false;
      if (where.escalatedAt?.gte && !(reminder.escalatedAt && reminder.escalatedAt >= where.escalatedAt.gte)) return false;
      if (where.escalationDueAt?.lte && !(reminder.escalationDueAt && reminder.escalationDueAt <= where.escalationDueAt.lte)) return false;
      if (where.task) {
        const task = s.tasks.find((item) => item.id === reminder.taskId);
        if (!task) return false;
        if (where.task.circleId && task.circleId !== where.task.circleId) return false;
        if (where.task.recipientId && task.recipientId !== where.task.recipientId) return false;
        if (where.task.archivedAt === null && task.archivedAt !== null) return false;
        if (where.task.status?.notIn?.includes(task.status)) return false;
        if (where.task.status?.not && task.status === where.task.status.not) return false;
      }
      return true;
    }

    function includeReminder(reminder, include) {
      if (!reminder) return null;
      if (!include?.task) return { ...reminder };
      const task = s.tasks.find((item) => item.id === reminder.taskId);
      const circle = task ? s.circles.find((item) => item.id === task.circleId) : null;
      return {
        ...reminder,
        task: task ? {
          ...task,
          recipient: include.task.include?.recipient
            ? (s.recipients.find((recipient) => recipient.id === task.recipientId) ?? null)
            : undefined,
          circle: include.task.include?.circle?.include?.members
            ? { ...circle, members: s.members.filter((member) => member.circleId === task.circleId) }
            : circle,
        } : null,
      };
    }

    return {
      create: async ({ data: d }) => {
        const r = {
          id: uid("r"),
          status: "PENDING",
          sentAt: null,
          snoozedUntil: null,
          snoozeCount: 0,
          escalationDueAt: null,
          escalatedAt: null,
          ...d,
        };
        s.reminders.push(r);
        return r;
      },
      findFirst: async ({ where }) =>
        includeReminder(s.reminders.find((reminder) => matchesReminderWhere(reminder, where)) ?? null),
      findMany: async ({ where, include } = {}) =>
        s.reminders
          .filter((reminder) => matchesReminderWhere(reminder, where))
          .map((reminder) => includeReminder(reminder, include)),
      update: async ({ where, data: d, include }) => {
        const reminder = s.reminders.find((item) => item.id === where.id);
        if (!reminder) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        Object.assign(reminder, d);
        return includeReminder(reminder, include);
      },
      deleteMany: async ({ where }) => {
        const before = s.reminders.length;
        s.reminders = s.reminders.filter((reminder) => {
          if (where.taskId && reminder.taskId === where.taskId) return false;
          return true;
        });
        return { count: before - s.reminders.length };
      },
    };
  }

  function taskCommentRepo(s) {
    return {
      create: async ({ data: d, include }) => {
        const comment = {
          id: uid("tc"),
          createdAt: new Date(),
          updatedAt: new Date(),
          ...d,
        };
        s.taskComments.push(comment);
        if (!include?.author) return comment;
        return {
          ...comment,
          author: s.users.find((user) => user.id === comment.authorId) ?? null,
        };
      },
      findMany: async ({ where, include, orderBy, cursor, skip, take } = {}) =>
        windowItems(
          orderItems(
            s.taskComments.filter((comment) => {
              if (where?.taskId && comment.taskId !== where.taskId) return false;
              return true;
            }),
            orderBy,
          ),
          { cursor, skip, take },
        ).map((comment) => ({
          ...comment,
          author: include?.author ? (s.users.find((user) => user.id === comment.authorId) ?? null) : undefined,
        })),
      findFirst: async ({ where, select } = {}) => {
        const comment = s.taskComments.find((item) => {
          if (where?.id && item.id !== where.id) return false;
          if (where?.taskId && item.taskId !== where.taskId) return false;
          return true;
        }) ?? null;
        if (!comment || !select) return comment;
        return Object.fromEntries(Object.keys(select).map((key) => [key, comment[key]]));
      },
      delete: async ({ where }) => {
        const index = s.taskComments.findIndex((item) => item.id === where.id);
        if (index === -1) throw Object.assign(new Error("NotFound"), { code: "P2025" });
        const [deleted] = s.taskComments.splice(index, 1);
        return deleted;
      },
    };
  }

  function eventRepo(s) {
    return {
      create:   async ({ data: d }) => { const e = { id: uid("e"), createdAt: new Date(), payload: {}, ...d }; s.events.push(e); return e; },
      findMany: async ({ where, orderBy, take, include, cursor, skip } = {}) => {
        let items = s.events.filter((event) => {
          if (where?.circleId && event.circleId !== where.circleId) return false;
          return true;
        });
        items = windowItems(orderItems(items, orderBy), { cursor, skip, take });
        return items.map((event) => ({
          ...event,
          actor: include?.actor ? (s.users.find((user) => user.id === event.actorId) ?? null) : undefined,
        }));
      },
      findFirst: async () => null,
    };
  }

  const txProxy = (s) => ({
    user:         userRepo(s),
    careCircle:   circleRepo(s),
    invitation:   invitationRepo(s),
    careRecipient: careRecipientRepo(s),
    careRecipientEntitlement: careRecipientEntitlementRepo(s),
    careRecipientAccess: careRecipientAccessRepo(s),
    premiumUpgradeRequest: premiumUpgradeRequestRepo(s),
    circleMember: memberRepo(s),
    authIdentity: authIdentityRepo(s),
    passwordResetCode: passwordResetCodeRepo(s),
    task:         taskRepo(s),
    taskComment:  taskCommentRepo(s),
    reminder:     reminderRepo(s),
    event:        eventRepo(s),
  });

  return {
    _s: S,
    user:         userRepo(S),
    invitation:   invitationRepo(S),
    authIdentity: authIdentityRepo(S),
    passwordResetCode: passwordResetCodeRepo(S),
    careCircle:   circleRepo(S),
    careRecipient: careRecipientRepo(S),
    careRecipientEntitlement: careRecipientEntitlementRepo(S),
    careRecipientAccess: careRecipientAccessRepo(S),
    premiumUpgradeRequest: premiumUpgradeRequestRepo(S),
    circleMember: memberRepo(S),
    task:         taskRepo(S),
    taskComment:  taskCommentRepo(S),
    reminder:     reminderRepo(S),
    event:        eventRepo(S),
    $transaction: async (fn) => fn(txProxy(S)),
  };
}

async function buildApp(db) {
  const app = Fastify({ logger: false });
  app.decorate("db", db);
  await app.register(authPlugin);
  app.register(authRoutes);
  app.register(usersRoute);
  app.register(circlesRoute);
  app.register(tasksRoute);
  await app.ready();
  return app;
}

// ═══════════════════════════════════════════════════════════════════════════════
// auth routes
// ═══════════════════════════════════════════════════════════════════════════════

describe("auth routes", () => {
  test("POST /auth/signup creates a password-backed user", async () => {
    const app = await buildApp(buildDb());
    const res = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "New@Example.com", name: "New User", password: "password123" },
    });
    assert.equal(res.statusCode, 201);
    const body = res.json();
    assert.equal(body.user.email, "new@example.com");
    assert.equal(body.method, "PASSWORD");
    assert.ok(body.accessToken, "access token is returned");
    await app.close();
  });

  test("POST /auth/login rejects wrong password", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "a@test.com", name: "Alice", passwordHash: hashPassword("password123") }],
    }));
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "a@test.com", password: "wrongpass" },
    });
    assert.equal(res.statusCode, 401);
    await app.close();
  });

  test("POST /auth/login returns the matching user", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "a@test.com", name: "Alice", passwordHash: hashPassword("password123") }],
    }));
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "A@Test.com", password: "password123" },
    });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.user.id, "u1");
    assert.equal(body.method, "PASSWORD");
    assert.ok(body.accessToken, "access token is returned");
    await app.close();
  });

  test("POST /auth/social creates a user and identity from local fallback payload", async () => {
    const app = await buildApp(buildDb());
    const res = await app.inject({
      method: "POST",
      url: "/auth/social",
      payload: {
        provider: "GOOGLE",
        providerUserId: "google-123",
        email: "social@test.com",
        name: "Social User",
      },
    });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.user.email, "social@test.com");
    assert.equal(body.method, "GOOGLE");
    assert.ok(body.accessToken, "access token is returned");
    await app.close();
  });

  test("POST /auth/social accepts provider names case-insensitively", async () => {
    const app = await buildApp(buildDb());
    const res = await app.inject({
      method: "POST",
      url: "/auth/social",
      payload: {
        provider: "google",
        providerUserId: "google-lowercase",
        email: "lowercase-provider@test.com",
        name: "Lowercase Provider",
      },
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.json().method, "GOOGLE");
    assert.equal(app.db._s.identities[0].provider, "GOOGLE");
    await app.close();
  });

  test("POST /auth/social rejects unsupported providers before profile resolution", async () => {
    const app = await buildApp(buildDb());
    const res = await app.inject({
      method: "POST",
      url: "/auth/social",
      payload: {
        provider: "gmail",
        providerUserId: "gmail-123",
        email: "gmail@test.com",
        name: "Gmail User",
      },
    });

    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "provider must be GOOGLE, FACEBOOK, or APPLE");
    assert.equal(app.db._s.users.length, 0);
    await app.close();
  });

  test("POST /auth/social rejects local fallback payloads in production mode", async () => {
    const previousNodeEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = "production";
    const app = await buildApp(buildDb());
    try {
      const res = await app.inject({
        method: "POST",
        url: "/auth/social",
        payload: {
          provider: "GOOGLE",
          providerUserId: "google-prod-fallback",
          email: "prod-social@test.com",
          name: "Prod Social",
        },
      });

      assert.equal(res.statusCode, 401);
      assert.equal(res.json().error, "Google authentication payload is incomplete");
      assert.equal(app.db._s.users.length, 0);
    } finally {
      if (previousNodeEnv === undefined) {
        delete process.env.NODE_ENV;
      } else {
        process.env.NODE_ENV = previousNodeEnv;
      }
      await app.close();
    }
  });

  test("POST /auth/login includes pending invitations for the authenticated email", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "member@test.com", name: "Member", passwordHash: hashPassword("password123") }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "member@test.com",
        name: "Member",
        role: "MEMBER",
        status: "PENDING",
        invitedById: null,
        acceptedById: null,
        acceptedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
    }));
    const res = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "member@test.com", password: "password123" },
    });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.user.pendingInvites.length, 1);
    assert.equal(body.user.pendingInvites[0].id, "i1");
    await app.close();
  });

  test("POST /auth/logout revokes the current bearer token version", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "logout@test.com", name: "Logout User", passwordHash: hashPassword("password123"), authVersion: 0 }],
    }));
    const token = await issueAccessToken({ id: "u1", email: "logout@test.com", name: "Logout User", authVersion: 0 });
    const headers = {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    };

    const logout = await app.inject({
      method: "POST",
      url: "/auth/logout",
      headers,
      payload: {},
    });
    assert.equal(logout.statusCode, 200);
    assert.equal(logout.json().loggedOut, true);
    assert.equal(app.db._s.users[0].authVersion, 1);

    const revoked = await app.inject({
      method: "GET",
      url: "/users/me",
      headers,
    });
    assert.equal(revoked.statusCode, 401);
    assert.equal(revoked.json().error, "Access token has been revoked");
    await app.close();
  });

  test("GET /auth/oauth/google/start redirects to Google's consent screen", async () => {
    const app = await buildApp(buildDb());
    const res = await app.inject({
      method: "GET",
      url: "/auth/oauth/google/start?callback_scheme=careloop",
    });
    assert.equal(res.statusCode, 302);
    assert.match(res.headers.location, /^https:\/\/accounts\.google\.com\/o\/oauth2\/v2\/auth\?/);
    assert.match(res.headers.location, /client_id=google-client/);
    assert.match(res.headers.location, /redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fauth%2Foauth%2Fgoogle%2Fcallback/);
    await app.close();
  });

  test("verifyOAuthState returns the signed callback payload", () => {
    const state = createOAuthState({ provider: "GOOGLE", callbackScheme: "careloop" });
    const payload = verifyOAuthState(state);
    assert.equal(payload.provider, "GOOGLE");
    assert.equal(payload.callbackScheme, "careloop");
  });

  test("forgot password request stores a reset code and returns debugCode in local dev", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "reset@test.com", name: "Reset User", passwordHash: hashPassword("password123") }],
    }));
    const res = await app.inject({
      method: "POST",
      url: "/auth/forgot-password/request",
      payload: { email: "reset@test.com" },
    });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.sent, true);
    assert.equal(typeof body.debugCode, "string");
    assert.equal(app.db._s.passwordResetCodes.length, 1);
    await app.close();
  });

  test("forgot password verify/reset updates password", async () => {
    const db = buildDb({
      users: [{ id: "u1", email: "reset@test.com", name: "Reset User", passwordHash: hashPassword("password123") }],
    });
    const app = await buildApp(db);
    const request = await app.inject({
      method: "POST",
      url: "/auth/forgot-password/request",
      payload: { email: "reset@test.com" },
    });
    const code = request.json().debugCode;
    const verify = await app.inject({
      method: "POST",
      url: "/auth/forgot-password/verify",
      payload: { email: "reset@test.com", code },
    });
    assert.equal(verify.statusCode, 200);
    const reset = await app.inject({
      method: "POST",
      url: "/auth/forgot-password/reset",
      payload: { email: "reset@test.com", code, password: "newpassword1" },
    });
    assert.equal(reset.statusCode, 200);

    const login = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "reset@test.com", password: "newpassword1" },
    });
    assert.equal(login.statusCode, 200);
    await app.close();
  });

  test("forgot password reset revokes previously issued access tokens", async () => {
    const db = buildDb({
      users: [{ id: "u1", email: "reset2@test.com", name: "Reset User", passwordHash: hashPassword("password123"), authVersion: 0 }],
    });
    const app = await buildApp(db);

    const login = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "reset2@test.com", password: "password123" },
    });
    assert.equal(login.statusCode, 200);
    const oldToken = login.json().accessToken;

    const request = await app.inject({
      method: "POST",
      url: "/auth/forgot-password/request",
      payload: { email: "reset2@test.com" },
    });
    const code = request.json().debugCode;

    const reset = await app.inject({
      method: "POST",
      url: "/auth/forgot-password/reset",
      payload: { email: "reset2@test.com", code, password: "newpassword1" },
    });
    assert.equal(reset.statusCode, 200);

    const staleSession = await app.inject({
      method: "GET",
      url: "/users/me",
      headers: { authorization: `Bearer ${oldToken}` },
    });
    assert.equal(staleSession.statusCode, 401);

    const freshLogin = await app.inject({
      method: "POST",
      url: "/auth/login",
      payload: { email: "reset2@test.com", password: "newpassword1" },
    });
    assert.equal(freshLogin.statusCode, 200);
    await app.close();
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// push.js — deliverTaskNotification
// ═══════════════════════════════════════════════════════════════════════════════

describe("deliverTaskNotification", () => {
  const task = { id: "t1", title: "Give meds", circle: { name: "Smith Family" } };

  test("returns NONE — user not found", async () => {
    const db = buildDb();
    const r = await deliverTaskNotification({ db, userId: "ghost", task, type: "reminder" });
    assert.equal(r.delivered, false);
    assert.equal(r.channel, "NONE");
    assert.equal(r.reason, "user_not_found");
  });

  test("returns NONE — user has no push token and no email", async () => {
    const db = buildDb({ users: [{ id: "u1", name: "A", email: null, pushToken: null }] });
    const r = await deliverTaskNotification({ db, userId: "u1", task, type: "reminder" });
    assert.equal(r.delivered, false);
    assert.equal(r.channel, "NONE");
  });

  test("simulates PUSH — user has push token, APNs not configured", async () => {
    const db = buildDb({ users: [{ id: "u1", name: "A", email: "a@t.com", pushToken: "tok123" }] });
    const r = await deliverTaskNotification({ db, userId: "u1", task, type: "reminder" });
    assert.equal(r.simulated, true);
    assert.equal(r.channel, "PUSH");
    assert.equal(r.reason, "apns_not_configured");
  });

  test("simulates EMAIL fallback — no push token, RESEND not configured", async () => {
    const db = buildDb({ users: [{ id: "u1", name: "A", email: "a@t.com", pushToken: null }] });
    const r = await deliverTaskNotification({ db, userId: "u1", task, type: "reminder" });
    assert.equal(r.delivered, true);
    assert.equal(r.simulated, true);
    assert.equal(r.channel, "EMAIL");
  });

  test("uses escalation content type without crashing", async () => {
    const db = buildDb({ users: [{ id: "u1", name: "A", email: null, pushToken: "tok" }] });
    const r = await deliverTaskNotification({ db, userId: "u1", task, type: "escalation" });
    assert.equal(r.channel, "PUSH");
    assert.equal(r.simulated, true);
  });

  test("uses assignment content type without crashing", async () => {
    const db = buildDb({ users: [{ id: "u1", name: "A", email: null, pushToken: "tok" }] });
    const r = await deliverTaskNotification({ db, userId: "u1", task, type: "assignment" });
    assert.equal(r.channel, "PUSH");
    assert.equal(r.simulated, true);
  });

  test("respects task assignment and escalation notification preferences", async () => {
    const db = buildDb({
      users: [{
        id: "u1",
        name: "A",
        email: "a@t.com",
        pushToken: "tok123",
        notifAssignments: false,
        notifEscalations: false,
      }],
    });

    const assignment = await deliverTaskNotification({ db, userId: "u1", task, type: "assignment" });
    const escalation = await deliverTaskNotification({ db, userId: "u1", task, type: "escalation" });

    assert.equal(assignment.delivered, false);
    assert.equal(assignment.reason, "notifications_disabled_by_user");
    assert.equal(escalation.delivered, false);
    assert.equal(escalation.reason, "notifications_disabled_by_user");
  });
});

describe("circle membership management", () => {
  test("POST /circles rejects creating a fourth circle for the same user", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "a@test.com", name: "Alice" }],
      circles: [
        { id: "c1", name: "One", recipientName: "A", archiveAfterDays: 7 },
        { id: "c2", name: "Two", recipientName: "B", archiveAfterDays: 7 },
        { id: "c3", name: "Three", recipientName: "C", archiveAfterDays: 7 },
      ],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u1", circleId: "c2", role: "ADMIN" },
        { id: "m3", userId: "u1", circleId: "c3", role: "MEMBER" },
      ],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles",
      headers: HDR,
      payload: { name: "Four", recipientName: "D", creatorId: "u1" },
    });

    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "Users can only belong to 3 circles.");
    await app.close();
  });

  test("POST /circles/:id/members rejects joining a fourth circle", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "a@test.com", name: "Alice" }],
      circles: [
        { id: "c1", name: "One", recipientName: "A", archiveAfterDays: 7 },
        { id: "c2", name: "Two", recipientName: "B", archiveAfterDays: 7 },
        { id: "c3", name: "Three", recipientName: "C", archiveAfterDays: 7 },
        { id: "c4", name: "Four", recipientName: "D", archiveAfterDays: 7 },
      ],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u1", circleId: "c2", role: "ADMIN" },
        { id: "m3", userId: "u1", circleId: "c3", role: "MEMBER" },
      ],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c4/members",
      headers: HDR,
      payload: { userId: "u1" },
    });

    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "Users can only belong to 3 circles.");
    await app.close();
  });

  test("POST /circles/:id/members/invite creates a pending invitation", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/members/invite",
      headers: HDR,
      payload: { userId: "u1", name: "New Member", email: "member@test.com", role: "ADMIN" },
    });

    assert.equal(res.statusCode, 201);
    const body = res.json();
    assert.equal(body.role, "ADMIN");
    assert.equal(body.email, "member@test.com");
    assert.equal(body.status, "PENDING");
    assert.ok(body.expiresAt, "invite expiration is returned");
    assert.equal(app.db._s.members.length, 1);
    await app.close();
  });

  test("POST /circles/:id/invitations/:inviteId/resend extends pending invitation", async () => {
    const originalExpiry = new Date(Date.now() + 24 * 60 * 60 * 1000);
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "member@test.com",
        name: "New Member",
        role: "MEMBER",
        status: "PENDING",
        recipientId: null,
        invitedById: "u1",
        acceptedById: null,
        acceptedAt: null,
        expiresAt: originalExpiry,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/invitations/i1/resend",
      headers: HDR,
      payload: { userId: "u1" },
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.json().status, "PENDING");
    assert.ok(new Date(res.json().expiresAt) > originalExpiry);
    assert.equal(app.db._s.events.at(-1).type, "INVITE_CREATED");
    assert.equal(app.db._s.events.at(-1).payload.action, "RESENT");
    await app.close();
  });

  test("recipient invitation marks the linked care receiver as invited", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: null,
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "DRAFT",
        activatedAt: null,
        receiverUserId: null,
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/members/invite",
      headers: HDR,
      payload: { userId: "u1", name: "Mom", email: "mom@test.com", role: "RECIPIENT", recipientId: "cr1" },
    });

    assert.equal(res.statusCode, 201);
    assert.equal(app.db._s.recipients[0].activationStatus, "INVITED");
    await app.close();
  });

  test("POST /circles creates the first care receiver as inactive until accepted", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
    }));
    const res = await app.inject({
      method: "POST",
      url: "/circles",
      headers: HDR,
      payload: { name: "Alpha", recipientName: "Mom" },
    });

    assert.equal(res.statusCode, 201);
    const recipient = app.db._s.recipients.find((item) => item.circleId === res.json().id);
    assert.equal(recipient.activationStatus, "DRAFT");
    assert.equal(recipient.receiverUserId, null);
    await app.close();
  });

  test("POST /invitations/:inviteId/accept creates membership after auth", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", email: "admin@test.com", name: "Admin" },
        { id: "u2", email: "member@test.com", name: "Member" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "member@test.com",
        name: "Member",
        role: "ADMIN",
        status: "PENDING",
        invitedById: "u1",
        acceptedById: null,
        acceptedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/invitations/i1/accept",
      headers: await authHeaders({ id: "u2", email: "member@test.com", name: "Member" }),
      payload: {},
    });

    assert.equal(res.statusCode, 201);
    const body = res.json();
    assert.equal(body.role, "ADMIN");
    assert.equal(app.db._s.members.length, 2);
    assert.equal(app.db._s.invitations[0].status, "ACCEPTED");
    await app.close();
  });

  test("caregiver invitation acceptance grants no receiver access by default", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", email: "admin@test.com", name: "Admin" },
        { id: "u2", email: "caregiver@test.com", name: "Caregiver" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: "Mother",
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "ACTIVE",
        activatedAt: new Date(),
        receiverUserId: null,
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "caregiver@test.com",
        name: "Caregiver",
        role: "MEMBER",
        status: "PENDING",
        invitedById: "u1",
        acceptedById: null,
        acceptedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      tasks: [{
        id: "t1",
        circleId: "c1",
        recipientId: "cr1",
        title: "Medication",
        status: "PENDING",
        priority: "NORMAL",
        creatorId: "u1",
        assigneeId: "u1",
        dueAt: null,
        completedAt: null,
        completedById: null,
        archivedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
        recurrenceFrequency: "NONE",
        recurrenceInterval: null,
        recurrenceWeekdays: [],
        recurrenceEndsAt: null,
        seriesId: null,
      }],
    }));

    const caregiverHeaders = await authHeaders({ id: "u2", email: "caregiver@test.com", name: "Caregiver" });
    const accept = await app.inject({
      method: "POST",
      url: "/invitations/i1/accept",
      headers: caregiverHeaders,
      payload: {},
    });

    assert.equal(accept.statusCode, 201);
    assert.equal(accept.json().role, "MEMBER");
    assert.equal(app.db._s.recipientAccesses.length, 0);

    const circle = await app.inject({
      method: "GET",
      url: "/circles/c1",
      headers: caregiverHeaders,
    });

    assert.equal(circle.statusCode, 200);
    assert.deepEqual(circle.json().recipients, []);
    assert.deepEqual(circle.json().tasks, []);
    await app.close();
  });

  test("recipient invitation activates the existing care receiver profile on acceptance", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", email: "admin@test.com", name: "Admin" },
        { id: "u2", email: "mom@test.com", name: "Mom" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: null,
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "DRAFT",
        activatedAt: null,
        receiverUserId: null,
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const invite = await app.inject({
      method: "POST",
      url: "/circles/c1/members/invite",
      headers: HDR,
      payload: { name: "Mom", email: "mom@test.com", role: "RECIPIENT", recipientId: "cr1" },
    });
    assert.equal(invite.statusCode, 201);
    assert.equal(invite.json().recipientId, "cr1");

    const accept = await app.inject({
      method: "POST",
      url: `/invitations/${invite.json().id}/accept`,
      headers: await authHeaders({ id: "u2", email: "mom@test.com", name: "Mom" }),
      payload: {},
    });
    assert.equal(accept.statusCode, 201);
    assert.equal(app.db._s.recipients.length, 1);
    assert.equal(app.db._s.recipients[0].activationStatus, "ACTIVE");
    assert.equal(app.db._s.recipients[0].receiverUserId, "u2");
    await app.close();
  });

  test("POST /invitations/:inviteId/decline marks the invite declined", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u2", email: "member@test.com", name: "Member" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "member@test.com",
        name: "Member",
        role: "MEMBER",
        status: "PENDING",
        invitedById: null,
        acceptedById: null,
        acceptedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/invitations/i1/decline",
      headers: await authHeaders({ id: "u2", email: "member@test.com", name: "Member" }),
      payload: {},
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.json().declined, true);
    assert.equal(app.db._s.invitations[0].status, "DECLINED");
    await app.close();
  });

  test("declining a recipient invitation resets the unclaimed care receiver to draft", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u2", email: "mom@test.com", name: "Mom" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: null,
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "INVITED",
        activatedAt: null,
        receiverUserId: null,
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "mom@test.com",
        name: "Mom",
        role: "RECIPIENT",
        recipientId: "cr1",
        status: "PENDING",
        invitedById: null,
        acceptedById: null,
        acceptedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/invitations/i1/decline",
      headers: await authHeaders({ id: "u2", email: "mom@test.com", name: "Mom" }),
      payload: {},
    });

    assert.equal(res.statusCode, 200);
    assert.equal(app.db._s.recipients[0].activationStatus, "DRAFT");
    await app.close();
  });

  test("POST /invitations/:inviteId/accept expires stale pending invitations", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u2", email: "member@test.com", name: "Member" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "member@test.com",
        name: "Member",
        role: "MEMBER",
        status: "PENDING",
        invitedById: null,
        acceptedById: null,
        acceptedAt: null,
        expiresAt: new Date(Date.now() - 60 * 1000),
        createdAt: new Date(Date.now() - 15 * 24 * 60 * 60 * 1000),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/invitations/i1/accept",
      headers: await authHeaders({ id: "u2", email: "member@test.com", name: "Member" }),
      payload: {},
    });

    assert.equal(res.statusCode, 409);
    assert.equal(res.json().error, "Invitation has expired");
    assert.equal(app.db._s.invitations[0].status, "EXPIRED");
    assert.equal(app.db._s.members.length, 0);
    await app.close();
  });

  test("POST /invitations/:inviteId/accept rejects wrong authenticated email", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u2", email: "member@test.com", name: "Member" },
        { id: "u3", email: "wrong@test.com", name: "Wrong User" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "member@test.com",
        name: "Member",
        role: "MEMBER",
        status: "PENDING",
        invitedById: null,
        acceptedById: null,
        acceptedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/invitations/i1/accept",
      headers: await authHeaders({ id: "u3", email: "wrong@test.com", name: "Wrong User" }),
      payload: {},
    });

    assert.equal(res.statusCode, 403);
    assert.equal(res.json().error, "Invitation email does not match the authenticated user");
    assert.equal(app.db._s.invitations[0].status, "PENDING");
    assert.equal(app.db._s.members.length, 0);
    await app.close();
  });

  test("POST /invitations/:inviteId/accept rejects fourth-circle invite acceptance", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "member@test.com", name: "Member" }],
      circles: [
        { id: "c1", name: "One", recipientName: "A", archiveAfterDays: 7 },
        { id: "c2", name: "Two", recipientName: "B", archiveAfterDays: 7 },
        { id: "c3", name: "Three", recipientName: "C", archiveAfterDays: 7 },
        { id: "c4", name: "Four", recipientName: "D", archiveAfterDays: 7 },
      ],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u1", circleId: "c2", role: "MEMBER" },
        { id: "m3", userId: "u1", circleId: "c3", role: "MEMBER" },
      ],
      invitations: [{
        id: "i1",
        circleId: "c4",
        email: "member@test.com",
        name: "Member",
        role: "MEMBER",
        status: "PENDING",
        invitedById: null,
        acceptedById: null,
        acceptedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/invitations/i1/accept",
      headers: await authHeaders({ id: "u1", email: "member@test.com", name: "Member" }),
      payload: {},
    });

    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "Users can only belong to 3 circles.");
    assert.equal(app.db._s.invitations[0].status, "PENDING");
    assert.equal(app.db._s.members.length, 3);
    await app.close();
  });

  test("POST /invitations/:inviteId/accept rejects already-member invite acceptance", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u2", email: "member@test.com", name: "Member" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u2", circleId: "c1", role: "MEMBER" }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "member@test.com",
        name: "Member",
        role: "MEMBER",
        status: "PENDING",
        invitedById: null,
        acceptedById: null,
        acceptedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/invitations/i1/accept",
      headers: await authHeaders({ id: "u2", email: "member@test.com", name: "Member" }),
      payload: {},
    });

    assert.equal(res.statusCode, 409);
    assert.equal(res.json().error, "User is already a member");
    assert.equal(app.db._s.invitations[0].status, "PENDING");
    assert.equal(app.db._s.members.length, 1);
    await app.close();
  });

  test("expired recipient invites reset draft state and allow a fresh invite", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: null,
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "INVITED",
        activatedAt: null,
        receiverUserId: null,
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "mom@test.com",
        name: "Mom",
        role: "RECIPIENT",
        recipientId: "cr1",
        status: "PENDING",
        invitedById: "u1",
        acceptedById: null,
        acceptedAt: null,
        expiresAt: new Date(Date.now() - 60 * 1000),
        createdAt: new Date(Date.now() - 15 * 24 * 60 * 60 * 1000),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/members/invite",
      headers: HDR,
      payload: { userId: "u1", name: "Mom", email: "mom@test.com", role: "RECIPIENT", recipientId: "cr1" },
    });

    assert.equal(res.statusCode, 201);
    assert.equal(app.db._s.invitations[0].status, "EXPIRED");
    assert.equal(app.db._s.invitations[1].status, "PENDING");
    assert.equal(app.db._s.recipients[0].activationStatus, "INVITED");
    await app.close();
  });

  test("POST /circles/:id/recipients/:recipientId/proxy-activate marks a care receiver proxy active", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: "Mother",
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "DRAFT",
        activatedAt: null,
        receiverUserId: null,
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/recipients/cr1/proxy-activate",
      headers: HDR,
      payload: { userId: "u1", authorizationAttested: true, consentDocumentReference: "family-consent-form" },
    });

    assert.equal(res.statusCode, 200);
    assert.equal(app.db._s.recipients[0].activationStatus, "PROXY_ACTIVE");
    assert.equal(app.db._s.recipients[0].proxyAuthorizedById, "u1");
    assert.equal(app.db._s.recipients[0].consentDocumentReference, "family-consent-form");
    assert.equal(app.db._s.events.at(-1).payload.authorizationAttested, true);
    assert.equal(app.db._s.events.at(-1).payload.hasConsentDocumentReference, true);
    assert.equal(app.db._s.events.at(-1).payload.consentDocumentReference, undefined);
    await app.close();
  });

  test("POST /circles/:id/recipients/:recipientId/proxy-activate requires explicit authorization attestation", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: "Mother",
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "DRAFT",
        activatedAt: null,
        receiverUserId: null,
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/recipients/cr1/proxy-activate",
      headers: HDR,
      payload: { userId: "u1", consentDocumentReference: "family-consent-form" },
    });

    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "Proxy activation requires explicit authorization attestation");
    assert.equal(app.db._s.recipients[0].activationStatus, "DRAFT");
    assert.equal(app.db._s.recipients[0].consentAttestedAt, null);
    assert.equal(app.db._s.recipients[0].proxyAuthorizedById, null);
    assert.equal(app.db._s.events.length, 0);
    await app.close();
  });

  test("POST /circles/:id/recipients/:recipientId/proxy-activate rejects a directly joined receiver", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", email: "admin@test.com", name: "Admin" },
        { id: "u2", email: "mom@test.com", name: "Mom" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: "Mother",
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "ACTIVE",
        activatedAt: new Date(),
        receiverUserId: "u2",
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u2", circleId: "c1", role: "RECIPIENT" },
      ],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/recipients/cr1/proxy-activate",
      headers: HDR,
      payload: { userId: "u1", authorizationAttested: true, consentDocumentReference: "family-consent-form" },
    });

    assert.equal(res.statusCode, 409);
    assert.equal(res.json().error, "Care receiver already joined directly");
    assert.equal(app.db._s.recipients[0].activationStatus, "ACTIVE");
    assert.equal(app.db._s.recipients[0].proxyAuthorizedById, null);
    await app.close();
  });

  test("POST /circles/:id/members/invite rejects direct invite for a proxy-activated receiver", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: "Mother",
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "PROXY_ACTIVE",
        activatedAt: new Date(),
        receiverUserId: null,
        consentAttestedAt: new Date(),
        consentAttestedById: "u1",
        proxyAuthorizedById: "u1",
        consentDocumentReference: "family-consent-form",
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/members/invite",
      headers: HDR,
      payload: { userId: "u1", name: "Mom", email: "mom@test.com", role: "RECIPIENT", recipientId: "cr1" },
    });

    assert.equal(res.statusCode, 409);
    assert.equal(res.json().error, "Care receiver is already proxy-activated");
    assert.equal(app.db._s.invitations.length, 0);
    await app.close();
  });

  test("DELETE /circles/:id removes an admin-owned circle and scoped records", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: null,
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "ACTIVE",
        activatedAt: new Date(),
        receiverUserId: null,
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
      invitations: [{
        id: "i1",
        circleId: "c1",
        email: "member@test.com",
        name: "Member",
        role: "MEMBER",
        status: "PENDING",
        invitedById: "u1",
        acceptedById: null,
        acceptedAt: null,
        expiresAt: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000),
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      tasks: [{
        id: "t1",
        circleId: "c1",
        recipientId: "cr1",
        title: "Medication",
        status: "PENDING",
        creatorId: "u1",
        assigneeId: "u1",
        dueAt: null,
        completedAt: null,
        archivedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
    }));

    const res = await app.inject({
      method: "DELETE",
      url: "/circles/c1",
      headers: HDR,
      payload: { userId: "u1" },
    });

    assert.equal(res.statusCode, 204);
    assert.equal(app.db._s.circles.length, 0);
    assert.equal(app.db._s.members.length, 0);
    assert.equal(app.db._s.recipients.length, 0);
    assert.equal(app.db._s.invitations.length, 0);
    assert.equal(app.db._s.tasks.length, 0);
    await app.close();
  });

  test("DELETE /circles/:id blocks non-admin circle deletion", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u2", email: "caregiver@test.com", name: "Caregiver" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      members: [{ id: "m2", userId: "u2", circleId: "c1", role: "MEMBER" }],
    }));

    const res = await app.inject({
      method: "DELETE",
      url: "/circles/c1",
      headers: await authHeaders({ id: "u2", email: "caregiver@test.com", name: "Caregiver" }),
      payload: {},
    });

    assert.equal(res.statusCode, 403);
    assert.equal(app.db._s.circles.length, 1);
    await app.close();
  });

  test("DELETE /circles/:id/members/me removes the current caregiver membership", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u2", email: "caregiver@test.com", name: "Caregiver" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Mom", archiveAfterDays: 7 }],
      members: [{ id: "m2", userId: "u2", circleId: "c1", role: "MEMBER" }],
    }));

    const res = await app.inject({
      method: "DELETE",
      url: "/circles/c1/members/me",
      headers: await authHeaders({ id: "u2", email: "caregiver@test.com", name: "Caregiver" }),
      payload: {},
    });

    assert.equal(res.statusCode, 204);
    assert.equal(app.db._s.members.length, 0);
    await app.close();
  });

  test("supports multi-user signup, invite acceptance, and self-join flows", async () => {
    const app = await buildApp(buildDb());

    const adminSignup = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "admin@careloop.test", name: "Admin User", password: "password123" },
    });
    assert.equal(adminSignup.statusCode, 201);
    const adminAuth = adminSignup.json();

    const invitedSignup = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "invitee@careloop.test", name: "Invitee User", password: "password123" },
    });
    assert.equal(invitedSignup.statusCode, 201);
    const inviteeAuth = invitedSignup.json();

    const joinerSignup = await app.inject({
      method: "POST",
      url: "/auth/signup",
      payload: { email: "joiner@careloop.test", name: "Joiner User", password: "password123" },
    });
    assert.equal(joinerSignup.statusCode, 201);
    const joinerAuth = joinerSignup.json();

    const adminHeaders = {
      authorization: `Bearer ${adminAuth.accessToken}`,
      "content-type": "application/json",
    };
    const inviteeHeaders = {
      authorization: `Bearer ${inviteeAuth.accessToken}`,
      "content-type": "application/json",
    };
    const joinerHeaders = {
      authorization: `Bearer ${joinerAuth.accessToken}`,
      "content-type": "application/json",
    };

    const createCircle = await app.inject({
      method: "POST",
      url: "/circles",
      headers: adminHeaders,
      payload: { name: "Care Team Alpha", recipientName: "John Doe" },
    });
    assert.equal(createCircle.statusCode, 201);
    const circle = createCircle.json();

    const invite = await app.inject({
      method: "POST",
      url: `/circles/${circle.id}/members/invite`,
      headers: adminHeaders,
      payload: { name: "Invitee User", email: "invitee@careloop.test", role: "MEMBER" },
    });
    assert.equal(invite.statusCode, 201);
    const invitation = invite.json();

    const inviteeContext = await app.inject({
      method: "GET",
      url: "/users/me",
      headers: inviteeHeaders,
    });
    assert.equal(inviteeContext.statusCode, 200);
    assert.equal(inviteeContext.json().pendingInvites.length, 1);
    assert.equal(inviteeContext.json().pendingInvites[0].id, invitation.id);

    const acceptInvite = await app.inject({
      method: "POST",
      url: `/invitations/${invitation.id}/accept`,
      headers: inviteeHeaders,
      payload: {},
    });
    assert.equal(acceptInvite.statusCode, 201);
    assert.equal(acceptInvite.json().userId, inviteeAuth.user.id);

    const selfJoin = await app.inject({
      method: "POST",
      url: `/circles/${circle.id}/members`,
      headers: joinerHeaders,
      payload: {},
    });
    assert.equal(selfJoin.statusCode, 201);
    assert.equal(selfJoin.json().userId, joinerAuth.user.id);

    const inviteeCircle = await app.inject({
      method: "GET",
      url: `/circles/${circle.id}`,
      headers: inviteeHeaders,
    });
    assert.equal(inviteeCircle.statusCode, 200);
    assert.equal(inviteeCircle.json().members.length, 3);

    const joinerTasks = await app.inject({
      method: "GET",
      url: `/circles/${circle.id}/tasks`,
      headers: joinerHeaders,
    });
    assert.equal(joinerTasks.statusCode, 200);
    assert.deepEqual(joinerTasks.json(), []);

    await app.close();
  });

  test("simulates 50 users through receiver activation invites tasks snooze completion and deletion", async () => {
    const app = await buildApp(buildDb());
    const password = "password123";
    const accounts = [];

    const headersFor = (auth) => ({
      authorization: `Bearer ${auth.accessToken}`,
      "content-type": "application/json",
    });

    for (let index = 1; index <= 50; index += 1) {
      const signup = await app.inject({
        method: "POST",
        url: "/auth/signup",
        payload: {
          email: `careloop-user-${String(index).padStart(2, "0")}@example.test`,
          name: `CareLoop User ${index}`,
          password,
        },
      });
      assert.equal(signup.statusCode, 201);
      const auth = signup.json();
      accounts.push({ ...auth, headers: headersFor(auth) });
    }

    const organizer = accounts[0];
    const receiver = accounts[1];
    const backupAdmins = accounts.slice(2, 6);
    const caregivers = accounts.slice(6);

    const createCircle = await app.inject({
      method: "POST",
      url: "/circles",
      headers: organizer.headers,
      payload: {
        creatorId: organizer.user.id,
        name: "50 User CareLoop Simulation",
        recipientName: "Primary Receiver",
      },
    });
    assert.equal(createCircle.statusCode, 201);
    const circle = createCircle.json();
    const recipientId = circle.recipients[0].id;

    const receiverInvite = await app.inject({
      method: "POST",
      url: `/circles/${circle.id}/members/invite`,
      headers: organizer.headers,
      payload: {
        userId: organizer.user.id,
        name: receiver.user.name,
        email: receiver.user.email,
        role: "RECIPIENT",
        recipientId,
      },
    });
    assert.equal(receiverInvite.statusCode, 201);

    const acceptReceiver = await app.inject({
      method: "POST",
      url: `/invitations/${receiverInvite.json().id}/accept`,
      headers: receiver.headers,
      payload: { userId: receiver.user.id },
    });
    assert.equal(acceptReceiver.statusCode, 201);
    assert.equal(acceptReceiver.json().role, "RECIPIENT");

    const premium = await app.inject({
      method: "PUT",
      url: `/circles/${circle.id}/recipients/${recipientId}/entitlement`,
      headers: organizer.headers,
      payload: { userId: organizer.user.id, source: "MANUAL" },
    });
    assert.equal(premium.statusCode, 200);
    assert.equal(premium.json().premium.hasPremium, true);

    const acceptedMembers = [];
    for (const account of [...backupAdmins, ...caregivers]) {
      const role = backupAdmins.includes(account) ? "ADMIN" : "MEMBER";
      const invite = await app.inject({
        method: "POST",
        url: `/circles/${circle.id}/members/invite`,
        headers: organizer.headers,
        payload: {
          userId: organizer.user.id,
          name: account.user.name,
          email: account.user.email,
          role,
        },
      });
      assert.equal(invite.statusCode, 201);

      const accept = await app.inject({
        method: "POST",
        url: `/invitations/${invite.json().id}/accept`,
        headers: account.headers,
        payload: { userId: account.user.id },
      });
      assert.equal(accept.statusCode, 201);
      assert.equal(accept.json().role, role);
      acceptedMembers.push({ account, member: accept.json(), role });
    }

    const caregiverMembers = acceptedMembers.filter((item) => item.role === "MEMBER");
    for (const { member } of caregiverMembers) {
      const grant = await app.inject({
        method: "PUT",
        url: `/circles/${circle.id}/members/${member.id}/recipient-access/${recipientId}`,
        headers: organizer.headers,
        payload: { userId: organizer.user.id },
      });
      assert.equal(grant.statusCode, 200);
    }

    const createdTasks = [];
    const dueAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    for (const { account } of caregiverMembers) {
      const task = await app.inject({
        method: "POST",
        url: `/circles/${circle.id}/tasks`,
        headers: organizer.headers,
        payload: {
          creatorId: organizer.user.id,
          title: `Daily check for ${account.user.name}`,
          recipientId,
          assigneeId: account.user.id,
          dueAt,
          recurrence: { frequency: "DAILY" },
        },
      });
      assert.equal(task.statusCode, 201);
      assert.equal(task.json().assigneeId, account.user.id);
      assert.equal(task.json().recurrenceFrequency, "DAILY");
      createdTasks.push(task.json());
    }

    assert.equal(createdTasks.length, 44);

    const assignedCaregiver = caregiverMembers[0].account;
    const snooze = await app.inject({
      method: "POST",
      url: `/circles/${circle.id}/tasks/${createdTasks[0].id}/reminder/snooze`,
      headers: assignedCaregiver.headers,
      payload: { minutes: 60 },
    });
    assert.equal(snooze.statusCode, 200);
    assert.equal(snooze.json().status, "SNOOZED");

    const receiverTask = await app.inject({
      method: "POST",
      url: `/circles/${circle.id}/tasks`,
      headers: organizer.headers,
      payload: {
        creatorId: organizer.user.id,
        title: "Receiver confirms morning routine",
        recipientId,
        assigneeId: receiver.user.id,
        dueAt,
      },
    });
    assert.equal(receiverTask.statusCode, 201);

    const completeAsReceiver = await app.inject({
      method: "PATCH",
      url: `/circles/${circle.id}/tasks/${receiverTask.json().id}`,
      headers: receiver.headers,
      payload: { userId: receiver.user.id, status: "DONE" },
    });
    assert.equal(completeAsReceiver.statusCode, 200);
    assert.equal(completeAsReceiver.json().status, "DONE");

    const caregiverCreatedTask = await app.inject({
      method: "POST",
      url: `/circles/${circle.id}/tasks`,
      headers: assignedCaregiver.headers,
      payload: {
        creatorId: assignedCaregiver.user.id,
        title: "Caregiver-created errand",
        recipientId,
        assigneeId: assignedCaregiver.user.id,
        dueAt,
      },
    });
    assert.equal(caregiverCreatedTask.statusCode, 201);

    const deleteTask = await app.inject({
      method: "DELETE",
      url: `/circles/${circle.id}/tasks/${caregiverCreatedTask.json().id}`,
      headers: assignedCaregiver.headers,
      payload: { userId: assignedCaregiver.user.id },
    });
    assert.equal(deleteTask.statusCode, 204);

    const caregiverView = await app.inject({
      method: "GET",
      url: `/circles/${circle.id}/tasks`,
      headers: assignedCaregiver.headers,
    });
    assert.equal(caregiverView.statusCode, 200);
    assert.ok(caregiverView.json().some((task) => task.id === createdTasks[0].id));
    assert.ok(!caregiverView.json().some((task) => task.id === caregiverCreatedTask.json().id));

    const deleteCircle = await app.inject({
      method: "DELETE",
      url: `/circles/${circle.id}`,
      headers: organizer.headers,
      payload: { userId: organizer.user.id },
    });
    assert.equal(deleteCircle.statusCode, 204);
    assert.equal(app.db._s.circles.length, 0);
    assert.equal(app.db._s.members.length, 0);
    assert.equal(app.db._s.tasks.length, 0);

    await app.close();
  });

  test("isolates one account across multiple circles with different roles", async () => {
    const app = await buildApp(buildDb());
    const password = "password123";
    const signups = {};
    const headersFor = (auth) => ({
      authorization: `Bearer ${auth.accessToken}`,
      "content-type": "application/json",
    });

    for (const [key, name] of [
      ["shared", "Shared Multi Role"],
      ["circleAOwner", "Circle A Organizer"],
      ["circleCOwner", "Circle C Organizer"],
      ["peerCaregiver", "Peer Caregiver"],
    ]) {
      const signup = await app.inject({
        method: "POST",
        url: "/auth/signup",
        payload: {
          email: `${key}@careloop.test`,
          name,
          password,
        },
      });
      assert.equal(signup.statusCode, 201);
      const auth = signup.json();
      signups[key] = { ...auth, headers: headersFor(auth) };
    }

    const createCircle = async ({ owner, name, recipientName }) => {
      const response = await app.inject({
        method: "POST",
        url: "/circles",
        headers: owner.headers,
        payload: {
          creatorId: owner.user.id,
          name,
          recipientName,
        },
      });
      assert.equal(response.statusCode, 201);
      return response.json();
    };

    const inviteAndAccept = async ({ inviter, circleId, invitee, role, recipientId }) => {
      const invite = await app.inject({
        method: "POST",
        url: `/circles/${circleId}/members/invite`,
        headers: inviter.headers,
        payload: {
          userId: inviter.user.id,
          name: invitee.user.name,
          email: invitee.user.email,
          role,
          ...(recipientId ? { recipientId } : {}),
        },
      });
      assert.equal(invite.statusCode, 201);

      const accept = await app.inject({
        method: "POST",
        url: `/invitations/${invite.json().id}/accept`,
        headers: invitee.headers,
        payload: { userId: invitee.user.id },
      });
      assert.equal(accept.statusCode, 201);
      assert.equal(accept.json().role, role);
      return accept.json();
    };

    const createTask = async ({ actor, circleId, recipientId, title, assigneeId }) => {
      const response = await app.inject({
        method: "POST",
        url: `/circles/${circleId}/tasks`,
        headers: actor.headers,
        payload: {
          creatorId: actor.user.id,
          title,
          recipientId,
          assigneeId,
          dueAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
        },
      });
      assert.equal(response.statusCode, 201);
      return response.json();
    };

    const shared = signups.shared;
    const circleAOwner = signups.circleAOwner;
    const circleCOwner = signups.circleCOwner;
    const peerCaregiver = signups.peerCaregiver;

    const circleA = await createCircle({
      owner: circleAOwner,
      name: "Circle A Receiver Role",
      recipientName: "Shared Receiver",
    });
    const recipientAId = circleA.recipients[0].id;
    await inviteAndAccept({
      inviter: circleAOwner,
      circleId: circleA.id,
      invitee: shared,
      role: "RECIPIENT",
      recipientId: recipientAId,
    });

    const circleB = await createCircle({
      owner: shared,
      name: "Circle B Admin Role",
      recipientName: "Receiver B",
    });
    const recipientBId = circleB.recipients[0].id;
    const activateB = await app.inject({
      method: "POST",
      url: `/circles/${circleB.id}/recipients/${recipientBId}/proxy-activate`,
      headers: shared.headers,
      payload: { userId: shared.user.id, authorizationAttested: true, consentDocumentReference: "test-proxy-b" },
    });
    assert.equal(activateB.statusCode, 200);

    const circleC = await createCircle({
      owner: circleCOwner,
      name: "Circle C Caregiver Role",
      recipientName: "Receiver C",
    });
    const recipientCId = circleC.recipients[0].id;
    const activateC = await app.inject({
      method: "POST",
      url: `/circles/${circleC.id}/recipients/${recipientCId}/proxy-activate`,
      headers: circleCOwner.headers,
      payload: { userId: circleCOwner.user.id, authorizationAttested: true, consentDocumentReference: "test-proxy-c" },
    });
    assert.equal(activateC.statusCode, 200);
    const sharedMemberC = await inviteAndAccept({
      inviter: circleCOwner,
      circleId: circleC.id,
      invitee: shared,
      role: "MEMBER",
    });
    const peerMemberC = await inviteAndAccept({
      inviter: circleCOwner,
      circleId: circleC.id,
      invitee: peerCaregiver,
      role: "MEMBER",
    });
    assert.ok(peerMemberC.id, "peer caregiver joins circle C without receiver access");
    const grantSharedAccess = await app.inject({
      method: "PUT",
      url: `/circles/${circleC.id}/members/${sharedMemberC.id}/recipient-access/${recipientCId}`,
      headers: circleCOwner.headers,
      payload: { userId: circleCOwner.user.id },
    });
    assert.equal(grantSharedAccess.statusCode, 200);

    const taskA = await createTask({
      actor: circleAOwner,
      circleId: circleA.id,
      recipientId: recipientAId,
      title: "Circle A receiver-only check-in",
      assigneeId: shared.user.id,
    });
    const taskB = await createTask({
      actor: shared,
      circleId: circleB.id,
      recipientId: recipientBId,
      title: "Circle B admin-owned task",
      assigneeId: shared.user.id,
    });
    const taskCVisible = await createTask({
      actor: circleCOwner,
      circleId: circleC.id,
      recipientId: recipientCId,
      title: "Circle C assigned caregiver task",
      assigneeId: shared.user.id,
    });
    const taskCHidden = await createTask({
      actor: circleCOwner,
      circleId: circleC.id,
      recipientId: recipientCId,
      title: "Circle C peer caregiver task",
      assigneeId: peerCaregiver.user.id,
    });

    const sharedContext = await app.inject({
      method: "GET",
      url: "/users/me",
      headers: shared.headers,
    });
    assert.equal(sharedContext.statusCode, 200);
    const roleByCircleId = new Map(
      sharedContext.json().memberships.map((membership) => [membership.circleId, membership.role]),
    );
    assert.equal(roleByCircleId.get(circleA.id), "RECIPIENT");
    assert.equal(roleByCircleId.get(circleB.id), "ADMIN");
    assert.equal(roleByCircleId.get(circleC.id), "MEMBER");

    const sharedCircleATasks = await app.inject({
      method: "GET",
      url: `/circles/${circleA.id}/tasks`,
      headers: shared.headers,
    });
    assert.equal(sharedCircleATasks.statusCode, 200);
    assert.deepEqual(sharedCircleATasks.json().map((task) => task.id), [taskA.id]);
    assert.equal(sharedCircleATasks.json()[0].capabilities.canMarkDone, true);
    assert.equal(sharedCircleATasks.json()[0].capabilities.canEdit, false);

    const blockedReceiverCreate = await app.inject({
      method: "POST",
      url: `/circles/${circleA.id}/tasks`,
      headers: shared.headers,
      payload: {
        creatorId: shared.user.id,
        title: "Receiver should not create",
        recipientId: recipientAId,
        assigneeId: shared.user.id,
      },
    });
    assert.equal(blockedReceiverCreate.statusCode, 403);

    const sharedCircleBTasks = await app.inject({
      method: "GET",
      url: `/circles/${circleB.id}/tasks`,
      headers: shared.headers,
    });
    assert.equal(sharedCircleBTasks.statusCode, 200);
    assert.deepEqual(sharedCircleBTasks.json().map((task) => task.id), [taskB.id]);
    assert.equal(sharedCircleBTasks.json()[0].capabilities.canEdit, true);
    assert.equal(sharedCircleBTasks.json()[0].capabilities.canAssign, true);

    const sharedCircleCTasks = await app.inject({
      method: "GET",
      url: `/circles/${circleC.id}/tasks`,
      headers: shared.headers,
    });
    assert.equal(sharedCircleCTasks.statusCode, 200);
    assert.deepEqual(sharedCircleCTasks.json().map((task) => task.id), [taskCVisible.id]);
    assert.ok(!sharedCircleCTasks.json().some((task) => task.id === taskCHidden.id));
    assert.equal(sharedCircleCTasks.json()[0].capabilities.canMarkDone, true);
    assert.equal(sharedCircleCTasks.json()[0].capabilities.canEdit, false);

    const completeCircleA = await app.inject({
      method: "PATCH",
      url: `/circles/${circleA.id}/tasks/${taskA.id}`,
      headers: shared.headers,
      payload: { userId: shared.user.id, status: "DONE" },
    });
    assert.equal(completeCircleA.statusCode, 200);
    assert.equal(completeCircleA.json().status, "DONE");

    const crossCircleTaskFetch = await app.inject({
      method: "GET",
      url: `/circles/${circleB.id}/tasks/${taskA.id}/comments`,
      headers: shared.headers,
    });
    assert.equal(crossCircleTaskFetch.statusCode, 404);

    await app.close();
  });

  test("PATCH /circles/:id/members/:memberId/role lets an admin promote a caregiver", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", email: "admin@test.com", name: "Admin" },
        { id: "u2", email: "member@test.com", name: "Member" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u2", circleId: "c1", role: "MEMBER" },
      ],
    }));

    const res = await app.inject({
      method: "PATCH",
      url: "/circles/c1/members/m2/role",
      headers: HDR,
      payload: { userId: "u1", role: "ADMIN" },
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.json().role, "ADMIN");
    await app.close();
  });

  test("DELETE /circles/:id/members/:memberId lets an admin remove another member", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", email: "admin@test.com", name: "Admin" },
        { id: "u2", email: "member@test.com", name: "Member" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Bob", archiveAfterDays: 7 }],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u2", circleId: "c1", role: "MEMBER" },
      ],
    }));

    const res = await app.inject({
      method: "DELETE",
      url: "/circles/c1/members/m2",
      headers: HDR,
      payload: { userId: "u1" },
    });

    assert.equal(res.statusCode, 204);
    await app.close();
  });

  test("POST /circles/:id/recipients blocks a second free care receiver without upgrade intent", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/recipients",
      headers: HDR,
      payload: { userId: "u1", name: "Jane Doe", relationship: "Spouse" },
    });

    assert.equal(res.statusCode, 402);
    assert.equal(res.json().code, "CARE_RECEIVER_LIMIT_REQUIRES_PREMIUM");
    await app.close();
  });

  test("POST /circles/:id/recipients rejects add-receiver intent without an active premium receiver", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/recipients",
      headers: HDR,
      payload: { userId: "u1", name: "Jane Doe", relationship: "Spouse", premiumIntent: "ADD_RECEIVER" },
    });

    assert.equal(res.statusCode, 402);
    assert.equal(res.json().code, "CARE_RECEIVER_LIMIT_REQUIRES_PREMIUM");
    await app.close();
  });

  test("POST /circles/:id/recipients lets an admin add another care recipient after active premium", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      recipientEntitlements: [{
        id: "cre1",
        recipientId: "cr1",
        status: "ACTIVE",
        source: "APP_STORE",
        startsAt: new Date("2026-04-01T00:00:00.000Z"),
        expiresAt: new Date("2026-07-01T00:00:00.000Z"),
        appleOriginalTransactionId: "otx-add-receiver",
        appleProductId: "com.careloop.ios.premium.monthly",
        purchasedById: "u1",
        createdAt: new Date("2026-04-01T00:00:00.000Z"),
        updatedAt: new Date("2026-04-01T00:00:00.000Z"),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/recipients",
      headers: HDR,
      payload: { userId: "u1", name: "Jane Doe", relationship: "Spouse", premiumIntent: "ADD_RECEIVER" },
    });

    assert.equal(res.statusCode, 201);
    const body = res.json();
    assert.equal(body.name, "Jane Doe");
    assert.equal(body.relationship, "Spouse");
    await app.close();
  });

  test("PATCH /circles/:id/recipients updates receiver details and primary circle summary", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
      recipients: [
        { id: "r1", circleId: "c1", name: "John Doe", relationship: "Dad", notes: null, isPrimary: true, sortOrder: 0 },
        { id: "r2", circleId: "c1", name: "Jane Doe", relationship: "Mom", notes: "Original", isPrimary: false, sortOrder: 1 },
      ],
    }));

    const res = await app.inject({
      method: "PATCH",
      url: "/circles/c1/recipients/r2",
      headers: HDR,
      payload: {
        userId: "u1",
        name: " Jane Ramgiri ",
        relationship: " Mother ",
        notes: " Updated notes ",
        isPrimary: true,
      },
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.json().name, "Jane Ramgiri");
    assert.equal(res.json().relationship, "Mother");
    assert.equal(res.json().notes, "Updated notes");
    assert.equal(res.json().isPrimary, true);
    assert.equal(app.db._s.recipients.find((recipient) => recipient.id === "r1").isPrimary, false);
    assert.equal(app.db._s.circles[0].recipientName, "Jane Ramgiri");
    await app.close();
  });

  test("POST /circles/:id/recipients/:recipientId/premium-requests lets a scoped caregiver ask once", async () => {
    const caregiverHeaders = await authHeaders({ id: "u2", email: "caregiver@test.com", name: "Caregiver" });
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", email: "admin@test.com", name: "Admin" },
        { id: "u2", email: "caregiver@test.com", name: "Caregiver" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      recipients: [
        { id: "r1", circleId: "c1", name: "John Doe", relationship: "Dad", notes: null, isPrimary: true, sortOrder: 0 },
      ],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u2", circleId: "c1", role: "MEMBER" },
      ],
      recipientAccesses: [{ id: "ra1", recipientId: "r1", memberId: "m2", revokedAt: null, grantedAt: new Date() }],
    }));

    const first = await app.inject({
      method: "POST",
      url: "/circles/c1/recipients/r1/premium-requests",
      headers: caregiverHeaders,
      payload: {},
    });
    assert.equal(first.statusCode, 201);
    assert.equal(first.json().recipientId, "r1");
    assert.equal(first.json().requesterUserId, "u2");

    const duplicate = await app.inject({
      method: "POST",
      url: "/circles/c1/recipients/r1/premium-requests",
      headers: caregiverHeaders,
      payload: {},
    });
    assert.equal(duplicate.statusCode, 409);
    assert.equal(duplicate.json().code, "PREMIUM_REQUEST_ALREADY_SENT");
    await app.close();
  });

  test("GET /circles/:id/premium-requests collapses visible recent requests by receiver", async () => {
    const now = new Date();
    const expired = new Date(now.getTime() - 8 * 24 * 60 * 60 * 1000);
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", email: "admin@test.com", name: "Admin" },
        { id: "u2", email: "caregiver@test.com", name: "Caregiver" },
        { id: "u3", email: "backup@test.com", name: "Backup" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      recipients: [
        { id: "r1", circleId: "c1", name: "John Doe", relationship: "Dad", notes: null, isPrimary: true, sortOrder: 0 },
      ],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u2", circleId: "c1", role: "MEMBER" },
        { id: "m3", userId: "u3", circleId: "c1", role: "MEMBER" },
      ],
      premiumUpgradeRequests: [
        { id: "pur1", circleId: "c1", recipientId: "r1", requesterUserId: "u2", createdAt: now, updatedAt: now },
        { id: "pur2", circleId: "c1", recipientId: "r1", requesterUserId: "u3", createdAt: new Date(now.getTime() - 60_000), updatedAt: now },
        { id: "pur3", circleId: "c1", recipientId: "r1", requesterUserId: "u4", createdAt: expired, updatedAt: expired },
      ],
    }));

    const res = await app.inject({
      method: "GET",
      url: "/circles/c1/premium-requests",
      headers: HDR,
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.json().length, 1);
    assert.equal(res.json()[0].recipientId, "r1");
    assert.equal(res.json()[0].requestCount, 2);
    assert.equal(res.json()[0].latestRequesterName, "Caregiver");
    await app.close();
  });

  test("POST /circles/:id/recipients/reorder updates recipient order and primary recipient", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
      recipients: [
        { id: "r1", circleId: "c1", name: "John Doe", relationship: "Dad", notes: null, isPrimary: true, sortOrder: 0 },
        { id: "r2", circleId: "c1", name: "Jane Doe", relationship: "Mom", notes: null, isPrimary: false, sortOrder: 1 },
        { id: "r3", circleId: "c1", name: "Mia Doe", relationship: "Grandma", notes: null, isPrimary: false, sortOrder: 2 },
      ],
    }));

    const res = await app.inject({
      method: "POST",
      url: "/circles/c1/recipients/reorder",
      headers: HDR,
      payload: {
        userId: "u1",
        recipientIds: ["r3", "r1", "r2"],
        primaryRecipientId: "r3",
      },
    });

    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.deepEqual(body.map((recipient) => recipient.id), ["r3", "r1", "r2"]);
    assert.equal(body[0].isPrimary, true);
    assert.equal(app.db._s.circles[0].recipientName, "Mia Doe");
    await app.close();
  });

  test("DELETE /circles/:id/recipients blocks removing the last care recipient", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    }));

    const recipientId = app.db._s.recipients[0].id;
    const res = await app.inject({
      method: "DELETE",
      url: `/circles/c1/recipients/${recipientId}`,
      headers: HDR,
      payload: { userId: "u1" },
    });

    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "Every circle must keep at least one care recipient.");
    await app.close();
  });

  test("DELETE /circles/:id/recipients blocks removal while active tasks exist", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
      recipients: [
        { id: "r1", circleId: "c1", name: "John Doe", relationship: "Dad", notes: null, isPrimary: true, sortOrder: 0 },
        { id: "r2", circleId: "c1", name: "Jane Doe", relationship: "Mom", notes: null, isPrimary: false, sortOrder: 1 },
      ],
      tasks: [{
        id: "t1",
        circleId: "c1",
        recipientId: "r2",
        title: "Open task",
        status: "PENDING",
        priority: "NORMAL",
        creatorId: "u1",
        assigneeId: "u1",
        dueAt: null,
        completedAt: null,
        completedById: null,
        archivedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
        recurrenceFrequency: "NONE",
        recurrenceInterval: null,
        recurrenceWeekdays: [],
        recurrenceEndsAt: null,
        seriesId: null,
      }],
    }));

    const res = await app.inject({
      method: "DELETE",
      url: "/circles/c1/recipients/r2",
      headers: HDR,
      payload: { userId: "u1" },
    });

    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "Move or archive this recipient's tasks before removing them.");
    assert.equal(app.db._s.recipients.length, 2);
    await app.close();
  });

  test("DELETE /circles/:id/recipients removes an unused receiver and promotes a replacement primary", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", email: "admin@test.com", name: "Admin" }],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
      recipients: [
        { id: "r1", circleId: "c1", name: "John Doe", relationship: "Dad", notes: null, isPrimary: true, sortOrder: 0 },
        { id: "r2", circleId: "c1", name: "Jane Doe", relationship: "Mom", notes: null, isPrimary: false, sortOrder: 1 },
      ],
    }));

    const res = await app.inject({
      method: "DELETE",
      url: "/circles/c1/recipients/r1",
      headers: HDR,
      payload: { userId: "u1" },
    });

    assert.equal(res.statusCode, 204);
    assert.deepEqual(app.db._s.recipients.map((recipient) => recipient.id), ["r2"]);
    assert.equal(app.db._s.recipients[0].isPrimary, true);
    assert.equal(app.db._s.circles[0].recipientName, "Jane Doe");
    await app.close();
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// push.js — sendReminderNotifications
// ═══════════════════════════════════════════════════════════════════════════════

describe("sendReminderNotifications", () => {
  const task = { id: "t1", title: "Meds", circleId: "c1", recipientId: "cr1", circle: { id: "c1", name: "Circle" } };

  test("delivers to all user IDs and returns one result per user", async () => {
    const db = buildDb({
      users: [
        { id: "u1", name: "Alice", email: "a@t.com", pushToken: null },
        { id: "u2", name: "Bob",   email: "b@t.com", pushToken: null },
      ],
    });
    const results = await sendReminderNotifications({ db, task, type: "reminder", userIds: ["u1", "u2"] });
    assert.equal(results.length, 2);
    assert.ok(results.every((r) => r.simulated === true), "all simulated (no RESEND key)");
  });

  test("handles empty userIds array", async () => {
    const db = buildDb();
    const results = await sendReminderNotifications({ db, task, type: "reminder", userIds: [] });
    assert.equal(results.length, 0);
  });

  test("returns NONE for users with no contact info", async () => {
    const db = buildDb({ users: [{ id: "u1", name: "Ghost", email: null, pushToken: null }] });
    const results = await sendReminderNotifications({ db, task, type: "reminder", userIds: ["u1"] });
    assert.equal(results[0].channel, "NONE");
    assert.equal(results[0].delivered, false);
  });

  test("push reminder payload includes task, circle, and care receiver ids for deep links", async () => {
    const db = buildDb({ users: [{ id: "u1", name: "Alice", email: "a@t.com", pushToken: "device-token" }] });
    const results = await sendReminderNotifications({ db, task, type: "reminder", userIds: ["u1"] });
    assert.equal(results[0].channel, "PUSH");
    assert.equal(results[0].simulated, true);
    assert.equal(results[0].payload.taskId, "t1");
    assert.equal(results[0].payload.circleId, "c1");
    assert.equal(results[0].payload.recipientId, "cr1");
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// push.js — sendDailyDigest
// ═══════════════════════════════════════════════════════════════════════════════

describe("sendDailyDigest", () => {
  test("returns NONE when user has no email", async () => {
    const r = await sendDailyDigest({
      user: { id: "u1", name: "Alice", email: null },
      digestDate: "2026-04-26",
      dueToday: [], overdue: [], completedToday: [],
    });
    assert.equal(r.delivered, false);
    assert.equal(r.channel, "NONE");
    assert.equal(r.reason, "user_has_no_email");
  });

  test("simulates send when RESEND not configured", async () => {
    const r = await sendDailyDigest({
      user: { id: "u1", name: "Alice", email: "alice@test.com" },
      digestDate: "2026-04-26",
      dueToday: [], overdue: [], completedToday: [],
    });
    assert.equal(r.delivered, true);
    assert.equal(r.simulated, true);
    assert.equal(r.channel, "EMAIL");
  });

  test("returns NONE when daily digest is disabled by the user", async () => {
    const r = await sendDailyDigest({
      user: { id: "u1", name: "Alice", email: "alice@test.com", notifDigest: false },
      digestDate: "2026-04-26",
      dueToday: [], overdue: [], completedToday: [],
    });
    assert.equal(r.delivered, false);
    assert.equal(r.channel, "NONE");
    assert.equal(r.reason, "notifications_disabled_by_user");
  });

  test("digest is idempotent — same function call returns simulated regardless of content", async () => {
    const user = { id: "u1", name: "Alice", email: "alice@test.com" };
    const [r1, r2] = await Promise.all([
      sendDailyDigest({ user, digestDate: "2026-04-26", dueToday: [{ title: "Task A" }], overdue: [], completedToday: [] }),
      sendDailyDigest({ user, digestDate: "2026-04-26", dueToday: [{ title: "Task A" }], overdue: [], completedToday: [] }),
    ]);
    // Idempotency is enforced at the scheduler layer (DigestLog check), not push.js itself
    assert.equal(r1.delivered, true);
    assert.equal(r2.delivered, true);
  });

  test("includes task data in digest HTML (no crash with real task objects)", async () => {
    const r = await sendDailyDigest({
      user: { id: "u1", name: "Alice", email: "alice@test.com" },
      digestDate: "2026-04-26",
      dueToday:       [{ title: "Give meds"        }],
      overdue:        [{ title: "Doctor appt"       }],
      completedToday: [{ title: "Morning walk done" }],
    });
    assert.equal(r.delivered, true);
    assert.equal(r.simulated, true);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Route — PATCH /users/:id/push-token
// ═══════════════════════════════════════════════════════════════════════════════

describe("PATCH /users/:id/push-token", () => {
  let app, db;

  before(async () => {
    db = buildDb({ users: [{ id: "u1", name: "Alice", email: "a@t.com", pushToken: null }] });
    app = await buildApp(db);
  });

  after(() => app.close());

  test("returns 200 with updated user including pushToken", async () => {
    const res = await app.inject({
      method: "PATCH", url: "/users/u1/push-token",
      headers: HDR, body: JSON.stringify({ pushToken: "device-abc-123" }),
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.pushToken, "device-abc-123");
  });

  test("persists push token in DB", async () => {
    await app.inject({
      method: "PATCH", url: "/users/u1/push-token",
      headers: HDR, body: JSON.stringify({ pushToken: "stored-token" }),
    });
    const user = db._s.users.find((u) => u.id === "u1");
    assert.equal(user.pushToken, "stored-token");
  });

  test("returns 400 when pushToken is absent from body", async () => {
    const res = await app.inject({
      method: "PATCH", url: "/users/u1/push-token",
      headers: HDR, body: JSON.stringify({}),
    });
    assert.equal(res.statusCode, 400);
    assert.equal(JSON.parse(res.payload).error, "pushToken required");
  });

  test("returns 401 when authorization header is missing", async () => {
    const res = await app.inject({
      method: "PATCH", url: "/users/u1/push-token",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ pushToken: "tok" }),
    });
    assert.equal(res.statusCode, 401);
  });

  test("returns 401 when bearer token is invalid", async () => {
    const res = await app.inject({
      method: "PATCH", url: "/users/u1/push-token",
      headers: { authorization: "Bearer wrong-token", "content-type": "application/json" },
      body: JSON.stringify({ pushToken: "tok" }),
    });
    assert.equal(res.statusCode, 401);
  });
});

describe("PATCH /users/:id/notification-preferences", () => {
  test("persists notification preferences for the authenticated user", async () => {
    const db = buildDb({
      users: [{
        id: "u1",
        name: "Alice",
        email: "a@t.com",
        notifAssignments: true,
        notifEscalations: true,
        notifDigest: true,
      }],
    });
    const app = await buildApp(db);

    const res = await app.inject({
      method: "PATCH",
      url: "/users/u1/notification-preferences",
      headers: HDR,
      body: JSON.stringify({
        notifAssignments: false,
        notifEscalations: false,
        notifDigest: false,
      }),
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.json().notifAssignments, false);
    assert.equal(res.json().notifEscalations, false);
    assert.equal(res.json().notifDigest, false);
    assert.equal(db._s.users.find((user) => user.id === "u1").notifDigest, false);
    await app.close();
  });

  test("rejects empty preference updates and cross-user mutations", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", name: "Alice", email: "a@t.com" },
        { id: "u2", name: "Bob", email: "b@t.com" },
      ],
    }));

    const empty = await app.inject({
      method: "PATCH",
      url: "/users/u1/notification-preferences",
      headers: HDR,
      body: JSON.stringify({}),
    });
    assert.equal(empty.statusCode, 400);

    const crossUser = await app.inject({
      method: "PATCH",
      url: "/users/u2/notification-preferences",
      headers: HDR,
      body: JSON.stringify({ notifDigest: false }),
    });
    assert.equal(crossUser.statusCode, 403);
    await app.close();
  });
});

describe("auth hardening and protected reads", () => {
  test("GET /users/me returns the authenticated user context", async () => {
    const app = await buildApp(buildDb({
      users: [{ id: "u1", name: "Alice", email: "alice@test.com", pushToken: null }],
    }));

    const res = await app.inject({
      method: "GET",
      url: "/users/me",
      headers: await authHeaders({ id: "u1", email: "alice@test.com", name: "Alice" }),
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.json().id, "u1");
    await app.close();
  });

  test("prevents cross-user profile and push-token mutation", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", name: "Alice", email: "alice@test.com", pushToken: null },
        { id: "u2", name: "Bob", email: "bob@test.com", pushToken: null },
      ],
    }));

    const userOneHeaders = await authHeaders({ id: "u1", email: "alice@test.com", name: "Alice" });

    const profile = await app.inject({
      method: "GET",
      url: "/users/u2",
      headers: userOneHeaders,
    });
    assert.equal(profile.statusCode, 403);

    const pushToken = await app.inject({
      method: "PATCH",
      url: "/users/u2/push-token",
      headers: userOneHeaders,
      payload: { pushToken: "forbidden" },
    });
    assert.equal(pushToken.statusCode, 403);
    await app.close();
  });

  test("prevents APP_SESSION writes into a foreign circle", async () => {
    const app = await buildApp(buildDb({
      users: [
        { id: "u1", name: "Alice", email: "alice@test.com", pushToken: null },
      ],
      circles: [
        { id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 },
        { id: "c2", name: "Beta", recipientName: "Jane Doe", archiveAfterDays: 7 },
      ],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
      ],
    }));

    const userHeaders = await authHeaders({ id: "u1", email: "alice@test.com", name: "Alice" });
    const res = await app.inject({
      method: "POST",
      url: "/users/u1/session",
      headers: userHeaders,
      payload: { circleId: "c2" },
    });

    assert.equal(res.statusCode, 403);
    assert.equal(app.db._s.events.length, 0);
    await app.close();
  });

  test("prevents non-members from reading circle data and returns empty insights for caregivers without receiver access", async () => {
    const db = buildDb({
      users: [
        { id: "u1", name: "Admin", email: "admin@test.com" },
        { id: "u2", name: "Member", email: "member@test.com" },
        { id: "u3", name: "Outsider", email: "outsider@test.com" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u2", circleId: "c1", role: "MEMBER" },
      ],
      tasks: [{
        id: "t1",
        title: "Give meds",
        status: "PENDING",
        priority: "NORMAL",
        circleId: "c1",
        creatorId: "u1",
        assigneeId: "u2",
        completedById: null,
        completedAt: null,
        dueAt: null,
        archivedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
        recurrenceFrequency: "NONE",
        recurrenceInterval: null,
        recurrenceWeekdays: [],
        recurrenceEndsAt: null,
        seriesId: null,
        recipientId: "cr1",
      }],
    });
    const app = await buildApp(db);

    const outsiderHeaders = await authHeaders({ id: "u3", email: "outsider@test.com", name: "Outsider" });
    const memberHeaders = await authHeaders({ id: "u2", email: "member@test.com", name: "Member" });

    const outsiderCircle = await app.inject({
      method: "GET",
      url: "/circles/c1",
      headers: outsiderHeaders,
    });
    assert.equal(outsiderCircle.statusCode, 403);

    const outsiderTasks = await app.inject({
      method: "GET",
      url: "/circles/c1/tasks",
      headers: outsiderHeaders,
    });
    assert.equal(outsiderTasks.statusCode, 403);

    const memberInsights = await app.inject({
      method: "GET",
      url: "/circles/c1/insights/completion?days=7",
      headers: memberHeaders,
    });
    assert.equal(memberInsights.statusCode, 200);
    assert.deepEqual(memberInsights.json(), {
      periodDays: 7,
      selectedRecipientId: null,
      completedByDay: [],
      taskTrendByDay: [],
      topCaregivers: [],
      caregiverLoad: [],
      escalationSummary: {
        totalEscalated: 0,
        averageResponseMinutes: null,
        recent: [],
      },
      recipientBreakdown: [],
      adherence: {
        scheduled: 0,
        completed: 0,
        onTime: 0,
        late: 0,
        missed: 0,
        completionRate: 0,
        onTimeRate: 0,
      },
      totals: {
        completed: 0,
        active: 0,
        overdue: 0,
      },
    });
    await app.close();
  });
});

describe("receiver-scoped access control", () => {
  function scopedAccessSeed() {
    const now = new Date("2026-04-29T12:00:00.000Z");
    return {
      users: [
        { id: "u1", name: "Organizer", email: "organizer@test.com" },
        { id: "u2", name: "Caregiver A", email: "caregiver-a@test.com" },
        { id: "u3", name: "Caregiver B", email: "caregiver-b@test.com" },
        { id: "u4", name: "Receiver One", email: "receiver-1@test.com" },
        { id: "u5", name: "Receiver Two", email: "receiver-2@test.com" },
        { id: "u6", name: "Caregiver No Access", email: "caregiver-none@test.com" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "Receiver One", archiveAfterDays: 7 }],
      recipients: [
        {
          id: "cr1",
          circleId: "c1",
          name: "Receiver One",
          relationship: "Parent",
          notes: null,
          isPrimary: true,
          sortOrder: 0,
          activationStatus: "ACTIVE",
          activatedAt: now,
          receiverUserId: "u4",
          consentAttestedAt: null,
          consentAttestedById: null,
          proxyAuthorizedById: null,
          consentDocumentReference: null,
          createdAt: now,
          updatedAt: now,
        },
        {
          id: "cr2",
          circleId: "c1",
          name: "Receiver Two",
          relationship: "Grandparent",
          notes: null,
          isPrimary: false,
          sortOrder: 1,
          activationStatus: "ACTIVE",
          activatedAt: now,
          receiverUserId: "u5",
          consentAttestedAt: null,
          consentAttestedById: null,
          proxyAuthorizedById: null,
          consentDocumentReference: null,
          createdAt: now,
          updatedAt: now,
        },
      ],
      recipientEntitlements: [
        {
          id: "cre1",
          recipientId: "cr1",
          status: "ACTIVE",
          source: "APP_STORE",
          startsAt: new Date("2026-04-01T00:00:00.000Z"),
          expiresAt: new Date("2026-06-01T00:00:00.000Z"),
          appleOriginalTransactionId: "otx-premium-cr1",
          appleProductId: "com.careloop.ios.premium.yearly",
          purchasedById: "u1",
          createdAt: now,
          updatedAt: now,
        },
      ],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u2", circleId: "c1", role: "MEMBER" },
        { id: "m3", userId: "u3", circleId: "c1", role: "MEMBER" },
        { id: "m4", userId: "u4", circleId: "c1", role: "RECIPIENT" },
        { id: "m5", userId: "u5", circleId: "c1", role: "RECIPIENT" },
        { id: "m6", userId: "u6", circleId: "c1", role: "MEMBER" },
      ],
      recipientAccesses: [
        { id: "cra1", memberId: "m2", recipientId: "cr1", grantedById: "u1", grantedAt: now, revokedAt: null, createdAt: now, updatedAt: now },
      ],
      tasks: [
        {
          id: "t1",
          title: "Caregiver A private task",
          status: "PENDING",
          priority: "NORMAL",
          circleId: "c1",
          creatorId: "u1",
          assigneeId: "u2",
          completedById: null,
          completedAt: null,
          dueAt: new Date("2026-04-30T12:00:00.000Z"),
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
          recurrenceFrequency: "NONE",
          recurrenceInterval: null,
          recurrenceWeekdays: [],
          recurrenceEndsAt: null,
          seriesId: null,
          recipientId: "cr1",
        },
        {
          id: "t2",
          title: "Receiver one self task",
          status: "PENDING",
          priority: "HIGH",
          circleId: "c1",
          creatorId: "u1",
          assigneeId: "u4",
          completedById: null,
          completedAt: null,
          dueAt: new Date("2026-04-30T15:00:00.000Z"),
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
          recurrenceFrequency: "NONE",
          recurrenceInterval: null,
          recurrenceWeekdays: [],
          recurrenceEndsAt: null,
          seriesId: null,
          recipientId: "cr1",
        },
        {
          id: "t3",
          title: "Caregiver B private task",
          status: "PENDING",
          priority: "NORMAL",
          circleId: "c1",
          creatorId: "u1",
          assigneeId: "u3",
          completedById: null,
          completedAt: null,
          dueAt: new Date("2026-04-30T18:00:00.000Z"),
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
          recurrenceFrequency: "NONE",
          recurrenceInterval: null,
          recurrenceWeekdays: [],
          recurrenceEndsAt: null,
          seriesId: null,
          recipientId: "cr1",
        },
        {
          id: "t4",
          title: "Receiver two self task",
          status: "PENDING",
          priority: "NORMAL",
          circleId: "c1",
          creatorId: "u1",
          assigneeId: "u5",
          completedById: null,
          completedAt: null,
          dueAt: new Date("2026-05-01T10:00:00.000Z"),
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
          recurrenceFrequency: "NONE",
          recurrenceInterval: null,
          recurrenceWeekdays: [],
          recurrenceEndsAt: null,
          seriesId: null,
          recipientId: "cr2",
        },
      ],
      events: [
        { id: "e1", type: "TASK_CREATED", circleId: "c1", actorId: "u1", payload: { taskId: "t1", recipientId: "cr1" }, createdAt: new Date("2026-04-30T12:00:00.000Z") },
        { id: "e2", type: "TASK_CREATED", circleId: "c1", actorId: "u1", payload: { taskId: "t3", recipientId: "cr1" }, createdAt: new Date("2026-04-30T13:00:00.000Z") },
        { id: "e3", type: "TASK_CREATED", circleId: "c1", actorId: "u1", payload: { taskId: "t4", recipientId: "cr2" }, createdAt: new Date("2026-04-30T14:00:00.000Z") },
        { id: "e4", type: "APP_SESSION_STARTED", circleId: "c1", actorId: "u2", payload: {}, createdAt: new Date("2026-04-30T15:00:00.000Z") },
      ],
    };
  }

  test("filters circle, recipient, and task reads by caregiver and receiver scope", async () => {
    const app = await buildApp(buildDb(scopedAccessSeed()));
    const caregiverHeaders = await authHeaders({ id: "u2", email: "caregiver-a@test.com", name: "Caregiver A" });
    const receiverHeaders = await authHeaders({ id: "u4", email: "receiver-1@test.com", name: "Receiver One" });
    const noAccessHeaders = await authHeaders({ id: "u6", email: "caregiver-none@test.com", name: "Caregiver No Access" });

    const caregiverCircle = await app.inject({
      method: "GET",
      url: "/circles/c1",
      headers: caregiverHeaders,
    });
    assert.equal(caregiverCircle.statusCode, 200);
    assert.deepEqual(caregiverCircle.json().recipients.map((recipient) => recipient.id), ["cr1"]);
    assert.deepEqual(caregiverCircle.json().tasks.map((task) => task.id), ["t1", "t2"]);

    const caregiverRecipients = await app.inject({
      method: "GET",
      url: "/circles/c1/recipients",
      headers: caregiverHeaders,
    });
    assert.equal(caregiverRecipients.statusCode, 200);
    assert.deepEqual(caregiverRecipients.json().map((recipient) => recipient.id), ["cr1"]);

    const receiverTasks = await app.inject({
      method: "GET",
      url: "/circles/c1/tasks",
      headers: receiverHeaders,
    });
    assert.equal(receiverTasks.statusCode, 200);
    assert.deepEqual(receiverTasks.json().map((task) => task.id), ["t2"]);

    const noAccessCircle = await app.inject({
      method: "GET",
      url: "/circles/c1",
      headers: noAccessHeaders,
    });
    assert.equal(noAccessCircle.statusCode, 200);
    assert.deepEqual(noAccessCircle.json().recipients, []);
    assert.deepEqual(noAccessCircle.json().tasks, []);
    await app.close();
  });

  test("lets organizers grant and revoke caregiver receiver access", async () => {
    const db = buildDb(scopedAccessSeed());
    const app = await buildApp(db);
    const adminHeaders = await authHeaders({ id: "u1", email: "organizer@test.com", name: "Organizer" });
    const noAccessHeaders = await authHeaders({ id: "u6", email: "caregiver-none@test.com", name: "Caregiver No Access" });

    const before = await app.inject({
      method: "GET",
      url: "/circles/c1/members/m6/recipient-access",
      headers: adminHeaders,
    });
    assert.equal(before.statusCode, 200);
    assert.equal(before.json().find((item) => item.recipientId === "cr1").hasAccess, false);

    const grant = await app.inject({
      method: "PUT",
      url: "/circles/c1/members/m6/recipient-access/cr1",
      headers: adminHeaders,
      payload: { userId: "u1" },
    });
    assert.equal(grant.statusCode, 200);

    const afterGrant = await app.inject({
      method: "GET",
      url: "/circles/c1/members/m6/recipient-access",
      headers: adminHeaders,
    });
    assert.equal(afterGrant.json().find((item) => item.recipientId === "cr1").hasAccess, true);

    const circleAfterGrant = await app.inject({
      method: "GET",
      url: "/circles/c1",
      headers: noAccessHeaders,
    });
    assert.equal(circleAfterGrant.statusCode, 200);
    assert.deepEqual(circleAfterGrant.json().recipients.map((recipient) => recipient.id), ["cr1"]);

    const tasksAfterGrant = await app.inject({
      method: "GET",
      url: "/circles/c1/tasks",
      headers: noAccessHeaders,
    });
    assert.equal(tasksAfterGrant.statusCode, 200);
    assert.deepEqual(tasksAfterGrant.json().map((task) => task.id), ["t2"]);

    const revoke = await app.inject({
      method: "DELETE",
      url: "/circles/c1/members/m6/recipient-access/cr1",
      headers: adminHeaders,
      payload: { userId: "u1" },
    });
    assert.equal(revoke.statusCode, 204);

    const circleAfterRevoke = await app.inject({
      method: "GET",
      url: "/circles/c1",
      headers: noAccessHeaders,
    });
    assert.equal(circleAfterRevoke.statusCode, 200);
    assert.deepEqual(circleAfterRevoke.json().recipients, []);
    assert.deepEqual(circleAfterRevoke.json().tasks, []);

    const tasksAfterRevoke = await app.inject({
      method: "GET",
      url: "/circles/c1/tasks",
      headers: noAccessHeaders,
    });
    assert.equal(tasksAfterRevoke.statusCode, 200);
    assert.deepEqual(tasksAfterRevoke.json(), []);
    await app.close();
  });

  test("blocks caregivers from creating tasks outside their granted receiver scope", async () => {
    const app = await buildApp(buildDb(scopedAccessSeed()));
    const caregiverHeaders = await authHeaders({ id: "u2", email: "caregiver-a@test.com", name: "Caregiver A" });

    const denied = await app.inject({
      method: "POST",
      url: "/circles/c1/tasks",
      headers: caregiverHeaders,
      payload: { title: "Unsupported receiver task", creatorId: "u2", recipientId: "cr2", assigneeId: "u2" },
    });
    assert.equal(denied.statusCode, 403);
    assert.equal(denied.json().error, "You do not have access to create tasks for this care receiver");

    const allowed = await app.inject({
      method: "POST",
      url: "/circles/c1/tasks",
      headers: caregiverHeaders,
      payload: { title: "Supported receiver task", creatorId: "u2", recipientId: "cr1", assigneeId: "u2" },
    });
    assert.equal(allowed.statusCode, 201);
    assert.equal(allowed.json().recipientId, "cr1");
    assert.equal(allowed.json().capabilities.canAssign, true);
    assert.equal(allowed.json().capabilities.canMarkDone, true);
    await app.close();
  });

  test("filters activity events to visible task scope", async () => {
    const app = await buildApp(buildDb(scopedAccessSeed()));
    const caregiverHeaders = await authHeaders({ id: "u2", email: "caregiver-a@test.com", name: "Caregiver A" });

    const res = await app.inject({
      method: "GET",
      url: "/circles/c1/events",
      headers: caregiverHeaders,
    });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.json().map((event) => event.id), ["e4", "e1"]);
    await app.close();
  });

  test("high-growth reads support opt-in cursor pagination without changing legacy array responses", async () => {
    const seed = scopedAccessSeed();
    seed.invitations = [
      { id: "i1", circleId: "c1", email: "one@test.com", name: "One", role: "MEMBER", status: "PENDING", acceptedAt: null, expiresAt: null, invitedById: "u1", acceptedById: null, createdAt: new Date("2026-04-30T12:00:00.000Z"), updatedAt: new Date("2026-04-30T12:00:00.000Z") },
      { id: "i2", circleId: "c1", email: "two@test.com", name: "Two", role: "MEMBER", status: "PENDING", acceptedAt: null, expiresAt: null, invitedById: "u1", acceptedById: null, createdAt: new Date("2026-04-30T13:00:00.000Z"), updatedAt: new Date("2026-04-30T13:00:00.000Z") },
      { id: "i3", circleId: "c1", email: "three@test.com", name: "Three", role: "MEMBER", status: "PENDING", acceptedAt: null, expiresAt: null, invitedById: "u1", acceptedById: null, createdAt: new Date("2026-04-30T14:00:00.000Z"), updatedAt: new Date("2026-04-30T14:00:00.000Z") },
    ];
    seed.taskComments = [
      { id: "tc1", taskId: "t1", authorId: "u1", body: "First", createdAt: new Date("2026-04-30T12:00:00.000Z"), updatedAt: new Date("2026-04-30T12:00:00.000Z") },
      { id: "tc2", taskId: "t1", authorId: "u2", body: "Second", createdAt: new Date("2026-04-30T13:00:00.000Z"), updatedAt: new Date("2026-04-30T13:00:00.000Z") },
      { id: "tc3", taskId: "t1", authorId: "u1", body: "Third", createdAt: new Date("2026-04-30T14:00:00.000Z"), updatedAt: new Date("2026-04-30T14:00:00.000Z") },
    ];
    const app = await buildApp(buildDb(seed));
    const organizerHeaders = await authHeaders({ id: "u1", email: "organizer@test.com", name: "Organizer" });
    const caregiverHeaders = await authHeaders({ id: "u2", email: "caregiver-a@test.com", name: "Caregiver A" });

    const legacyTasks = await app.inject({
      method: "GET",
      url: "/circles/c1/tasks",
      headers: caregiverHeaders,
    });
    assert.equal(legacyTasks.statusCode, 200);
    assert.equal(Array.isArray(legacyTasks.json()), true);

    const firstTaskPage = await app.inject({
      method: "GET",
      url: "/circles/c1/tasks?limit=1",
      headers: caregiverHeaders,
    });
    assert.equal(firstTaskPage.statusCode, 200);
    assert.deepEqual(firstTaskPage.json().items.map((task) => task.id), ["t1"]);
    assert.equal(firstTaskPage.json().hasMore, true);
    assert.equal(firstTaskPage.json().nextCursor, "t1");

    const secondTaskPage = await app.inject({
      method: "GET",
      url: `/circles/c1/tasks?limit=1&cursor=${firstTaskPage.json().nextCursor}`,
      headers: caregiverHeaders,
    });
    assert.equal(secondTaskPage.statusCode, 200);
    assert.deepEqual(secondTaskPage.json().items.map((task) => task.id), ["t2"]);

    const commentPage = await app.inject({
      method: "GET",
      url: "/circles/c1/tasks/t1/comments?limit=2",
      headers: organizerHeaders,
    });
    assert.equal(commentPage.statusCode, 200);
    assert.deepEqual(commentPage.json().items.map((comment) => comment.id), ["tc1", "tc2"]);
    assert.equal(commentPage.json().nextCursor, "tc2");

    const invitationPage = await app.inject({
      method: "GET",
      url: "/circles/c1/invitations?status=PENDING&limit=2",
      headers: organizerHeaders,
    });
    assert.equal(invitationPage.statusCode, 200);
    assert.deepEqual(invitationPage.json().items.map((invite) => invite.id), ["i3", "i2"]);
    assert.equal(invitationPage.json().nextCursor, "i2");

    const eventPage = await app.inject({
      method: "GET",
      url: "/circles/c1/events?limit=2",
      headers: organizerHeaders,
    });
    assert.equal(eventPage.statusCode, 200);
    assert.deepEqual(eventPage.json().items.map((event) => event.id), ["e4", "e3"]);
    assert.equal(eventPage.json().nextCursor, "e3");

    await app.close();
  });

  test("returns caregiver progress insights within receiver scope without caregiver attribution", async () => {
    const now = new Date("2026-04-30T18:00:00.000Z");
    const db = buildDb(scopedAccessSeed());
    const app = await buildApp(db);
    const caregiverHeaders = await authHeaders({ id: "u2", email: "caregiver-a@test.com", name: "Caregiver A" });
    const realDateNow = Date.now;
    Date.now = () => now.getTime();

    try {
      const res = await app.inject({
        method: "GET",
        url: "/circles/c1/insights/completion?days=7",
        headers: caregiverHeaders,
      });
      assert.equal(res.statusCode, 200);
      assert.deepEqual(res.json().recipientBreakdown, [{
        recipientId: "cr1",
        name: "Receiver One",
        completed: 0,
        active: 3,
        overdue: 2,
        adherence: {
          scheduled: 3,
          completed: 0,
          onTime: 0,
          late: 0,
          missed: 2,
          completionRate: 0,
          onTimeRate: 0,
        },
      }]);
      assert.deepEqual(res.json().totals, {
        completed: 0,
        active: 3,
        overdue: 2,
      });
      assert.deepEqual(res.json().topCaregivers, []);
      assert.deepEqual(res.json().caregiverLoad, []);
      assert.deepEqual(res.json().escalationSummary, {
        totalEscalated: 0,
        averageResponseMinutes: null,
        recent: [],
      });

      const hiddenRecipient = await app.inject({
        method: "GET",
        url: "/circles/c1/insights/completion?days=7&recipientId=cr2",
        headers: caregiverHeaders,
      });
      assert.equal(hiddenRecipient.statusCode, 404);
    } finally {
      Date.now = realDateNow;
      await app.close();
    }
  });

  test("returns 404 for hidden task mutations and comments outside the visible scope", async () => {
    const app = await buildApp(buildDb(scopedAccessSeed()));
    const caregiverHeaders = await authHeaders({ id: "u2", email: "caregiver-a@test.com", name: "Caregiver A" });
    const receiverHeaders = await authHeaders({ id: "u4", email: "receiver-1@test.com", name: "Receiver One" });

    const hiddenUpdate = await app.inject({
      method: "PATCH",
      url: "/circles/c1/tasks/t3",
      headers: caregiverHeaders,
      payload: { userId: "u2", status: "DONE" },
    });
    assert.equal(hiddenUpdate.statusCode, 404);

    const hiddenComment = await app.inject({
      method: "POST",
      url: "/circles/c1/tasks/t1/comments",
      headers: receiverHeaders,
      payload: { body: "I can’t see this task" },
    });
    assert.equal(hiddenComment.statusCode, 404);
    await app.close();
  });

  test("requires premium receiver scope for insights", async () => {
    const app = await buildApp(buildDb(scopedAccessSeed()));
    const organizerHeaders = await authHeaders({ id: "u1", email: "organizer@test.com", name: "Organizer" });

    const allRecipients = await app.inject({
      method: "GET",
      url: "/circles/c1/insights/completion?days=7",
      headers: organizerHeaders,
    });
    assert.equal(allRecipients.statusCode, 402);
    assert.equal(allRecipients.json().error, "Completion insights are available only for premium care receivers");
    assert.equal(allRecipients.json().recipientId, "cr2");

    const premiumRecipient = await app.inject({
      method: "GET",
      url: "/circles/c1/insights/completion?days=7&recipientId=cr1",
      headers: organizerHeaders,
    });
    assert.equal(premiumRecipient.statusCode, 200);

    const freeRecipient = await app.inject({
      method: "GET",
      url: "/circles/c1/insights/completion?days=7&recipientId=cr2",
      headers: organizerHeaders,
    });
    assert.equal(freeRecipient.statusCode, 402);
    await app.close();
  });

  test("enforces free caregiver access limits until a receiver is upgraded", async () => {
    const db = buildDb(scopedAccessSeed());
    const app = await buildApp(db);
    const adminHeaders = await authHeaders({ id: "u1", email: "organizer@test.com", name: "Organizer" });

    const firstGrant = await app.inject({
      method: "PUT",
      url: "/circles/c1/members/m3/recipient-access/cr2",
      headers: adminHeaders,
      payload: { userId: "u1" },
    });
    assert.equal(firstGrant.statusCode, 200);

    const blockedSecondGrant = await app.inject({
      method: "PUT",
      url: "/circles/c1/members/m6/recipient-access/cr2",
      headers: adminHeaders,
      payload: { userId: "u1" },
    });
    assert.equal(blockedSecondGrant.statusCode, 402);
    assert.equal(blockedSecondGrant.json().error, "Upgrade this care receiver to unlock more caregiver access");

    const entitlement = await app.inject({
      method: "PUT",
      url: "/circles/c1/recipients/cr2/entitlement",
      headers: adminHeaders,
      payload: {
        userId: "u1",
        source: "APP_STORE",
        expiresAt: "2026-06-01T00:00:00.000Z",
        appleOriginalTransactionId: "otx-premium-cr2",
        appleProductId: "com.careloop.ios.premium.monthly",
      },
    });
    assert.equal(entitlement.statusCode, 200);
    assert.equal(entitlement.json().premium.hasPremium, true);
    assert.equal(entitlement.json().premium.appleProductId, "com.careloop.ios.premium.monthly");

    const allowedSecondGrant = await app.inject({
      method: "PUT",
      url: "/circles/c1/members/m6/recipient-access/cr2",
      headers: adminHeaders,
      payload: { userId: "u1" },
    });
    assert.equal(allowedSecondGrant.statusCode, 200);
    await app.close();
  });

  test("validates premium entitlement sync source and App Store transaction identity", async () => {
    const app = await buildApp(buildDb(scopedAccessSeed()));
    const adminHeaders = await authHeaders({ id: "u1", email: "organizer@test.com", name: "Organizer" });

    const missingAppleIdentity = await app.inject({
      method: "PUT",
      url: "/circles/c1/recipients/cr2/entitlement",
      headers: adminHeaders,
      payload: { userId: "u1", source: "APP_STORE" },
    });
    assert.equal(missingAppleIdentity.statusCode, 400);
    assert.equal(
      missingAppleIdentity.json().error,
      "App Store entitlements require appleOriginalTransactionId and appleProductId",
    );

    const unsupportedProduct = await app.inject({
      method: "PUT",
      url: "/circles/c1/recipients/cr2/entitlement",
      headers: adminHeaders,
      payload: {
        userId: "u1",
        source: "APP_STORE",
        appleOriginalTransactionId: "otx-unsupported",
        appleProductId: "com.careloop.ios.premium.family",
      },
    });
    assert.equal(unsupportedProduct.statusCode, 400);
    assert.equal(unsupportedProduct.json().error, "Unsupported App Store premium product");

    const invalidSource = await app.inject({
      method: "PUT",
      url: "/circles/c1/recipients/cr2/entitlement",
      headers: adminHeaders,
      payload: { userId: "u1", source: "STRIPE" },
    });
    assert.equal(invalidSource.statusCode, 400);
    assert.equal(invalidSource.json().error, "source must be APP_STORE or MANUAL");

    const manualEntitlement = await app.inject({
      method: "PUT",
      url: "/circles/c1/recipients/cr2/entitlement",
      headers: adminHeaders,
      payload: { userId: "u1", source: "MANUAL" },
    });
    assert.equal(manualEntitlement.statusCode, 200);
    assert.equal(manualEntitlement.json().premium.source, "MANUAL");
    assert.equal(manualEntitlement.json().premium.hasPremium, true);

    const invalidManualStatus = await app.inject({
      method: "PUT",
      url: "/circles/c1/recipients/cr2/entitlement",
      headers: adminHeaders,
      payload: { userId: "u1", source: "MANUAL", status: "REFUNDED" },
    });
    assert.equal(invalidManualStatus.statusCode, 400);
    assert.equal(invalidManualStatus.json().error, "Manual entitlements can only be synced as ACTIVE");
    await app.close();
  });

  test("fails closed when App Store verification is enabled without server credentials", async () => {
    const previousEnabled = process.env.APP_STORE_SERVER_API_ENABLED;
    const previousIssuer = process.env.APP_STORE_CONNECT_ISSUER_ID;
    const previousKey = process.env.APP_STORE_CONNECT_KEY_ID;
    const previousPrivateKey = process.env.APP_STORE_CONNECT_PRIVATE_KEY;
    const previousBundle = process.env.APP_STORE_BUNDLE_ID;
    process.env.APP_STORE_SERVER_API_ENABLED = "true";
    delete process.env.APP_STORE_CONNECT_ISSUER_ID;
    delete process.env.APP_STORE_CONNECT_KEY_ID;
    delete process.env.APP_STORE_CONNECT_PRIVATE_KEY;
    delete process.env.APP_STORE_BUNDLE_ID;

    try {
      const app = await buildApp(buildDb(scopedAccessSeed()));
      const adminHeaders = await authHeaders({ id: "u1", email: "organizer@test.com", name: "Organizer" });
      const res = await app.inject({
        method: "PUT",
        url: "/circles/c1/recipients/cr2/entitlement",
        headers: adminHeaders,
        payload: {
          userId: "u1",
          source: "APP_STORE",
          appleOriginalTransactionId: "otx-misconfigured",
          appleProductId: "com.careloop.ios.premium.monthly",
        },
      });

      assert.equal(res.statusCode, 500);
      assert.equal(res.json().code, "APP_STORE_SERVER_CONFIG_MISSING");
      await app.close();
    } finally {
      if (previousEnabled === undefined) delete process.env.APP_STORE_SERVER_API_ENABLED;
      else process.env.APP_STORE_SERVER_API_ENABLED = previousEnabled;
      if (previousIssuer === undefined) delete process.env.APP_STORE_CONNECT_ISSUER_ID;
      else process.env.APP_STORE_CONNECT_ISSUER_ID = previousIssuer;
      if (previousKey === undefined) delete process.env.APP_STORE_CONNECT_KEY_ID;
      else process.env.APP_STORE_CONNECT_KEY_ID = previousKey;
      if (previousPrivateKey === undefined) delete process.env.APP_STORE_CONNECT_PRIVATE_KEY;
      else process.env.APP_STORE_CONNECT_PRIVATE_KEY = previousPrivateKey;
      if (previousBundle === undefined) delete process.env.APP_STORE_BUNDLE_ID;
      else process.env.APP_STORE_BUNDLE_ID = previousBundle;
    }
  });

  test("treats billing retry and refunded receiver entitlements as locked but visible", async () => {
    const app = await buildApp(buildDb(scopedAccessSeed()));
    const organizerHeaders = await authHeaders({ id: "u1", email: "organizer@test.com", name: "Organizer" });

    for (const status of ["BILLING_RETRY", "REFUNDED"]) {
      const entitlement = await app.inject({
        method: "PUT",
        url: "/circles/c1/recipients/cr2/entitlement",
        headers: organizerHeaders,
        payload: {
          userId: "u1",
          source: "APP_STORE",
          status,
          expiresAt: "2026-07-01T00:00:00.000Z",
          appleOriginalTransactionId: `otx-${status.toLowerCase()}`,
          appleProductId: "com.careloop.ios.premium.monthly",
        },
      });
      assert.equal(entitlement.statusCode, 200);
      assert.equal(entitlement.json().premium.status, status);
      assert.equal(entitlement.json().premium.hasPremium, false);
      assert.equal(entitlement.json().premium.capabilities.canUseInsights, false);

      const tasks = await app.inject({
        method: "GET",
        url: "/circles/c1/tasks",
        headers: organizerHeaders,
      });
      assert.equal(tasks.statusCode, 200);
      assert.ok(tasks.json().some((task) => task.recipientId === "cr2"));

      const blockedRecurring = await app.inject({
        method: "POST",
        url: "/circles/c1/tasks",
        headers: organizerHeaders,
        payload: {
          title: `${status} plan check-in`,
          creatorId: "u1",
          recipientId: "cr2",
          assigneeId: "u5",
          dueAt: "2026-05-01T18:00:00.000Z",
          recurrence: { frequency: "DAILY" },
        },
      });
      assert.equal(blockedRecurring.statusCode, 402);
      assert.equal(blockedRecurring.json().error, "Recurring schedules require premium for this care receiver");
    }

    await app.close();
  });

  test("blocks recurring tasks for free receivers and allows them for premium receivers", async () => {
    const app = await buildApp(buildDb(scopedAccessSeed()));
    const organizerHeaders = await authHeaders({ id: "u1", email: "organizer@test.com", name: "Organizer" });

    const freeReceiverRecurring = await app.inject({
      method: "POST",
      url: "/circles/c1/tasks",
      headers: organizerHeaders,
      payload: {
        title: "Evening check-in",
        creatorId: "u1",
        recipientId: "cr2",
        assigneeId: "u5",
        dueAt: "2026-05-01T18:00:00.000Z",
        recurrence: { frequency: "DAILY" },
      },
    });
    assert.equal(freeReceiverRecurring.statusCode, 402);
    assert.equal(freeReceiverRecurring.json().error, "Recurring schedules require premium for this care receiver");

    const premiumReceiverRecurring = await app.inject({
      method: "POST",
      url: "/circles/c1/tasks",
      headers: organizerHeaders,
      payload: {
        title: "Morning check-in",
        creatorId: "u1",
        recipientId: "cr1",
        assigneeId: "u4",
        dueAt: "2026-05-01T09:00:00.000Z",
        recurrence: { frequency: "DAILY" },
      },
    });
    assert.equal(premiumReceiverRecurring.statusCode, 201);
    assert.equal(premiumReceiverRecurring.json().recurrenceFrequency, "DAILY");
    await app.close();
  });

  test("keeps existing receiver data visible but blocks premium actions after entitlement expiry", async () => {
    const app = await buildApp(buildDb(scopedAccessSeed()));
    const organizerHeaders = await authHeaders({ id: "u1", email: "organizer@test.com", name: "Organizer" });

    const firstGrant = await app.inject({
      method: "PUT",
      url: "/circles/c1/members/m3/recipient-access/cr2",
      headers: organizerHeaders,
      payload: { userId: "u1" },
    });
    assert.equal(firstGrant.statusCode, 200);

    const expiredEntitlement = await app.inject({
      method: "PUT",
      url: "/circles/c1/recipients/cr2/entitlement",
      headers: organizerHeaders,
      payload: {
        userId: "u1",
        source: "APP_STORE",
        expiresAt: "2026-01-01T00:00:00.000Z",
        appleOriginalTransactionId: "otx-expired-cr2",
        appleProductId: "com.careloop.ios.premium.monthly",
      },
    });
    assert.equal(expiredEntitlement.statusCode, 200);
    assert.equal(expiredEntitlement.json().premium.status, "ACTIVE");
    assert.equal(expiredEntitlement.json().premium.hasPremium, false);
    assert.equal(expiredEntitlement.json().premium.capabilities.canUseInsights, false);

    const visibleTasks = await app.inject({
      method: "GET",
      url: "/circles/c1/tasks",
      headers: organizerHeaders,
    });
    assert.equal(visibleTasks.statusCode, 200);
    assert.ok(visibleTasks.json().some((task) => task.id === "t4" && task.recipientId === "cr2"));

    const blockedRecurring = await app.inject({
      method: "POST",
      url: "/circles/c1/tasks",
      headers: organizerHeaders,
      payload: {
        title: "Expired plan check-in",
        creatorId: "u1",
        recipientId: "cr2",
        assigneeId: "u5",
        dueAt: "2026-05-01T18:00:00.000Z",
        recurrence: { frequency: "DAILY" },
      },
    });
    assert.equal(blockedRecurring.statusCode, 402);
    assert.equal(blockedRecurring.json().error, "Recurring schedules require premium for this care receiver");

    const blockedInsights = await app.inject({
      method: "GET",
      url: "/circles/c1/insights/completion?days=7&recipientId=cr2",
      headers: organizerHeaders,
    });
    assert.equal(blockedInsights.statusCode, 402);
    assert.equal(blockedInsights.json().error, "Completion insights are available only for premium care receivers");

    const blockedSecondGrant = await app.inject({
      method: "PUT",
      url: "/circles/c1/members/m6/recipient-access/cr2",
      headers: organizerHeaders,
      payload: { userId: "u1" },
    });
    assert.equal(blockedSecondGrant.statusCode, 402);
    assert.equal(blockedSecondGrant.json().error, "Upgrade this care receiver to unlock more caregiver access");
    await app.close();
  });

  test("escalation fanout logs a sanitized timeline summary without blocking on disabled alerts", async () => {
    const db = buildDb(scopedAccessSeed());
    db._s.users.find((user) => user.id === "u1").pushToken = "push-admin";
    db._s.users.find((user) => user.id === "u2").pushToken = "push-assignee";
    const extraCaregiver = db._s.users.find((user) => user.id === "u6");
    extraCaregiver.pushToken = "push-support";
    extraCaregiver.notifEscalations = false;
    db._s.recipientAccesses.push({
      id: "cra-escalation-support",
      memberId: "m6",
      recipientId: "cr1",
      grantedById: "u1",
      grantedAt: new Date(),
      revokedAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    db._s.reminders.push({
      id: "rem-escalation-fanout",
      taskId: "t1",
      status: "SENT",
      scheduledAt: new Date(Date.now() - 30 * 60 * 1000),
      sentAt: new Date(Date.now() - 20 * 60 * 1000),
      snoozedUntil: null,
      snoozeCount: 0,
      escalationDueAt: new Date(Date.now() - 1000),
      escalatedAt: null,
    });

    await processEscalations(db);

    const reminder = db._s.reminders.find((item) => item.id === "rem-escalation-fanout");
    assert.equal(reminder.status, "ESCALATED");
    assert.ok(reminder.escalatedAt);

    const event = db._s.events.find((item) => item.type === "REMINDER_ESCALATED" && item.payload.taskId === "t1");
    assert.ok(event, "scheduler logs an escalation timeline event");
    assert.equal(event.payload.recipientId, "cr1");
    assert.equal(event.payload.status, "ESCALATED");
    assert.equal(event.payload.recipientCount, 3);
    assert.equal(event.payload.simulatedCount, 2);
    assert.equal(event.payload.blockedCount, 1);
    assert.equal(event.payload.failedCount, 0);
    assert.deepEqual(event.payload.deliveryChannels, ["NONE", "PUSH"]);
    assert.equal(event.payload.deliveries, undefined);
    assert.equal(JSON.stringify(event.payload).includes("@"), false, "timeline payload must not leak emails");
  });

  test("escalation fanout handles legacy unscoped tasks without querying null receiver access", async () => {
    const db = buildDb(scopedAccessSeed());
    db._s.tasks.push({
      id: "t-unscoped-escalation",
      title: "Legacy unscoped reminder",
      status: "PENDING",
      priority: "NORMAL",
      circleId: "c1",
      creatorId: "u1",
      assigneeId: "u2",
      completedById: null,
      completedAt: null,
      dueAt: new Date("2026-04-30T12:00:00.000Z"),
      archivedAt: null,
      createdAt: new Date("2026-04-29T12:00:00.000Z"),
      updatedAt: new Date("2026-04-29T12:00:00.000Z"),
      recurrenceFrequency: "NONE",
      recurrenceInterval: null,
      recurrenceWeekdays: [],
      recurrenceEndsAt: null,
      seriesId: null,
      recipientId: null,
    });
    db._s.reminders.push({
      id: "rem-unscoped-escalation",
      taskId: "t-unscoped-escalation",
      status: "SENT",
      scheduledAt: new Date(Date.now() - 30 * 60 * 1000),
      sentAt: new Date(Date.now() - 20 * 60 * 1000),
      snoozedUntil: null,
      snoozeCount: 0,
      escalationDueAt: new Date(Date.now() - 1000),
      escalatedAt: null,
    });

    let receiverAccessQueried = false;
    db.careRecipientAccess.findMany = async () => {
      receiverAccessQueried = true;
      throw new Error("unscoped tasks must not query receiver access with a null recipientId");
    };

    await processEscalations(db);

    const reminder = db._s.reminders.find((item) => item.id === "rem-unscoped-escalation");
    assert.equal(receiverAccessQueried, false);
    assert.equal(reminder.status, "ESCALATED");
    assert.ok(reminder.escalatedAt);
    const event = db._s.events.find((item) => item.type === "REMINDER_ESCALATED" && item.payload.taskId === "t-unscoped-escalation");
    assert.ok(event, "scheduler logs the legacy unscoped escalation");
    assert.equal(event.payload.recipientId, null);
    assert.equal(event.payload.recipientCount, 2);
    assert.equal(JSON.stringify(event.payload).includes("@"), false, "timeline payload must not leak emails");
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Route — Task creation → Reminder scheduling
// ═══════════════════════════════════════════════════════════════════════════════

describe("POST /circles/:circleId/tasks — Reminder creation", () => {
  let app, db;

  before(async () => {
    db = buildDb({
      users:   [{ id: "u1", name: "Alice", email: "a@t.com", pushToken: null }],
      circles: [{ id: "c1", name: "Smith Family", recipientName: "Mom" }],
      recipientEntitlements: [{
        id: "cre-reminders",
        recipientId: "cr1",
        status: "ACTIVE",
        source: "APP_STORE",
        startsAt: new Date("2026-04-01T00:00:00.000Z"),
        expiresAt: new Date("2026-06-01T00:00:00.000Z"),
        appleOriginalTransactionId: "otx-reminders",
        appleProductId: "com.careloop.ios.premium.monthly",
        purchasedById: "u1",
        createdAt: new Date("2026-04-01T00:00:00.000Z"),
        updatedAt: new Date("2026-04-01T00:00:00.000Z"),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    });
    app = await buildApp(db);
  });

  after(() => app.close());

  test("creates Reminder scheduled at dueAt minus 15 minutes", async () => {
    const dueAt = new Date(Date.now() + 3600 * 1000).toISOString();
    const res = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Give meds", creatorId: "u1", dueAt, assigneeId: "u1" }),
    });
    assert.equal(res.statusCode, 201);
    const task = JSON.parse(res.payload);
    assert.equal(task.recipient.sortOrder, 0);
    assert.equal(task.recipient.notes, null);

    const reminder = db._s.reminders.find((r) => r.taskId === task.id);
    assert.ok(reminder, "Reminder exists in DB");
    assert.equal(reminder.status, "PENDING");

    const expectedMs = new Date(dueAt).getTime() - 15 * 60 * 1000;
    const diff = Math.abs(new Date(reminder.scheduledAt).getTime() - expectedMs);
    assert.ok(diff < 2000, `scheduledAt within 2s of dueAt-15m (actual diff: ${diff}ms)`);
  });

  test("does NOT create a Reminder when task has no dueAt", async () => {
    const countBefore = db._s.reminders.length;
    const res = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Check in on Dad", creatorId: "u1", assigneeId: "u1" }),
    });
    assert.equal(res.statusCode, 201);
    assert.equal(db._s.reminders.length, countBefore, "no new reminder created");
  });

  test("snoozes a task reminder and delays scheduler delivery", async () => {
    const dueAt = new Date(Date.now() - 60 * 1000).toISOString();
    const create = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Snooze meds", creatorId: "u1", dueAt, assigneeId: "u1" }),
    });
    assert.equal(create.statusCode, 201);
    const task = create.json();

    const beforeSnooze = Date.now();
    const snooze = await app.inject({
      method: "POST",
      url: `/circles/c1/tasks/${task.id}/reminder/snooze`,
      headers: HDR,
      payload: { minutes: 15 },
    });
    const afterSnooze = Date.now();
    assert.equal(snooze.statusCode, 200);
    const snoozeBody = snooze.json();
    assert.equal(snoozeBody.status, "SNOOZED");
    assert.equal(snoozeBody.snoozeCount, 1);
    assert.equal(snoozeBody.scheduledAt, snoozeBody.snoozedUntil);

    const expectedMin = beforeSnooze + 15 * 60 * 1000 - 1000;
    const expectedMax = afterSnooze + 15 * 60 * 1000 + 1000;
    const rescheduledMs = new Date(snoozeBody.snoozedUntil).getTime();
    assert.ok(rescheduledMs >= expectedMin, "snoozedUntil is not before the requested delay window");
    assert.ok(rescheduledMs <= expectedMax, "snoozedUntil is not after the requested delay window");

    await processPendingReminders(db);
    const reminder = db._s.reminders.find((item) => item.taskId === task.id);
    assert.equal(reminder.status, "SNOOZED", "scheduler skips reminders snoozed into the future");
    assert.equal(reminder.scheduledAt.getTime(), rescheduledMs);
    assert.equal(reminder.snoozedUntil.getTime(), rescheduledMs);
  });

  test("rejects invalid snooze durations and completed task snoozes", async () => {
    const dueAt = new Date(Date.now() - 60 * 1000).toISOString();
    const create = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Complete before snooze", creatorId: "u1", dueAt, assigneeId: "u1" }),
    });
    assert.equal(create.statusCode, 201);
    const task = create.json();

    const invalid = await app.inject({
      method: "POST",
      url: `/circles/c1/tasks/${task.id}/reminder/snooze`,
      headers: HDR,
      payload: { minutes: 5 },
    });
    assert.equal(invalid.statusCode, 400);

    const done = await app.inject({
      method: "PATCH",
      url: `/circles/c1/tasks/${task.id}`,
      headers: HDR,
      payload: { userId: "u1", status: "DONE" },
    });
    assert.equal(done.statusCode, 200);

    const snoozeDone = await app.inject({
      method: "POST",
      url: `/circles/c1/tasks/${task.id}/reminder/snooze`,
      headers: HDR,
      payload: { minutes: 15 },
    });
    assert.equal(snoozeDone.statusCode, 400);
    assert.equal(snoozeDone.json().error, "Completed tasks cannot be snoozed");
  });

  test("snoozed reminder sends when snooze expires and then escalates once overdue", async () => {
    const dueAt = new Date(Date.now() - 60 * 1000).toISOString();
    const create = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Escalate after snooze", creatorId: "u1", dueAt, assigneeId: "u1" }),
    });
    assert.equal(create.statusCode, 201);
    const task = create.json();
    const reminder = db._s.reminders.find((item) => item.taskId === task.id);
    Object.assign(reminder, {
      status: "SNOOZED",
      scheduledAt: new Date(Date.now() - 1000),
      snoozedUntil: new Date(Date.now() - 1000),
      snoozeCount: 1,
    });

    await processPendingReminders(db);
    assert.equal(reminder.status, "SENT");
    assert.equal(reminder.snoozedUntil, null);
    assert.ok(reminder.escalationDueAt, "sent reminder gets escalationDueAt");

    reminder.escalationDueAt = new Date(Date.now() - 1000);
    await processEscalations(db);
    assert.equal(reminder.status, "ESCALATED");
    assert.ok(reminder.escalatedAt, "escalation timestamp is set");
  });

  test("completed task reminders do not send or escalate", async () => {
    const dueAt = new Date(Date.now() - 60 * 1000).toISOString();
    const create = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Done before reminder", creatorId: "u1", dueAt, assigneeId: "u1" }),
    });
    assert.equal(create.statusCode, 201);
    const task = create.json();
    const reminder = db._s.reminders.find((item) => item.taskId === task.id);
    db._s.tasks.find((item) => item.id === task.id).status = "DONE";

    await processPendingReminders(db);
    assert.equal(reminder.status, "PENDING");

    Object.assign(reminder, { status: "SENT", escalationDueAt: new Date(Date.now() - 1000) });
    await processEscalations(db);
    assert.equal(reminder.status, "SENT");
  });

  test("logs TASK_CREATED event for every task", async () => {
    const countBefore = db._s.events.filter((e) => e.type === "TASK_CREATED").length;
    await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Morning walk", creatorId: "u1", assigneeId: "u1" }),
    });
    const countAfter = db._s.events.filter((e) => e.type === "TASK_CREATED").length;
    assert.equal(countAfter, countBefore + 1);
  });

  test("returns 400 when title is missing", async () => {
    const res = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ creatorId: "u1" }),
    });
    assert.equal(res.statusCode, 400);
  });

  test("returns 400 when title exceeds 200 characters", async () => {
    const res = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "x".repeat(201), creatorId: "u1", assigneeId: "u1" }),
    });
    assert.equal(res.statusCode, 400);
  });

  test("returns 400 when assigneeId is missing", async () => {
    const res = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Needs an assignee", creatorId: "u1" }),
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "assigneeId is required");
  });

  test("returns 400 when the care receiver has not accepted or been proxy-activated", async () => {
    const inactiveDb = buildDb({
      users: [{ id: "u1", name: "Alice", email: "a@t.com", pushToken: null }],
      circles: [{ id: "c1", name: "Smith Family", recipientName: "Mom" }],
      recipients: [{
        id: "cr1",
        circleId: "c1",
        name: "Mom",
        relationship: null,
        notes: null,
        isPrimary: true,
        sortOrder: 0,
        activationStatus: "DRAFT",
        activatedAt: null,
        receiverUserId: null,
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      }],
      members: [{ id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" }],
    });
    const inactiveApp = await buildApp(inactiveDb);
    const res = await inactiveApp.inject({
      method: "POST",
      url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Give meds", creatorId: "u1", recipientId: "cr1", assigneeId: "u1" }),
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "Care receiver must accept or be proxy-activated before tasks can be created");
    await inactiveApp.close();
  });

  test("returns 403 when creatorId is not a circle member", async () => {
    const res = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({ title: "Intruder task", creatorId: "not-a-member", assigneeId: "not-a-member" }),
    });
    assert.equal(res.statusCode, 403);
  });

  test("creates a recurring task series and logs TASK_SERIES_CREATED", async () => {
    const recipientId = db._s.recipients[0].id;
    const dueAt = new Date(Date.now() + 2 * 3600 * 1000).toISOString();
    const beforeSeriesEvents = db._s.events.filter((event) => event.type === "TASK_SERIES_CREATED").length;
    const res = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({
        title: "Evening meds",
        creatorId: "u1",
        dueAt,
        recipientId,
        assigneeId: "u1",
        recurrence: {
          frequency: "DAILY",
          interval: 1,
        },
      }),
    });
    assert.equal(res.statusCode, 201);
    const task = res.json();
    assert.equal(task.recurrenceFrequency, "DAILY");
    assert.equal(task.recipientId, recipientId);
    assert.ok(task.seriesId, "seriesId is assigned");
    const afterSeriesEvents = db._s.events.filter((event) => event.type === "TASK_SERIES_CREATED").length;
    assert.equal(afterSeriesEvents, beforeSeriesEvents + 1);
  });

  test("completing a recurring task creates the next occurrence", async () => {
    const recipientId = db._s.recipients[0].id;
    const dueAt = new Date("2026-04-29T12:00:00.000Z").toISOString();
    const create = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({
        title: "Weekly check-in",
        creatorId: "u1",
        dueAt,
        recipientId,
        assigneeId: "u1",
        recurrence: {
          frequency: "WEEKLY",
          interval: 1,
        },
      }),
    });
    assert.equal(create.statusCode, 201);
    const createdTask = create.json();

    const update = await app.inject({
      method: "PATCH",
      url: `/circles/c1/tasks/${createdTask.id}`,
      headers: HDR,
      body: JSON.stringify({
        userId: "u1",
        status: "DONE",
      }),
    });
    assert.equal(update.statusCode, 200);

    const seriesTasks = db._s.tasks.filter((task) => task.seriesId === createdTask.seriesId);
    assert.equal(seriesTasks.length, 2);
    const nextTask = seriesTasks.find((task) => task.id !== createdTask.id);
    assert.ok(nextTask, "next recurring occurrence exists");
    assert.equal(nextTask.status, "PENDING");
    assert.equal(nextTask.recipientId, recipientId);
    assert.equal(nextTask.dueAt.toISOString(), "2026-05-06T12:00:00.000Z");
  });

  test("editing a recurring task with SERIES scope updates future occurrences", async () => {
    const recipientId = db._s.recipients[0].id;
    const dueAt = new Date("2026-04-29T12:00:00.000Z").toISOString();
    const create = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({
        title: "Weekly check-in",
        creatorId: "u1",
        dueAt,
        recipientId,
        assigneeId: "u1",
        recurrence: {
          frequency: "WEEKLY",
          interval: 1,
        },
      }),
    });
    assert.equal(create.statusCode, 201);
    const createdTask = create.json();

    await app.inject({
      method: "PATCH",
      url: `/circles/c1/tasks/${createdTask.id}`,
      headers: HDR,
      body: JSON.stringify({ userId: "u1", status: "DONE" }),
    });

    const nextTask = db._s.tasks.find((task) => task.seriesId === createdTask.seriesId && task.id !== createdTask.id);
    assert.ok(nextTask);

    const update = await app.inject({
      method: "PATCH",
      url: `/circles/c1/tasks/${nextTask.id}`,
      headers: HDR,
      body: JSON.stringify({
        userId: "u1",
        title: "Updated weekly check-in",
        priority: "HIGH",
        seriesScope: "SERIES",
      }),
    });

    assert.equal(update.statusCode, 200);
    const editableSeriesTasks = db._s.tasks.filter((task) =>
      task.seriesId === createdTask.seriesId && ["PENDING", "IN_PROGRESS"].includes(task.status)
    );
    assert.ok(editableSeriesTasks.every((task) => task.title === "Updated weekly check-in"));
    assert.ok(editableSeriesTasks.every((task) => task.priority === "HIGH"));
  });

  test("editing a recurring task with SERIES scope rejects status updates", async () => {
    const recipientId = db._s.recipients[0].id;
    const create = await app.inject({
      method: "POST", url: "/circles/c1/tasks",
      headers: HDR,
      body: JSON.stringify({
        title: "Weekly check-in",
        creatorId: "u1",
        dueAt: new Date("2026-04-29T12:00:00.000Z").toISOString(),
        recipientId,
        assigneeId: "u1",
        recurrence: {
          frequency: "WEEKLY",
          interval: 1,
        },
      }),
    });
    assert.equal(create.statusCode, 201);
    const createdTask = create.json();

    const update = await app.inject({
      method: "PATCH",
      url: `/circles/c1/tasks/${createdTask.id}`,
      headers: HDR,
      body: JSON.stringify({
        userId: "u1",
        status: "DONE",
        seriesScope: "SERIES",
      }),
    });

    assert.equal(update.statusCode, 400);
    assert.equal(update.json().error, "Status updates only apply to a single occurrence");
  });
});

describe("GET /circles/:id/insights/completion", () => {
  test("returns admin completion chart data for the requested window", async () => {
    const now = new Date("2026-04-29T18:00:00.000Z");
    const db = buildDb({
      users: [
        { id: "u1", email: "admin@test.com", name: "Admin" },
        { id: "u2", email: "caregiver@test.com", name: "Caregiver" },
      ],
      circles: [{ id: "c1", name: "Alpha", recipientName: "John Doe", archiveAfterDays: 7 }],
      recipients: [
        { id: "cr1", circleId: "c1", name: "John Doe", relationship: null, notes: null, isPrimary: true, createdAt: now, updatedAt: now },
        { id: "cr2", circleId: "c1", name: "Jane Doe", relationship: "Spouse", notes: null, isPrimary: false, createdAt: now, updatedAt: now },
      ],
      recipientEntitlements: [
        {
          id: "cre-insights-1",
          recipientId: "cr1",
          status: "ACTIVE",
          source: "APP_STORE",
          startsAt: new Date("2026-04-01T00:00:00.000Z"),
          expiresAt: new Date("2026-06-01T00:00:00.000Z"),
          appleOriginalTransactionId: "otx-insights-1",
          appleProductId: "com.careloop.ios.premium.monthly",
          purchasedById: "u1",
          createdAt: now,
          updatedAt: now,
        },
        {
          id: "cre-insights-2",
          recipientId: "cr2",
          status: "ACTIVE",
          source: "APP_STORE",
          startsAt: new Date("2026-04-01T00:00:00.000Z"),
          expiresAt: new Date("2026-06-01T00:00:00.000Z"),
          appleOriginalTransactionId: "otx-insights-2",
          appleProductId: "com.careloop.ios.premium.monthly",
          purchasedById: "u1",
          createdAt: now,
          updatedAt: now,
        },
      ],
      members: [
        { id: "m1", userId: "u1", circleId: "c1", role: "ADMIN" },
        { id: "m2", userId: "u2", circleId: "c1", role: "MEMBER" },
      ],
      tasks: [
        {
          id: "t1",
          title: "Task 1",
          status: "DONE",
          priority: "NORMAL",
          circleId: "c1",
          creatorId: "u1",
          assigneeId: "u2",
          completedById: "u2",
          completedAt: new Date("2026-04-29T13:00:00.000Z"),
          dueAt: new Date("2026-04-29T12:00:00.000Z"),
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
          recurrenceFrequency: "NONE",
          recurrenceInterval: null,
          recurrenceWeekdays: [],
          recurrenceEndsAt: null,
          seriesId: null,
          recipientId: "cr1",
        },
        {
          id: "t2",
          title: "Task 2",
          status: "DONE",
          priority: "NORMAL",
          circleId: "c1",
          creatorId: "u1",
          assigneeId: "u2",
          completedById: "u2",
          completedAt: new Date("2026-04-28T13:00:00.000Z"),
          dueAt: new Date("2026-04-28T12:00:00.000Z"),
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
          recurrenceFrequency: "NONE",
          recurrenceInterval: null,
          recurrenceWeekdays: [],
          recurrenceEndsAt: null,
          seriesId: null,
          recipientId: "cr1",
        },
        {
          id: "t3",
          title: "Overdue Task",
          status: "PENDING",
          priority: "HIGH",
          circleId: "c1",
          creatorId: "u1",
          assigneeId: "u2",
          completedById: null,
          completedAt: null,
          dueAt: new Date("2026-04-27T12:00:00.000Z"),
          archivedAt: null,
          createdAt: now,
          updatedAt: now,
          recurrenceFrequency: "NONE",
          recurrenceInterval: null,
          recurrenceWeekdays: [],
          recurrenceEndsAt: null,
          seriesId: null,
          recipientId: "cr2",
        },
      ],
      reminders: [
        {
          id: "rem-escalated-1",
          taskId: "t3",
          scheduledAt: new Date("2026-04-27T11:45:00.000Z"),
          sentAt: new Date("2026-04-27T12:00:00.000Z"),
          snoozedUntil: null,
          snoozeCount: 0,
          escalationDueAt: new Date("2026-04-27T12:15:00.000Z"),
          escalatedAt: new Date("2026-04-27T12:20:00.000Z"),
          status: "ESCALATED",
        },
      ],
    });
    const app = await buildApp(db);

    const realDateNow = Date.now;
    Date.now = () => now.getTime();
    try {
      const res = await app.inject({
        method: "GET",
        url: "/circles/c1/insights/completion?days=7",
        headers: HDR,
      });

      assert.equal(res.statusCode, 200);
      const body = res.json();
      assert.equal(body.periodDays, 7);
      assert.equal(body.totals.completed, 2);
      assert.equal(body.totals.active, 1);
      assert.equal(body.totals.overdue, 1);
      assert.deepEqual(body.adherence, {
        scheduled: 3,
        completed: 2,
        onTime: 0,
        late: 2,
        missed: 1,
        completionRate: 67,
        onTimeRate: 0,
      });
      assert.equal(body.recipientBreakdown.length, 2);
      assert.deepEqual(body.recipientBreakdown.find((item) => item.recipientId === "cr1"), {
        recipientId: "cr1",
        name: "John Doe",
        completed: 2,
        active: 0,
        overdue: 0,
        adherence: {
          scheduled: 2,
          completed: 2,
          onTime: 0,
          late: 2,
          missed: 0,
          completionRate: 100,
          onTimeRate: 0,
        },
      });
      assert.deepEqual(body.recipientBreakdown.find((item) => item.recipientId === "cr2"), {
        recipientId: "cr2",
        name: "Jane Doe",
        completed: 0,
        active: 1,
        overdue: 1,
        adherence: {
          scheduled: 1,
          completed: 0,
          onTime: 0,
          late: 0,
          missed: 1,
          completionRate: 0,
          onTimeRate: 0,
        },
      });
      assert.deepEqual(body.topCaregivers[0], {
        userId: "u2",
        name: "Caregiver",
        email: "caregiver@test.com",
        completedCount: 2,
      });
      assert.deepEqual(body.caregiverLoad[0], {
        userId: "u2",
        name: "Caregiver",
        email: "caregiver@test.com",
        completedCount: 2,
        activeAssignedCount: 1,
        overdueAssignedCount: 1,
        totalAssignedCount: 3,
      });
      assert.equal(body.escalationSummary.totalEscalated, 1);
      assert.equal(body.escalationSummary.averageResponseMinutes, 20);
      assert.equal(body.escalationSummary.recent[0].taskId, "t3");
      assert.equal(body.escalationSummary.recent[0].taskTitle, "Overdue Task");
      assert.equal(body.escalationSummary.recent[0].recipientId, "cr2");
      assert.equal(body.escalationSummary.recent[0].recipientName, "Jane Doe");
      assert.equal(body.escalationSummary.recent[0].responseMinutes, 20);
      assert.equal(body.completedByDay.find((item) => item.date === "2026-04-29").count, 1);
      assert.equal(body.completedByDay.find((item) => item.date === "2026-04-28").count, 1);
      assert.deepEqual(body.taskTrendByDay.find((item) => item.date === "2026-04-29"), {
        date: "2026-04-29",
        due: 1,
        completed: 1,
        missed: 0,
      });
      assert.deepEqual(body.taskTrendByDay.find((item) => item.date === "2026-04-28"), {
        date: "2026-04-28",
        due: 1,
        completed: 1,
        missed: 0,
      });
      assert.deepEqual(body.taskTrendByDay.find((item) => item.date === "2026-04-27"), {
        date: "2026-04-27",
        due: 1,
        completed: 0,
        missed: 1,
      });

      const filtered = await app.inject({
        method: "GET",
        url: "/circles/c1/insights/completion?days=7&recipientId=cr1",
        headers: HDR,
      });
      assert.equal(filtered.statusCode, 200);
      const filteredBody = filtered.json();
      assert.equal(filteredBody.selectedRecipientId, "cr1");
      assert.equal(filteredBody.totals.completed, 2);
      assert.equal(filteredBody.totals.active, 0);
      assert.equal(filteredBody.totals.overdue, 0);
      assert.deepEqual(filteredBody.adherence, {
        scheduled: 2,
        completed: 2,
        onTime: 0,
        late: 2,
        missed: 0,
        completionRate: 100,
        onTimeRate: 0,
      });
    } finally {
      Date.now = realDateNow;
      await app.close();
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Scheduler logic — escalation cutoff rule
// ═══════════════════════════════════════════════════════════════════════════════

describe("Scheduler escalation rules (unit)", () => {
  const ESCALATION_MIN = 15;

  test("escalation window: sentAt + 15min is before now → should escalate", () => {
    const sentAt = new Date(Date.now() - (ESCALATION_MIN + 1) * 60 * 1000);
    const cutoff  = new Date(Date.now() - ESCALATION_MIN * 60 * 1000);
    assert.ok(sentAt <= cutoff, "reminder older than 15min qualifies for escalation");
  });

  test("escalation window: sentAt + 14min is after now → should NOT escalate", () => {
    const sentAt = new Date(Date.now() - (ESCALATION_MIN - 1) * 60 * 1000);
    const cutoff  = new Date(Date.now() - ESCALATION_MIN * 60 * 1000);
    assert.ok(sentAt > cutoff, "reminder younger than 15min does not qualify");
  });

  test("escalation recipients include the assignee, organizers, and supporting caregivers only", () => {
    const userIds = escalationUserIdsForTask({
      task: {
        assigneeId: "u2",
        creatorId: "u1",
        recipientId: "cr1",
      },
      circleMembers: [
        { id: "m1", userId: "u1", role: "ADMIN" },
        { id: "m2", userId: "u2", role: "MEMBER" },
        { id: "m3", userId: "u3", role: "MEMBER" },
        { id: "m4", userId: "u4", role: "MEMBER" },
        { id: "m5", userId: "u5", role: "RECIPIENT" },
      ],
      activeRecipientAccesses: [
        { memberId: "m2", recipientId: "cr1", revokedAt: null },
        { memberId: "m3", recipientId: "cr1", revokedAt: null },
        { memberId: "m4", recipientId: "cr2", revokedAt: null },
      ],
    }).sort();

    assert.deepEqual(userIds, ["u1", "u2", "u3"]);
  });

  test("digest date string format is YYYY-MM-DD", () => {
    const date = new Date("2026-04-26T18:00:00Z");
    const formatted = date.toISOString().split("T")[0];
    assert.equal(formatted, "2026-04-26");
  });

  test("DIGEST_HOUR default is 18", () => {
    const digestHour = parseInt(process.env.DAILY_DIGEST_HOUR || "18", 10);
    assert.equal(digestHour, 18);
  });
});
