import { randomUUID } from "node:crypto";
import { assertRequestMember, logEvent, requireAuthenticatedUser } from "../lib/roles.js";
import { deliverTaskNotification } from "../lib/push.js";
import {
  isRecurringTask,
  isTerminalTaskStatus,
  nextDueAtForTask,
  normalizeRecurrenceInput,
  recurrenceFields,
} from "../lib/recurrence.js";
import { canCreateTasksForReceiver } from "../lib/receiver-state.js";
import { pageResponse, parseCursorPagination, prismaCursorWindow } from "../lib/pagination.js";
import {
  canCreateTaskWithAccess,
  eligibleAssigneeUserIdsForReceiver,
  filterVisibleTasks,
  isCareOrganizer,
  isCareReceiver,
  loadReceiverAccessContext,
  taskCapabilities,
} from "../lib/access.js";
import { receiverEntitlementCapabilities } from "../lib/entitlements.js";

const taskInclude = {
  assignee: { select: { id: true, email: true, name: true, phone: true, pushToken: true, timezone: true } },
  completedBy: { select: { id: true, name: true, email: true } },
  recipient: { select: { id: true, name: true, relationship: true, notes: true, isPrimary: true, sortOrder: true } },
  circle: { select: { id: true, name: true } },
};
const SNOOZE_OPTIONS_MINUTES = new Set([15, 60, 1440]);
const MAX_REMINDER_SNOOZES = 3;
const taskListOrder = [{ completedAt: "asc" }, { dueAt: "asc" }, { createdAt: "desc" }, { id: "desc" }];

function parseOptionalDate(value, fieldName) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`${fieldName} must be a valid ISO8601 date`);
  }
  return date;
}

function completionStateForStatus(nextStatus) {
  if (nextStatus === "DONE" || nextStatus === "SKIPPED") {
    return new Date();
  }
  return null;
}

function nextSeriesScope(raw) {
  return String(raw ?? "THIS_OCCURRENCE").toUpperCase() === "SERIES"
    ? "SERIES"
    : "THIS_OCCURRENCE";
}

function createHttpError(message, statusCode = 400) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function syncReminderForTask(tx, taskId, dueAt) {
  if (dueAt) {
    const scheduledAt = new Date(dueAt.getTime() - 15 * 60 * 1000);
    const existingReminder = await tx.reminder.findFirst({ where: { taskId } });
    if (existingReminder) {
      await tx.reminder.update({
        where: { id: existingReminder.id },
        data: {
          scheduledAt,
          status: "PENDING",
          sentAt: null,
          snoozedUntil: null,
          snoozeCount: 0,
          escalationDueAt: null,
          escalatedAt: null,
        },
      });
    } else {
      await tx.reminder.create({ data: { taskId, scheduledAt } });
    }
    return;
  }

  await tx.reminder.deleteMany({ where: { taskId } });
}

function canSnoozeTaskReminder({ member, task, userId }) {
  if (member.role === "ADMIN") return true;
  return task.assigneeId === userId || task.creatorId === userId;
}

function reminderSummary(reminder) {
  return {
    id: reminder.id,
    taskId: reminder.taskId,
    scheduledAt: reminder.scheduledAt,
    sentAt: reminder.sentAt ?? null,
    snoozedUntil: reminder.snoozedUntil ?? null,
    snoozeCount: reminder.snoozeCount ?? 0,
    escalationDueAt: reminder.escalationDueAt ?? null,
    status: reminder.status,
    escalatedAt: reminder.escalatedAt ?? null,
  };
}

async function createTaskRecord(tx, data) {
  const task = await tx.task.create({
    data,
    include: taskInclude,
  });

  await syncReminderForTask(tx, task.id, task.dueAt);
  return task;
}

async function ensureNextRecurringOccurrence(tx, task) {
  const nextDueAt = nextDueAtForTask(task);
  if (!nextDueAt || !task.seriesId) return null;

  const existing = await tx.task.findFirst({
    where: {
      seriesId: task.seriesId,
      dueAt: nextDueAt,
    },
  });
  if (existing) return existing;

  return createTaskRecord(tx, {
    title: task.title,
    notes: task.notes,
    dueAt: nextDueAt,
    priority: task.priority,
    recipientId: task.recipientId,
    recurrenceFrequency: task.recurrenceFrequency,
    recurrenceInterval: task.recurrenceInterval,
    recurrenceWeekdays: task.recurrenceWeekdays ?? [],
    recurrenceEndsAt: task.recurrenceEndsAt ?? null,
    seriesId: task.seriesId,
    circleId: task.circleId,
    creatorId: task.creatorId,
    assigneeId: task.assigneeId ?? null,
  });
}

export default async function tasks(app) {
  const db = app.db;

  async function assignmentContextForMember(dbLike, circleId, member, userId) {
    const [accessContext, circleMembers, activeRecipientAccesses] = await Promise.all([
      loadReceiverAccessContext(dbLike, {
        circleId,
        member,
        userId,
      }),
      dbLike.circleMember.findMany({ where: { circleId } }),
      dbLike.careRecipientAccess.findMany({ where: { revokedAt: null } }),
    ]);

    return {
      ...accessContext,
      recipients: accessContext.recipients.map((recipient) => ({
        ...recipient,
        eligibleAssigneeIds: eligibleAssigneeUserIdsForReceiver({
          member,
          receiver: recipient,
          circleMembers,
          activeRecipientAccesses,
        }),
      })),
      circleMembers,
      activeRecipientAccesses,
    };
  }

  async function accessContextForMember(circleId, member) {
    return assignmentContextForMember(db, circleId, member, member.userId);
  }

  function visibleTaskWhere(circleId, member, accessContext) {
    const baseWhere = { circleId, archivedAt: null };
    if (isCareOrganizer(member)) return baseWhere;

    const recipientIds = [...accessContext.recipientIds];
    if (recipientIds.length === 0) return null;

    if (isCareReceiver(member)) {
      return {
        ...baseWhere,
        recipientId: { in: recipientIds },
        assigneeId: member.userId,
      };
    }

    const receiverUserIds = accessContext.recipients
      .map((recipient) => recipient.receiverUserId)
      .filter(Boolean);

    return {
      ...baseWhere,
      recipientId: { in: recipientIds },
      OR: [
        { creatorId: member.userId },
        { assigneeId: member.userId },
        ...(receiverUserIds.length > 0 ? [{ assigneeId: { in: receiverUserIds } }] : []),
      ],
    };
  }

  function assertAssigneeAllowed(assigneeId, receiver) {
    if (!assigneeId) {
      throw createHttpError("assigneeId is required", 400);
    }
    if (!receiver.eligibleAssigneeIds?.includes(assigneeId)) {
      throw createHttpError("You cannot assign this task to that user", 403);
    }
  }

  function decorateTaskForMember(task, member, accessContext) {
    const receiver = accessContext.recipients.find((recipient) => recipient.id === task.recipientId);
    if (!receiver) return task;
    return {
      ...task,
      recipient: task.recipient
        ? { ...task.recipient, receiverUserId: receiver.receiverUserId, eligibleAssigneeIds: receiver.eligibleAssigneeIds ?? [] }
        : receiver,
      capabilities: taskCapabilities({
        member,
        userId: member.userId,
        task,
        receiver,
        accessGrant: accessContext.accessGrantByRecipientId.get(task.recipientId) ?? null,
      }),
    };
  }

  async function findVisibleTask(circleId, taskId, member, include = taskInclude) {
    const [task, accessContext] = await Promise.all([
      db.task.findFirst({
        where: { id: taskId, circleId },
        include,
      }),
      accessContextForMember(circleId, member),
    ]);
    if (!task) return { task: null, accessContext };
    const visibleTask = filterVisibleTasks([task], {
      member,
      userId: member.userId,
      accessContext,
    })[0] ?? null;
    return {
      task: visibleTask ? decorateTaskForMember(visibleTask, member, accessContext) : null,
      accessContext,
    };
  }

  async function resolveRecipientId(tx, circleId, requestedRecipientId, assigneeId) {
    if (requestedRecipientId) {
      const recipient = await tx.careRecipient.findFirst({
        where: { id: requestedRecipientId, circleId },
      });
      if (!recipient) throw new Error("recipientId must belong to this circle");
      return recipient.id;
    }

    const primaryRecipient = await tx.careRecipient.findFirst({
      where: { circleId },
      orderBy: [{ isPrimary: "desc" }, { sortOrder: "asc" }, { createdAt: "asc" }],
    });
    if (primaryRecipient) return primaryRecipient.id;

    // No CareRecipient profile exists yet. If the assignee is a RECIPIENT member,
    // auto-create their profile so tasks can be saved without manual setup.
    if (assigneeId) {
      const assigneeMember = await tx.circleMember.findUnique({
        where: { userId_circleId: { userId: assigneeId, circleId } },
        include: { user: true },
      });
      if (assigneeMember?.role === "RECIPIENT" && assigneeMember.user) {
        return (await tx.careRecipient.create({
          data: { circleId, name: assigneeMember.user.name, isPrimary: true },
        })).id;
      }
    }

    return null;
  }

  async function assertTaskableRecipient(tx, circleId, recipientId) {
    const recipient = await tx.careRecipient.findFirst({
      where: { id: recipientId, circleId },
      include: { entitlement: true },
    });
    if (!recipient) throw new Error("recipientId must belong to this circle");
    if (!canCreateTasksForReceiver(recipient)) {
      throw new Error("Care receiver must accept or be proxy-activated before tasks can be created");
    }
    return recipient;
  }

  function assertRecurringFeatureAccess(receiver, recurrence) {
    if (!recurrence || recurrence.frequency === "NONE") return;
    if (!receiverEntitlementCapabilities(receiver.entitlement).canUseAdvancedReminders) {
      throw createHttpError("Recurring schedules require premium for this care receiver", 402);
    }
  }

  // POST /circles/:circleId/tasks
  app.post("/circles/:circleId/tasks", async (req, reply) => {
    const { title, notes, dueAt, priority, creatorId, assigneeId, recurrence, recipientId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (!title)
      return reply.code(400).send({ error: "title is required" });
    if (creatorId && creatorId !== authenticatedUserId) {
      return reply.code(403).send({ error: "creatorId must match the authenticated user" });
    }
    if (title.length > 200)
      return reply.code(400).send({ error: "title exceeds 200 characters" });
    if (notes && notes.length > 1000)
      return reply.code(400).send({ error: "notes exceeds 1000 characters" });

    const member = await assertRequestMember(db, req.params.circleId, req, reply);
    if (!member) return;

    const dueDate = parseOptionalDate(dueAt, "dueAt");
    let normalizedRecurrence;
    try {
      normalizedRecurrence = normalizeRecurrenceInput(recurrence);
    } catch (error) {
      return reply.code(400).send({ error: error.message });
    }

    if (normalizedRecurrence.frequency !== "NONE" && !dueDate) {
      return reply.code(400).send({ error: "Recurring tasks require dueAt" });
    }

    const seriesId = normalizedRecurrence.frequency === "NONE" ? null : randomUUID();

    let task;
    try {
      task = await db.$transaction(async (tx) => {
        const assignmentContext = await assignmentContextForMember(
          tx,
          req.params.circleId,
          member,
          authenticatedUserId,
        );
        const resolvedRecipientId = await resolveRecipientId(tx, req.params.circleId, recipientId, assigneeId);
        if (!resolvedRecipientId) throw new Error("recipientId is required");
        const receiverBase = await assertTaskableRecipient(tx, req.params.circleId, resolvedRecipientId);
        const receiver = assignmentContext.recipients.find((recipient) => recipient.id === resolvedRecipientId)
          ?? {
            ...receiverBase,
            eligibleAssigneeIds: eligibleAssigneeUserIdsForReceiver({
              member,
              receiver: receiverBase,
              circleMembers: assignmentContext.circleMembers,
              activeRecipientAccesses: assignmentContext.activeRecipientAccesses,
            }),
          };
        if (!canCreateTaskWithAccess({ member, receiver, accessContext: assignmentContext })) {
          throw createHttpError("You do not have access to create tasks for this care receiver", 403);
        }
        assertRecurringFeatureAccess(receiver, normalizedRecurrence);
        assertAssigneeAllowed(assigneeId, receiver);

        const createdTask = await createTaskRecord(tx, {
          title,
          notes: notes ?? null,
          priority: priority ?? "NORMAL",
          dueAt: dueDate,
          circleId: req.params.circleId,
          recipientId: resolvedRecipientId,
          creatorId: authenticatedUserId,
          assigneeId: assigneeId ?? null,
          ...recurrenceFields(normalizedRecurrence, seriesId),
        });

        if (seriesId) {
          await tx.event.create({
            data: {
              type: "TASK_SERIES_CREATED",
              circleId: req.params.circleId,
              actorId: authenticatedUserId,
              payload: {
                seriesId,
                taskId: createdTask.id,
                frequency: normalizedRecurrence.frequency,
              },
            },
          });
        }

        await tx.event.create({
          data: { type: "TASK_CREATED", circleId: req.params.circleId, actorId: authenticatedUserId, payload: { taskId: createdTask.id, title } },
        });

        return decorateTaskForMember(createdTask, member, assignmentContext);
      });
    } catch (error) {
      return reply.code(error.statusCode ?? 400).send({ error: error.message });
    }

    if (task.assigneeId) {
      const assigneeMember = await db.circleMember.findUnique({
        where: { userId_circleId: { userId: task.assigneeId, circleId: task.circleId } },
        select: { role: true },
      });
      const notifType = assigneeMember?.role === "RECIPIENT" ? "recipientAssignment" : "assignment";
      await deliverTaskNotification({ db, userId: task.assigneeId, task, type: notifType });
    }

    return reply.code(201).send(task);
  });

  // GET /circles/:circleId/tasks
  app.get("/circles/:circleId/tasks", async (req, reply) => {
    const member = await assertRequestMember(db, req.params.circleId, req, reply);
    if (!member) return;
    const pagination = parseCursorPagination(req.query);
    const accessContext = await accessContextForMember(req.params.circleId, member);
    const where = visibleTaskWhere(req.params.circleId, member, accessContext);
    if (!where) return pageResponse([], pagination);

    const tasks = await db.task.findMany({
      where,
      orderBy: taskListOrder,
      include: taskInclude,
      ...prismaCursorWindow(pagination),
    });
    const visibleTasks = filterVisibleTasks(tasks, {
      member,
      userId: member.userId,
      accessContext,
    }).map((task) => decorateTaskForMember(task, member, accessContext));
    return pageResponse(visibleTasks, pagination);
  });

  // PATCH /circles/:circleId/tasks/:taskId
  app.patch("/circles/:circleId/tasks/:taskId", async (req, reply) => {
    const { userId, status, title, notes, dueAt, priority, assigneeId, recipientId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (userId && userId !== authenticatedUserId) {
      return reply.code(403).send({ error: "userId must match the authenticated user" });
    }
    const recurrenceWasProvided = Object.prototype.hasOwnProperty.call(req.body ?? {}, "recurrence");
    const seriesScope = nextSeriesScope(req.body?.seriesScope);

    const member = await assertRequestMember(db, req.params.circleId, req, reply);
    if (!member) return;

    const { task, accessContext } = await findVisibleTask(req.params.circleId, req.params.taskId, member);
    if (!task) return reply.code(404).send({ error: "Task not found" });

    if (title !== undefined && title.length > 200)
      return reply.code(400).send({ error: "title exceeds 200 characters" });
    if (notes !== undefined && notes && notes.length > 1000)
      return reply.code(400).send({ error: "notes exceeds 1000 characters" });

    if (member.role === "RECIPIENT") {
      const isAssignedToMe = task.assigneeId === authenticatedUserId;
      if (!isAssignedToMe || status === undefined || assigneeId !== undefined || recipientId !== undefined
          || title !== undefined || notes !== undefined || dueAt !== undefined || priority !== undefined || recurrenceWasProvided)
        return reply.code(403).send({ error: "Care receivers can only mark their own assigned tasks as done" });
      if (status !== "DONE")
        return reply.code(403).send({ error: "Care receivers can only mark tasks as done" });
    }

    if (member.role === "MEMBER") {
      const isOwn = task.creatorId === authenticatedUserId;
      const isStructuralEdit = title !== undefined
        || notes !== undefined
        || dueAt !== undefined
        || priority !== undefined
        || assigneeId !== undefined
        || recipientId !== undefined
        || recurrenceWasProvided;
      if (!isOwn && isStructuralEdit)
        return reply.code(403).send({ error: "Caregivers can only edit or reassign tasks they created" });
      if (status !== undefined && status !== task.status && !task.capabilities?.canChangeStatus)
        return reply.code(403).send({ error: "Caregivers cannot change status for this task" });
      if (status === "SKIPPED" && !task.capabilities?.canSkip)
        return reply.code(403).send({ error: "Caregivers can only skip tasks they control" });
    }

    const currentDueAt = task.dueAt ?? null;
    const nextDueAt = dueAt !== undefined
      ? parseOptionalDate(dueAt, "dueAt")
      : currentDueAt;

    let normalizedRecurrence = null;
    if (recurrenceWasProvided) {
      try {
        normalizedRecurrence = normalizeRecurrenceInput(req.body.recurrence);
      } catch (error) {
        return reply.code(400).send({ error: error.message });
      }
    }

    const nextRecurrenceFrequency = recurrenceWasProvided
      ? normalizedRecurrence.frequency
      : task.recurrenceFrequency;
    if (nextRecurrenceFrequency !== "NONE" && !nextDueAt) {
      return reply.code(400).send({ error: "Recurring tasks require dueAt" });
    }
    if (seriesScope === "SERIES" && task.seriesId && status !== undefined && status !== task.status) {
      return reply.code(400).send({ error: "Status updates only apply to a single occurrence" });
    }

    const data = {};
    if (status !== undefined) {
      data.status = status;
      data.completedAt = completionStateForStatus(status);
      data.completedById = status === "DONE" ? authenticatedUserId : null;
      data.archivedAt = null;
    }
    if (title !== undefined) data.title = title;
    if (notes !== undefined) data.notes = notes;
    if (dueAt !== undefined) data.dueAt = nextDueAt;
    if (priority !== undefined) data.priority = priority;
    if (assigneeId !== undefined) data.assigneeId = assigneeId;

    const previousAssigneeId = task.assigneeId;
    const applyToSeries = seriesScope === "SERIES" && Boolean(task.seriesId) && (
      title !== undefined
      || notes !== undefined
      || dueAt !== undefined
      || priority !== undefined
      || assigneeId !== undefined
      || recipientId !== undefined
      || recurrenceWasProvided
    );
    let updated;
    try {
      updated = await db.$transaction(async (tx) => {
        const assignmentContext = await assignmentContextForMember(
          tx,
          req.params.circleId,
          member,
          authenticatedUserId,
        );
        let targetRecipient = assignmentContext.recipients.find((recipient) => recipient.id === task.recipientId)
          ?? task.recipient;

        if (recipientId !== undefined) {
          const resolvedRecipientId = await resolveRecipientId(tx, req.params.circleId, recipientId);
          if (!resolvedRecipientId) throw new Error("recipientId is required");
          const receiverBase = await assertTaskableRecipient(tx, req.params.circleId, resolvedRecipientId);
          const receiver = assignmentContext.recipients.find((recipient) => recipient.id === resolvedRecipientId)
            ?? {
              ...receiverBase,
              eligibleAssigneeIds: eligibleAssigneeUserIdsForReceiver({
                member,
                receiver: receiverBase,
                circleMembers: assignmentContext.circleMembers,
                activeRecipientAccesses: assignmentContext.activeRecipientAccesses,
              }),
            };
          if (!canCreateTaskWithAccess({ member, receiver, accessContext: assignmentContext })) {
            throw createHttpError("You do not have access to assign tasks for this care receiver", 403);
          }
          targetRecipient = receiver;
          data.recipientId = resolvedRecipientId;
        }

        if ((recurrenceWasProvided && normalizedRecurrence.frequency !== "NONE")
          || (recipientId !== undefined && nextRecurrenceFrequency !== "NONE")) {
          assertRecurringFeatureAccess(
            targetRecipient ?? task.recipient,
            recurrenceWasProvided ? normalizedRecurrence : { frequency: nextRecurrenceFrequency },
          );
        }

        const nextAssigneeId = assigneeId !== undefined ? assigneeId : task.assigneeId;
        if (recipientId !== undefined || assigneeId !== undefined) {
          assertAssigneeAllowed(nextAssigneeId, targetRecipient);
        }

        if (recurrenceWasProvided) {
          const seriesId = normalizedRecurrence.frequency === "NONE"
            ? null
            : (task.seriesId ?? randomUUID());
          Object.assign(data, recurrenceFields(normalizedRecurrence, seriesId));
        }

        let nextTask;
        if (applyToSeries) {
          const futureTasks = await tx.task.findMany({
            where: {
              circleId: req.params.circleId,
              seriesId: task.seriesId,
              archivedAt: null,
              dueAt: task.dueAt ? { gte: task.dueAt } : undefined,
              status: { in: ["PENDING", "IN_PROGRESS"] },
            },
          });
          const dueShiftMs = dueAt !== undefined && task.dueAt && nextDueAt
            ? nextDueAt.getTime() - task.dueAt.getTime()
            : null;

          for (const seriesTask of futureTasks) {
            const seriesData = { ...data };
            if (dueShiftMs !== null && seriesTask.dueAt) {
              seriesData.dueAt = new Date(seriesTask.dueAt.getTime() + dueShiftMs);
            }

            const seriesUpdatedTask = await tx.task.update({
              where: { id: seriesTask.id },
              data: seriesData,
              include: taskInclude,
            });

            if (dueAt !== undefined) {
              await syncReminderForTask(tx, seriesUpdatedTask.id, seriesUpdatedTask.dueAt);
            }

            if (seriesTask.id === req.params.taskId) {
              nextTask = seriesUpdatedTask;
            }
          }

          if (!nextTask) {
            nextTask = await tx.task.findFirst({
              where: { id: req.params.taskId, circleId: req.params.circleId },
              include: taskInclude,
            });
          }
        } else {
          nextTask = await tx.task.update({
            where: { id: req.params.taskId },
            data,
            include: taskInclude,
          });

          if (dueAt !== undefined) {
            await syncReminderForTask(tx, nextTask.id, nextTask.dueAt);
          }
        }

        if (recurrenceWasProvided && task.recurrenceFrequency === "NONE" && nextTask.recurrenceFrequency !== "NONE" && nextTask.seriesId) {
          await tx.event.create({
            data: {
              type: "TASK_SERIES_CREATED",
              circleId: req.params.circleId,
              actorId: authenticatedUserId,
              payload: {
                seriesId: nextTask.seriesId,
                taskId: nextTask.id,
                frequency: nextTask.recurrenceFrequency,
              },
            },
          });
        }

        if (!isTerminalTaskStatus(task.status) && isTerminalTaskStatus(nextTask.status) && isRecurringTask(nextTask)) {
          await ensureNextRecurringOccurrence(tx, nextTask);
        }

        return decorateTaskForMember(nextTask, member, assignmentContext);
      });
    } catch (error) {
      return reply.code(error.statusCode ?? 400).send({ error: error.message });
    }

    if (status === "DONE" && task.status !== "DONE") {
      await logEvent(db, {
        type: "TASK_COMPLETED",
        circleId: req.params.circleId,
        actorId: authenticatedUserId,
        payload: { taskId: task.id },
      });

      if (updated.assigneeId && updated.assigneeId !== authenticatedUserId) {
        const assigneeMember = await db.circleMember.findUnique({
          where: { userId_circleId: { userId: updated.assigneeId, circleId: updated.circleId } },
          select: { role: true },
        });
        if (assigneeMember?.role === "RECIPIENT") {
          const completerFirst = updated.completedBy?.name?.split(" ")[0] ?? "Your caregiver";
          await deliverTaskNotification({
            db, userId: updated.assigneeId, task: updated,
            type: "taskCompletedForRecipient", extra: completerFirst,
          });
        }
      } else if (member.role === "RECIPIENT" && updated.creatorId !== authenticatedUserId) {
        const recipientName = updated.recipient?.name ?? updated.completedBy?.name ?? "Care receiver";
        await deliverTaskNotification({
          db, userId: updated.creatorId, task: updated,
          type: "recipientCompletedTask", extra: recipientName,
        });
      }
    } else if (
      status && status !== task.status
      || recurrenceWasProvided
      || title !== undefined
      || notes !== undefined
      || dueAt !== undefined
      || priority !== undefined
      || assigneeId !== undefined
      || recipientId !== undefined
    ) {
      await logEvent(db, {
        type: "TASK_UPDATED",
        circleId: req.params.circleId,
        actorId: authenticatedUserId,
        payload: { taskId: task.id, status: status ?? task.status, seriesScope },
      });
    }

    if (assigneeId !== undefined && assigneeId && assigneeId !== previousAssigneeId) {
      const assigneeMember = await db.circleMember.findUnique({
        where: { userId_circleId: { userId: assigneeId, circleId: updated.circleId } },
        select: { role: true },
      });
      const notifType = assigneeMember?.role === "RECIPIENT" ? "recipientAssignment" : "assignment";
      await deliverTaskNotification({ db, userId: assigneeId, task: updated, type: notifType });
    }

    return updated;
  });

  // DELETE /circles/:circleId/tasks/:taskId — admin or own task
  app.delete("/circles/:circleId/tasks/:taskId", async (req, reply) => {
    const { userId } = req.body ?? {};
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    if (userId && userId !== authenticatedUserId) {
      return reply.code(403).send({ error: "userId must match the authenticated user" });
    }

    const member = await assertRequestMember(db, req.params.circleId, req, reply);
    if (!member) return;

    const { task } = await findVisibleTask(req.params.circleId, req.params.taskId, member, undefined);
    if (!task) return reply.code(404).send({ error: "Task not found" });

    if (member.role === "MEMBER" && task.creatorId !== authenticatedUserId)
      return reply.code(403).send({ error: "Members can only delete their own tasks" });

    await db.task.delete({ where: { id: req.params.taskId } });
    await logEvent(db, {
      type: "TASK_DELETED",
      circleId: req.params.circleId,
      actorId: authenticatedUserId,
      payload: { taskId: task.id },
    });
    return reply.code(204).send();
  });

  // POST /circles/:circleId/tasks/:taskId/reminder/snooze — assigned user, creator, or admin
  app.post("/circles/:circleId/tasks/:taskId/reminder/snooze", async (req, reply) => {
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    const minutes = Number(req.body?.minutes ?? 15);
    if (!SNOOZE_OPTIONS_MINUTES.has(minutes)) {
      return reply.code(400).send({ error: "minutes must be one of 15, 60, or 1440" });
    }

    const member = await assertRequestMember(db, req.params.circleId, req, reply);
    if (!member) return;

    const { task } = await findVisibleTask(req.params.circleId, req.params.taskId, member);
    if (!task) return reply.code(404).send({ error: "Task not found" });
    if (["DONE", "SKIPPED"].includes(task.status)) {
      return reply.code(400).send({ error: "Completed tasks cannot be snoozed" });
    }
    if (!canSnoozeTaskReminder({ member, task, userId: authenticatedUserId })) {
      return reply.code(403).send({ error: "You cannot snooze this reminder" });
    }

    const existingReminder = await db.reminder.findFirst({ where: { taskId: task.id } });
    if (!existingReminder) {
      return reply.code(404).send({ error: "Reminder not found" });
    }
    if ((existingReminder.snoozeCount ?? 0) >= MAX_REMINDER_SNOOZES) {
      return reply.code(400).send({ error: "Reminder snooze limit reached" });
    }

    const snoozedUntil = new Date(Date.now() + minutes * 60 * 1000);
    const reminder = await db.reminder.update({
      where: { id: existingReminder.id },
      data: {
        status: "SNOOZED",
        scheduledAt: snoozedUntil,
        snoozedUntil,
        snoozeCount: (existingReminder.snoozeCount ?? 0) + 1,
        escalationDueAt: null,
        escalatedAt: null,
      },
    });

    await logEvent(db, {
      type: "REMINDER_SNOOZED",
      circleId: task.circleId,
      actorId: authenticatedUserId,
      payload: { taskId: task.id, reminderId: reminder.id, minutes, snoozedUntil },
    });
    return reply.code(200).send(reminderSummary(reminder));
  });

  const commentInclude = {
    author: { select: { id: true, name: true } },
  };

  // GET /circles/:circleId/tasks/:taskId/comments
  app.get("/circles/:circleId/tasks/:taskId/comments", async (req, reply) => {
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    const member = await assertRequestMember(db, req.params.circleId, req, reply);
    if (!member) return;
    const { task } = await findVisibleTask(req.params.circleId, req.params.taskId, member);
    if (!task) return reply.code(404).send({ error: "Task not found" });
    const pagination = parseCursorPagination(req.query);
    const comments = await db.taskComment.findMany({
      where: { taskId: req.params.taskId },
      orderBy: [{ createdAt: "asc" }, { id: "asc" }],
      include: commentInclude,
      ...prismaCursorWindow(pagination),
    });
    return pageResponse(comments, pagination);
  });

  // POST /circles/:circleId/tasks/:taskId/comments
  app.post("/circles/:circleId/tasks/:taskId/comments", async (req, reply) => {
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    const member = await assertRequestMember(db, req.params.circleId, req, reply);
    if (!member) return;
    const { body } = req.body ?? {};
    if (!body?.trim()) return reply.code(400).send({ error: "body is required" });
    const { task } = await findVisibleTask(req.params.circleId, req.params.taskId, member);
    if (!task) return reply.code(404).send({ error: "Task not found" });
    const comment = await db.taskComment.create({
      data: { body: body.trim(), taskId: req.params.taskId, authorId: authenticatedUserId },
      include: commentInclude,
    });
    return reply.code(201).send(comment);
  });

  // DELETE /circles/:circleId/tasks/:taskId/comments/:commentId
  app.delete("/circles/:circleId/tasks/:taskId/comments/:commentId", async (req, reply) => {
    const authenticatedUserId = requireAuthenticatedUser(req, reply);
    if (!authenticatedUserId) return;
    const member = await assertRequestMember(db, req.params.circleId, req, reply);
    if (!member) return;
    const { task } = await findVisibleTask(req.params.circleId, req.params.taskId, member);
    if (!task) return reply.code(404).send({ error: "Task not found" });
    const comment = await db.taskComment.findFirst({
      where: { id: req.params.commentId, taskId: req.params.taskId },
      select: { id: true, authorId: true },
    });
    if (!comment) return reply.code(404).send({ error: "Comment not found" });
    if (member.role !== "ADMIN" && comment.authorId !== authenticatedUserId)
      return reply.code(403).send({ error: "Only admins or the comment author can delete comments" });
    await db.taskComment.delete({ where: { id: req.params.commentId } });
    return reply.code(204).send();
  });
}
