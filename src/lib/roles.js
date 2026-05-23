export function requireAuthenticatedUser(req, reply) {
  const userId = req.userId ?? req.auth?.userId ?? null;
  if (!userId) {
    reply.code(401).send({ error: "Unauthorized" });
    return null;
  }
  return userId;
}

export function assertSelf(req, targetUserId, reply) {
  const userId = requireAuthenticatedUser(req, reply);
  if (!userId) return null;
  if (userId !== targetUserId) {
    reply.code(403).send({ error: "Authenticated user does not match requested user" });
    return null;
  }
  return userId;
}

export async function assertMember(db, circleId, userId, reply) {
  if (!userId) { reply.code(400).send({ error: "userId required" }); return null; }
  const member = await db.circleMember.findUnique({
    where: { userId_circleId: { userId, circleId } },
  });
  if (!member) { reply.code(403).send({ error: "Not a circle member" }); return null; }
  return member;
}

export async function assertAdmin(db, circleId, userId, reply) {
  const member = await assertMember(db, circleId, userId, reply);
  if (!member) return null;
  if (member.role !== "ADMIN") { reply.code(403).send({ error: "Admin role required" }); return null; }
  return member;
}

export async function assertRequestMember(db, circleId, req, reply) {
  const userId = requireAuthenticatedUser(req, reply);
  if (!userId) return null;
  return assertMember(db, circleId, userId, reply);
}

export async function assertRequestAdmin(db, circleId, req, reply) {
  const userId = requireAuthenticatedUser(req, reply);
  if (!userId) return null;
  return assertAdmin(db, circleId, userId, reply);
}

export async function logEvent(db, { type, circleId, actorId = null, payload = {} }) {
  try {
    await db.event.create({ data: { type, circleId, actorId, payload } });
  } catch (err) {
    console.error("logEvent failed:", err.message);
  }
}
