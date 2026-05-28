# CareLoop Implementation Kanban

**Last updated:** 2026-05-27

This board tracks CareLoop app work only. It mirrors the PRD implementation phases and must be updated whenever a subphase moves state.

## Done Criteria

A card can move to `Done` only when all of these are true:

- Product behavior is implemented without duplicate screens or duplicated business rules.
- Focused backend and/or Xcode tests cover the new behavior.
- `docs/PRD.md`, `docs/qa/test-runbook.md`, `docs/qa/testability-matrix.md`, and `docs/NEXUS_PROJECT_STATUS.md` are updated when scope or coverage changes.
- Demo seed/launcher data is updated if the showcase path changes.
- Changes are committed and pushed on the active CareLoop branch.

## In Progress

No CareLoop implementation card is actively in progress. Phase K1, K2A, K2B, K3A Railway/API deployment hardening, and K3B local release-config cleanup are complete. J2-J5 can continue locally, while H4/H5 and F5 remain blocked on external Apple/App Store/physical-device setup.

## Ready

| ID | Outcome | Code Areas | Required Tests | Demo Impact | PRD Status |
| --- | --- | --- | --- | --- | --- |
| F5 | Physical-device APNs/TestFlight validation. | Apple Developer setup; app entitlements; backend push provider. | Manual physical-device checklist. | No simulator demo dependency. | External Setup |
| H4 | Verify production API URL, entitlements, privacy strings, push, Sign in with Apple, and StoreKit product IDs. | Xcode config; backend environment; App Store Connect. | Release checklist plus physical-device validation. | No demo dependency. | External Setup |
| H5 | TestFlight checklist and final device validation. | TestFlight build and devices. | Manual physical-device sign-off. | No demo dependency. | External Setup |
| I1 | Shared care calendar and coverage planning for meals, rides, appointments, visits, and task coverage. | Existing task/receiver/access policy; new calendar surface. | Backend scoped calendar contract tests plus organizer/caregiver/receiver Xcode UI tests. | Add calendar-oriented demo moments after data model lands. | Planned |
| I2 | Invite delivery transparency. | Invite routes, email/SMS provider abstraction, People & Access UI. | Provider simulation tests, resend/revoke/expired UI coverage, PII-safe audit checks. | Improves demo credibility for real invite flow. | Planned |
| I3 | Non-clinical care journal and wellness updates. | Event/comment model extension; receiver-scoped feed UI. | Access-scope tests, PII redaction checks, journal UI coverage. | Add history-rich journal moments. | Planned |
| I4 | Care receiver profile and emergency information. | Receiver profile schema/UI; privacy/export/delete plumbing. | Authz, export/delete, and profile UI tests. | Adds real handoff context. | Planned |
| I5 | Consent, privacy, and self-service controls. | Receiver settings, access grants, audit/export/delete routes. | Receiver revoke/export/delete tests and UI coverage. | Demonstrates trust controls. | Planned |
| I6 | Calendar export and Apple ecosystem integrations. | Calendar/Reminders export, deep links, APNs/device validation. | Simulator deep-link tests plus physical-device validation. | Optional after care calendar stabilizes. | Planned |
| J2 | Scheduler and queue readiness for multiple API instances. | Reminder, snooze, escalation, digest, and archive jobs. | Backend concurrent-claim and idempotent retry tests. | No demo change unless job state appears in seeded history. | Planned |
| J3 | Postgres load testing and query-plan baselines. | Large seed profiles, Prisma query paths, index coverage. | Load-shape scripts and query-plan assertions for high-cardinality reads. | No direct demo change. | Planned |
| J4 | PII retention, export/delete, and encryption review. | Event/invite/comment/reminder retention, export/delete routes, security checks. | PII redaction, export/delete, and scoped-access regressions. | Adds trust/privacy talking points after implemented. | Planned |
| J5 | Observability and performance budgets. | API timing/error/job-lag telemetry without private care details. | Telemetry contract tests and local performance smoke checks. | No direct demo change. | Planned |
| K3 | Standalone CI and release gates. | CI config, secret placeholders, Prisma validation, Xcode build jobs. | First CI run must pass without Nexus workspace files. | No direct demo change. | Planned |
| K4 | Nexus archive/read-only integration. | Nexus references only, no app source mutation. | Nexus checks must not require CareLoop app source writes. | No direct demo change. | Planned |

## Backlog

| ID | Outcome | Code Areas | Required Tests | Demo Impact | PRD Status |
| --- | --- | --- | --- | --- | --- |
| H4a | Store production API base URL in release-safe configuration once backend hosting is selected. | Xcode build settings/config files; backend deployment. | Release hygiene plus smoke against staging/prod. | No demo dependency. | Blocked |
| I7 | Dedicated medication module. | Medication list, dose schedule, refill, adherence, and medication-specific reminders. | Requires product/legal/liability approval before test design. | On hold; do not implement yet. | On Hold |

## Done

| ID | Outcome | Evidence |
| --- | --- | --- |
| P1-P8 | Receiver-scoped premium planning, gates, request flow, purchase UI, expired/revoked states, and demo foundation. | Tracked in `docs/PREMIUM_PHASE_PLAN.md`, `docs/NEXUS_PROJECT_STATUS.md`, and premium test-runner suites. |
| A1-A6 | Task Detail policy, edit mode, delete confirmation, inactive receiver blocking, escalation visibility, and docs/test refresh. | Xcode task-detail UI/unit coverage and commits through `a9e2af1`. |
| B1 | Pending invite visibility plus organizer resend/revoke controls. | Backend `backend:circles` coverage and Xcode UI pending-invite tests; commit `e8b35cf`. |
| B2 | Direct care receiver invite acceptance and declined/expired disabled states. | Xcode UI `test_careReceiverCanAcceptPendingInviteFromDirectory`; commit `7d29930`. |
| B3 | Caregiver invite acceptance with no receiver access by default. | Backend `caregiver invitation acceptance grants no receiver access by default`; Xcode UI `test_caregiverAcceptsInviteWithNoReceiverAccessByDefault`. |
| B4 | Organizer grants and revokes receiver access after caregiver acceptance. | Backend `lets organizers grant and revoke caregiver receiver access`; Xcode UI `test_organizerCanGrantAndRevokeCaregiverReceiverAccess`. |
| B5 | Invite edge cases show clear errors and block invalid joins. | Backend wrong-user, expired-link, fourth-circle-limit, and already-member acceptance tests; Xcode UI `test_inviteEdgeStatesDisableResponseActions`. |
| C1 | Add/edit/reorder/remove receiver lifecycle polish. | Backend receiver lifecycle tests for detail update, reorder, active-task delete blocking, last-receiver protection, and primary promotion; Xcode UI `test_organizerCanAddEditAndRemoveCareReceiverLocally` plus premium-gate coverage. |
| C2 | Direct invite vs proxy activation decision path. | Backend activation conflict tests for direct-joined and proxy-active receivers; Xcode UI `test_organizerChoosesReceiverActivationPath` plus receiver-management regression trio. |
| C3 | Explicit authorization attestation for proxy activation. | Backend attestation-required and audit-payload tests; Xcode UI `test_organizerChoosesReceiverActivationPath` verifies the proxy action stays disabled until attestation is checked. |
| C4 | Block task creation until direct acceptance or proxy activation. | Backend inactive-receiver task-create rejection test; Xcode UI `test_newTaskBlocksInactiveCareReceiverUntilActivation` verifies New Task explains the blocked state and keeps Add disabled. |
| C5 | Receiver removal confirmation and blocked delete states. | Backend receiver-delete regression tests; Xcode UI `test_organizerCanAddEditAndRemoveCareReceiverLocally` confirms destructive removal and `test_organizerSeesBlockedCareReceiverRemovalReason` verifies task-preservation copy. |
| D1 | StoreKit product metadata and local purchase fixtures. | Centralized iOS product metadata, paywall fallback prices aligned to `CareLoop.storekit`, backend unsupported App Store product rejection, backend entitlement metadata regression, and `xcodebuild build-for-testing` after StoreKit parity unit-test additions. |
| D2 | Restore purchases and entitlement refresh hardening. | Shared iOS receiver entitlement sync helper for purchase/restore, management restore CTA syncs restored active transactions to the selected receiver, `xcodebuild build-for-testing`, and focused Xcode UI `test_organizerCanManagePremiumReceiverPlan`. |
| D3 | Expired, revoked, billing retry, and refund states. | Added backend/iOS receiver entitlement states for billing retry and refunded, kept locked-but-visible policy centralized in entitlement capabilities, added Prisma migration, backend entitlement regressions, iOS model coverage, and focused Xcode UI `test_organizerSeesPremiumBillingAndRefundStates`. |
| D4 | Free-one-receiver policy across add receiver, recurrence, insights, and caregiver limits. | Backend now requires an active premium receiver before accepting add-receiver premium intent, existing entitlement capability gates continue to enforce recurrence/insights/caregiver access, and focused backend plus Xcode UI coverage prove the cross-surface free-vs-premium contrast. |
| D5 | Server-side App Store transaction verification readiness. | Added App Store Server API transaction adapter, optional fail-closed entitlement verification behind `APP_STORE_SERVER_API_ENABLED`, signed transaction fixture tests, route misconfiguration regression, and README/runbook credential documentation. |
| E1 | Receiver adherence summary. | Extended the existing completion insights contract with receiver-scoped adherence summaries, displayed adherence cards in organizer insights and caregiver activity, and validated with backend aggregation tests plus focused Xcode model/UI coverage. |
| E2 | Missed and overdue task trends. | Added daily due/completed/missed trend data to the existing completion insights contract, displayed a missed-trend Insights chart, and validated with backend aggregation tests plus focused Xcode model/UI coverage. |
| E3 | Caregiver activity and load distribution. | Added organizer-only caregiver load distribution to the existing completion insights contract, displayed active/overdue/completed/total assigned work, and validated caregiver privacy with backend access regressions plus focused Xcode model/UI coverage. |
| E4 | Escalation history and response timing. | Added organizer-only escalation history and average response timing to the existing completion insights contract, displayed recent escalated tasks in Insights, and validated caregiver privacy with backend access regressions plus focused Xcode model/UI coverage. |
| E5 | Free/locked/premium insight states with clear upgrade value. | Clarified premium, selected locked-receiver, and all-recipient locked states in the existing Insights screen, added a premium report value preview, and kept upgrade CTAs receiver-scoped. |
| F1 | Reminder preference UX and backend persistence. | Persisted task assignment, escalation, and daily digest notification toggles through the existing Settings and user-preferences route, made digest delivery respect `notifDigest`, and validated backend delivery gates plus Settings UI automation. |
| F2 | Simulator deep-link coverage for pending, wrong-circle, and completed tasks. | Added organizer and care receiver UI coverage for pending task deep links, completed task deep links, and wrong-circle guards; focused Xcode UI deep-link suite passed with 6 tests. |
| F3 | Snooze mutation and rescheduled reminder visibility. | Backend snooze regressions now assert `scheduledAt` and `snoozedUntil` move to the requested future window, and Task Detail shows the rescheduled reminder time with escalation paused copy; focused backend and Xcode UI tests passed. |
| F4 | Escalation timeline and notification fanout verification. | Scheduler escalation payloads now store non-PII delivery summaries, user-disabled escalation alerts are blocked without failing the reminder, organizer Activity shows escalation timeline entries, and focused backend/Xcode UI tests plus `xcodebuild build-for-testing` passed. |
| G1 | Four realistic Care Circles with distinct use cases. | CareLoop-local demo readiness now enforces aging parent, post-surgery, postpartum/newborn, and memory-care scenarios; direct seed validation emitted 4 circles and 5 care receivers. |
| G2 | Multiple personas per circle with roles and access scopes. | Demo readiness now enforces organizer, care receiver, and caregiver launch profiles plus caregiver receiver-access grants across scenarios. |
| G3 | Mixed task states, history, reminders, premium, expired, and locked states. | Demo readiness now enforces pending, in-progress, done, skipped, snoozed, escalated, comment/history, premium request, active premium, manual premium, and expired premium states. |
| G4 | One-command launch plus optional screen-recording script. | CareLoop-local `npm run careloop:demo:check` validates the existing `npm run careloop:demo` launcher contract. `npm run careloop:record-personas` seeds realistic reserved-domain profiles and records organizer, caregiver, and care receiver simulator journeys as MP4 files. |
| G5 | Demo readiness validation fails if fixtures drift from the PRD. | Added CareLoop-local `npm run check:demo-showcase` / `npm run check:careloop-demo-readiness` guard for four scenarios, launch personas, mixed task/reminder/premium states, reserved-domain demo emails, StoreKit product parity, and one-command launcher contract; direct seed validation emitted 4 circles, 4 launch profiles, 23 tasks, and 5 care receivers. |
| H1 | Xcode target membership audit. | `npm run check:ios-release-hygiene` validates app target membership for demo/UI-test bridge files without changing Nexus OS files. |
| H2 | Debug-gate UI-test and demo launch hooks. | `UITestScenario.current`, UI-test fixture data, demo launch session parsing, and app launch activation are compile-time gated behind `DEBUG`; the Xcode Release simulator build passes with production `AppState()` fallback outside Debug. |
| H3 | Inspect Release archive for demo data, mock accounts, StoreKit config, and launch args. | `npm run check:ios-release-artifact` scans the built Release `.app` and passes only when no demo seed files, mock emails, local StoreKit fixture, demo env keys, or UI-test launch args are bundled. |
| I0 | Scenario reliability and API-backed test harness. | Fixed scheduler escalation for legacy unscoped tasks without querying null receiver access, added a CareLoop-local API-aware iOS runner, repaired admin demo/persona UI test contracts, reseeded API-backed journeys before launch, and removed medication-module claims from demo/onboarding/test fixtures while leaving prescription pickup as a generic care task. |
| J1 | Hot-path indexes and cursor pagination. | Added PostgreSQL indexes for auth reset lookup, invitations, receiver access/order, task lists, comments, reminders, and activity events; added opt-in cursor pagination for tasks, task comments, invitations, and events while preserving legacy array responses; focused backend scale/pagination regression and Prisma schema validation passed. |
| K1 | CareLoop-local command boundary. | Added CareLoop-local room demo launcher, centralized iOS path resolution for local/sibling/extracted layouts, updated demo/readiness/recording/release/test scripts, and documented standalone build/test layout. |
| K2A | Standalone export tooling. | Added guarded `npm run standalone:export` and `npm run check:standalone-export` commands that create/validate an app-only layout while excluding secrets, runtime artifacts, Nexus OS files, dashboard, reports, roadmap, `node_modules`, and simulator output. |
| K2B | Physical standalone repository extraction. | Exported CareLoop to `/Users/sucheth/Downloads/careloop`, validated backend/demo/standalone checks, and pushed the standalone app repository to GitHub. |
| K3A | Railway/API deployment hardening. | Added `railway.json`, Node engine pinning, production env validation, safe env checker tests, `.env.example` production placeholders, and docs for Railway/Supabase readiness without committing secrets. |
| K3B | Local release-config cleanup. | Moved iOS API base URL into `CARELOOP_API_BASE_URL` build settings, removed the stale shared `API_KEY` from the app plist, hardened `npm run check:ios-release-hygiene`, refreshed bearer-token docs, and kept Debug local networking separate from Release hosted-API configuration. |

## Blocked / External Setup

| ID | Blocker | Needed From Owner |
| --- | --- | --- |
| D5/H4 | App Store Connect products, subscription IDs, sandbox testers, and transaction verification credentials. | Apple Developer/App Store Connect setup. |
| F5/H5 | APNs delivery, push entitlement, notification tap, and TestFlight validation. | Apple Developer account, device, and TestFlight build. |
| H4 | Google/Facebook/Apple real auth redirect URIs and credentials. | Provider app credentials and callback URLs. |
