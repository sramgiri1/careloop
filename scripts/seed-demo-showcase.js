import "dotenv/config";
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { hashPassword, issueAccessToken } from "../src/lib/auth.js";
import { ACTIVE_TERMS_VERSION } from "../src/lib/legal.js";

const db = new PrismaClient();

const DEMO_PASSWORD = process.env.CARELOOP_DEMO_PASSWORD?.trim() || "DemoCare123!";
const TIMEZONE = "America/New_York";
const legacyDemoEmails = [
  "demo.organizer@careloop.local",
  "demo.aging.caregiver@careloop.local",
  "demo.aging.backup@careloop.local",
  "demo.aging.recipient@careloop.local",
  "demo.recovery.caregiver@careloop.local",
  "demo.recovery.backup@careloop.local",
  "demo.recovery.recipient@careloop.local",
  "demo.newparent.caregiver@careloop.local",
  "demo.newparent.backup@careloop.local",
  "demo.newparent.recipient@careloop.local",
  "demo.memory.caregiver@careloop.local",
  "demo.memory.backup@careloop.local",
  "demo.memory.recipient@careloop.local",
];

const userDirectory = {
  organizer: { email: "anita.ramgiri@example.com", name: "Anita Ramgiri" },
  agingCaregiver: { email: "ravi.ramgiri@example.com", name: "Ravi Ramgiri" },
  agingBackup: { email: "meera.patel@example.com", name: "Meera Patel" },
  agingRecipient: { email: "lakshmi.ramgiri@example.com", name: "Lakshmi Ramgiri" },
  recoveryOrganizer: { email: "daniel.morris@example.com", name: "Daniel Morris" },
  recoveryCaregiver: { email: "sophia.morris@example.com", name: "Sophia Morris" },
  recoveryBackup: { email: "james.lee@example.com", name: "James Lee" },
  recoveryRecipient: { email: "elena.morris@example.com", name: "Elena Morris" },
  newParentOrganizer: { email: "priya.shah@example.com", name: "Priya Shah" },
  newParentCaregiver: { email: "arjun.shah@example.com", name: "Arjun Shah" },
  newParentBackup: { email: "nina.desai@example.com", name: "Nina Desai" },
  newParentRecipient: { email: "maya.shah@example.com", name: "Maya Shah" },
  memoryOrganizer: { email: "thomas.wilson@example.com", name: "Thomas Wilson" },
  memoryCaregiver: { email: "emma.wilson@example.com", name: "Emma Wilson" },
  memoryBackup: { email: "olivia.brooks@example.com", name: "Olivia Brooks" },
  memoryRecipient: { email: "robert.wilson@example.com", name: "Robert Wilson" },
};

const circleScenarios = [
  {
    key: "aging-parent",
    useCase: "Aging parent support",
    organizerKey: "organizer",
    name: "Ramgiri Family Care",
    recipientName: "Lakshmi Ramgiri",
    archiveAfterDays: 14,
    recipients: [
      {
        key: "elena",
        name: "Lakshmi Ramgiri",
        relationship: "Mom",
        notes: "Needs help coordinating appointments, meals, and light mobility support after a dizzy spell last week.",
        isPrimary: true,
        activationStatus: "ACTIVE",
        userKey: "agingRecipient",
        entitlement: {
          status: "ACTIVE",
          source: "APP_STORE",
          appleOriginalTransactionId: "story-aging-lakshmi-001",
          appleProductId: "com.careloop.ios.premium.yearly",
        },
      },
      {
        key: "luis",
        name: "Suresh Ramgiri",
        relationship: "Dad",
        notes: "Proxy-managed by Anita after a recent fall. Lives in the same home.",
        isPrimary: false,
        activationStatus: "PROXY_ACTIVE",
        proxyDocumentReference: "careloop://consent/suresh-ramgiri",
        entitlement: {
          status: "ACTIVE",
          source: "MANUAL",
        },
      },
    ],
    caregivers: [
      { userKey: "agingCaregiver", accessTo: ["elena", "luis"] },
      { userKey: "agingBackup", accessTo: ["elena"] },
    ],
    pendingInvites: [
      { email: "marta.pharmacy@example.com", name: "Marta Pharmacy", role: "MEMBER" },
    ],
    tasks: [
      {
        key: "aging-pharmacy-pickup",
        title: "Pick up prescriptions from Greenway Pharmacy",
        notes: "Call Greenway Pharmacy and confirm pickup before the evening check-in.",
        recipientKey: "elena",
        creatorKey: "organizer",
        assigneeKey: "agingCaregiver",
        status: "PENDING",
        priority: "HIGH",
        dueHoursFromNow: 4,
        createdHoursAgo: 8,
        comments: [
          { authorKey: "organizer", body: "The last pickup was delayed and Mom was anxious. Please confirm pickup time.", createdHoursAgo: 7.5 },
        ],
        reminder: { status: "PENDING" },
      },
      {
        key: "aging-blood-sugar",
        title: "Morning blood sugar check",
        notes: "Capture the reading in the kitchen notebook and confirm breakfast was eaten.",
        recipientKey: "elena",
        creatorKey: "organizer",
        assigneeKey: "agingBackup",
        status: "IN_PROGRESS",
        priority: "NORMAL",
        dueHoursFromNow: -0.5,
        createdHoursAgo: 16,
        comments: [
          { authorKey: "agingBackup", body: "On my way over now. Test strips are already in the kitchen drawer.", createdHoursAgo: 0.4 },
        ],
        reminder: { status: "SNOOZED", snoozeMinutes: 60, snoozeCount: 1 },
      },
      {
        key: "aging-grab-bars",
        title: "Install bathroom grab bars",
        notes: "The hallway bath still needs the contractor quote approved after Dad's fall.",
        recipientKey: "luis",
        creatorKey: "organizer",
        assigneeKey: "agingCaregiver",
        status: "PENDING",
        priority: "URGENT",
        dueHoursFromNow: -26,
        createdHoursAgo: 72,
        comments: [
          { authorKey: "agingCaregiver", body: "Contractor availability slipped. Escalating so we do not lose another day.", createdHoursAgo: 5 },
        ],
        reminder: { status: "ESCALATED", escalatedHoursAgo: 2.5 },
      },
      {
        key: "aging-stretch-yesterday",
        title: "Guided stretching routine",
        notes: "20-minute morning routine from physical therapy.",
        recipientKey: "elena",
        creatorKey: "organizer",
        assigneeKey: "agingRecipient",
        status: "DONE",
        priority: "NORMAL",
        dueHoursFromNow: -22,
        completedHoursAgo: -20,
        createdHoursAgo: 30,
        recurrence: {
          seriesKey: "aging-stretching",
          frequency: "DAILY",
          interval: 1,
        },
        comments: [
          { authorKey: "agingRecipient", body: "Completed before breakfast. I felt steadier today.", createdHoursAgo: 19.5 },
        ],
      },
      {
        key: "aging-stretch-tomorrow",
        title: "Guided stretching routine",
        notes: "20-minute morning routine from physical therapy.",
        recipientKey: "elena",
        creatorKey: "organizer",
        assigneeKey: "agingRecipient",
        status: "PENDING",
        priority: "NORMAL",
        dueHoursFromNow: 26,
        createdHoursAgo: 1,
        recurrence: {
          seriesKey: "aging-stretching",
          frequency: "DAILY",
          interval: 1,
        },
        reminder: { status: "PENDING" },
      },
      {
        key: "aging-insurance",
        title: "Review insurance claim summary",
        notes: "The missing statement was already faxed, so skip the older follow-up reminder.",
        recipientKey: "elena",
        creatorKey: "organizer",
        assigneeKey: "agingCaregiver",
        status: "SKIPPED",
        priority: "LOW",
        dueHoursFromNow: -48,
        completedHoursAgo: -40,
        createdHoursAgo: 60,
      },
    ],
  },
  {
    key: "post-surgery",
    useCase: "Post-surgery recovery",
    organizerKey: "recoveryOrganizer",
    name: "Morris Recovery Plan",
    recipientName: "Elena Morris",
    archiveAfterDays: 10,
    recipients: [
      {
        key: "grace",
        name: "Elena Morris",
        relationship: "Spouse",
        notes: "Knee replacement recovery. Basic plan stays on the free tier until recurring reminders are needed.",
        isPrimary: true,
        activationStatus: "ACTIVE",
        userKey: "recoveryRecipient",
      },
    ],
    caregivers: [
      { userKey: "recoveryCaregiver", accessTo: ["grace"] },
      { userKey: "recoveryBackup", accessTo: ["grace"] },
    ],
    premiumRequests: [
      { recipientKey: "grace", requesterKey: "recoveryCaregiver", createdHoursAgo: 2 },
      { recipientKey: "grace", requesterKey: "recoveryBackup", createdHoursAgo: 1 },
    ],
    pendingInvites: [
      { email: "casey.volunteer@example.com", name: "Casey Volunteer", role: "MEMBER" },
    ],
    tasks: [
      {
        key: "recovery-lunch-check",
        title: "Lunch and recovery check-in",
        notes: "Confirm lunch was delivered, note appetite, and mark done so Daniel knows the midday check happened.",
        recipientKey: "grace",
        creatorKey: "organizer",
        assigneeKey: "recoveryRecipient",
        status: "PENDING",
        priority: "HIGH",
        dueHoursFromNow: 2,
        createdHoursAgo: 4,
        reminder: { status: "PENDING" },
      },
      {
        key: "recovery-photo",
        title: "Upload incision photo",
        notes: "Send a well-lit photo to the surgeon portal before tonight.",
        recipientKey: "grace",
        creatorKey: "recoveryCaregiver",
        assigneeKey: "recoveryRecipient",
        status: "IN_PROGRESS",
        priority: "NORMAL",
        dueHoursFromNow: 5,
        createdHoursAgo: 6,
        comments: [
          { authorKey: "recoveryRecipient", body: "I already cleaned the area and will upload after my next walk.", createdHoursAgo: 1.2 },
        ],
        reminder: { status: "SNOOZED", snoozeMinutes: 15, snoozeCount: 2 },
      },
      {
        key: "recovery-dressing",
        title: "Change dressing",
        notes: "Use the sterile kit from the top cabinet and note any redness.",
        recipientKey: "grace",
        creatorKey: "organizer",
        assigneeKey: "recoveryCaregiver",
        status: "DONE",
        priority: "HIGH",
        dueHoursFromNow: -7,
        completedHoursAgo: -4,
        createdHoursAgo: 22,
        comments: [
          { authorKey: "recoveryCaregiver", body: "Changed and documented. No redness around the incision.", createdHoursAgo: 3.8 },
        ],
      },
      {
        key: "recovery-walk",
        title: "Walk for 10 minutes",
        notes: "If pain spikes above 6, pause and log it instead.",
        recipientKey: "grace",
        creatorKey: "recoveryBackup",
        assigneeKey: "recoveryRecipient",
        status: "SKIPPED",
        priority: "NORMAL",
        dueHoursFromNow: -30,
        completedHoursAgo: -28,
        createdHoursAgo: 38,
      },
      {
        key: "recovery-followup",
        title: "Schedule post-op follow-up appointment",
        notes: "Confirm transport before locking the surgeon's follow-up slot.",
        recipientKey: "grace",
        creatorKey: "organizer",
        assigneeKey: "recoveryBackup",
        status: "PENDING",
        priority: "URGENT",
        dueHoursFromNow: -18,
        createdHoursAgo: 36,
        reminder: { status: "ESCALATED", escalatedHoursAgo: 4 },
      },
    ],
  },
  {
    key: "new-parent",
    useCase: "Postpartum and newborn support",
    organizerKey: "newParentOrganizer",
    name: "Shah New Parent Support",
    recipientName: "Maya Shah",
    archiveAfterDays: 7,
    recipients: [
      {
        key: "asha",
        name: "Maya Shah",
        relationship: "Sister",
        notes: "Postpartum support plan with recurring overnight coverage and meal coordination.",
        isPrimary: true,
        activationStatus: "ACTIVE",
        userKey: "newParentRecipient",
        entitlement: {
          status: "ACTIVE",
          source: "APP_STORE",
          appleOriginalTransactionId: "story-new-parent-maya-001",
          appleProductId: "com.careloop.ios.premium.yearly",
        },
      },
    ],
    caregivers: [
      { userKey: "newParentCaregiver", accessTo: ["asha"] },
      { userKey: "newParentBackup", accessTo: ["asha"] },
    ],
    pendingInvites: [
      { email: "morgan.doula@example.com", name: "Morgan Doula", role: "MEMBER" },
    ],
    tasks: [
      {
        key: "newparent-feeding-last-night",
        title: "2am feeding coverage",
        notes: "Bottle prep and burping log are both in the nursery notebook.",
        recipientKey: "asha",
        creatorKey: "organizer",
        assigneeKey: "newParentBackup",
        status: "DONE",
        priority: "HIGH",
        dueHoursFromNow: -18,
        completedHoursAgo: -17,
        createdHoursAgo: 30,
        recurrence: {
          seriesKey: "newparent-overnight-feed",
          frequency: "DAILY",
          interval: 1,
        },
        comments: [
          { authorKey: "newParentBackup", body: "Handled the full feeding and settled the baby back to sleep. Maya got almost four straight hours.", createdHoursAgo: 16.8 },
        ],
      },
      {
        key: "newparent-feeding-tonight",
        title: "2am feeding coverage",
        notes: "Bottle prep and burping log are both in the nursery notebook.",
        recipientKey: "asha",
        creatorKey: "organizer",
        assigneeKey: "newParentBackup",
        status: "PENDING",
        priority: "HIGH",
        dueHoursFromNow: 11,
        createdHoursAgo: 1,
        recurrence: {
          seriesKey: "newparent-overnight-feed",
          frequency: "DAILY",
          interval: 1,
        },
        reminder: { status: "PENDING" },
      },
      {
        key: "newparent-bottles",
        title: "Sanitize bottles",
        notes: "Run the small steam batch before the afternoon handoff.",
        recipientKey: "asha",
        creatorKey: "newParentCaregiver",
        assigneeKey: "newParentCaregiver",
        status: "IN_PROGRESS",
        priority: "NORMAL",
        dueHoursFromNow: 3,
        createdHoursAgo: 5,
        reminder: { status: "PENDING" },
      },
      {
        key: "newparent-formula",
        title: "Restock formula and diapers",
        notes: "Use the bulk order draft saved in the grocery app before the weekend rush.",
        recipientKey: "asha",
        creatorKey: "organizer",
        assigneeKey: "newParentCaregiver",
        status: "PENDING",
        priority: "NORMAL",
        dueHoursFromNow: 8,
        createdHoursAgo: 7,
      },
      {
        key: "newparent-consult",
        title: "Join lactation consultant check-in",
        notes: "Ask about the latch discomfort from yesterday afternoon.",
        recipientKey: "asha",
        creatorKey: "organizer",
        assigneeKey: "newParentRecipient",
        status: "PENDING",
        priority: "HIGH",
        dueHoursFromNow: 22,
        createdHoursAgo: 3,
      },
      {
        key: "newparent-nap",
        title: "Afternoon nap coverage",
        notes: "Skipped because family visitors stayed longer than expected.",
        recipientKey: "asha",
        creatorKey: "organizer",
        assigneeKey: "newParentBackup",
        status: "SKIPPED",
        priority: "LOW",
        dueHoursFromNow: -20,
        completedHoursAgo: -18,
        createdHoursAgo: 24,
      },
    ],
  },
  {
    key: "memory-care",
    useCase: "Memory care and home safety",
    organizerKey: "memoryOrganizer",
    name: "Wilson Memory Care",
    recipientName: "Robert Wilson",
    archiveAfterDays: 21,
    recipients: [
      {
        key: "walter",
        name: "Robert Wilson",
        relationship: "Dad",
        notes: "Short-term memory support with safety checks and structured routines.",
        isPrimary: true,
        activationStatus: "ACTIVE",
        userKey: "memoryRecipient",
        entitlement: {
          status: "ACTIVE",
          source: "APP_STORE",
          expiresAtHoursFromNow: -48,
          appleOriginalTransactionId: "story-memory-robert-expired-001",
          appleProductId: "com.careloop.ios.premium.monthly",
        },
      },
    ],
    caregivers: [
      { userKey: "memoryCaregiver", accessTo: ["walter"] },
      { userKey: "memoryBackup", accessTo: ["walter"] },
    ],
    pendingInvites: [
      { email: "linda.neighbor@example.com", name: "Linda Neighbor", role: "MEMBER" },
    ],
    tasks: [
      {
        key: "memory-evening-safety",
        title: "Evening safety check",
        notes: "Confirm dinner is done, doors are locked, and leave a note if anything looks off.",
        recipientKey: "walter",
        creatorKey: "organizer",
        assigneeKey: "memoryRecipient",
        status: "PENDING",
        priority: "HIGH",
        dueHoursFromNow: 1,
        createdHoursAgo: 2,
        reminder: { status: "PENDING" },
      },
      {
        key: "memory-sensor",
        title: "Replace front door sensor battery",
        notes: "Low battery alert is already firing twice each evening, and Dad missed yesterday's door check.",
        recipientKey: "walter",
        creatorKey: "organizer",
        assigneeKey: "memoryCaregiver",
        status: "PENDING",
        priority: "URGENT",
        dueHoursFromNow: -14,
        createdHoursAgo: 26,
        reminder: { status: "ESCALATED", escalatedHoursAgo: 3 },
      },
      {
        key: "memory-grocery-last-week",
        title: "Weekly grocery delivery check-in",
        notes: "Verify staples and replace fruit before the weekend.",
        recipientKey: "walter",
        creatorKey: "organizer",
        assigneeKey: "memoryBackup",
        status: "DONE",
        priority: "NORMAL",
        dueHoursFromNow: -28,
        completedHoursAgo: -26,
        createdHoursAgo: 52,
        recurrence: {
          seriesKey: "memory-grocery",
          frequency: "WEEKLY",
          interval: 1,
          weekdays: ["FRIDAY"],
        },
      },
      {
        key: "memory-grocery-next",
        title: "Weekly grocery delivery check-in",
        notes: "Verify staples and replace fruit before the weekend.",
        recipientKey: "walter",
        creatorKey: "organizer",
        assigneeKey: "memoryBackup",
        status: "PENDING",
        priority: "NORMAL",
        dueHoursFromNow: 140,
        createdHoursAgo: 1,
        recurrence: {
          seriesKey: "memory-grocery",
          frequency: "WEEKLY",
          interval: 1,
          weekdays: ["FRIDAY"],
        },
      },
      {
        key: "memory-game",
        title: "Memory game session",
        notes: "Use the card deck from occupational therapy for 15 minutes.",
        recipientKey: "walter",
        creatorKey: "memoryCaregiver",
        assigneeKey: "memoryRecipient",
        status: "IN_PROGRESS",
        priority: "LOW",
        dueHoursFromNow: 5,
        createdHoursAgo: 4,
        comments: [
          { authorKey: "memoryRecipient", body: "Started already and want to finish after tea.", createdHoursAgo: 0.8 },
        ],
      },
      {
        key: "memory-hydration",
        title: "Hydration check before bed",
        notes: "Skipped because the nurse confirmed it in person.",
        recipientKey: "walter",
        creatorKey: "organizer",
        assigneeKey: "memoryBackup",
        status: "SKIPPED",
        priority: "LOW",
        dueHoursFromNow: -12,
        completedHoursAgo: -10,
        createdHoursAgo: 18,
      },
    ],
  },
];

function hoursFromNow(now, hours) {
  return new Date(now.getTime() + hours * 60 * 60 * 1000);
}

function minutesFromDate(date, minutes) {
  return new Date(date.getTime() + minutes * 60 * 1000);
}

function entitlementData(recipientId, organizerId, entitlement, now) {
  if (!entitlement) return null;
  return {
    recipientId,
    status: entitlement.status,
    source: entitlement.source,
    startsAt: hoursFromNow(now, -24 * 14),
    expiresAt: hoursFromNow(now, entitlement.expiresAtHoursFromNow ?? 24 * 30),
    purchasedById: organizerId,
    appleOriginalTransactionId: entitlement.appleOriginalTransactionId ?? null,
    appleProductId: entitlement.appleProductId ?? null,
  };
}

function reminderData(task, reminder, now) {
  if (!reminder || !task.dueAt) return null;
  const scheduledAt = minutesFromDate(task.dueAt, -15);

  if (reminder.status === "PENDING") {
    return {
      taskId: task.id,
      scheduledAt,
      status: "PENDING",
    };
  }

  if (reminder.status === "SNOOZED") {
    const snoozedUntil = minutesFromDate(now, reminder.snoozeMinutes ?? 15);
    return {
      taskId: task.id,
      scheduledAt: snoozedUntil,
      status: "SNOOZED",
      snoozedUntil,
      snoozeCount: reminder.snoozeCount ?? 1,
    };
  }

  if (reminder.status === "ESCALATED") {
    const sentAt = minutesFromDate(scheduledAt, 5);
    const escalatedAt = hoursFromNow(now, -(reminder.escalatedHoursAgo ?? 1));
    return {
      taskId: task.id,
      scheduledAt,
      sentAt,
      status: "ESCALATED",
      escalationDueAt: minutesFromDate(sentAt, 30),
      escalatedAt,
    };
  }

  return {
    taskId: task.id,
    scheduledAt,
    status: reminder.status,
  };
}

function taskEventPayload(taskId, title = null) {
  const payload = { taskId };
  if (title) payload.title = title;
  return payload;
}

async function cleanupDemoData() {
  const demoEmails = [
    ...Object.values(userDirectory).map((user) => user.email),
    ...legacyDemoEmails,
  ];

  const circles = await db.careCircle.findMany({
    where: {
      OR: [
        { members: { some: { user: { email: { in: demoEmails } } } } },
        { recipients: { some: { receiverUser: { email: { in: demoEmails } } } } },
      ],
    },
    select: { id: true },
  });

  if (circles.length > 0) {
    await db.careCircle.deleteMany({
      where: { id: { in: circles.map((circle) => circle.id) } },
    });
  }

  await db.user.deleteMany({
    where: { email: { in: demoEmails } },
  });
}

async function createUsers() {
  const passwordHash = hashPassword(DEMO_PASSWORD);
  const users = {};

  for (const [key, spec] of Object.entries(userDirectory)) {
    users[key] = await db.user.create({
      data: {
        email: spec.email,
        name: spec.name,
        passwordHash,
        timezone: TIMEZONE,
        notifAssignments: true,
        notifEscalations: true,
        notifDigest: true,
        termsAcceptedAt: new Date(),
        termsAcceptedVersion: ACTIVE_TERMS_VERSION,
      },
    });
  }

  return users;
}

async function createCircleScenario(scenario, users, now) {
  const organizer = users[scenario.organizerKey ?? "organizer"];
  const createdCircleAt = hoursFromNow(now, -96 + circleScenarios.findIndex(({ key }) => key === scenario.key) * 6);

  return db.$transaction(async (tx) => {
    const circle = await tx.careCircle.create({
      data: {
        name: scenario.name,
        recipientName: scenario.recipientName,
        archiveAfterDays: scenario.archiveAfterDays,
        createdAt: createdCircleAt,
      },
    });

    await tx.circleMember.create({
      data: {
        circleId: circle.id,
        userId: organizer.id,
        role: "ADMIN",
        joinedAt: minutesFromDate(createdCircleAt, 10),
      },
    });

    const recipients = {};
    for (const [index, recipientSpec] of scenario.recipients.entries()) {
      const recipientUser = recipientSpec.userKey ? users[recipientSpec.userKey] : null;
      const activatedAt = recipientSpec.activationStatus === "DRAFT"
        ? null
        : hoursFromNow(now, -72 + index * 4);

      const recipient = await tx.careRecipient.create({
        data: {
          circleId: circle.id,
          name: recipientSpec.name,
          relationship: recipientSpec.relationship,
          notes: recipientSpec.notes,
          isPrimary: recipientSpec.isPrimary,
          sortOrder: index,
          activationStatus: recipientSpec.activationStatus,
          activatedAt,
          receiverUserId: recipientUser?.id ?? null,
          consentAttestedAt: recipientSpec.activationStatus === "PROXY_ACTIVE" ? activatedAt : null,
          consentAttestedById: recipientSpec.activationStatus === "PROXY_ACTIVE" ? organizer.id : null,
          proxyAuthorizedById: recipientSpec.activationStatus === "PROXY_ACTIVE" ? organizer.id : null,
          consentDocumentReference: recipientSpec.proxyDocumentReference ?? null,
          createdAt: minutesFromDate(createdCircleAt, 30 + index * 5),
        },
      });
      recipients[recipientSpec.key] = recipient;

      const entitlement = entitlementData(recipient.id, organizer.id, recipientSpec.entitlement, now);
      if (entitlement) {
        await tx.careRecipientEntitlement.create({ data: entitlement });
      }

      if (recipientUser) {
        await tx.circleMember.create({
          data: {
            circleId: circle.id,
            userId: recipientUser.id,
            role: "RECIPIENT",
            joinedAt: minutesFromDate(createdCircleAt, 60 + index * 8),
          },
        });

        await tx.invitation.create({
          data: {
            circleId: circle.id,
            email: recipientUser.email,
            name: recipientUser.name,
            role: "RECIPIENT",
            status: "ACCEPTED",
            recipientId: recipient.id,
            invitedById: organizer.id,
            acceptedById: recipientUser.id,
            acceptedAt: minutesFromDate(createdCircleAt, 75 + index * 8),
            expiresAt: hoursFromNow(createdCircleAt, 24 * 14),
            createdAt: minutesFromDate(createdCircleAt, 45 + index * 8),
          },
        });
      }
    }

    const caregiverMembers = {};
    for (const [index, caregiverSpec] of scenario.caregivers.entries()) {
      const caregiverUser = users[caregiverSpec.userKey];
      const member = await tx.circleMember.create({
        data: {
          circleId: circle.id,
          userId: caregiverUser.id,
          role: "MEMBER",
          joinedAt: minutesFromDate(createdCircleAt, 90 + index * 8),
        },
      });
      caregiverMembers[caregiverSpec.userKey] = member;

      await tx.invitation.create({
        data: {
          circleId: circle.id,
          email: caregiverUser.email,
          name: caregiverUser.name,
          role: "MEMBER",
          status: "ACCEPTED",
          invitedById: organizer.id,
          acceptedById: caregiverUser.id,
          acceptedAt: minutesFromDate(createdCircleAt, 105 + index * 8),
          expiresAt: hoursFromNow(createdCircleAt, 24 * 14),
          createdAt: minutesFromDate(createdCircleAt, 80 + index * 8),
        },
      });

      for (const recipientKey of caregiverSpec.accessTo) {
        await tx.careRecipientAccess.create({
          data: {
            recipientId: recipients[recipientKey].id,
            memberId: member.id,
            grantedById: organizer.id,
            grantedAt: minutesFromDate(createdCircleAt, 110 + index * 8),
            createdAt: minutesFromDate(createdCircleAt, 110 + index * 8),
          },
        });
      }
    }

    for (const requestSpec of scenario.premiumRequests ?? []) {
      await tx.premiumUpgradeRequest.create({
        data: {
          circleId: circle.id,
          recipientId: recipients[requestSpec.recipientKey].id,
          requesterUserId: users[requestSpec.requesterKey].id,
          createdAt: hoursFromNow(now, -requestSpec.createdHoursAgo),
        },
      });
    }

    for (const [index, inviteSpec] of scenario.pendingInvites.entries()) {
      await tx.invitation.create({
        data: {
          circleId: circle.id,
          email: inviteSpec.email,
          name: inviteSpec.name,
          role: inviteSpec.role,
          status: "PENDING",
          invitedById: organizer.id,
          expiresAt: hoursFromNow(now, 24 * 10),
          createdAt: hoursFromNow(now, -6 + index),
        },
      });
    }

    const taskIds = {};
    const recurringSeriesIds = new Map();

    for (const taskSpec of scenario.tasks) {
      const assigneeUser = users[taskSpec.assigneeKey];
      const creatorUser = users[taskSpec.creatorKey];
      const dueAt = hoursFromNow(now, taskSpec.dueHoursFromNow);
      const completedAt = taskSpec.completedHoursAgo === undefined
        ? null
        : hoursFromNow(now, taskSpec.completedHoursAgo);
      const recurrence = taskSpec.recurrence ?? null;
      let seriesId = null;
      if (recurrence) {
        seriesId = recurringSeriesIds.get(recurrence.seriesKey) ?? randomUUID();
        recurringSeriesIds.set(recurrence.seriesKey, seriesId);
      }

      const task = await tx.task.create({
        data: {
          title: taskSpec.title,
          notes: taskSpec.notes,
          dueAt,
          status: taskSpec.status,
          priority: taskSpec.priority,
          recurrenceFrequency: recurrence?.frequency ?? "NONE",
          recurrenceInterval: recurrence?.interval ?? null,
          recurrenceWeekdays: recurrence?.weekdays ?? [],
          recurrenceEndsAt: recurrence?.endsAtHoursFromNow === undefined
            ? null
            : hoursFromNow(now, recurrence.endsAtHoursFromNow),
          seriesId,
          completedAt,
          completedById: taskSpec.status === "DONE" ? assigneeUser.id : null,
          circleId: circle.id,
          recipientId: recipients[taskSpec.recipientKey].id,
          creatorId: creatorUser.id,
          assigneeId: assigneeUser.id,
          createdAt: hoursFromNow(now, -taskSpec.createdHoursAgo),
        },
      });
      taskIds[taskSpec.key] = task.id;

      const reminder = reminderData(task, taskSpec.reminder, now);
      if (reminder) {
        await tx.reminder.create({ data: reminder });
      }

      for (const commentSpec of taskSpec.comments ?? []) {
        await tx.taskComment.create({
          data: {
            taskId: task.id,
            authorId: users[commentSpec.authorKey].id,
            body: commentSpec.body,
            createdAt: hoursFromNow(now, -commentSpec.createdHoursAgo),
          },
        });
      }
    }

    const eventRows = [
      {
        type: "CIRCLE_CREATED",
        circleId: circle.id,
        actorId: organizer.id,
        payload: {},
        createdAt: createdCircleAt,
      },
    ];

    for (const recipientSpec of scenario.recipients.filter((recipient) => recipient.userKey)) {
      const recipientUser = users[recipientSpec.userKey];
      const recipient = recipients[recipientSpec.key];
      eventRows.push(
        {
          type: "INVITE_ACCEPTED",
          circleId: circle.id,
          actorId: recipientUser.id,
          payload: { role: "RECIPIENT", recipientId: recipient.id },
          createdAt: minutesFromDate(createdCircleAt, 75),
        },
        {
          type: "MEMBER_JOINED",
          circleId: circle.id,
          actorId: recipientUser.id,
          payload: { userId: recipientUser.id, role: "RECIPIENT" },
          createdAt: minutesFromDate(createdCircleAt, 76),
        },
      );
    }

    for (const caregiverSpec of scenario.caregivers) {
      const caregiverUser = users[caregiverSpec.userKey];
      eventRows.push(
        {
          type: "INVITE_ACCEPTED",
          circleId: circle.id,
          actorId: caregiverUser.id,
          payload: { role: "MEMBER" },
          createdAt: hoursFromNow(now, -70 + eventRows.length),
        },
        {
          type: "MEMBER_JOINED",
          circleId: circle.id,
          actorId: caregiverUser.id,
          payload: { userId: caregiverUser.id, role: "MEMBER" },
          createdAt: hoursFromNow(now, -69.8 + eventRows.length),
        },
      );
    }

    for (const pendingInvite of scenario.pendingInvites) {
      eventRows.push({
        type: "INVITE_CREATED",
        circleId: circle.id,
        actorId: organizer.id,
        payload: { email: pendingInvite.email, role: pendingInvite.role },
        createdAt: hoursFromNow(now, -5),
      });
    }

    for (const recipientSpec of scenario.recipients) {
      const recipient = recipients[recipientSpec.key];
      eventRows.push({
        type: "RECIPIENT_ADDED",
        circleId: circle.id,
        actorId: organizer.id,
        payload: { recipientId: recipient.id, name: recipient.name },
        createdAt: minutesFromDate(createdCircleAt, 30 + recipient.sortOrder * 5),
      });

      if (recipientSpec.activationStatus === "PROXY_ACTIVE") {
        eventRows.push({
          type: "RECIPIENT_UPDATED",
          circleId: circle.id,
          actorId: organizer.id,
          payload: { recipientId: recipient.id, activationStatus: "PROXY_ACTIVE", proxyActivated: true },
          createdAt: minutesFromDate(createdCircleAt, 50 + recipient.sortOrder * 5),
        });
      }
    }

    const seriesLogged = new Set();
    for (const taskSpec of scenario.tasks) {
      const taskId = taskIds[taskSpec.key];
      if (taskSpec.recurrence?.seriesKey && !seriesLogged.has(taskSpec.recurrence.seriesKey)) {
        seriesLogged.add(taskSpec.recurrence.seriesKey);
        eventRows.push({
          type: "TASK_SERIES_CREATED",
          circleId: circle.id,
          actorId: users[taskSpec.creatorKey].id,
          payload: {
            taskId,
            seriesId: recurringSeriesIds.get(taskSpec.recurrence.seriesKey),
            frequency: taskSpec.recurrence.frequency,
          },
          createdAt: hoursFromNow(now, -taskSpec.createdHoursAgo + 0.1),
        });
      }

      eventRows.push({
        type: "TASK_CREATED",
        circleId: circle.id,
        actorId: users[taskSpec.creatorKey].id,
        payload: taskEventPayload(taskId, taskSpec.title),
        createdAt: hoursFromNow(now, -taskSpec.createdHoursAgo),
      });

      if (taskSpec.status === "DONE") {
        eventRows.push({
          type: "TASK_COMPLETED",
          circleId: circle.id,
          actorId: users[taskSpec.assigneeKey].id,
          payload: taskEventPayload(taskId),
          createdAt: hoursFromNow(now, taskSpec.completedHoursAgo),
        });
      } else if (taskSpec.status !== "PENDING") {
        eventRows.push({
          type: "TASK_UPDATED",
          circleId: circle.id,
          actorId: users[taskSpec.assigneeKey].id,
          payload: { taskId, status: taskSpec.status, seriesScope: "THIS_OCCURRENCE" },
          createdAt: hoursFromNow(now, taskSpec.completedHoursAgo ?? -1),
        });
      }

      if (taskSpec.reminder?.status === "ESCALATED") {
        eventRows.push({
          type: "REMINDER_ESCALATED",
          circleId: circle.id,
          actorId: organizer.id,
          payload: { taskId },
          createdAt: hoursFromNow(now, -(taskSpec.reminder.escalatedHoursAgo ?? 1)),
        });
      }
    }

    await tx.event.createMany({ data: eventRows });

    return {
      id: circle.id,
      name: circle.name,
      useCase: scenario.useCase,
      recipients: Object.fromEntries(
        Object.entries(recipients).map(([key, recipient]) => [key, recipient.id]),
      ),
      tasks: taskIds,
    };
  });
}

async function createManifest(users, circles) {
  const tokens = {};
  for (const [key, user] of Object.entries(users)) {
    tokens[key] = await issueAccessToken(user);
  }

  const byKey = Object.fromEntries(circles.map((circle) => [circle.key, circle]));

  return {
    generatedAt: new Date().toISOString(),
    defaultPassword: DEMO_PASSWORD,
    users: Object.fromEntries(
      Object.entries(users).map(([key, user]) => [
        key,
        {
          id: user.id,
          email: user.email,
          name: user.name,
          token: tokens[key],
        },
      ]),
    ),
    circles: circles.map((circle) => ({
      key: circle.key,
      id: circle.id,
      name: circle.name,
      useCase: circle.useCase,
      recipients: circle.recipients,
      tasks: circle.tasks,
    })),
    launchProfiles: [
      {
        key: "aging-organizer",
        title: "Aging Parent · Organizer",
        userKey: "organizer",
        circleId: byKey["aging-parent"].id,
      },
      {
        key: "recovery-recipient",
        title: "Recovery · Care Receiver",
        userKey: "recoveryRecipient",
        circleId: byKey["post-surgery"].id,
      },
      {
        key: "new-parent-caregiver",
        title: "New Parent · Caregiver",
        userKey: "newParentCaregiver",
        circleId: byKey["new-parent"].id,
      },
      {
        key: "memory-caregiver",
        title: "Memory Care · Caregiver",
        userKey: "memoryCaregiver",
        circleId: byKey["memory-care"].id,
      },
    ].map((profile) => ({
      ...profile,
      email: users[profile.userKey].email,
      name: users[profile.userKey].name,
      token: tokens[profile.userKey],
    })),
  };
}

async function main() {
  const now = new Date();
  await cleanupDemoData();
  const users = await createUsers();
  const circles = [];

  for (const scenario of circleScenarios) {
    const result = await createCircleScenario(scenario, users, now);
    circles.push({ key: scenario.key, ...result });
  }

  const manifest = await createManifest(users, circles);
  process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
}

main()
  .catch((error) => {
    console.error("CareLoop demo showcase seed failed:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await db.$disconnect();
  });
