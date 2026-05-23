import { Prisma } from "@prisma/client";
import { assertRequestAdmin, assertRequestMember, logEvent, requireAuthenticatedUser } from "../lib/roles.js";
import { normalizeEmail } from "../lib/auth.js";
import { pageResponse, parseCursorPagination, prismaCursorWindow } from "../lib/pagination.js";
import { activationForAcceptedReceiver, activationForProxyReceiver } from "../lib/receiver-state.js";
import { AppStoreVerificationError, verifyAppStoreTransaction } from "../lib/app-store-server.js";
import {
  RECEIVER_ENTITLEMENT_STATUS,
  isSupportedReceiverPremiumProductId,
  isSupportedReceiverEntitlementStatus,
  maxCaregiversForReceiver,
  receiverEntitlementCapabilities,
  receiverEntitlementSummary,
} from "../lib/entitlements.js";
import {
  eligibleAssigneeUserIdsForReceiver,
  filterVisibleTasks,
  isCareOrganizer,
  loadReceiverAccessContext,
} from "../lib/access.js";

const circleInclude = {
  members: { include: { user: { select: { id: true, name: true, email: true } } } },
  recipients: {
    orderBy: [{ isPrimary: "desc" }, { sortOrder: "asc" }, { createdAt: "asc" }],
    include: { entitlement: true },
  },
  tasks:   true,
};
const invitationInclude = {
  circle: { select: { id: true, name: true, recipientName: true, archiveAfterDays: true } },
  recipient: { select: { id: true, name: true, activationStatus: true, receiverUserId: true } },
  invitedBy: { select: { id: true, name: true, email: true } },
};
const MAX_CIRCLES_PER_USER = 3;
const INVITATION_EXPIRES_AFTER_DAYS = 14;
const ENTITLEMENT_SOURCES = new Set(["APP_STORE", "MANUAL"]);
const ACTIVE_ENTITLEMENT_STATUSES = new Set([RECEIVER_ENTITLEMENT_STATUS.ACTIVE]);
const PREMIUM_REQUEST_VISIBLE_DAYS = 7;
const eventOrder = [{ createdAt: "desc" }, { id: "desc" }];
const invitationOrder = [{ createdAt: "desc" }, { id: "desc" }];
const taskActivityOrder = [{ completedAt: "asc" }, { dueAt: "asc" }, { createdAt: "desc" }, { id: "desc" }];

export default async function circles(app) {
  const db = app.db;

  function decorateRecipientsForMember(recipients, member, circleMembers, activeRecipientAccesses) {
    return recipients.map((recipient) => ({
      ...recipientSummary(recipient),
      eligibleAssigneeIds: eligibleAssigneeUserIdsForReceiver({
        member,
        receiver: recipient,
        circleMembers,
        activeRecipientAccesses,
      }),
    }));
  }

  function recipientSummary(recipient) {
    const { entitlement, ...rest } = recipient;
    return {
      ...rest,
      premium: receiverEntitlementSummary(entitlement),
    };
  }

  function filteredCircleForMember(circle, member, accessContext, activeRecipientAccesses) {
    if (isCareOrganizer(member)) {
      return {
        ...circle,
        recipients: decorateRecipientsForMember(
          circle.recipients ?? [],
          member,
          circle.members ?? [],
          activeRecipientAccesses,
        ),
      };
    }
    const filteredRecipients = decorateRecipientsForMember(
      accessContext.recipients,
      member,
      circle.members ?? [],
      activeRecipientAccesses,
    );
    const filteredTasks = filterVisibleTasks(circle.tasks ?? [], {
      member,
      userId: member.userId,
      accessContext,
    });
    return {
      ...circle,
      recipientName: filteredRecipients[0]?.name ?? "",
      recipients: filteredRecipients,
      tasks: filteredTasks,
    };
  }

  function emptyCompletionInsights(periodDays, selectedRecipientId = null) {
    return {
      periodDays,
      selectedRecipientId,
      completedByDay: [],
      taskTrendByDay: [],
      topCaregivers: [],
      caregiverLoad: [],
      escalationSummary: emptyEscalationSummary(),
      recipientBreakdown: [],
      adherence: emptyAdherenceSummary(),
      totals: {
        completed: 0,
        active: 0,
        overdue: 0,
      },
    };
  }

  function emptyAdherenceSummary() {
    return {
      scheduled: 0,
      completed: 0,
      onTime: 0,
      late: 0,
      missed: 0,
      completionRate: 0,
      onTimeRate: 0,
    };
  }

  function percent(numerator, denominator) {
    if (!denominator) return 0;
    return Math.round((numerator / denominator) * 100);
  }

  function adherenceForTasks(tasks, { since, now }) {
    const dueTasks = tasks.filter((task) => task.dueAt && task.dueAt >= since && task.dueAt <= now);
    const completed = dueTasks.filter((task) => task.status === "DONE" && task.completedAt);
    const onTime = completed.filter((task) => task.completedAt <= task.dueAt);
    const late = completed.length - onTime.length;
    const missed = dueTasks.filter((task) =>
      ["PENDING", "IN_PROGRESS"].includes(task.status) && task.dueAt < now,
    ).length;
    return {
      scheduled: dueTasks.length,
      completed: completed.length,
      onTime: onTime.length,
      late,
      missed,
      completionRate: percent(completed.length, dueTasks.length),
      onTimeRate: percent(onTime.length, dueTasks.length),
    };
  }

  function emptyEscalationSummary() {
    return {
      totalEscalated: 0,
      averageResponseMinutes: null,
      recent: [],
    };
  }

  function escalationSummaryForReminders(reminders) {
    if (reminders.length === 0) return emptyEscalationSummary();
    const responseTimes = reminders
      .filter((reminder) => reminder.sentAt && reminder.escalatedAt)
      .map((reminder) => Math.max(0, Math.round((reminder.escalatedAt.getTime() - reminder.sentAt.getTime()) / 60000)));
    const averageResponseMinutes = responseTimes.length
      ? Math.round(responseTimes.reduce((sum, value) => sum + value, 0) / responseTimes.length)
      : null;
    return {
      totalEscalated: reminders.length,
      averageResponseMinutes,
      recent: reminders
        .slice()
        .sort((lhs, rhs) => rhs.escalatedAt - lhs.escalatedAt)
        .slice(0, 5)
        .map((reminder) => ({
          taskId: reminder.taskId,
          taskTitle: reminder.task?.title ?? "Task",
          recipientId: reminder.task?.recipientId ?? null,
          recipientName: reminder.task?.recipient?.name ?? null,
          escalatedAt: reminder.escalatedAt,
          responseMinutes: reminder.sentAt && reminder.escalatedAt
            ? Math.max(0, Math.round((reminder.escalatedAt.getTime() - reminder.sentAt.getTime()) / 60000))
            : null,
        })),
    };
  }

  function eventVisibleToMember(event, member, accessContext, visibleTaskIds) {
    if (isCareOrganizer(member)) return true;
    const payload = event.payload ?? {};
    if (payload.taskId) return visibleTaskIds.has(payload.taskId);
    if (payload.recipientId && accessContext.recipientIds.has(payload.recipientId)) return true;
    return event.actorId === member.userId;
  }

  async function caregiverMemberOrReply(circleId, memberId, reply) {
    const member = await db.circleMember.findUnique({
      where: { id: memberId },
      include: { user: { select: { id: true, name: true, email: true } } },
    });
    if (!member || member.circleId !== circleId) {
      reply.code(404).send({ error: "Member not found" });
      return null;
    }
    if (member.role !== "MEMBER") {
      reply.code(400).send({ error: "Receiver access can only be managed for caregivers" });
      return null;
    }
    return member;
  }

  function normalizedArchiveAfterDays(value) {
    if (!Number.isInteger(value)) return undefined;
    return Math.min(30, Math.max(1, value));
  }

  async function resetRecipientInviteStateIfUnclaimed(tx, recipientId) {
    if (!recipientId) return;
    const recipient = await tx.careRecipient.findUnique({ where: { id: recipientId } });
    if (!recipient || recipient.receiverUserId) return;
    await tx.careRecipient.update({
      where: { id: recipientId },
      data: {
        activationStatus: "DRAFT",
        consentAttestedAt: null,
        consentAttestedById: null,
        proxyAuthorizedById: null,
        consentDocumentReference: null,
      },
    });
  }

  function invitationExpiryDate() {
    return new Date(Date.now() + INVITATION_EXPIRES_AFTER_DAYS * 24 * 60 * 60 * 1000);
  }

  function invitationHasExpired(invitation, now = new Date()) {
    return invitation?.status === "PENDING" && invitation.expiresAt && new Date(invitation.expiresAt) <= now;
  }

  function premiumRequestCutoff(now = new Date()) {
    return new Date(now.getTime() - PREMIUM_REQUEST_VISIBLE_DAYS * 24 * 60 * 60 * 1000);
  }

  function summarizePremiumRequests(requests) {
    const byRecipient = new Map();
    for (const request of requests) {
      const current = byRecipient.get(request.recipientId) ?? {
        recipientId: request.recipientId,
        recipientName: request.recipient?.name ?? "Care receiver",
        requestCount: 0,
        latestRequesterName: null,
        latestRequesterId: null,
        latestRequestedAt: null,
      };
      current.requestCount += 1;
      if (!current.latestRequestedAt || request.createdAt > current.latestRequestedAt) {
        current.latestRequesterName = request.requester?.name ?? "Caregiver";
        current.latestRequesterId = request.requesterUserId;
        current.latestRequestedAt = request.createdAt;
      }
      byRecipient.set(request.recipientId, current);
    }
    return [...byRecipient.values()].sort((lhs, rhs) => rhs.latestRequestedAt - lhs.latestRequestedAt);
  }

  async function markInvitationExpired(tx, invitation) {
    await tx.invitation.update({
      where: { id: invitation.id },
      data: { status: "EXPIRED" },
    });
    await resetRecipientInviteStateIfUnclaimed(tx, invitation.recipientId);
  }

  async function membershipCount(userId) {
    return db.circleMember.count({ where: { userId } });
  }

  async function ensureCircleCapacity(userId, reply) {
    const count = await membershipCount(userId);
    if (count >= MAX_CIRCLES_PER_USER) {
      reply.code(400).send({ error: `Users can only belong to ${MAX_CIRCLES_PER_USER} circles.` });
      return false;
    }
    return true;
  }

  async function resolvePrimaryRecipient(tx, circleId) {
    return tx.careRecipient.findFirst({
      where: { circleId },
      orderBy: [{ isPrimary: "desc" }, { sortOrder: "asc" }, { createdAt: "asc" }],
    });
  }

  async function findInvitationOr404(inviteId, reply) {
    const invitation = await db.invitation.findUnique({
      where: { id: inviteId },
      include: invitationInclude,
    });
    if (!invitation) {
      reply.code(404).send({ error: "Invitation not found" });
      return null;
    }
    return invitation;
  }

  function rejectUserMismatch(providedUserId, authenticatedUserId, reply) {
    if (providedUserId && providedUserId !== authenticatedUserId) {
      reply.code(403).send({ error: "userId must match the authenticated user" });
      return true;
    }
    return false;
  }

  // POST /circles — create circle, auto-add creator as Admin
  app.post("/circles", async (req, reply) => {
    const { name, recipientName, creatorId, archiveAfterDays } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(creatorId, authenticatedUserId, reply)) return;
    if (!name)
      return reply.code(400).send({ error: "name is required" });

    const creator = await db.user.findUnique({ where: { id: authenticatedUserId } });
    if (!creator) return reply.code(404).send({ error: "Creator user not found" });
    if (!await ensureCircleCapacity(authenticatedUserId, reply)) return;

    const normalizedDays = normalizedArchiveAfterDays(archiveAfterDays);

    const circle = await db.$transaction(async (tx) => {
      const c = await tx.careCircle.create({
        data: {
          name,
          recipientName: recipientName ?? "",
          archiveAfterDays: normalizedDays,
        },
      });
      if (recipientName?.trim()) {
        await tx.careRecipient.create({
          data: {
            circleId: c.id,
            name: recipientName.trim(),
            isPrimary: true,
          },
        });
      }
      await tx.circleMember.create({ data: { circleId: c.id, userId: authenticatedUserId, role: "ADMIN" } });
      await tx.event.create({ data: { type: "CIRCLE_CREATED", circleId: c.id, actorId: authenticatedUserId } });
      return tx.careCircle.findUnique({ where: { id: c.id }, include: circleInclude });
    });

    return reply.code(201).send(circle);
  });

  // GET /circles/:id
  app.get("/circles/:id", async (req, reply) => {
    const member = await assertRequestMember(db, req.params.id, req, reply);
    if (!member) return;
    const circle = await db.careCircle.findUnique({
      where:   { id: req.params.id },
      include: circleInclude,
    });
    if (!circle) return reply.code(404).send({ error: "Not found" });
    const accessContext = await loadReceiverAccessContext(db, {
      circleId: req.params.id,
      member,
      userId: member.userId,
    });
    const activeRecipientAccesses = await db.careRecipientAccess.findMany({ where: { revokedAt: null } });
    return filteredCircleForMember(circle, member, accessContext, activeRecipientAccesses);
  });

  // GET /circles/:id/insights/completion — organizers + caregivers within receiver scope
  app.get("/circles/:id/insights/completion", async (req, reply) => {
    const requestedDays = Number.parseInt(req.query?.days ?? "7", 10);
    const recipientId = req.query?.recipientId || null;
    const periodDays = Number.isInteger(requestedDays) ? Math.min(30, Math.max(7, requestedDays)) : 7;
    const member = await assertRequestMember(db, req.params.id, req, reply);
    if (!member) return;
    if (member.role === "RECIPIENT") {
      return reply.code(403).send({ error: "Care receivers cannot view progress insights" });
    }

    const accessContext = isCareOrganizer(member)
      ? null
      : await loadReceiverAccessContext(db, {
        circleId: req.params.id,
        member,
        userId: member.userId,
      });

    if (!isCareOrganizer(member) && recipientId && !accessContext.recipientIds.has(recipientId)) {
      return reply.code(404).send({ error: "Recipient not found" });
    }

    const now = new Date(Date.now());
    const since = new Date(now);
    since.setUTCHours(0, 0, 0, 0);
    since.setUTCDate(since.getUTCDate() - (periodDays - 1));
    const scopedRecipientIds = isCareOrganizer(member)
      ? null
      : [...accessContext.recipientIds];
    if (!isCareOrganizer(member) && scopedRecipientIds.length === 0) {
      return reply.send(emptyCompletionInsights(periodDays, recipientId));
    }

    const visibleRecipients = await db.careRecipient.findMany({
      where: {
        circleId: req.params.id,
        ...(recipientId
          ? { id: recipientId }
          : (!isCareOrganizer(member) ? { id: { in: scopedRecipientIds } } : {})),
      },
      include: { entitlement: true },
      orderBy: [{ isPrimary: "desc" }, { sortOrder: "asc" }, { createdAt: "asc" }],
    });
    const selectedRecipients = visibleRecipients.filter((recipient) =>
      recipientId ? recipient.id === recipientId : true,
    );
    if (recipientId && selectedRecipients.length === 0) {
      return reply.code(404).send({ error: "Recipient not found" });
    }

    const premiumEligibleRecipients = selectedRecipients.filter((recipient) =>
      receiverEntitlementCapabilities(recipient.entitlement).canUseInsights,
    );
    if (selectedRecipients.length > 0 && premiumEligibleRecipients.length !== selectedRecipients.length) {
      const blockingRecipient = selectedRecipients.find((recipient) =>
        !receiverEntitlementCapabilities(recipient.entitlement).canUseInsights,
      );
      return reply.code(402).send({
        error: "Completion insights are available only for premium care receivers",
        recipientId: blockingRecipient?.id ?? null,
      });
    }

    const recipientScope = recipientId ? { recipientId } : {};
    const allowedRecipientIds = recipientId
      ? new Set([recipientId])
      : (!isCareOrganizer(member) ? new Set(scopedRecipientIds) : null);

    const [rawCompletedTasks, rawActiveTasks, rawAllTasks, rawEscalatedReminders] = await Promise.all([
      db.task.findMany({
        where: {
          circleId: req.params.id,
          status: "DONE",
          completedAt: { gte: since },
          archivedAt: null,
          ...recipientScope,
        },
        include: {
          completedBy: { select: { id: true, name: true, email: true } },
          assignee: { select: { id: true, name: true, email: true } },
          recipient: { select: { id: true, name: true } },
        },
      }),
      db.task.findMany({
        where: {
          circleId: req.params.id,
          archivedAt: null,
          status: { in: ["PENDING", "IN_PROGRESS"] },
          ...recipientScope,
        },
        include: { recipient: { select: { id: true, name: true } } },
      }),
      db.task.findMany({
        where: {
          circleId: req.params.id,
          archivedAt: null,
          ...recipientScope,
        },
        include: {
          assignee: { select: { id: true, name: true, email: true } },
          completedBy: { select: { id: true, name: true, email: true } },
          recipient: { select: { id: true, name: true } },
        },
      }),
      db.reminder.findMany({
        where: {
          status: "ESCALATED",
          escalatedAt: { gte: since },
          task: {
            circleId: req.params.id,
            archivedAt: null,
            ...recipientScope,
          },
        },
        include: {
          task: {
            include: {
              recipient: { select: { id: true, name: true } },
            },
          },
        },
      }),
    ]);
    const completedTasks = allowedRecipientIds
      ? rawCompletedTasks.filter((task) => allowedRecipientIds.has(task.recipientId))
      : rawCompletedTasks;
    const activeTasks = allowedRecipientIds
      ? rawActiveTasks.filter((task) => allowedRecipientIds.has(task.recipientId))
      : rawActiveTasks;
    const allTasks = allowedRecipientIds
      ? rawAllTasks.filter((task) => allowedRecipientIds.has(task.recipientId))
      : rawAllTasks;
    const escalatedReminders = allowedRecipientIds
      ? rawEscalatedReminders.filter((reminder) => allowedRecipientIds.has(reminder.task?.recipientId))
      : rawEscalatedReminders;
    const circleRecipients = allowedRecipientIds
      ? visibleRecipients.filter((recipient) => allowedRecipientIds.has(recipient.id))
      : visibleRecipients;
    const overdueCount = activeTasks.filter((task) => task.dueAt && task.dueAt < now).length;

    const dailyMap = new Map();
    const trendMap = new Map();
    for (let offset = 0; offset < periodDays; offset += 1) {
      const day = new Date(since);
      day.setUTCDate(day.getUTCDate() + offset);
      const date = day.toISOString().slice(0, 10);
      dailyMap.set(date, 0);
      trendMap.set(date, {
        date,
        due: 0,
        completed: 0,
        missed: 0,
      });
    }

    const caregiverCounts = new Map();
    for (const task of completedTasks) {
      const date = task.completedAt?.toISOString().slice(0, 10);
      if (date && dailyMap.has(date)) {
        dailyMap.set(date, (dailyMap.get(date) ?? 0) + 1);
      }

      const caregiver = task.completedBy ?? task.assignee;
      if (!caregiver) continue;
      const current = caregiverCounts.get(caregiver.id) ?? {
        userId: caregiver.id,
        name: caregiver.name,
        email: caregiver.email,
        completedCount: 0,
      };
      current.completedCount += 1;
      caregiverCounts.set(caregiver.id, current);
    }

    for (const task of allTasks) {
      const dueDate = task.dueAt?.toISOString().slice(0, 10);
      if (!dueDate || !trendMap.has(dueDate)) continue;
      const current = trendMap.get(dueDate);
      current.due += 1;
      if (task.status === "DONE" && task.completedAt) {
        current.completed += 1;
      } else if (["PENDING", "IN_PROGRESS"].includes(task.status) && task.dueAt < now) {
        current.missed += 1;
      }
    }

    const caregiverLoad = new Map();
    if (isCareOrganizer(member)) {
      for (const task of allTasks) {
        const assignee = task.assignee;
        if (!assignee) continue;
        const current = caregiverLoad.get(assignee.id) ?? {
          userId: assignee.id,
          name: assignee.name,
          email: assignee.email,
          completedCount: 0,
          activeAssignedCount: 0,
          overdueAssignedCount: 0,
          totalAssignedCount: 0,
        };
        current.totalAssignedCount += 1;
        if (task.status === "DONE" && task.completedAt && task.completedAt >= since) {
          current.completedCount += 1;
        }
        if (["PENDING", "IN_PROGRESS"].includes(task.status)) {
          current.activeAssignedCount += 1;
          if (task.dueAt && task.dueAt < now) {
            current.overdueAssignedCount += 1;
          }
        }
        caregiverLoad.set(assignee.id, current);
      }
    }

    const recipientBreakdown = circleRecipients.map((recipient) => {
      const tasksForRecipient = allTasks.filter((task) => task.recipientId === recipient.id);
      const completed = tasksForRecipient.filter((task) => task.status === "DONE" && task.completedAt && task.completedAt >= since).length;
      const active = tasksForRecipient.filter((task) => ["PENDING", "IN_PROGRESS"].includes(task.status)).length;
      const overdue = tasksForRecipient.filter((task) => ["PENDING", "IN_PROGRESS"].includes(task.status) && task.dueAt && task.dueAt < now).length;
      const adherence = adherenceForTasks(tasksForRecipient, { since, now });
      return {
        recipientId: recipient.id,
        name: recipient.name,
        completed,
        active,
        overdue,
        adherence,
      };
    });

    return {
      periodDays,
      selectedRecipientId: recipientId,
      completedByDay: [...dailyMap.entries()].map(([date, count]) => ({ date, count })),
      taskTrendByDay: [...trendMap.values()],
      topCaregivers: isCareOrganizer(member)
        ? [...caregiverCounts.values()]
          .sort((lhs, rhs) => rhs.completedCount - lhs.completedCount || lhs.name.localeCompare(rhs.name))
          .slice(0, 5)
        : [],
      caregiverLoad: [...caregiverLoad.values()]
        .sort((lhs, rhs) =>
          rhs.overdueAssignedCount - lhs.overdueAssignedCount
          || rhs.activeAssignedCount - lhs.activeAssignedCount
          || rhs.completedCount - lhs.completedCount
          || lhs.name.localeCompare(rhs.name),
        ),
      escalationSummary: isCareOrganizer(member)
        ? escalationSummaryForReminders(escalatedReminders)
        : emptyEscalationSummary(),
      recipientBreakdown,
      adherence: adherenceForTasks(allTasks, { since, now }),
      totals: {
        completed: completedTasks.length,
        active: activeTasks.length,
        overdue: overdueCount,
      },
    };
  });

  // PATCH /circles/:id — admin only, update circle settings
  app.patch("/circles/:id", async (req, reply) => {
    const { userId, name, recipientName, archiveAfterDays } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;
    const normalizedDays = normalizedArchiveAfterDays(archiveAfterDays);

    const circle = await db.$transaction(async (tx) => {
      const updatedCircle = await tx.careCircle.update({
        where:   { id: req.params.id },
        data:    {
          ...(name && { name }),
          ...(recipientName && { recipientName }),
          ...(normalizedDays !== undefined && { archiveAfterDays: normalizedDays }),
        },
      });

      if (recipientName) {
        const primaryRecipient = await resolvePrimaryRecipient(tx, req.params.id);
        if (primaryRecipient) {
          await tx.careRecipient.update({
            where: { id: primaryRecipient.id },
            data: { name: recipientName },
          });
        } else {
          await tx.careRecipient.create({
            data: {
              circleId: req.params.id,
              name: recipientName,
              isPrimary: true,
            },
          });
        }
      }

      return tx.careCircle.findUnique({
        where: { id: updatedCircle.id },
        include: circleInclude,
      });
    });
    return circle;
  });

  // GET /circles/:id/recipients — members can view recipients
  app.get("/circles/:id/recipients", async (req, reply) => {
    const member = await assertRequestMember(db, req.params.id, req, reply);
    if (!member) return;
    const accessContext = await loadReceiverAccessContext(db, {
      circleId: req.params.id,
      member,
      userId: member.userId,
    });
    const circleMembers = await db.circleMember.findMany({ where: { circleId: req.params.id } });
    const activeRecipientAccesses = await db.careRecipientAccess.findMany({ where: { revokedAt: null } });
    return decorateRecipientsForMember(accessContext.recipients, member, circleMembers, activeRecipientAccesses);
  });

  // POST /circles/:id/recipients — admin only
  app.post("/circles/:id/recipients", async (req, reply) => {
    const { userId, name, relationship, notes, premiumIntent } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;
    if (!name?.trim()) {
      return reply.code(400).send({ error: "name is required" });
    }

    const existingRecipients = await db.careRecipient.findMany({
      where: { circleId: req.params.id },
      include: { entitlement: true },
    });
    const recipientCount = existingRecipients.length;
    const hasPremiumReceiver = existingRecipients.some((recipient) =>
      receiverEntitlementCapabilities(recipient.entitlement).hasPremium,
    );
    if (recipientCount >= 1 && (premiumIntent !== "ADD_RECEIVER" || !hasPremiumReceiver)) {
      return reply.code(402).send({
        error: "Upgrade is required to add another care receiver",
        code: "CARE_RECEIVER_LIMIT_REQUIRES_PREMIUM",
      });
    }

    const recipient = await db.$transaction(async (tx) => {
      const created = await tx.careRecipient.create({
        data: {
          circleId: req.params.id,
          name: name.trim(),
          relationship: relationship?.trim() || null,
          notes: notes?.trim() || null,
          sortOrder: recipientCount,
        },
      });
      await tx.event.create({
        data: {
          type: "RECIPIENT_ADDED",
          circleId: req.params.id,
          actorId: authenticatedUserId,
          payload: { recipientId: created.id, name: created.name },
        },
      });
      return created;
    });

    return reply.code(201).send(recipient);
  });

  // PATCH /circles/:id/recipients/:recipientId — admin only
  app.patch("/circles/:id/recipients/:recipientId", async (req, reply) => {
    const { userId, name, relationship, notes, isPrimary } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const existing = await db.careRecipient.findFirst({
      where: { id: req.params.recipientId, circleId: req.params.id },
    });
    if (!existing) return reply.code(404).send({ error: "Recipient not found" });

    const recipient = await db.$transaction(async (tx) => {
      if (isPrimary === true && !existing.isPrimary) {
        await tx.careRecipient.updateMany({
          where: { circleId: req.params.id },
          data: { isPrimary: false },
        });
      }
      const updated = await tx.careRecipient.update({
        where: { id: req.params.recipientId },
        data: {
          ...(name !== undefined && { name: name.trim() }),
          ...(relationship !== undefined && { relationship: relationship?.trim() || null }),
          ...(notes !== undefined && { notes: notes?.trim() || null }),
          ...(isPrimary === true && { isPrimary: true }),
        },
      });

      if (updated.isPrimary && name?.trim()) {
        await tx.careCircle.update({
          where: { id: req.params.id },
          data: { recipientName: updated.name },
        });
      }

      await tx.event.create({
        data: {
          type: "RECIPIENT_UPDATED",
          circleId: req.params.id,
          actorId: authenticatedUserId,
          payload: { recipientId: updated.id },
        },
      });

      return updated;
    });

    return recipient;
  });

  // POST /circles/:id/recipients/:recipientId/proxy-activate — admin only
  app.post("/circles/:id/recipients/:recipientId/proxy-activate", async (req, reply) => {
    const { userId, authorizationAttested, consentDocumentReference } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;
    if (authorizationAttested !== true) {
      return reply.code(400).send({ error: "Proxy activation requires explicit authorization attestation" });
    }
    const normalizedConsentReference = typeof consentDocumentReference === "string"
      ? consentDocumentReference.trim()
      : "";
    if (normalizedConsentReference.length > 120) {
      return reply.code(400).send({ error: "Consent reference must be 120 characters or less" });
    }

    const existing = await db.careRecipient.findFirst({
      where: { id: req.params.recipientId, circleId: req.params.id },
    });
    if (!existing) return reply.code(404).send({ error: "Recipient not found" });
    if (existing.activationStatus === "ACTIVE" && existing.receiverUserId) {
      return reply.code(409).send({ error: "Care receiver already joined directly" });
    }
    if (existing.activationStatus === "PROXY_ACTIVE") {
      return reply.code(409).send({ error: "Care receiver is already proxy-activated" });
    }

    const recipient = await db.$transaction(async (tx) => {
      const updated = await tx.careRecipient.update({
        where: { id: req.params.recipientId },
        data: activationForProxyReceiver({
          attestedById: authenticatedUserId,
          documentReference: normalizedConsentReference || null,
        }),
      });

      await tx.event.create({
        data: {
          type: "RECIPIENT_UPDATED",
          circleId: req.params.id,
          actorId: authenticatedUserId,
          payload: {
            recipientId: updated.id,
            activationStatus: updated.activationStatus,
            proxyActivated: true,
            authorizationAttested: true,
            hasConsentDocumentReference: Boolean(updated.consentDocumentReference),
          },
        },
      });

      return updated;
    });

    return recipient;
  });

  // PUT /circles/:id/recipients/:recipientId/entitlement — admin-only premium sync
  app.put("/circles/:id/recipients/:recipientId/entitlement", async (req, reply) => {
    const {
      userId,
      source,
      status,
      expiresAt,
      appleOriginalTransactionId,
      appleProductId,
    } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const normalizedSource = source ?? "APP_STORE";
    if (!ENTITLEMENT_SOURCES.has(normalizedSource)) {
      return reply.code(400).send({ error: "source must be APP_STORE or MANUAL" });
    }
    if (normalizedSource === "APP_STORE" && (!appleOriginalTransactionId || !appleProductId)) {
      return reply.code(400).send({ error: "App Store entitlements require appleOriginalTransactionId and appleProductId" });
    }
    if (normalizedSource === "APP_STORE" && !isSupportedReceiverPremiumProductId(appleProductId)) {
      return reply.code(400).send({ error: "Unsupported App Store premium product" });
    }
    const normalizedStatus = status ?? RECEIVER_ENTITLEMENT_STATUS.ACTIVE;
    if (!isSupportedReceiverEntitlementStatus(normalizedStatus)) {
      return reply.code(400).send({ error: "status must be a supported receiver entitlement status" });
    }
    if (normalizedSource === "MANUAL" && !ACTIVE_ENTITLEMENT_STATUSES.has(normalizedStatus)) {
      return reply.code(400).send({ error: "Manual entitlements can only be synced as ACTIVE" });
    }

    const recipient = await db.careRecipient.findFirst({
      where: { id: req.params.recipientId, circleId: req.params.id },
      include: { entitlement: true },
    });
    if (!recipient) return reply.code(404).send({ error: "Recipient not found" });

    let expirationDate = null;
    if (expiresAt) {
      expirationDate = new Date(expiresAt);
      if (Number.isNaN(expirationDate.getTime())) {
        return reply.code(400).send({ error: "expiresAt must be a valid ISO8601 date" });
      }
    }

    let verification = { verified: false };
    if (normalizedSource === "APP_STORE") {
      try {
        verification = await verifyAppStoreTransaction({
          transactionId: appleOriginalTransactionId,
          expectedProductId: appleProductId,
          expectedOriginalTransactionId: appleOriginalTransactionId,
        });
      } catch (error) {
        if (error instanceof AppStoreVerificationError) {
          return reply.code(error.statusCode ?? 400).send({ error: error.message, code: error.code });
        }
        throw error;
      }

      if (verification.verified) {
        expirationDate = verification.transaction.expiresAt ?? expirationDate;
      }
    }

    const updatedRecipient = await db.$transaction(async (tx) => {
      const payload = {
        status: verification.verified ? verification.transaction.status : normalizedStatus,
        source: normalizedSource,
        startsAt: recipient.entitlement?.startsAt ?? new Date(),
        expiresAt: expirationDate,
        purchasedById: authenticatedUserId,
        appleOriginalTransactionId: appleOriginalTransactionId ?? null,
        appleProductId: appleProductId ?? null,
      };

      if (recipient.entitlement) {
        await tx.careRecipientEntitlement.update({
          where: { recipientId: recipient.id },
          data: payload,
        });
      } else {
        await tx.careRecipientEntitlement.create({
          data: {
            recipientId: recipient.id,
            ...payload,
          },
        });
      }

      await tx.event.create({
        data: {
          type: "RECIPIENT_UPDATED",
          circleId: req.params.id,
          actorId: authenticatedUserId,
          payload: {
            recipientId: recipient.id,
            entitlementStatus: verification.verified ? verification.transaction.status : normalizedStatus,
            appleProductId: appleProductId ?? null,
            appStoreVerified: verification.verified === true,
          },
        },
      });

      return tx.careRecipient.findUnique({
        where: { id: recipient.id },
        include: { entitlement: true },
      });
    });

    return recipientSummary(updatedRecipient);
  });

  // POST /circles/:id/recipients/:recipientId/premium-requests — caregivers can request organizer upgrade
  app.post("/circles/:id/recipients/:recipientId/premium-requests", async (req, reply) => {
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    const member = await assertRequestMember(db, req.params.id, req, reply);
    if (!member) return;
    if (member.role !== "MEMBER") {
      return reply.code(403).send({ error: "Only caregivers can request a premium upgrade" });
    }

    const accessContext = await loadReceiverAccessContext(db, {
      circleId: req.params.id,
      member,
      userId: authenticatedUserId,
    });
    if (!accessContext.recipientIds.has(req.params.recipientId)) {
      return reply.code(404).send({ error: "Recipient not found" });
    }

    try {
      const request = await db.$transaction(async (tx) => {
        const created = await tx.premiumUpgradeRequest.create({
          data: {
            circleId: req.params.id,
            recipientId: req.params.recipientId,
            requesterUserId: authenticatedUserId,
          },
          include: {
            recipient: { select: { id: true, name: true } },
            requester: { select: { id: true, name: true, email: true } },
          },
        });
        await tx.event.create({
          data: {
            type: "APP_SESSION",
            circleId: req.params.id,
            actorId: authenticatedUserId,
            payload: {
              action: "PREMIUM_UPGRADE_REQUESTED",
              recipientId: req.params.recipientId,
            },
          },
        });
        return created;
      });
      return reply.code(201).send(request);
    } catch (err) {
      if ((err instanceof Prisma.PrismaClientKnownRequestError || err?.code === "P2002") && err.code === "P2002") {
        return reply.code(409).send({
          error: "You already requested premium for this care receiver",
          code: "PREMIUM_REQUEST_ALREADY_SENT",
        });
      }
      throw err;
    }
  });

  // GET /circles/:id/premium-requests — admins see collapsed recent request summaries
  app.get("/circles/:id/premium-requests", async (req, reply) => {
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;
    const requests = await db.premiumUpgradeRequest.findMany({
      where: {
        circleId: req.params.id,
        createdAt: { gte: premiumRequestCutoff() },
      },
      include: {
        recipient: { select: { id: true, name: true } },
        requester: { select: { id: true, name: true, email: true } },
      },
      orderBy: { createdAt: "desc" },
    });
    return summarizePremiumRequests(requests);
  });

  // POST /circles/:id/recipients/reorder — admin only
  app.post("/circles/:id/recipients/reorder", async (req, reply) => {
    const { userId, recipientIds, primaryRecipientId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;
    if (!Array.isArray(recipientIds) || recipientIds.length === 0) {
      return reply.code(400).send({ error: "recipientIds must be a non-empty array" });
    }

    const recipients = await db.careRecipient.findMany({
      where: { circleId: req.params.id },
      orderBy: [{ isPrimary: "desc" }, { sortOrder: "asc" }, { createdAt: "asc" }],
    });
    const existingIds = recipients.map((recipient) => recipient.id).sort();
    const requestedIds = [...recipientIds].sort();
    if (existingIds.length !== requestedIds.length || existingIds.some((id, index) => id !== requestedIds[index])) {
      return reply.code(400).send({ error: "recipientIds must include every recipient in the circle exactly once" });
    }

    const nextPrimaryId = primaryRecipientId && recipientIds.includes(primaryRecipientId)
      ? primaryRecipientId
      : recipientIds[0];

    await db.$transaction(async (tx) => {
      for (const [index, recipientId] of recipientIds.entries()) {
        await tx.careRecipient.update({
          where: { id: recipientId },
          data: {
            sortOrder: index,
            isPrimary: recipientId === nextPrimaryId,
          },
        });
      }

      const primaryRecipient = await tx.careRecipient.findUnique({ where: { id: nextPrimaryId } });
      if (primaryRecipient) {
        await tx.careCircle.update({
          where: { id: req.params.id },
          data: { recipientName: primaryRecipient.name },
        });
      }

      await tx.event.create({
        data: {
          type: "RECIPIENT_UPDATED",
          circleId: req.params.id,
          actorId: authenticatedUserId,
          payload: { recipientIds, primaryRecipientId: nextPrimaryId },
        },
      });
    });

    return db.careRecipient.findMany({
      where: { circleId: req.params.id },
      orderBy: [{ isPrimary: "desc" }, { sortOrder: "asc" }, { createdAt: "asc" }],
    });
  });

  // DELETE /circles/:id/recipients/:recipientId — admin only
  app.delete("/circles/:id/recipients/:recipientId", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const recipient = await db.careRecipient.findFirst({
      where: { id: req.params.recipientId, circleId: req.params.id },
    });
    if (!recipient) return reply.code(404).send({ error: "Recipient not found" });

    const [recipientCount, recipientTaskCount] = await Promise.all([
      db.careRecipient.count({ where: { circleId: req.params.id } }),
      db.task.count({ where: { circleId: req.params.id, recipientId: req.params.recipientId, archivedAt: null } }),
    ]);

    if (recipientCount <= 1) {
      return reply.code(400).send({ error: "Every circle must keep at least one care recipient." });
    }
    if (recipientTaskCount > 0) {
      return reply.code(400).send({ error: "Move or archive this recipient's tasks before removing them." });
    }

    await db.$transaction(async (tx) => {
      await tx.careRecipient.delete({ where: { id: req.params.recipientId } });

      if (recipient.isPrimary) {
        const replacement = await tx.careRecipient.findFirst({
          where: { circleId: req.params.id },
          orderBy: [{ sortOrder: "asc" }, { createdAt: "asc" }],
        });
        if (replacement) {
          await tx.careRecipient.update({
            where: { id: replacement.id },
            data: { isPrimary: true },
          });
          await tx.careCircle.update({
            where: { id: req.params.id },
            data: { recipientName: replacement.name },
          });
        }
      }

      await tx.event.create({
        data: {
          type: "RECIPIENT_REMOVED",
          circleId: req.params.id,
          actorId: authenticatedUserId,
          payload: { recipientId: req.params.recipientId },
        },
      });
    });

    return reply.code(204).send();
  });

  // DELETE /circles/:id — admin only
  app.delete("/circles/:id", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    await db.careCircle.delete({ where: { id: req.params.id } });
    return reply.code(204).send();
  });

  // DELETE /circles/:id/members/me — authenticated self-leave
  app.delete("/circles/:id/members/me", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;

    const member = await db.circleMember.findUnique({
      where: { userId_circleId: { userId: authenticatedUserId, circleId: req.params.id } },
    });
    if (!member) return reply.code(404).send({ error: "Member not found" });
    if (member.role === "RECIPIENT") {
      return reply.code(403).send({ error: "Care receivers cannot leave from this screen" });
    }
    if (member.role === "ADMIN") {
      const adminCount = await db.circleMember.count({
        where: { circleId: req.params.id, role: "ADMIN" },
      });
      if (adminCount <= 1) {
        return reply.code(400).send({ error: "Cannot leave as the last admin" });
      }
    }

    await db.circleMember.delete({ where: { id: member.id } });
    await logEvent(db, {
      type: "MEMBER_REMOVED",
      circleId: req.params.id,
      actorId: authenticatedUserId,
      payload: { memberId: member.id, selfRemoved: true },
    });
    return reply.code(204).send();
  });

  // POST /circles/:id/members — authenticated self-join
  app.post("/circles/:id/members", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;

    const [user, circle] = await Promise.all([
      db.user.findUnique({ where: { id: authenticatedUserId } }),
      db.careCircle.findUnique({ where: { id: req.params.id } }),
    ]);
    if (!user)   return reply.code(404).send({ error: "User not found" });
    if (!circle) return reply.code(404).send({ error: "Circle not found" });

    const existing = await db.circleMember.findUnique({
      where: { userId_circleId: { userId: authenticatedUserId, circleId: req.params.id } },
    });
    if (existing) return reply.code(409).send({ error: "User is already a member" });
    if (!await ensureCircleCapacity(authenticatedUserId, reply)) return;

    try {
      const member = await db.circleMember.create({
        data: { circleId: req.params.id, userId: authenticatedUserId, role: "MEMBER" },
      });
      await logEvent(db, { type: "MEMBER_JOINED", circleId: req.params.id, actorId: authenticatedUserId, payload: { userId: authenticatedUserId } });
      return reply.code(201).send(member);
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002")
        return reply.code(409).send({ error: "User is already a member" });
      throw err;
    }
  });

  // GET /circles/:id/invitations — admin only
  app.get("/circles/:id/invitations", async (req, reply) => {
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const requestedStatus = String(req.query?.status ?? "PENDING").toUpperCase();
    const status = ["PENDING", "ACCEPTED", "DECLINED", "REVOKED", "EXPIRED"].includes(requestedStatus)
      ? requestedStatus
      : "PENDING";
    const pagination = parseCursorPagination(req.query);

    const invitations = await db.invitation.findMany({
      where: { circleId: req.params.id, status },
      include: invitationInclude,
      orderBy: invitationOrder,
      ...prismaCursorWindow(pagination),
    });
    return pageResponse(invitations, pagination);
  });

  // POST /circles/:id/members/invite — admin invite by email, membership created on acceptance
  app.post("/circles/:id/members/invite", async (req, reply) => {
    const { userId, email, name, role, recipientId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const normalizedEmail = normalizeEmail(email);
    const normalizedRole = String(role ?? "MEMBER").toUpperCase();
    if (!normalizedEmail || !name?.trim()) {
      return reply.code(400).send({ error: "name and email are required" });
    }
    if (!["ADMIN", "MEMBER", "RECIPIENT"].includes(normalizedRole)) {
      return reply.code(400).send({ error: "role must be ADMIN, MEMBER, or RECIPIENT" });
    }

    const circle = await db.careCircle.findUnique({ where: { id: req.params.id } });
    if (!circle) return reply.code(404).send({ error: "Circle not found" });

    let invitedRecipient = null;
    if (recipientId !== undefined) {
      if (normalizedRole !== "RECIPIENT") {
        return reply.code(400).send({ error: "recipientId can only be used for care receiver invitations" });
      }
      invitedRecipient = await db.careRecipient.findFirst({
        where: { id: recipientId, circleId: req.params.id },
      });
      if (!invitedRecipient) {
        return reply.code(404).send({ error: "Care receiver not found" });
      }
      if (invitedRecipient.receiverUserId) {
        return reply.code(409).send({ error: "Care receiver already has an account" });
      }
      if (invitedRecipient.activationStatus === "PROXY_ACTIVE") {
        return reply.code(409).send({ error: "Care receiver is already proxy-activated" });
      }
    }

    const existingUser = await db.user.findUnique({ where: { email: normalizedEmail } });
    if (existingUser) {
      const existingMembership = await db.circleMember.findUnique({
        where: { userId_circleId: { userId: existingUser.id, circleId: req.params.id } },
      });
      if (existingMembership) {
        return reply.code(409).send({ error: "User is already a member" });
      }
    }

    const existingPending = await db.invitation.findFirst({
      where: { circleId: req.params.id, email: normalizedEmail, status: "PENDING" },
    });
    if (existingPending) {
      if (invitationHasExpired(existingPending)) {
        await db.$transaction((tx) => markInvitationExpired(tx, existingPending));
      } else {
        return reply.code(409).send({ error: "A pending invitation already exists for this email" });
      }
    }

    const invitation = await db.$transaction(async (tx) => {
      const created = await tx.invitation.create({
        data: {
          circleId: req.params.id,
          email: normalizedEmail,
          name: name.trim(),
          role: normalizedRole,
          recipientId: invitedRecipient?.id ?? null,
          invitedById: authenticatedUserId,
          expiresAt: invitationExpiryDate(),
        },
      });

      if (invitedRecipient && invitedRecipient.activationStatus === "DRAFT") {
        await tx.careRecipient.update({
          where: { id: invitedRecipient.id },
          data: { activationStatus: "INVITED" },
        });
      }

      await tx.event.create({
        data: {
          type: "INVITE_CREATED",
          circleId: req.params.id,
          actorId: authenticatedUserId,
          payload: {
            invitationId: created.id,
            email: normalizedEmail,
            role: normalizedRole,
            recipientId: invitedRecipient?.id ?? null,
          },
        },
      });

      return tx.invitation.findUnique({
        where: { id: created.id },
        include: invitationInclude,
      });
    });

    return reply.code(201).send(invitation);
  });

  // POST /circles/:id/invitations/:inviteId/resend — admin only, extends a pending invite
  app.post("/circles/:id/invitations/:inviteId/resend", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const invitation = await db.invitation.findUnique({ where: { id: req.params.inviteId } });
    if (!invitation || invitation.circleId !== req.params.id) {
      return reply.code(404).send({ error: "Invitation not found" });
    }
    if (invitation.status !== "PENDING") {
      return reply.code(409).send({ error: "Only pending invitations can be resent" });
    }

    const resent = await db.$transaction(async (tx) => {
      const updated = await tx.invitation.update({
        where: { id: req.params.inviteId },
        data: { expiresAt: invitationExpiryDate() },
        include: invitationInclude,
      });
      await tx.event.create({
        data: {
          type: "INVITE_CREATED",
          circleId: req.params.id,
          actorId: authenticatedUserId,
          payload: {
            invitationId: req.params.inviteId,
            email: invitation.email,
            role: invitation.role,
            recipientId: invitation.recipientId ?? null,
            action: "RESENT",
          },
        },
      });
      return updated;
    });

    return resent;
  });

  // DELETE /circles/:id/invitations/:inviteId — admin only
  app.delete("/circles/:id/invitations/:inviteId", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const invitation = await db.invitation.findUnique({ where: { id: req.params.inviteId } });
    if (!invitation || invitation.circleId !== req.params.id) {
      return reply.code(404).send({ error: "Invitation not found" });
    }
    if (invitation.status !== "PENDING") {
      return reply.code(409).send({ error: "Only pending invitations can be revoked" });
    }
    if (invitationHasExpired(invitation)) {
      await db.$transaction((tx) => markInvitationExpired(tx, invitation));
      return reply.code(409).send({ error: "Invitation has expired" });
    }

    await db.$transaction(async (tx) => {
      await tx.invitation.update({
        where: { id: req.params.inviteId },
        data: { status: "REVOKED" },
      });
      await resetRecipientInviteStateIfUnclaimed(tx, invitation.recipientId);
      await tx.event.create({
        data: {
          type: "INVITE_REVOKED",
          circleId: req.params.id,
          actorId: authenticatedUserId,
          payload: { invitationId: req.params.inviteId },
        },
      });
    });

    return reply.code(204).send();
  });

  // DELETE /circles/:id/members/:memberId — admin only
  app.delete("/circles/:id/members/:memberId", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const target = await db.circleMember.findUnique({ where: { id: req.params.memberId } });
    if (!target || target.circleId !== req.params.id)
      return reply.code(404).send({ error: "Member not found" });

    if (target.role === "ADMIN") {
      const adminCount = await db.circleMember.count({
        where: { circleId: req.params.id, role: "ADMIN" },
      });
      if (adminCount <= 1)
        return reply.code(400).send({ error: "Cannot remove the last admin" });
    }

    await db.circleMember.delete({ where: { id: req.params.memberId } });
    await logEvent(db, { type: "MEMBER_REMOVED", circleId: req.params.id, actorId: authenticatedUserId, payload: { memberId: req.params.memberId } });
    return reply.code(204).send();
  });

  // PATCH /circles/:id/members/:memberId/role — admin only, prevent last admin demotion
  app.patch("/circles/:id/members/:memberId/role", async (req, reply) => {
    const { userId, role } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!role || !["ADMIN", "MEMBER"].includes(role))
      return reply.code(400).send({ error: "role must be ADMIN or MEMBER" });
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const target = await db.circleMember.findUnique({ where: { id: req.params.memberId } });
    if (!target || target.circleId !== req.params.id)
      return reply.code(404).send({ error: "Member not found" });

    if (role === "MEMBER" && target.role === "ADMIN") {
      const adminCount = await db.circleMember.count({
        where: { circleId: req.params.id, role: "ADMIN" },
      });
      if (adminCount <= 1)
        return reply.code(400).send({ error: "Cannot demote the last admin" });
    }

    const updated = await db.circleMember.update({
      where: { id: req.params.memberId },
      data:  { role },
    });
    await logEvent(db, {
      type: "MEMBER_ROLE_UPDATED",
      circleId: req.params.id,
      actorId: authenticatedUserId,
      payload: { memberId: req.params.memberId, role },
    });
    return updated;
  });

  // GET /circles/:id/members/:memberId/recipient-access — admin only
  app.get("/circles/:id/members/:memberId/recipient-access", async (req, reply) => {
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;
    const caregiver = await caregiverMemberOrReply(req.params.id, req.params.memberId, reply);
    if (!caregiver) return;

    const [recipients, grants] = await Promise.all([
      db.careRecipient.findMany({
        where: { circleId: req.params.id },
        orderBy: [{ isPrimary: "desc" }, { sortOrder: "asc" }, { createdAt: "asc" }],
      }),
      db.careRecipientAccess.findMany({
        where: { memberId: caregiver.id, revokedAt: null },
      }),
    ]);
    const grantByRecipientId = new Map(grants.map((grant) => [grant.recipientId, grant]));
    return recipients.map((recipient) => ({
      recipientId: recipient.id,
      name: recipient.name,
      activationStatus: recipient.activationStatus,
      hasAccess: grantByRecipientId.has(recipient.id),
      grantedAt: grantByRecipientId.get(recipient.id)?.grantedAt ?? null,
    }));
  });

  // PUT /circles/:id/members/:memberId/recipient-access/:recipientId — admin only
  app.put("/circles/:id/members/:memberId/recipient-access/:recipientId", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const caregiver = await caregiverMemberOrReply(req.params.id, req.params.memberId, reply);
    if (!caregiver) return;
    const recipient = await db.careRecipient.findFirst({
      where: { id: req.params.recipientId, circleId: req.params.id },
      include: { entitlement: true },
    });
    if (!recipient) return reply.code(404).send({ error: "Care receiver not found" });

    const [existingGrant] = await db.careRecipientAccess.findMany({
      where: { memberId: caregiver.id, recipientId: recipient.id },
    });
    const caregiverLimit = maxCaregiversForReceiver(recipient.entitlement);
    if (caregiverLimit !== null && (!existingGrant || existingGrant.revokedAt)) {
      const activeGrantCount = await db.careRecipientAccess.count({
        where: { recipientId: recipient.id, revokedAt: null },
      });
      if (activeGrantCount >= caregiverLimit) {
        return reply.code(402).send({
          error: "Upgrade this care receiver to unlock more caregiver access",
          recipientId: recipient.id,
        });
      }
    }
    let grant;
    if (existingGrant && !existingGrant.revokedAt) {
      grant = existingGrant;
    } else if (existingGrant) {
      grant = await db.careRecipientAccess.update({
        where: { id: existingGrant.id },
        data: {
          revokedAt: null,
          grantedAt: new Date(),
          grantedById: authenticatedUserId,
        },
      });
    } else {
      grant = await db.careRecipientAccess.create({
        data: {
          memberId: caregiver.id,
          recipientId: recipient.id,
          grantedById: authenticatedUserId,
        },
      });
    }

    await logEvent(db, {
      type: "RECIPIENT_ACCESS_GRANTED",
      circleId: req.params.id,
      actorId: authenticatedUserId,
      payload: { memberId: caregiver.id, recipientId: recipient.id },
    });
    return grant;
  });

  // DELETE /circles/:id/members/:memberId/recipient-access/:recipientId — admin only
  app.delete("/circles/:id/members/:memberId/recipient-access/:recipientId", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;
    if (!await assertRequestAdmin(db, req.params.id, req, reply)) return;

    const caregiver = await caregiverMemberOrReply(req.params.id, req.params.memberId, reply);
    if (!caregiver) return;
    const recipient = await db.careRecipient.findFirst({
      where: { id: req.params.recipientId, circleId: req.params.id },
    });
    if (!recipient) return reply.code(404).send({ error: "Care receiver not found" });

    const [existingGrant] = await db.careRecipientAccess.findMany({
      where: { memberId: caregiver.id, recipientId: recipient.id, revokedAt: null },
    });
    if (!existingGrant) return reply.code(404).send({ error: "Receiver access grant not found" });

    await db.careRecipientAccess.update({
      where: { id: existingGrant.id },
      data: { revokedAt: new Date() },
    });
    await logEvent(db, {
      type: "RECIPIENT_ACCESS_REVOKED",
      circleId: req.params.id,
      actorId: authenticatedUserId,
      payload: { memberId: caregiver.id, recipientId: recipient.id },
    });
    return reply.code(204).send();
  });

  // POST /invitations/:inviteId/accept — authenticated user accepts own pending invite
  app.post("/invitations/:inviteId/accept", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;

    const [user, invitation] = await Promise.all([
      db.user.findUnique({ where: { id: authenticatedUserId } }),
      findInvitationOr404(req.params.inviteId, reply),
    ]);
    if (!invitation) return;
    if (!user) return reply.code(404).send({ error: "User not found" });
    if (normalizeEmail(user.email) !== invitation.email) {
      return reply.code(403).send({ error: "Invitation email does not match the authenticated user" });
    }

    const existingMembership = await db.circleMember.findUnique({
      where: { userId_circleId: { userId: authenticatedUserId, circleId: invitation.circleId } },
      include: { user: { select: { id: true, name: true, email: true } } },
    });
    if (existingMembership) {
      return reply.code(409).send({ error: "User is already a member" });
    }

    if (invitation.status !== "PENDING") {
      return reply.code(409).send({ error: `Invitation is already ${invitation.status.toLowerCase()}` });
    }
    if (invitationHasExpired(invitation)) {
      await db.$transaction((tx) => markInvitationExpired(tx, invitation));
      return reply.code(409).send({ error: "Invitation has expired" });
    }
    if (!await ensureCircleCapacity(authenticatedUserId, reply)) return;

    const member = await db.$transaction(async (tx) => {
      const created = await tx.circleMember.create({
        data: { circleId: invitation.circleId, userId: authenticatedUserId, role: invitation.role },
      });

      if (invitation.role === "RECIPIENT") {
        if (invitation.recipientId) {
          await tx.careRecipient.update({
            where: { id: invitation.recipientId },
            data: activationForAcceptedReceiver(authenticatedUserId),
          });
        } else {
          const existing = await tx.careRecipient.findFirst({
            where: { circleId: invitation.circleId },
            orderBy: [{ isPrimary: "desc" }, { sortOrder: "asc" }, { createdAt: "asc" }],
          });
          const isPrimary = !existing;
          await tx.careRecipient.create({
            data: {
              circleId: invitation.circleId,
              name: user.name,
              isPrimary,
              ...activationForAcceptedReceiver(authenticatedUserId),
            },
          });
        }
      }

      await tx.invitation.update({
        where: { id: invitation.id },
        data: {
          status: "ACCEPTED",
          acceptedAt: new Date(),
          acceptedById: authenticatedUserId,
        },
      });
      await tx.event.create({
        data: {
          type: "INVITE_ACCEPTED",
          circleId: invitation.circleId,
          actorId: authenticatedUserId,
          payload: { invitationId: invitation.id, role: invitation.role },
        },
      });
      await tx.event.create({
        data: {
          type: "MEMBER_JOINED",
          circleId: invitation.circleId,
          actorId: authenticatedUserId,
          payload: { userId: authenticatedUserId, invitationId: invitation.id, role: invitation.role },
        },
      });
      return tx.circleMember.findUnique({
        where: { id: created.id },
        include: { user: { select: { id: true, name: true, email: true } } },
      });
    });

    return reply.code(201).send(member);
  });

  // POST /invitations/:inviteId/decline — authenticated user declines own pending invite
  app.post("/invitations/:inviteId/decline", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (rejectUserMismatch(userId, authenticatedUserId, reply)) return;

    const [user, invitation] = await Promise.all([
      db.user.findUnique({ where: { id: authenticatedUserId } }),
      findInvitationOr404(req.params.inviteId, reply),
    ]);
    if (!invitation) return;
    if (!user) return reply.code(404).send({ error: "User not found" });
    if (normalizeEmail(user.email) !== invitation.email) {
      return reply.code(403).send({ error: "Invitation email does not match the authenticated user" });
    }
    if (invitation.status !== "PENDING") {
      return reply.code(409).send({ error: `Invitation is already ${invitation.status.toLowerCase()}` });
    }
    if (invitationHasExpired(invitation)) {
      await db.$transaction((tx) => markInvitationExpired(tx, invitation));
      return reply.code(409).send({ error: "Invitation has expired" });
    }

    await db.$transaction(async (tx) => {
      await tx.invitation.update({
        where: { id: invitation.id },
        data: { status: "DECLINED" },
      });
      await resetRecipientInviteStateIfUnclaimed(tx, invitation.recipientId);
      await tx.event.create({
        data: {
          type: "INVITE_DECLINED",
          circleId: invitation.circleId,
          actorId: authenticatedUserId,
          payload: { invitationId: invitation.id },
        },
      });
    });

    return reply.send({ declined: true });
  });

  // GET /circles/:circleId/events
  app.get("/circles/:circleId/events", async (req, reply) => {
    const member = await assertRequestMember(db, req.params.circleId, req, reply);
    if (!member) return;
    const pagination = parseCursorPagination(req.query);
    const eventWindow = pagination.enabled ? prismaCursorWindow(pagination, isCareOrganizer(member) ? 1 : 4) : { take: 100 };
    const [events, tasks, accessContext] = await Promise.all([
      db.event.findMany({
        where:   { circleId: req.params.circleId },
        orderBy: eventOrder,
        ...eventWindow,
        include: { actor: { select: { id: true, name: true } } },
      }),
      db.task.findMany({
        where: { circleId: req.params.circleId, archivedAt: null },
        orderBy: taskActivityOrder,
      }),
      loadReceiverAccessContext(db, {
        circleId: req.params.circleId,
        member,
        userId: member.userId,
      }),
    ]);
    if (isCareOrganizer(member)) return pageResponse(events, pagination);
    const visibleTaskIds = new Set(
      filterVisibleTasks(tasks, { member, userId: member.userId, accessContext }).map((task) => task.id),
    );
    return pageResponse(
      events.filter((event) => eventVisibleToMember(event, member, accessContext, visibleTaskIds)),
      pagination,
    );
  });
}
