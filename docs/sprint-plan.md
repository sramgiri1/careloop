# CareLoop — 3-Sprint Delivery Plan

**Sprints:** 4 × 2 weeks  
**Capacity:** Solo founder + AI  
**Public launch:** End of Sprint 4  
**Status:** Sprint 4 in progress — subscription system delivered 2026-05-01

---

## Sprint 1 — Core Coordination Complete

**Goal:** Finish the real day-to-day coordination product before adding automations.

**Scope:**

- Finalize the core user journey: create circle, join circle, create task, view tasks, complete tasks, resume session
- Complete task-management behavior to match the PRD role model:
  - Members can complete any task
  - Members can edit, skip, and delete only their own tasks
  - Admins can edit any task and reassign tasks
- Add missing iOS screens/flows:
  - Task detail / edit
  - Skip / delete own task
  - Admin assignee picker and reassign flow
  - Admin circle settings (edit circle name, recipient name)
  - Basic member list display so assignment is usable
- Keep Sprint-1-style access model:
  - Shared app API key
  - Self-join by circle ID
  - GET routes API-key-only (no membership enforcement)
- Emit required analytics events: `CIRCLE_CREATED`, `TASK_CREATED`, `TASK_COMPLETED`, `APP_SESSION`
- Add basic manual QA support:
  - Repeatable seed/reset flow for local testing
  - Written test checklist for onboarding, join, task CRUD, and role restrictions

**Exit criteria:**

- A user can create a circle or self-join an existing one
- An admin can assign and reassign tasks from the app
- A member can complete any task and edit/skip/delete only their own
- The app survives relaunch and restores session/circle state
- Role-based mutation rules return correct `401/403/404/409` responses

---

## Sprint 2 — Reminders, Digests, and Push

**Goal:** Deliver the automation features that make CareLoop materially better than group text.

**Operating rule:** Build Sprint 2 to feature-complete locally before paying for deployment or Apple infrastructure. Treat Railway deploy, APNs, and live email verification as late-stage validation work inside the sprint, not prerequisites to begin coding.

**Scope:**

- Implement background scheduler using `node-cron` inside the API process
- Build reminder processing:
  - Create reminder at `dueAt - 15m`
  - Send scheduled reminder
  - Re-check 15 minutes later
  - Escalate if still not `DONE`
  - Update `Reminder.status`, `sentAt`, and `escalatedAt`
- Build daily digest delivery:
  - 6pm per-user local timezone
  - Due today, overdue, completed today
  - Plain HTML via Resend
  - Idempotent send using `DigestLog`
- Wire push end-to-end:
  - iOS notification permission request
  - APNs device token registration
  - Upload token to backend
  - Backend push sender for reminder, escalation, and task assignment notifications
  - If Apple infrastructure is not yet provisioned, complete the code paths locally with clear mock/stub verification points
- Implement fallback rules:
  - No push token → send email where PRD requires fallback
  - Resend failure → mark failed, no retry in Sprint 2
- Add missing data plumbing:
  - `DigestLog.messageId` for outbound digest correlation
  - Minimal delivery metadata for push/email tracing
- Keep digest-open tracking deferred — do not block Sprint 2 on webhook analytics
- Keep paid external verification deferred until the local feature set is stable

**Exit criteria:**

- A task with `dueAt` creates a reminder and sends at the correct time
- An overdue task escalates correctly
- Assignment notifications send when an admin assigns or reassigns
- A user with timezone set receives one digest at 6pm local time
- Digest sends are idempotent per user/day
- Push missing or failing falls back per PRD rules

**Deferred verification inside Sprint 2:**

- Railway deploy and deployed migration verification
- Live APNs delivery
- Live Resend delivery verification
- Apple Developer account and APNs key provisioning

---

## Sprint 3 — Public Launch Hardening

**Goal:** Replace private-build shortcuts with launch-grade access control, admin controls, and release readiness.

**Scope:**

- Replace shared `x-api-key` with per-user auth:
  - CareLoop-owned email/password auth for iOS sign-in
  - Backend validates first-party bearer tokens signed with `AUTH_TOKEN_SECRET`
  - App traffic stops using shared API key
- Replace self-join by plain circle ID with launch-safe invite flow:
  - Admin creates invite link/token
  - Invited user redeems token after auth
  - Invite creates membership as `MEMBER`
  - Disable direct public self-join in production
- Enforce membership on all read endpoints:
  - `GET /circles/:id`
  - `GET /circles/:circleId/tasks`
  - `GET /circles/:circleId/events`
- Add final admin/member-management UX:
  - Promote/demote member
  - Remove member
  - Generate/share invite
  - Admin settings polish
- Finish launch readiness:
  - Privacy policy live
  - `incident-response.md` completed and shipped
  - Production env separation and config audit
  - Release checklist and smoke test pass
  - TestFlight / App Store submission readiness
- Clarify launch-time auth and reads:
  - Bearer-token auth starts here
  - Membership-checked reads start here
  - `GET /users/:id` becomes authenticated and self-only here
- Post-launch deferrals (explicitly out of Sprint 3):
  - Digest open tracking webhook
  - Retry logic
  - Distributed scheduler
  - User-facing activity feed

**Exit criteria:**

- A brand-new public user can authenticate, accept an invite, join only authorized circles, and use the app without developer setup
- Non-members cannot read circle data
- Removed users lose access
- Reminders, digests, and assignment notifications work in the production path
- Compliance docs and release checklist are complete

---

## Public API Changes by Sprint

**Sprint 1:** No breaking API change. iOS must begin using existing task patch/delete and circle patch/member-management routes already in the backend.

**Sprint 2:** Add non-user-facing scheduler modules and delivery services. Add `DigestLog.messageId`. No new public mobile endpoint required if push token upload stays on the existing user route.

**Sprint 3:**
- Replace `x-api-key` mobile auth with `Authorization: Bearer <accessToken>`
- Add invite endpoints: `POST /circles/:id/invites` (admin-only), `POST /invites/redeem` (authenticated)
- Deprecate production use of `POST /circles/:id/members` self-join
- Change read routes from API-key-only to authenticated + membership-checked
- Make `GET /users/:id` authenticated and self-only

---

## Test Plan

**Sprint 1:** Create circle, join circle, restore session. Member edit/skip/delete own task only. Admin reassign/edit any task. Unauthorized and role-forbidden mutations return correct status codes.

**Sprint 2:** Reminder created only when `dueAt` exists. Reminder scheduler is idempotent. Done-before-escalation suppresses escalation. No push token triggers fallback path. Digest sends once per local day and timezone is respected.

**Sprint 3:** Unauthenticated requests fail. Non-member reads fail. Invite redeem works once only. Removed member loses access immediately. Production-path smoke test from sign-in to task completion passes. Full manual regression on at least one simulator and one physical device.

---

---

## Sprint 4 — Public Launch Hardening and Monetization

**Goal:** Ship the subscription system, harden the app for App Store submission, and complete launch readiness.

**Scope:**

- **iOS subscription system (DELIVERED 2026-05-01):**
  - `SubscriptionManager.swift` — StoreKit 2 singleton (`@MainActor ObservableObject`):
    - Product IDs: `com.careloop.ios.premium.monthly`, `com.careloop.ios.premium.yearly`
    - `loadProducts()` → `Product.products(for:)` on init
    - `refreshEntitlements()` → `Transaction.currentEntitlements` async sequence
    - `observeTransactionUpdates()` → `Transaction.updates` observer; finishes both verified and unverified transactions
    - `purchase(_ product:)` with haptic feedback on success
    - `restorePurchases()` via `AppStore.sync()` with user-visible restore message
    - `openSubscriptionManagement()` via `AppStore.showManageSubscriptions(in:)`
  - `PaywallView.swift` — dark-navy paywall:
    - Crown hero, "CareLoop Premium" headline, 6-feature checklist
    - Monthly/yearly plan cards with live prices from `product.displayPrice`
    - Yearly card shows "Best Value" badge
    - CTA shows `ProgressView` during initial product load and purchase
    - Auto-dismisses on `store.isPremium` becoming true
    - App Store-compliant disclosure text (auto-renewal, 24hr cancel rule, App Store Settings)
    - Trial-aware: shows trial length from `introductoryOffer` when present
    - Restore Purchases button with feedback message
  - `CircleListView` — premium UX integration:
    - Premium badge in header (crown + "Premium", teal) when `isPremium`
    - `upgradePrompt` card when free (purple gradient, "Unlock CareLoop Premium")
    - `showPaywall` sheet driven from parent `CircleListView` state
    - `AccountSheet` `onUpgrade` callback pattern (parent-owned state survives child sheet dismissal)
    - Enhanced hero: "Hi, [firstName]" greeting, stat pills for circles and invites
  - 34 unit tests in `SubscriptionManagerTests.swift` across 5 test classes
- Privacy policy live
- `incident-response.md` completed and shipped
- Production env separation and config audit
- TestFlight / App Store submission readiness
- Server-side entitlement sync (map Apple transaction to group-level premium unlock)
- Group-level premium unlocks
- Admin insights charts
- Launch QA for full invite-based onboarding path

**Deferred post-launch:**

- Distributed scheduler
- User-facing activity feed
- `DIGEST_OPENED` webhook
- Retry logic

**Exit criteria:**

- iOS subscription purchase, trial start, and restore all work end-to-end in TestFlight
- Paywall satisfies App Store Review Guidelines (disclosure text, compliant payment path)
- Server-side entitlement sync maps Apple transaction to group premium status
- Compliance docs live and reviewed
- Full smoke test from sign-in → task completion → subscription purchase passes

---

## Assumptions

- Sprint length: 2 weeks, fixed
- Capacity: solo founder + AI — no additional engineer bandwidth assumed
- Stack: iOS SwiftUI, Fastify + Prisma, PostgreSQL/Supabase, Resend, APNs, StoreKit 2
- Public launch by Sprint 4 is realistic only if scope is frozen to this plan
- `DIGEST_OPENED` tracking is post-launch unless Sprint 4 finishes early
- `SHEPHERD`, `WARDEN`, and `RELAY` are process ownership roles used in founder workflow; runner wiring is deferred
- EHR/clinic, medication tracking, web, Android, AI features: permanently out of scope for v1
