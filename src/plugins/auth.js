import fp from "fastify-plugin";
import { verifyAccessToken } from "../lib/auth.js";

export default fp(async function auth(app) {
  app.decorateRequest("auth", null);
  app.decorateRequest("userId", null);

  app.addHook("onRequest", async (req, reply) => {
    if (req.routeOptions?.config?.public) return;
    const authorization = req.headers.authorization;
    if (!authorization?.startsWith("Bearer ")) {
      return reply.code(401).send({ error: "Authorization bearer token required" });
    }

    const token = authorization.slice("Bearer ".length).trim();
    if (!token) {
      return reply.code(401).send({ error: "Authorization bearer token required" });
    }

    try {
      const auth = await verifyAccessToken(token);
      if (!auth.userId) {
        return reply.code(401).send({ error: "Invalid access token" });
      }
      const user = await app.db.user.findUnique({
        where: { id: auth.userId },
      });
      if (!user) {
        return reply.code(401).send({ error: "Invalid access token" });
      }
      if ((user.authVersion ?? 0) !== (auth.tokenVersion ?? 0)) {
        return reply.code(401).send({ error: "Access token has been revoked" });
      }
      req.auth = auth;
      req.userId = auth.userId;
    } catch {
      return reply.code(401).send({ error: "Invalid or expired access token" });
    }
  });
});
