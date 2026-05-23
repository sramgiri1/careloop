-- CreateEnum
CREATE TYPE "RecurrenceFrequency" AS ENUM ('NONE', 'DAILY', 'WEEKLY', 'MONTHLY', 'CUSTOM');

-- AlterEnum
ALTER TYPE "EventType" ADD VALUE 'TASK_SERIES_CREATED';

-- AlterTable
ALTER TABLE "Task" ADD COLUMN     "completedById" TEXT,
ADD COLUMN     "recurrenceEndsAt" TIMESTAMP(3),
ADD COLUMN     "recurrenceFrequency" "RecurrenceFrequency" NOT NULL DEFAULT 'NONE',
ADD COLUMN     "recurrenceInterval" INTEGER,
ADD COLUMN     "recurrenceWeekdays" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "seriesId" TEXT;

-- AddForeignKey
ALTER TABLE "Task" ADD CONSTRAINT "Task_completedById_fkey" FOREIGN KEY ("completedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
