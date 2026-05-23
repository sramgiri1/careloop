import "dotenv/config";
import { PrismaClient } from "@prisma/client";

const db = new PrismaClient();

async function main() {
  await db.$transaction([
    db.reminder.deleteMany(),
    db.event.deleteMany(),
    db.task.deleteMany(),
    db.circleMember.deleteMany(),
    db.digestLog.deleteMany(),
    db.careCircle.deleteMany(),
    db.user.deleteMany(),
  ]);

  console.log("CareLoop QA reset complete.");
}

main()
  .catch((err) => {
    console.error("CareLoop QA reset failed:", err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await db.$disconnect();
  });
