ALTER TYPE "InvitationStatus" ADD VALUE 'EXPIRED';

ALTER TABLE "Invitation"
ADD COLUMN "expiresAt" TIMESTAMP(3);

CREATE INDEX "Invitation_status_expiresAt_idx" ON "Invitation"("status", "expiresAt");
