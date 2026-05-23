import { Prisma } from "@prisma/client";
import { normalizeEmail, sanitizeUser } from "../lib/auth.js";
import { assertSelf, requireAuthenticatedUser } from "../lib/roles.js";

export default async function users(app) {
  const db = app.db;

  async function userWithContext(where) {
    const user = await db.user.findUnique({
      where,
      include: { memberships: { include: { circle: true } }, identities: true },
    });
    if (!user) return null;
    const pendingInvites = await db.invitation.findMany({
      where: {
        email: user.email,
        status: "PENDING",
      },
      include: {
        circle: { select: { id: true, name: true, recipientName: true, archiveAfterDays: true } },
        invitedBy: { select: { id: true, name: true, email: true } },
      },
      orderBy: { createdAt: "desc" },
    });
    return sanitizeUser({ ...user, pendingInvites });
  }

  app.post("/users", async (req, reply) => {
    const { email, name, phone } = req.body ?? {};
    const normalizedEmail = normalizeEmail(email);
    if (!normalizedEmail || !name) return reply.code(400).send({ error: "email and name are required" });
    try {
      const user = await db.user.create({ data: { email: normalizedEmail, name, phone: phone ?? null } });
      return reply.code(201).send(sanitizeUser(user));
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002")
        return reply.code(409).send({ error: "Email already exists" });
      throw err;
    }
  });

  app.get("/users/by-email", async (req, reply) => {
    const { email } = req.query ?? {};
    if (!email) return reply.code(400).send({ error: "email required" });
    const normalizedEmail = normalizeEmail(email);
    const authenticatedEmail = normalizeEmail(req.auth?.email);
    if (!authenticatedEmail || authenticatedEmail !== normalizedEmail) {
      return reply.code(403).send({ error: "Authenticated user does not match requested email" });
    }
    const user = await userWithContext({ email: normalizedEmail });
    if (!user) return reply.code(404).send({ error: "Not found" });
    return user;
  });

  app.get("/users/me", async (req, reply) => {
    const userId = requireAuthenticatedUser(req, reply);
    if (!userId) return;
    const user = await userWithContext({ id: userId });
    if (!user) return reply.code(404).send({ error: "Not found" });
    return user;
  });

  app.get("/users/:id", async (req, reply) => {
    if (!assertSelf(req, req.params.id, reply)) return;
    const user = await userWithContext({ id: req.params.id });
    if (!user) return reply.code(404).send({ error: "Not found" });
    return user;
  });

  app.patch("/users/:id/push-token", async (req, reply) => {
    if (!assertSelf(req, req.params.id, reply)) return;
    const { pushToken } = req.body ?? {};
    if (!pushToken) return reply.code(400).send({ error: "pushToken required" });
    const user = await db.user.update({ where: { id: req.params.id }, data: { pushToken } });
    return sanitizeUser(user);
  });

  // PATCH /users/:id/notification-preferences — self only
  app.patch("/users/:id/notification-preferences", async (req, reply) => {
    if (!assertSelf(req, req.params.id, reply)) return;
    const { notifAssignments, notifEscalations, notifDigest } = req.body ?? {};
    const data = {};
    if (typeof notifAssignments === "boolean") data.notifAssignments = notifAssignments;
    if (typeof notifEscalations === "boolean") data.notifEscalations = notifEscalations;
    if (typeof notifDigest === "boolean") data.notifDigest = notifDigest;
    if (Object.keys(data).length === 0)
      return reply.code(400).send({ error: "At least one preference field is required" });
    const user = await db.user.update({ where: { id: req.params.id }, data });
    return sanitizeUser(user);
  });

  // POST /users/:id/session — log APP_SESSION, one per user per UTC day
  app.post("/users/:id/session", async (req, reply) => {
    if (!assertSelf(req, req.params.id, reply)) return;
    const { circleId } = req.body ?? {};
    let cid = circleId;
    if (!cid) {
      const membership = await db.circleMember.findFirst({ where: { userId: req.params.id } });
      if (!membership) return reply.code(404).send({ error: "No circle membership found" });
      cid = membership.circleId;
    } else {
      const membership = await db.circleMember.findFirst({
        where: { userId: req.params.id, circleId: cid },
      });
      if (!membership) return reply.code(403).send({ error: "Authenticated user is not a member of that circle" });
    }

    const todayStart = new Date(); todayStart.setUTCHours(0,  0,  0,   0);
    const todayEnd   = new Date(); todayEnd.setUTCHours(23,  59, 59, 999);

    const existing = await db.event.findFirst({
      where: { actorId: req.params.id, type: "APP_SESSION", createdAt: { gte: todayStart, lte: todayEnd } },
    });
    if (existing) return reply.send({ logged: false });

    await db.event.create({ data: { type: "APP_SESSION", circleId: cid, actorId: req.params.id } });
    return reply.send({ logged: true });
  });

  app.patch("/users/:id/timezone", async (req, reply) => {
    if (!assertSelf(req, req.params.id, reply)) return;
    const { timezone } = req.body ?? {};
    if (!timezone) return reply.code(400).send({ error: "timezone required" });
    try {
      Intl.DateTimeFormat(undefined, { timeZone: timezone });
    } catch {
      return reply.code(400).send({ error: "Invalid IANA timezone" });
    }
    const user = await db.user.update({ where: { id: req.params.id }, data: { timezone } });
    return sanitizeUser(user);
  });
}
