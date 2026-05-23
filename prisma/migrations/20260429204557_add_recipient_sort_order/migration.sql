-- AlterTable
ALTER TABLE "CareRecipient" ADD COLUMN     "sortOrder" INTEGER NOT NULL DEFAULT 0;

WITH ranked AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY "circleId"
            ORDER BY "isPrimary" DESC, "createdAt" ASC, id ASC
        ) - 1 AS next_sort_order
    FROM "CareRecipient"
)
UPDATE "CareRecipient"
SET "sortOrder" = ranked.next_sort_order
FROM ranked
WHERE "CareRecipient".id = ranked.id;
