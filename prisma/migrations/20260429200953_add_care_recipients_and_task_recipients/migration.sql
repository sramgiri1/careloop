-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "EventType" ADD VALUE 'RECIPIENT_ADDED';
ALTER TYPE "EventType" ADD VALUE 'RECIPIENT_UPDATED';
ALTER TYPE "EventType" ADD VALUE 'RECIPIENT_REMOVED';

-- AlterTable
ALTER TABLE "Task" ADD COLUMN     "recipientId" TEXT;

-- CreateTable
CREATE TABLE "CareRecipient" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "relationship" TEXT,
    "notes" TEXT,
    "isPrimary" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "circleId" TEXT NOT NULL,

    CONSTRAINT "CareRecipient_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "CareRecipient" ADD CONSTRAINT "CareRecipient_circleId_fkey" FOREIGN KEY ("circleId") REFERENCES "CareCircle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Task" ADD CONSTRAINT "Task_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "CareRecipient"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Backfill one primary recipient per existing circle.
INSERT INTO "CareRecipient" ("id", "name", "relationship", "notes", "isPrimary", "createdAt", "updatedAt", "circleId")
SELECT
  'rec_' || substr(md5("id"), 1, 20),
  "recipientName",
  NULL,
  NULL,
  true,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP,
  "id"
FROM "CareCircle"
WHERE NOT EXISTS (
  SELECT 1
  FROM "CareRecipient"
  WHERE "CareRecipient"."circleId" = "CareCircle"."id"
);

-- Attach existing tasks to the primary recipient of their circle.
UPDATE "Task"
SET "recipientId" = "CareRecipient"."id"
FROM "CareRecipient"
WHERE "Task"."circleId" = "CareRecipient"."circleId"
  AND "CareRecipient"."isPrimary" = true
  AND "Task"."recipientId" IS NULL;
