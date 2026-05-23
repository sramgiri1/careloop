-- AlterTable
ALTER TABLE "Invitation" ADD COLUMN "recipientId" TEXT;

-- CreateIndex
CREATE INDEX "Invitation_recipientId_idx" ON "Invitation"("recipientId");

-- AddForeignKey
ALTER TABLE "Invitation" ADD CONSTRAINT "Invitation_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "CareRecipient"("id") ON DELETE SET NULL ON UPDATE CASCADE;
