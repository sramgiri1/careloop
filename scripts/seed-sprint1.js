import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { ACTIVE_TERMS_VERSION } from "../src/lib/legal.js";

const db = new PrismaClient();

async function main() {
  const now = new Date();
  const dueSoon = new Date(now.getTime() + 2 * 60 * 60 * 1000);
  const overdue = new Date(now.getTime() - 60 * 60 * 1000);

  const admin = await db.user.create({
    data: {
      email: "alice.admin@test.careloop.local",
      name: "Alice Admin",
      timezone: "America/New_York",
      termsAcceptedAt: now,
      termsAcceptedVersion: ACTIVE_TERMS_VERSION,
    },
  });

  const member = await db.user.create({
    data: {
      email: "carol.member@test.careloop.local",
      name: "Carol Member",
      timezone: "America/New_York",
      termsAcceptedAt: now,
      termsAcceptedVersion: ACTIVE_TERMS_VERSION,
    },
  });

  const extraMember = await db.user.create({
    data: {
      email: "dave.member@test.careloop.local",
      name: "Dave Member",
      timezone: "America/New_York",
      termsAcceptedAt: now,
      termsAcceptedVersion: ACTIVE_TERMS_VERSION,
    },
  });

  const circle = await db.careCircle.create({
    data: {
      name: "Smith Family",
      recipientName: "Bob Smith",
      members: {
        create: [
          { userId: admin.id, role: "ADMIN" },
          { userId: member.id, role: "MEMBER" },
          { userId: extraMember.id, role: "MEMBER" },
        ],
      },
    },
    include: { members: true },
  });

  const adminTask = await db.task.create({
    data: {
      title: "Book primary care visit",
      notes: "Call Dr. Lee's office",
      dueAt: dueSoon,
      priority: "HIGH",
      circleId: circle.id,
      creatorId: admin.id,
      assigneeId: member.id,
    },
  });

  const memberTask = await db.task.create({
    data: {
      title: "Pick up groceries",
      notes: "Milk, soup, bananas",
      priority: "NORMAL",
      circleId: circle.id,
      creatorId: member.id,
      assigneeId: member.id,
    },
  });

  const overdueTask = await db.task.create({
    data: {
      title: "Check in after lunch",
      dueAt: overdue,
      priority: "URGENT",
      circleId: circle.id,
      creatorId: admin.id,
      assigneeId: extraMember.id,
    },
  });

  await db.reminder.create({
    data: {
      taskId: adminTask.id,
      scheduledAt: new Date(dueSoon.getTime() - 15 * 60 * 1000),
    },
  });

  await db.reminder.create({
    data: {
      taskId: overdueTask.id,
      scheduledAt: new Date(overdue.getTime() - 15 * 60 * 1000),
      sentAt: overdue,
      status: "SENT",
    },
  });

  await db.event.createMany({
    data: [
      { type: "CIRCLE_CREATED", circleId: circle.id, actorId: admin.id, payload: {} },
      { type: "MEMBER_JOINED", circleId: circle.id, actorId: member.id, payload: { userId: member.id } },
      { type: "TASK_CREATED", circleId: circle.id, actorId: admin.id, payload: { taskId: adminTask.id } },
      { type: "TASK_CREATED", circleId: circle.id, actorId: member.id, payload: { taskId: memberTask.id } },
      { type: "APP_SESSION", circleId: circle.id, actorId: admin.id, payload: {} },
    ],
  });

  console.log(JSON.stringify({
    users: {
      adminId: admin.id,
      memberId: member.id,
      extraMemberId: extraMember.id,
    },
    circle: {
      circleId: circle.id,
      memberIds: circle.members.map((m) => m.id),
    },
    tasks: {
      adminTaskId: adminTask.id,
      memberTaskId: memberTask.id,
      overdueTaskId: overdueTask.id,
    },
  }, null, 2));
}

main()
  .catch((err) => {
    console.error("CareLoop Sprint 1 seed failed:", err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await db.$disconnect();
  });
