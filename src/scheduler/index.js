import cron from "node-cron";
import { logEvent } from "../lib/roles.js";
import { sendDailyDigest, sendReminderNotifications } from "../lib/push.js";
import { isRecurringTask, nextDueAtForTask } from "../lib/recurrence.js";
import {
  escalationUserIdsForTask,
  filterVisibleTasks,
  loadReceiverAccessContext,
} from "../lib/access.js";

const DIGEST_HOUR = parseInt(process.env.DAILY_DIGEST_HOUR || "18", 10);
const ESCALATION_MINUTES = parseInt(process.env.REMINDER_ESCALATION_MINUTES || "15", 10);

async function claimReminder(db, { id, fromStatus, toStatus }) {
  const claimedAt = new Date();
  const result = await db.reminder.updateMany({
    where: { id, status: fromStatus },
    data: { status: toStatus, processingStartedAt: claimedAt },
  });
  return result.count === 1 ? claimedAt : null;
}

function deliveryFailed(delivery) {
  if (delivery.delivered || delivery.simulated) return false;
  return delivery.reason !== "notifications_disabled_by_user";
}

function deliverySummary(deliveries) {
  const channels = new Set();
  let deliveredCount = 0;
  let simulatedCount = 0;
  let blockedCount = 0;
  let failedCount = 0;

  for (const delivery of deliveries) {
    if (delivery.channel) channels.add(delivery.channel);
    if (delivery.delivered) deliveredCount += 1;
    if (delivery.simulated) simulatedCount += 1;
    if (delivery.reason === "notifications_disabled_by_user") blockedCount += 1;
    if (deliveryFailed(delivery)) failedCount += 1;
  }

  return {
    recipientCount: deliveries.length,
    deliveredCount,
    simulatedCount,
    blockedCount,
    failedCount,
    deliveryChannels: [...channels].sort(),
  };
}

function userLocalParts(date, timezone) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const parts = Object.fromEntries(fmt.formatToParts(date).filter((part) => part.type !== "literal").map((part) => [part.type, part.value]));
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    hour: Number(parts.hour),
    minute: Number(parts.minute),
  };
}

export async function processPendingReminders(db) {
  const reminders = await db.reminder.findMany({
    where: {
      status: { in: ["PENDING", "SNOOZED"] },
      scheduledAt: { lte: new Date() },
      task: { status: { notIn: ["DONE", "SKIPPED"] } },
    },
    include: {
      task: {
        include: {
          circle: true,
        },
      },
    },
  });

  for (const reminder of reminders) {
    const claimedAt = await claimReminder(db, {
      id: reminder.id,
      fromStatus: reminder.status,
      toStatus: "PROCESSING",
    });
    if (!claimedAt) continue;

    const targetUserId = reminder.task.assigneeId || reminder.task.creatorId;
    let reminderType = "reminder";
    if (reminder.task.assigneeId) {
      const member = await db.circleMember.findUnique({
        where: { userId_circleId: { userId: reminder.task.assigneeId, circleId: reminder.task.circleId } },
        select: { role: true },
      });
      if (member?.role === "RECIPIENT") reminderType = "recipientReminder";
    }
    const deliveries = await sendReminderNotifications({
      db,
      task: reminder.task,
      type: reminderType,
      userIds: [targetUserId],
    });
    const failed = deliveries.some(deliveryFailed);
    const status = failed ? "FAILED" : "SENT";
    const sentAt = new Date();
    await db.reminder.update({
      where: { id: reminder.id },
      data: {
        status,
        sentAt,
        processingStartedAt: null,
        snoozedUntil: null,
        escalationDueAt: failed ? null : new Date(sentAt.getTime() + ESCALATION_MINUTES * 60 * 1000),
      },
    });
    await logEvent(db, {
      type: "REMINDER_SENT",
      circleId: reminder.task.circleId,
      actorId: reminder.task.creatorId,
      payload: {
        taskId: reminder.taskId,
        recipientId: reminder.task.recipientId ?? null,
        status,
        sentAt,
        ...deliverySummary(deliveries),
      },
    });
  }
}

export async function processEscalations(db) {
  const now = new Date();
  const reminders = await db.reminder.findMany({
    where: {
      status: "SENT",
      escalationDueAt: { lte: now },
      task: { status: { notIn: ["DONE", "SKIPPED"] } },
    },
    include: {
      task: {
        include: {
          circle: {
            include: {
              members: true,
            },
          },
        },
      },
    },
  });

  for (const reminder of reminders) {
    const claimedAt = await claimReminder(db, {
      id: reminder.id,
      fromStatus: "SENT",
      toStatus: "ESCALATING",
    });
    if (!claimedAt) continue;

    const activeRecipientAccesses = reminder.task.recipientId
      ? await db.careRecipientAccess.findMany({
        where: {
          recipientId: reminder.task.recipientId,
          revokedAt: null,
        },
      })
      : [];
    const userIds = escalationUserIdsForTask({
      task: reminder.task,
      circleMembers: reminder.task.circle.members,
      activeRecipientAccesses,
    });
    const deliveries = await sendReminderNotifications({
      db,
      task: reminder.task,
      type: "escalation",
      userIds,
    });
    const failed = deliveries.some(deliveryFailed);
    const status = failed ? "FAILED" : "ESCALATED";
    const escalatedAt = new Date();
    await db.reminder.update({
      where: { id: reminder.id },
      data: {
        status,
        escalatedAt,
        processingStartedAt: null,
      },
    });
    await logEvent(db, {
      type: "REMINDER_ESCALATED",
      circleId: reminder.task.circleId,
      actorId: reminder.task.creatorId,
      payload: {
        taskId: reminder.taskId,
        recipientId: reminder.task.recipientId ?? null,
        status,
        escalatedAt,
        ...deliverySummary(deliveries),
      },
    });
  }
}

export async function processDigests(db) {
  const users = await db.user.findMany({
    where: {
      timezone: { not: null },
    },
  });

  for (const user of users) {
    const timezone = user.timezone;
    if (!timezone) continue;
    if (user.notifDigest === false) continue;
    const now = userLocalParts(new Date(), timezone);
    if (now.hour !== DIGEST_HOUR) continue;

    const existing = await db.digestLog.findUnique({
      where: { userId_date: { userId: user.id, date: now.date } },
    });
    if (existing) continue;

    const memberships = await db.circleMember.findMany({
      where: { userId: user.id },
      include: { circle: true },
    });
    if (memberships.length === 0) continue;

    const startOfDay = new Date(`${now.date}T00:00:00Z`);
    const dueToday = [];
    const overdue = [];
    const completedToday = [];

    for (const membership of memberships) {
      const accessContext = await loadReceiverAccessContext(db, {
        circleId: membership.circleId,
        member: membership,
        userId: user.id,
      });
      const circleTasks = await db.task.findMany({
        where: {
          circleId: membership.circleId,
          archivedAt: null,
        },
        orderBy: [{ dueAt: "asc" }, { updatedAt: "desc" }],
      });
      const visibleTasks = filterVisibleTasks(circleTasks, {
        member: membership,
        userId: user.id,
        accessContext,
      });

      dueToday.push(
        ...visibleTasks.filter((task) => task.dueAt && !["DONE", "SKIPPED"].includes(task.status)),
      );
      overdue.push(
        ...visibleTasks.filter((task) => task.dueAt && task.dueAt < new Date() && !["DONE", "SKIPPED"].includes(task.status)),
      );
      completedToday.push(
        ...visibleTasks.filter((task) => task.status === "DONE" && task.updatedAt >= startOfDay),
      );
    }

    const digestResult = await sendDailyDigest({
      user,
      digestDate: now.date,
      dueToday,
      overdue,
      completedToday,
    });

    if (!digestResult.delivered && !digestResult.simulated) continue;

    await db.digestLog.create({
      data: {
        userId: user.id,
        date: now.date,
        messageId: digestResult.messageId ?? null,
      },
    });

    if (memberships[0]?.circleId) {
      await logEvent(db, {
        type: "DIGEST_SENT",
        circleId: memberships[0].circleId,
        actorId: user.id,
        payload: { date: now.date, messageId: digestResult.messageId ?? null, simulated: Boolean(digestResult.simulated) },
      });
    }
  }
}

export async function processTaskArchiving(db) {
  const circles = await db.careCircle.findMany({
    select: { id: true, archiveAfterDays: true },
  });

  for (const circle of circles) {
    const archiveAfterDays = Math.max(1, circle.archiveAfterDays ?? 7);
    const cutoff = new Date(Date.now() - archiveAfterDays * 24 * 60 * 60 * 1000);
    await db.task.updateMany({
      where: {
        circleId: circle.id,
        archivedAt: null,
        completedAt: { lte: cutoff },
        status: { in: ["DONE", "SKIPPED"] },
      },
      data: { archivedAt: new Date() },
    });
  }
}

async function createRecurringOccurrence(tx, task, dueAt) {
  const createdTask = await tx.task.create({
    data: {
      title: task.title,
      notes: task.notes,
      dueAt,
      priority: task.priority,
      recurrenceFrequency: task.recurrenceFrequency,
      recurrenceInterval: task.recurrenceInterval,
      recurrenceWeekdays: task.recurrenceWeekdays ?? [],
      recurrenceEndsAt: task.recurrenceEndsAt ?? null,
      seriesId: task.seriesId,
      circleId: task.circleId,
      creatorId: task.creatorId,
      assigneeId: task.assigneeId ?? null,
    },
  });

  await tx.reminder.create({
    data: {
      taskId: createdTask.id,
      scheduledAt: new Date(dueAt.getTime() - 15 * 60 * 1000),
    },
  });

  return createdTask;
}

export async function processRecurringOccurrences(db) {
  const now = new Date();
  const recurringTasks = await db.task.findMany({
    where: {
      archivedAt: null,
      dueAt: { lte: now },
      recurrenceFrequency: { not: "NONE" },
    },
  });

  for (const seedTask of recurringTasks) {
    if (!isRecurringTask(seedTask) || !seedTask.seriesId) continue;

    await db.$transaction(async (tx) => {
      let currentTask = seedTask;
      for (let index = 0; index < 180; index += 1) {
        const nextDueAt = nextDueAtForTask(currentTask);
        if (!nextDueAt) break;

        let nextTask = await tx.task.findFirst({
          where: {
            seriesId: currentTask.seriesId,
            dueAt: nextDueAt,
          },
        });

        if (!nextTask) {
          nextTask = await createRecurringOccurrence(tx, currentTask, nextDueAt);
        }

        if (!nextTask?.dueAt || nextTask.dueAt > now) break;
        currentTask = nextTask;
      }
    });
  }
}

export function startScheduler(db, logger = console) {
  if (process.env.DISABLE_SCHEDULER === "true") {
    logger.info?.("CareLoop scheduler disabled via DISABLE_SCHEDULER=true");
    return { stop() {} };
  }

  const jobs = [
    cron.schedule("* * * * *", async () => {
      try {
        await processPendingReminders(db);
      } catch (error) {
        logger.error?.({ error }, "processPendingReminders failed");
      }
    }),
    cron.schedule("* * * * *", async () => {
      try {
        await processEscalations(db);
      } catch (error) {
        logger.error?.({ error }, "processEscalations failed");
      }
    }),
    cron.schedule("* * * * *", async () => {
      try {
        await processDigests(db);
      } catch (error) {
        logger.error?.({ error }, "processDigests failed");
      }
    }),
    cron.schedule("0 * * * *", async () => {
      try {
        await processTaskArchiving(db);
      } catch (error) {
        logger.error?.({ error }, "processTaskArchiving failed");
      }
    }),
    cron.schedule("0 * * * *", async () => {
      try {
        await processRecurringOccurrences(db);
      } catch (error) {
        logger.error?.({ error }, "processRecurringOccurrences failed");
      }
    }),
  ];

  logger.info?.("CareLoop scheduler started");
  return {
    stop() {
      jobs.forEach((job) => job.stop());
    },
  };
}
