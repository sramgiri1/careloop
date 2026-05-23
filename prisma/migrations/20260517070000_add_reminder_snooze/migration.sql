ALTER TYPE "ReminderStatus" ADD VALUE IF NOT EXISTS 'SNOOZED';
ALTER TYPE "ReminderStatus" ADD VALUE IF NOT EXISTS 'CANCELLED';
ALTER TYPE "EventType" ADD VALUE IF NOT EXISTS 'REMINDER_SNOOZED';

ALTER TABLE "Reminder"
  ADD COLUMN "snoozedUntil" TIMESTAMP(3),
  ADD COLUMN "snoozeCount" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "escalationDueAt" TIMESTAMP(3);

CREATE INDEX "Reminder_status_scheduledAt_idx" ON "Reminder"("status", "scheduledAt");
CREATE INDEX "Reminder_status_escalationDueAt_idx" ON "Reminder"("status", "escalationDueAt");
