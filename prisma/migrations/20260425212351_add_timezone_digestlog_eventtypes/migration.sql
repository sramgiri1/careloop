-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "EventType" ADD VALUE 'CIRCLE_CREATED';
ALTER TYPE "EventType" ADD VALUE 'TASK_DELETED';
ALTER TYPE "EventType" ADD VALUE 'MEMBER_REMOVED';
ALTER TYPE "EventType" ADD VALUE 'DIGEST_OPENED';
ALTER TYPE "EventType" ADD VALUE 'APP_SESSION';

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "timezone" TEXT;

-- CreateTable
CREATE TABLE "DigestLog" (
    "id" TEXT NOT NULL,
    "date" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "userId" TEXT NOT NULL,

    CONSTRAINT "DigestLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "DigestLog_userId_date_key" ON "DigestLog"("userId", "date");

-- AddForeignKey
ALTER TABLE "DigestLog" ADD CONSTRAINT "DigestLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
