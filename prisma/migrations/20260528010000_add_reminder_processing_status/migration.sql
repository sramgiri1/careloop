ALTER TYPE "ReminderStatus" ADD VALUE IF NOT EXISTS 'PROCESSING';
ALTER TYPE "ReminderStatus" ADD VALUE IF NOT EXISTS 'ESCALATING';

ALTER TABLE "Reminder" ADD COLUMN "processingStartedAt" TIMESTAMP(3);

CREATE INDEX "Reminder_status_processingStartedAt_idx" ON "Reminder"("status", "processingStartedAt");
