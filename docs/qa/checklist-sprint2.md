# CareLoop Sprint 2 — QA Checklist

**Status:** FEATURES COMPLETE — 7/7 features implemented, manual QA pending  
**Date:** 2026-05-02  
**Gate owner:** SENTINEL

---

## Automated test results

### Backend (`npm test`)

```text
58 passed | 0 failed
Coverage includes:
- auth signup/login/social + forgot-password
- bearer-token enforcement
- self-only user mutations
- member/admin circle authorization
- multi-user signup → invite → accept → self-join flow
- reminder/digest delivery and escalation rules
- notification preference persistence and assignment/escalation/digest opt-out delivery gates
- recurring tasks and archive behavior
- admin completion insights, receiver adherence summaries, missed-trend reporting, caregiver load distribution, and escalation response reporting
```

### iOS (`xcodebuild test` + Sentinel)

```text
sentinel qa.tests.execute: 52 passed | 0 failed | 52 executed
```

---

## Sprint 2 exit criteria

### 1. Push token registration

- [x] `PATCH /users/:id/push-token` returns 200 with updated user  
- [x] pushToken persisted in DB  
- [x] Returns 400 when pushToken absent from body  
- [x] Returns 401 without valid bearer token  

**curl:**

```bash
curl -X PATCH http://localhost:3000/users/<userId>/push-token \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"pushToken":"<device-hex-token>"}'
```

### 2. Reminder creation — task with dueAt

- [x] Creating task with `dueAt` creates `Reminder` with `status=PENDING`  
- [x] `scheduledAt` = `dueAt - 15 minutes` (verified to within 2s)  
- [x] Creating task without `dueAt` creates NO Reminder  
- [x] `TASK_CREATED` event logged for every task  

**curl:**

```bash
curl -X POST http://localhost:3000/circles/<circleId>/tasks \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Give meds","recipientId":"<recipientId>","dueAt":"2026-04-27T10:00:00Z"}'
```

### 3. Reminder send — scheduler loop

- [x] `processPendingReminders` finds `Reminder.status=PENDING` where `scheduledAt <= now`  
- [x] `processPendingReminders` also sends expired `SNOOZED` reminders when their moved `scheduledAt <= now`
- [x] Calls `sendReminderNotifications` for assignee or creator  
- [x] Updates `Reminder.status=SENT`, `sentAt=now`  
- [x] Logs `REMINDER_SENT` event  
- [x] No push token → falls back to email (or NONE if no email either)  
- [x] Simulated mode (no APNS config) returns `{simulated:true}` without crashing  
- [x] Simulator deep-link coverage includes organizer and care receiver pending tasks, completed tasks, and wrong-circle guards

### 3A. Reminder snooze

- [x] `POST /circles/:circleId/tasks/:taskId/reminder/snooze` accepts 15, 60, or 1440 minutes only
- [x] Assigned caregiver, task creator, or Care Organizer can snooze an active reminder
- [x] Snooze moves `scheduledAt`, sets `snoozedUntil`, increments `snoozeCount`, and logs `REMINDER_SNOOZED`
- [x] Snooze response and stored reminder expose the same rescheduled `scheduledAt` / `snoozedUntil` window
- [x] Snoozed reminders do not send before the new `scheduledAt`
- [x] Completed and skipped tasks cannot be snoozed
- [x] iOS Task Detail exposes 15 min / 1 hour / Tomorrow snooze controls and confirms the rescheduled reminder time with UI test coverage

### 4. Escalation — 15-minute window

- [x] Reminder with `status=SENT` and `sentAt <= (now - 15min)` qualifies for escalation  
- [x] Reminder with `sentAt <= (now - 14min)` does NOT qualify  
- [x] `task.status = DONE` suppresses escalation (Prisma filter: `task.status { not: "DONE" }`)  
- [x] `task.status = SKIPPED` also suppresses reminder send and escalation
- [x] Escalation fans out to the assignee, Care Organizers, and caregivers with explicit access to the task's care receiver
- [x] Updates `Reminder.status=ESCALATED`, `escalatedAt=now`  
- [x] Logs `REMINDER_ESCALATED` event with non-PII delivery summary counts/channels instead of raw delivery records
- [x] User-disabled escalation alerts are counted as blocked and do not force the reminder into `FAILED`

### 5. Daily digest

- [x] `sendDailyDigest` returns `{delivered:false,channel:"NONE"}` when user has no email  
- [x] Simulates send when `RESEND_API_KEY` not configured  
- [x] No crash when dueToday/overdue/completedToday contain real task objects  
- [x] Digest idempotency enforced via `DigestLog.userId_date` unique constraint (Prisma)  
- [x] `DIGEST_HOUR` defaults to 18 (6pm)  
- [x] `DIGEST_SENT` event logged with `messageId` and `simulated` flag  

**Verify idempotency:**

```bash
# Two calls on the same date must produce exactly one DigestLog row
SELECT COUNT(*) FROM "DigestLog" WHERE "userId"='<id>' AND date='2026-04-26';
-- expected: 1
```

### 6. No push token — graceful fallback

- [x] `deliverTaskNotification` tries push → falls to email → returns NONE if both absent  
- [x] No crash, no unhandled promise rejection  

### 7. Foreground push / deep link (iOS)

- [ ] Banner shown when app is foregrounded (`UNUserNotificationCenterDelegate.willPresent`)  
- [x] Tapping notification sets `AppState.pendingTaskId` via `careLoopPushTaskOpened` notification  
- [x] Reminder push payload includes `taskId`, `circleId`, and `recipientId` for scoped deep links  
- [x] Tapping notification sets both pending task and pending circle context when provided  
- [x] `CirclesView.syncDeepLink()` matches `pendingTaskId` to a task and sets `selectedTask` (drives navigationDestination)  
- [x] `CircleHomeView` observes `pendingTaskId`: navigates to `RecipientBoardView` for RECIPIENT role, `CirclesView` task list for ADMIN/MEMBER  
- [x] Wrong-circle pending task links do not open a task board until the owning circle is active  
- [x] `RecipientBoardView` observes `pendingTaskId` on appear and on tasks load — fires `highlightedTaskId` and calls `consumePendingTask()`  
- [x] `ScrollViewReader` scrolls to the highlighted task with `.center` anchor  
- [x] Rose-colored ring overlay animates in on matched task, fades after 2 seconds  
- [x] `consumePendingTask()` clears `pendingTaskId` after navigation — no double-fire  
- [ ] End-to-end: send push from server → tap banner → lands on correct task with highlight (physical device / TestFlight)  

**Note:** Banner display and end-to-end tap require a physical device or simulator with APNs. Mark end-to-end row after TestFlight in Sprint 3.

### 8. iOS unit tests (XCTest)

- [x] `AppState.pendingTaskId` defaults to nil  
- [x] `AppState.pendingTaskCircleId` defaults to nil  
- [x] `consumePendingTask()` clears pending task and circle values  
- [x] `consumePendingTask()` is idempotent when nil  
- [x] `careLoopPushTaskOpened` notification sets `pendingTaskId` and optional `pendingTaskCircleId`  
- [x] Push token request body encodes `{"pushToken": <value>}`  
- [x] Reminder scheduledAt = dueAt - 15min (unit)  
- [x] Escalation window boundary conditions (unit)  

---

## Remaining before Sprint 3

| Item | Owner | Blocker? |
|------|-------|----------|
| Foreground push + deep link (device test) | SWIFT + SENTINEL | No — needs TestFlight |
| Railway env vars: APNS_KEY, RESEND_API_KEY | FORGE | No — deploy gate |
| `incident-response.md` | WARDEN | No — pre-launch |
| DigestLog migration to prod DB | FORGE | Sprint 3 start |

---

## Auth and onboarding surface (local-first)

### 9. Sign in requires email and password

- [x] Sign In form shows email field
- [x] Sign In form shows password field
- [x] Validation rejects blank credentials
- [x] Validation rejects passwords shorter than 8 characters

### 10. Sign up and provider entry points

- [x] Sign Up surface exposes Email option
- [x] Sign Up surface exposes Google option
- [x] Sign Up surface exposes Facebook option
- [x] Sign Up surface exposes Apple option
- [x] Provider buttons launch real auth entry sessions
- [x] Email/password sign-up hits backend auth endpoint
- [x] Terms & Conditions link opens in-app terms and requires `OK, I agree` before sign-up
- [x] Backend stores accepted terms timestamp/version for first-time password and social account creation
- [x] Email/password login hits backend auth endpoint
- [x] Forgot-password request / verify / reset flow hits backend auth endpoints
- [x] Social sign-in resolves into a real CareLoop account session

### 10A. Transport auth and account isolation

- [x] Signup returns `accessToken`
- [x] Login returns `accessToken`
- [x] Social auth returns `accessToken`
- [x] `GET /users/me` returns the authenticated CareLoop user
- [x] `GET /users/:id` is self-only
- [x] `PATCH /users/:id/push-token` is self-only
- [x] `PATCH /users/:id/timezone` is self-only
- [x] `POST /users/:id/session` is self-only
- [x] Missing bearer token returns `401`
- [x] Invalid bearer token returns `401`
- [x] Legacy caller IDs that do not match the authenticated user are rejected with `403`
- [x] Password reset revokes previously issued bearer tokens
- [x] Logout revokes the current bearer token version server-side
- [x] Social auth accepts supported provider names case-insensitively and rejects unsupported providers
- [x] Production mode rejects local/dev social fallback payloads without provider token validation
- [x] iOS stores the bearer token in Keychain rather than `UserDefaults`

### 11. Circle setup after authentication

- [x] Join existing circle requires only `circleId`
- [x] Circle ID field does not auto-capitalize input
- [x] Joining a circle the user already belongs to re-enters that circle successfully
- [x] Create new circle requires `circle name`
- [x] Create new circle requires `circle name` only — `recipientName` is optional
- [x] New circles default `archiveAfterDays` to 7
- [x] Joining a fourth circle is blocked with a clear product error
- [x] Creating a fourth circle is blocked with a clear product error
- [x] Circle settings allows admins to edit archive retention from 1 to 30 days
- [x] After first circle creation, New Task opens automatically

### 12. Task lifecycle and archive behavior

- [x] Task list splits into `Active` and `Completed` sections
- [x] Saving task detail persists title, notes, due date, priority, assignee, and status together
- [x] Saving task detail persists recurrence together with the main task payload
- [x] Saving task detail returns the user to the task list
- [x] Completed or skipped tasks stay visible in `Completed` until retention window expires
- [x] Archived tasks are excluded from the normal tasks API response
- [x] Hourly scheduler archives completed/skipped tasks once `completedAt + archiveAfterDays` has elapsed

### 12A. Recurring tasks

- [x] Creating a recurring task requires `dueAt`
- [x] Recurring task create accepts frequency + interval + optional end date
- [x] Recurring tasks render recurrence copy in the task list
- [x] Completing a recurring task creates the next occurrence automatically
- [x] New recurring occurrence keeps the same `seriesId`
- [x] New recurring occurrence gets a fresh reminder at `dueAt - 15 minutes`
- [x] Task detail allows recurrence editing and saving
- [x] Weekly recurrence weekday selection UI
- [x] Edit-one-occurrence vs edit-whole-series split

### 13. Multi-circle operations

- [x] Data model allows one user to belong to multiple circles
- [x] Joining or creating an additional circle does not remove existing memberships
- [x] Total memberships per user are capped at 3 across self-join, create, and admin-add flows
- [x] Authenticated users land on a circle list page first
- [x] Tapping a circle opens a circle hub with explicit operations
- [x] Circle hub links to task board, members, settings, and admin insights
- [x] Returning from an active circle back to the circle list is a first-class nav action
- [x] Switching circles reloads the selected circle context before opening operations
- [x] Last selected circle is persisted for session restore
- [x] Admin-only full circle deletion is covered by backend regression tests
- [x] Non-admin full circle deletion is blocked by backend regression tests
- [ ] Manual QA for switching between two circles and confirming task scope follows the active circle on device

### 13A. Multi-recipient group operations

- [x] Every new circle creates a primary care recipient profile from the setup flow
- [x] Existing circles are backfilled with one primary care recipient during DB migration
- [x] Admin can add another care recipient inside group settings
- [x] Admin can edit a care recipient's name and relationship
- [x] Admin cannot remove the last remaining care recipient
- [x] Admin cannot remove a care recipient while active tasks still point at them
- [x] Task creation is scoped to a selected care recipient
- [x] Task create / fetch responses include the full recipient payload required by iOS decode (`notes`, `sortOrder`)
- [x] Task detail editing can change the task recipient
- [x] Task list exposes an all-recipient view plus a per-recipient filter
- [x] Active circle card summarizes one or more recipients cleanly
- [x] Recipient reordering / primary recipient reassignment UI
- [x] Invite acceptance flow tied to recipient-aware group onboarding

### 14. Member management

- [x] Admin can invite a member by name + email from the member list
- [x] Admin can choose `MEMBER` or `ADMIN` access before sending the invite
- [x] Invited email stays `PENDING` until the invited user authenticates and accepts
- [x] New invites include a server-side expiration timestamp
- [x] Expired pending invites cannot be accepted and are marked `EXPIRED`
- [x] Expired recipient invites reset unclaimed receiver state and allow a fresh invite
- [x] Pending invites are visible to admins and can be revoked
- [x] Admin can remove another member from the active circle
- [x] Admin can promote a caregiver to `ADMIN`
- [x] Admin can demote another caregiver back to `MEMBER`
- [x] Removing the last remaining admin is blocked at the API
- [ ] Manual QA: invite a member, verify they accept after auth, then remove them

### 14A. Multi-user live flow

- [x] Create admin account via `/auth/signup`
- [x] Create invitee account via `/auth/signup`
- [x] Create third user account via `/auth/signup`
- [x] Admin creates a new circle
- [x] Admin invites the second user to the circle
- [x] Invitee sees the pending invitation on `GET /users/me`
- [x] Invitee accepts the invitation after authentication
- [x] Third user joins the same circle by circle ID
- [x] Invitee can fetch the circle as a member
- [x] Third user can fetch the circle task list as a member

### 15. Admin completion insights

- [x] Admin-only completion insights endpoint returns `completedByDay`
- [x] Admin-only completion insights endpoint returns `topCaregivers`
- [x] Admin-only completion insights endpoint returns `totals.completed`
- [x] Admin-only completion insights endpoint returns `totals.active`
- [x] Admin-only completion insights endpoint returns `totals.overdue`
- [x] iOS settings exposes `Completion Insights` for admins
- [x] iOS insights view shows 7 / 14 / 30 day window switching
- [x] iOS insights view can filter the chart window by recipient
- [x] iOS insights view renders a completion chart per day
- [x] iOS insights view renders top caregiver counts
- [x] Recipient-level insights breakdown for multi-recipient groups

**XCTest coverage:**

```text
OnboardingValidationTests
- sign in requires email + password
- sign up requires name + email + password + confirm password
- provider list includes Email / Google / Facebook / Apple
- social helper text references real CareLoop account access
- auth callback parsing extracts email + name

ModelTests
- recurring task summary labels
- completion insight day label formatting
- active-circle membership ordering
- directory-state sign-in without an explicit active circle
```

**Boundary note:** Email/password auth and forgot-password are fully wired through the CareLoop backend. Social sign-in launches through backend-owned OAuth start/callback routes and resolves to real CareLoop users plus linked identities, but still depends on real provider credentials and approved redirect URIs. The local build now includes invite acceptance, a circle list root, a circle hub, recipient profiles, recipient-scoped tasks, recipient filters, admin recipient management, recipient reordering, weekly weekday recurrence selection, and recipient-aware completion insights. Remaining major product work is public invite delivery hardening, physical-device push validation, and the paid entitlement layer.

---

### 16. Care receiver task assignment (Feature #1)

#### Backend

- [x] `POST /circles/:id/invitations` accepts `role=RECIPIENT` (Prisma enum includes RECIPIENT)
- [x] `PATCH /circles/:id/members/:memberId` accepts `role=RECIPIENT`
- [x] `PATCH /circles/:id/tasks/:taskId` — RECIPIENT can only update `status=DONE` on tasks assigned to themselves
- [x] RECIPIENT attempting to edit title/notes/dueAt/assigneeId returns `403`
- [x] RECIPIENT attempting to set status other than DONE returns `403`
- [x] Task assigned to RECIPIENT triggers `recipientAssignment` notification type ("A care reminder was set for you")
- [x] Reminder fires `recipientReminder` type for RECIPIENT assignees ("Care reminder")

**curl — invite as RECIPIENT:**

```bash
curl -X POST http://localhost:3000/circles/<circleId>/invitations \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Jane Doe","email":"jane@example.com","role":"RECIPIENT"}'
```

**curl — RECIPIENT marks own task done:**

```bash
curl -X PATCH http://localhost:3000/circles/<circleId>/tasks/<taskId> \
  -H "Authorization: Bearer $RECIPIENT_TOKEN" -H "Content-Type: application/json" \
  -d '{"status":"DONE"}'
```

**curl — RECIPIENT editing title (expect 403):**

```bash
curl -X PATCH http://localhost:3000/circles/<circleId>/tasks/<taskId> \
  -H "Authorization: Bearer $RECIPIENT_TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Hacked title"}'
# Expected: 403 "Care receivers can only mark their own assigned tasks as done"
```

#### iOS (RecipientBoardView)

- [x] Assignee picker labels RECIPIENT members as "(Care Receiver)"
- [x] RecipientBoardView shows "Your reminder" rose badge on tasks assigned to the current user
- [x] "I've done this" rose button appears for own tasks with status pending/in-progress
- [x] Tapping "I've done this" calls `PATCH /tasks/:id { status: DONE }` and updates row in-place
- [x] Tasks assigned to other members show caregiver name label instead
- [x] RECIPIENT users land on RecipientBoardView directly (not the admin task list)

### 17. Push notification deep link — care receiver flow (Feature #1)

- [x] `AppState.pendingTaskId` set via `careLoopPushTaskOpened` notification
- [x] `CircleHomeView.onChange(of: appState.pendingTaskId)` sets `deepLinkToTaskBoard = true` exactly once (guard prevents double-set)
- [x] `navigationDestination(isPresented: $deepLinkToTaskBoard)` routes to `RecipientBoardView` for RECIPIENT, `CirclesView` for ADMIN/MEMBER
- [x] `RecipientBoardView.onChange(of: appState.pendingTaskId)` fires highlight + consume when tasks already loaded
- [x] `RecipientBoardView.onChange(of: tasks)` fires highlight + consume when tasks load after pendingTaskId was set
- [x] `highlightedTaskId` guard prevents double-consume race between the two `onChange` handlers
- [x] `Task.sleep(2s)` clears `highlightedTaskId` using structured concurrency (cancels on re-navigation)
- [x] Rose ring overlay animates in/out on the matched task card (`.easeOut(duration: 0.3)`)
- [x] `ScrollViewReader.scrollTo(id, anchor: .center)` scrolls to the highlighted task
- [x] `consumePendingTask()` called exactly once — `pendingTaskId` becomes nil after navigation
- [ ] End-to-end: physical device — push arrives, tap opens app, lands on correct task with highlight visible for 2s

---

### 18. Completion acknowledgment — "Done by [Name]" (Feature #2)

#### Backend (Feature #2)

- [x] `GET /circles/:id/tasks` response includes `completedBy: { id, name, email }` on done tasks
- [x] `completedById` set to the authenticated user's id when `status=DONE` is patched
- [x] `completedBy` is `null` when status is pending, in-progress, or skipped

**curl — verify completedBy populated:**

```bash
curl -X PATCH http://localhost:3000/circles/<circleId>/tasks/<taskId> \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"status":"DONE"}' | jq '.completedBy'
# Expected: { "id": "...", "name": "Jane Doe", "email": "..." }
```

#### iOS (Feature #2)

- [x] `CareTask` model includes `completedById: String?` and `completedBy: CareUser?` decoded from API
- [x] `TaskRowView` meta row shows "Done by [firstName]" green chip when `task.status == .done && completedBy != nil`
- [x] `TaskRowView` hides due date and assignee chips on done tasks (replaced by "Done by")
- [x] `RecipientBoardView` done task rows show "Done by [firstName]" green label instead of "Your reminder" or assignee
- [x] `RecipientBoardView` done task rows hide due date label
- [x] `TaskDetailView` status card shows "Completed by [full name]" below the status chips when done with completedBy
- [x] Completing a task via "I've done this" (RecipientBoardView) — row updates to show "Done by [firstName]" after in-place refresh
- [x] Completing the next due task from care receiver home advances the home card to the next open task
- [x] Tasks completed before this update (no `completedBy`) degrade gracefully — no crash, row shows "Done" fallback chip
- [x] `.skipped` tasks show "Done" fallback chip (not "Done by") since `completedBy` is nil for skipped
- [x] `TaskDetailView` "Completed by" row and bottom padding react to `@State var status`, not `task.status` (no desync on chip tap)

---

### 19. Completion notifications (Feature #3)

#### Backend (Feature #3)

- [x] New notification type `taskCompletedForRecipient` — title "Care task completed", body "[firstName] completed: [title]"
- [x] New notification type `recipientCompletedTask` — title "[recipientName] completed a task", body "[title]"
- [x] `deliverTaskNotification` accepts optional `extra` string passed through to notification copy
- [x] When non-RECIPIENT member marks a RECIPIENT-assigned task DONE → `taskCompletedForRecipient` sent to the assignee (care receiver)
- [x] When RECIPIENT marks their own task DONE → `recipientCompletedTask` sent to task creator (if different from the RECIPIENT)
- [x] No notification sent when member completes their own task (`assigneeId == authenticatedUserId`)
- [x] No notification sent when creator completes a task not assigned to a RECIPIENT

**curl — caregiver completes RECIPIENT task (expect notification to recipient):**

```bash
curl -X PATCH http://localhost:3000/circles/<circleId>/tasks/<taskId> \
  -H "Authorization: Bearer $CAREGIVER_TOKEN" -H "Content-Type: application/json" \
  -d '{"status":"DONE"}'
# Recipient should receive: "Care task completed — [caregiver] completed: [title]"
```

**curl — RECIPIENT marks own task done (expect notification to creator):**

```bash
curl -X PATCH http://localhost:3000/circles/<circleId>/tasks/<taskId> \
  -H "Authorization: Bearer $RECIPIENT_TOKEN" -H "Content-Type: application/json" \
  -d '{"status":"DONE"}'
# Creator should receive: "[recipientName] completed a task — [title]"
```

---

### 20. Activity feed (Feature #4)

#### Backend (Feature #4)

- [x] `GET /circles/:id/events` includes `actor: { id, name }` via Prisma `include`
- [x] Response capped at 100 most recent events (ordered descending by `createdAt`)
- [x] All 20 `EventType` values are present in the Prisma schema
- [x] Reminder events (`REMINDER_SENT`, `REMINDER_ESCALATED`) are logged with non-PII payload summaries and visible in organizer Activity
- [x] Digest/session system events (`DIGEST_SENT`, `DIGEST_OPENED`, `APP_SESSION`) are logged but filtered client-side

**curl:**

```bash
curl http://localhost:3000/circles/<circleId>/events \
  -H "Authorization: Bearer $TOKEN" | jq '.[0]'
# Expected: { id, type, createdAt, actorId, actor: { id, name }, payload }
```

#### iOS (Feature #4)

- [x] `APIClient` date decoder handles fractional seconds (`2024-05-02T12:34:56.789Z`) — fixes silent empty feed and all date fields across the app
- [x] `CircleEventType` has `unknown` case with custom `init(from:)` — unknown types from server decode to `.unknown`, which is hidden (`isVisible = false`), not a crash
- [x] `CircleEvent` model decodes all 20 known event types + forward-compatible `unknown` fallback
- [x] `EventActor` struct decodes `{ id, name }` from `actor` key
- [x] `CircleEvent.feedDescription` returns human-readable string for all visible event types
- [x] System events return empty `feedDescription`; `isVisible` returns `false` — filtered before render
- [x] `CircleEvent.feedIcon` and `feedIconColor` return appropriate SF Symbol and color per event category
- [x] `ActivityFeedView` groups events by Today / Yesterday / formatted date
- [x] `ActivityFeedView` shows empty state when no visible events
- [x] Admin hub shows "Activity" secondary card linking to `ActivityFeedView`
- [x] Member hub shows "Activity" secondary card linking to `ActivityFeedView`
- [x] Refresh button in toolbar re-fetches events
- [ ] Manual QA: create tasks, complete one, invite member — verify all appear in feed with correct labels

---

### 21. Shareable invite link (Feature #5)

#### iOS (Feature #5)

- [x] `MemberListView` admin toolbar shows a share button (`square.and.arrow.up`) alongside the invite button
- [x] Share sheet text: "Join [circle name] on CareLoop!\nCircle code: [circleId]" with subject "Join my CareLoop circle"
- [x] Share button only visible to admins (inside `appState.userRole == .admin` guard)
- [x] `CircleHomeView` admin grid shows "Share Circle" card (6th card, even grid)
- [x] "Share Circle" card uses iOS `ShareLink` — no custom HTTP call, no backend changes required
- [x] Recipient copies circle code from share text and enters it in `JoinCircleView` join flow
- [ ] Manual QA: share from admin, copy circle code, paste into join flow on second device — confirm joined as MEMBER

---

### 22. Task comments (Feature #6)

#### Backend (Feature #6)

- [x] `TaskComment` Prisma model: `id, body, createdAt, updatedAt, taskId, authorId`
- [x] Migration `20260502140000_add_task_comments` creates `TaskComment` table with FK cascade on task delete
- [x] `GET /circles/:id/tasks/:taskId/comments` — any circle member; returns comments ascending by `createdAt`; includes `author: { id, name }`
- [x] `POST /circles/:id/tasks/:taskId/comments` — any circle member; requires non-empty `body`; returns 201
- [x] `DELETE /circles/:id/tasks/:taskId/comments/:commentId` — author or admin only; returns 204
- [x] Non-member attempting to comment returns 403
- [x] Commenting on a task in a different circle returns 404

**curl — post comment:**

```bash
curl -X POST http://localhost:3000/circles/<circleId>/tasks/<taskId>/comments \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"body":"Picked up the prescriptions."}'
```

**curl — delete comment:**

```bash
curl -X DELETE http://localhost:3000/circles/<circleId>/tasks/<taskId>/comments/<commentId> \
  -H "Authorization: Bearer $TOKEN"
```

#### iOS (Feature #6)

- [x] `TaskComment` model: `id, body, createdAt, authorId, author: CommentAuthor?`
- [x] `CommentAuthor` struct: `id, name` (Codable)
- [x] `TaskDetailView` shows "Comments" NavigationLink row above the delete button
- [x] `TaskCommentsView` shows thread with avatar initials, author name, timestamp, body
- [x] Own comments + admin: trash button visible on row; others cannot delete
- [x] Composer: multiline TextField (1–4 lines), send disabled when draft empty or posting
- [x] Send posts comment, appends to list, scrolls to bottom, clears draft
- [x] Error shown inline; `load()` guard sets `loading = false` before early return
- [x] Empty state when no comments
- [ ] Manual QA: two users comment on same task — both see each other's comments after refresh

---

## Feature #7 — Notification preferences

### Backend (Feature #7)

- [x] `User` schema: `notifAssignments`, `notifEscalations`, `notifDigest` Bool `@default(true)`
- [x] Migration `20260502150000_add_notification_preferences` adds three columns
- [x] `PATCH /users/:id/notification-preferences` — self-only; accepts any subset of three booleans
- [x] `deliverTaskNotification`: returns early (no push/email) when `notifAssignments === false` for assignment-type notifications
- [x] `deliverTaskNotification`: returns early when `notifEscalations === false` for escalation-type notifications
- [x] Daily digest scheduler: skips user when `notifDigest === false`
- [x] `sanitizeUser` still strips only `passwordHash` — all three new fields flow through automatically

**curl — update preferences:**

```bash
curl -X PATCH http://localhost:3000/users/<userId>/notification-preferences \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"notifAssignments":false,"notifEscalations":true,"notifDigest":false}'
```

**curl — verify fields returned on /users/me:**

```bash
curl http://localhost:3000/users/me -H "Authorization: Bearer $TOKEN"
# expect notifAssignments, notifEscalations, notifDigest in response
```

#### iOS (Feature #7)

- [x] `CareUser` model: `notifAssignments: Bool?`, `notifEscalations: Bool?`, `notifDigest: Bool?`
- [x] `updateNotificationPreferences(userId:notifAssignments:notifEscalations:notifDigest:)` in `Endpoints.swift`
- [x] `SettingsView` — Notifications section: three Toggle rows (Task assignments, Escalation alerts, Daily digest)
- [x] `onAppear` loads current values from `appState.currentUser?.notifX ?? true` into `@State` vars
- [x] `onChange` on each toggle calls `saveNotifPrefs(userId:)` immediately
- [x] `prefsLoaded` flag: `onAppear` seeds state values then schedules `Task { prefsLoaded = true }` async so `onChange` handlers ignore the initial seed and only fire on real user interaction
- [x] `saveNotifPrefs`: cancels previous `saveTask`, debounces 300 ms, skips if cancelled, guards `appState.currentUser != nil` before assigning updated user
- [x] Concurrent rapid toggles collapse into one PATCH (cancel-and-replace)
- [x] `recipientReminder` classified as `isAssignmentType` — respects recipient's `notifAssignments` preference
- [x] Inline `ProgressView` row visible while save is in flight
- [x] Error shown in existing error section below Danger Zone on save failure
- [ ] Manual QA: toggle off Task assignments → assign a task to self → no push/email received
- [ ] Manual QA: toggle off Daily digest → confirm no digest at 6pm local time for that user

---

## Premium entitlement hardening

- [x] `PUT /circles/:id/recipients/:recipientId/entitlement` remains admin-only and receiver-scoped
- [x] App Store entitlement sync rejects missing `appleOriginalTransactionId` or `appleProductId`
- [x] Entitlement sync rejects unsupported sources; `MANUAL` remains available for admin operations/testing
- [x] Premium receiver unlocks additional caregiver access grants
- [x] Free receiver blocks recurring schedules with 402
- [x] Server-side App Store transaction verification adapter is ready for Apple production and sandbox APIs
- [x] Entitlement sync fails closed when App Store verification is enabled without required credentials
- [ ] Live Apple transaction verification with App Store Connect credentials and sandbox purchases
