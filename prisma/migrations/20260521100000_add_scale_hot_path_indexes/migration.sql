CREATE INDEX IF NOT EXISTS "PasswordResetCode_userId_consumedAt_createdAt_idx"
  ON "PasswordResetCode"("userId", "consumedAt", "createdAt");

CREATE INDEX IF NOT EXISTS "Invitation_circleId_status_createdAt_idx"
  ON "Invitation"("circleId", "status", "createdAt");

CREATE INDEX IF NOT EXISTS "Invitation_email_status_createdAt_idx"
  ON "Invitation"("email", "status", "createdAt");

CREATE INDEX IF NOT EXISTS "CareRecipient_circleId_isPrimary_sortOrder_createdAt_idx"
  ON "CareRecipient"("circleId", "isPrimary", "sortOrder", "createdAt");

CREATE INDEX IF NOT EXISTS "CircleMember_circleId_role_idx"
  ON "CircleMember"("circleId", "role");

CREATE INDEX IF NOT EXISTS "CareRecipientAccess_recipientId_revokedAt_idx"
  ON "CareRecipientAccess"("recipientId", "revokedAt");

CREATE INDEX IF NOT EXISTS "Task_circleId_archivedAt_completedAt_dueAt_createdAt_idx"
  ON "Task"("circleId", "archivedAt", "completedAt", "dueAt", "createdAt");

CREATE INDEX IF NOT EXISTS "Task_circleId_recipientId_archivedAt_status_dueAt_idx"
  ON "Task"("circleId", "recipientId", "archivedAt", "status", "dueAt");

CREATE INDEX IF NOT EXISTS "Task_circleId_status_completedAt_idx"
  ON "Task"("circleId", "status", "completedAt");

CREATE INDEX IF NOT EXISTS "Task_assigneeId_status_dueAt_idx"
  ON "Task"("assigneeId", "status", "dueAt");

CREATE INDEX IF NOT EXISTS "Task_creatorId_createdAt_idx"
  ON "Task"("creatorId", "createdAt");

CREATE INDEX IF NOT EXISTS "Task_seriesId_dueAt_idx"
  ON "Task"("seriesId", "dueAt");

CREATE INDEX IF NOT EXISTS "TaskComment_taskId_createdAt_idx"
  ON "TaskComment"("taskId", "createdAt");

CREATE INDEX IF NOT EXISTS "TaskComment_authorId_createdAt_idx"
  ON "TaskComment"("authorId", "createdAt");

CREATE INDEX IF NOT EXISTS "Reminder_taskId_idx"
  ON "Reminder"("taskId");

CREATE INDEX IF NOT EXISTS "Reminder_status_escalatedAt_idx"
  ON "Reminder"("status", "escalatedAt");

CREATE INDEX IF NOT EXISTS "Event_circleId_createdAt_idx"
  ON "Event"("circleId", "createdAt");

CREATE INDEX IF NOT EXISTS "Event_actorId_type_createdAt_idx"
  ON "Event"("actorId", "type", "createdAt");
