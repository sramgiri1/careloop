-- CreateEnum
CREATE TYPE "CareRecipientActivationStatus" AS ENUM ('DRAFT', 'INVITED', 'ACTIVE', 'PROXY_ACTIVE');

-- CreateEnum
CREATE TYPE "CareRecipientEntitlementStatus" AS ENUM ('FREE', 'ACTIVE', 'EXPIRED', 'REVOKED');

-- CreateEnum
CREATE TYPE "CareRecipientEntitlementSource" AS ENUM ('APP_STORE', 'MANUAL');

-- AlterTable
ALTER TABLE "CareRecipient"
ADD COLUMN "activationStatus" "CareRecipientActivationStatus" NOT NULL DEFAULT 'DRAFT',
ADD COLUMN "activatedAt" TIMESTAMP(3),
ADD COLUMN "receiverUserId" TEXT,
ADD COLUMN "consentAttestedAt" TIMESTAMP(3),
ADD COLUMN "consentAttestedById" TEXT,
ADD COLUMN "proxyAuthorizedById" TEXT,
ADD COLUMN "consentDocumentReference" TEXT;

-- CreateTable
CREATE TABLE "CareRecipientAccess" (
    "id" TEXT NOT NULL,
    "grantedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "recipientId" TEXT NOT NULL,
    "memberId" TEXT NOT NULL,
    "grantedById" TEXT,

    CONSTRAINT "CareRecipientAccess_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CareRecipientEntitlement" (
    "id" TEXT NOT NULL,
    "status" "CareRecipientEntitlementStatus" NOT NULL DEFAULT 'FREE',
    "source" "CareRecipientEntitlementSource",
    "startsAt" TIMESTAMP(3),
    "expiresAt" TIMESTAMP(3),
    "appleOriginalTransactionId" TEXT,
    "appleProductId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "recipientId" TEXT NOT NULL,
    "purchasedById" TEXT,

    CONSTRAINT "CareRecipientEntitlement_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "CareRecipient_circleId_activationStatus_idx" ON "CareRecipient"("circleId", "activationStatus");

-- CreateIndex
CREATE INDEX "CareRecipient_receiverUserId_idx" ON "CareRecipient"("receiverUserId");

-- CreateIndex
CREATE UNIQUE INDEX "CareRecipientAccess_recipientId_memberId_key" ON "CareRecipientAccess"("recipientId", "memberId");

-- CreateIndex
CREATE INDEX "CareRecipientAccess_memberId_revokedAt_idx" ON "CareRecipientAccess"("memberId", "revokedAt");

-- CreateIndex
CREATE UNIQUE INDEX "CareRecipientEntitlement_recipientId_key" ON "CareRecipientEntitlement"("recipientId");

-- CreateIndex
CREATE INDEX "CareRecipientEntitlement_status_expiresAt_idx" ON "CareRecipientEntitlement"("status", "expiresAt");

-- AddForeignKey
ALTER TABLE "CareRecipient" ADD CONSTRAINT "CareRecipient_receiverUserId_fkey" FOREIGN KEY ("receiverUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CareRecipient" ADD CONSTRAINT "CareRecipient_consentAttestedById_fkey" FOREIGN KEY ("consentAttestedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CareRecipient" ADD CONSTRAINT "CareRecipient_proxyAuthorizedById_fkey" FOREIGN KEY ("proxyAuthorizedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CareRecipientAccess" ADD CONSTRAINT "CareRecipientAccess_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "CareRecipient"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CareRecipientAccess" ADD CONSTRAINT "CareRecipientAccess_memberId_fkey" FOREIGN KEY ("memberId") REFERENCES "CircleMember"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CareRecipientAccess" ADD CONSTRAINT "CareRecipientAccess_grantedById_fkey" FOREIGN KEY ("grantedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CareRecipientEntitlement" ADD CONSTRAINT "CareRecipientEntitlement_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "CareRecipient"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CareRecipientEntitlement" ADD CONSTRAINT "CareRecipientEntitlement_purchasedById_fkey" FOREIGN KEY ("purchasedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
