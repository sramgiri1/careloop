import "dotenv/config";
import Fastify         from "fastify";
import cors            from "@fastify/cors";
import formbody        from "@fastify/formbody";
import { PrismaClient } from "@prisma/client";

import authPlugin from "./plugins/auth.js";
import authRoutes from "./routes/auth.js";
import health     from "./routes/health.js";
import circles    from "./routes/circles.js";
import tasks      from "./routes/tasks.js";
import users      from "./routes/users.js";
import { startScheduler } from "./scheduler/index.js";
import { assertProductionEnvironment } from "./lib/env.js";

const app = Fastify({ logger: true });
const environmentReport = assertProductionEnvironment();
if (process.env.NODE_ENV === "production") {
  for (const warning of environmentReport.warnings) {
    app.log.warn({ warning }, "CareLoop production environment warning");
  }
}

const db  = new PrismaClient();

app.decorate("db", db);

await app.register(cors);
await app.register(formbody);
await app.register(authPlugin);

app.register(health);
app.register(authRoutes);
app.register(users);
app.register(circles);
app.register(tasks);

const port = parseInt(process.env.PORT || "3000");
await app.listen({ port, host: "0.0.0.0" });
startScheduler(db, app.log);
console.log(`CareLoop API running on port ${port}`);

let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  app.log.info({ signal }, "Shutting down CareLoop API");
  try {
    await app.close();
    await db.$disconnect();
    process.exit(0);
  } catch (error) {
    app.log.error({ error }, "CareLoop API shutdown failed");
    process.exit(1);
  }
}

process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);
