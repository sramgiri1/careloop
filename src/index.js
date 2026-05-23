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

const app = Fastify({ logger: true });
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
