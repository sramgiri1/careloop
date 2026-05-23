# Sprint 2 Gap Audit

Date: 2026-04-26
Status: Open

## Summary

Sprint 2 was marked complete in the task queue, but the codebase is still missing core planned implementation. The gaps below were verified against `docs/sprint-plan.md`, the backend source, the iOS app source, and Prisma schema.

## Verified Present

- `PATCH /users/:id/push-token` exists in `src/routes/users.js`
- Task creation creates a `Reminder` row when `dueAt` is set
- `User.pushToken`, `User.timezone`, `Reminder.sentAt`, and `Reminder.escalatedAt` exist in schema
- Local QA skill path for simulator boot and XCTest is now working again

## Missing Backend Scope

- `src/scheduler/index.js` does not exist
- No `node-cron` scheduler is wired into `src/index.js`
- No reminder send loop
- No escalation loop
- No daily digest loop
- No APNs sender module (for reminder, escalation, assignment notifications)
- No email fallback logic for missing push tokens
- No digest HTML generator
- No digest idempotency implementation using `DigestLog`
- `DigestLog.messageId` is missing from Prisma schema

## Missing iOS Scope

- No notification permission sheet component
- No `UNUserNotificationCenter` authorization request flow
- No remote notification registration
- No app delegate callback for APNs token registration
- No push token upload client method in `Endpoints.swift`
- No foreground notification banner delegate
- No deep-link handling from push tap into task navigation
- No `pendingTaskId` or equivalent app-state routing hook

## Missing QA / Sign-Off Artifacts

- `docs/qa/checklist-sprint2.md` missing
- Sprint 2 sign-off file missing
- Sprint docs still say Sprint 2 is in progress

## Required To Close Sprint 2

1. Implement backend scheduler, push sender, digest flow, and schema update
2. Implement iOS notification permission, token registration, and deep-link flow
3. Write Sprint 2 QA checklist and sign-off
4. Re-run local verification and update sprint-close docs
