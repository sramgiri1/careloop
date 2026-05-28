# CareLoop Test Runbook

Date: 2026-05-22

Use `scripts/careloop-test-runner.sh` from the repo root. The runner groups existing backend, iOS unit, and iOS UI tests so agents can run the smallest useful suite instead of always running the full regression.

CareLoop also exposes project-local iOS runners from the CareLoop API package for API-backed simulator validation. These runners verify or start the local API, seed showcase data when needed, and then run Xcode against `CARELOOP_IOS_ROOT`, `./ios`, `../careloop-ios`, or `../ios`.

## Gates

| When | Suite | Command |
| --- | --- | --- |
| Every code change before commit | Smoke | `scripts/careloop-test-runner.sh smoke` |
| Backend-only change | Backend focused suite | `scripts/careloop-test-runner.sh backend:<area>` |
| iOS view/model-only change | iOS focused suite | `scripts/careloop-test-runner.sh ios:<area>` |
| End of phase | Full regression | `scripts/careloop-test-runner.sh full` |
| Release candidate | Full regression plus manual/device matrix | `scripts/careloop-test-runner.sh full` and `testability-matrix.md` |
| API-backed iOS journey change | CareLoop-local API-backed Xcode suite | `npm run test:ios:api` from the CareLoop repo root |

## Backend Suites

| Suite | Purpose |
| --- | --- |
| `backend` | Runs all backend tests. |
| `backend:domain` | Pure domain rules: receiver activation, task visibility, premium limits. |
| `backend:auth` | Signup, login, logout, OAuth, forgot password, token/session behavior. |
| `backend:circles` | Create circle, invite, accept/decline/expire invites, member/receiver management, delete. |
| `backend:tasks` | Task create/edit/complete, recurrence, comments, activity, insights. |
| `backend:reminders` | Reminder creation, snooze, escalation, push/email/digest delivery simulation. |
| `backend:security` | Scope isolation, cross-user mutation protection, blocked unauthorized flows. |
| `backend:payments` | Premium entitlement sync, free limits, premium-gated capabilities. |
| `backend:scale` | 50-user simulation, multi-circle/multi-role isolation, and high-growth read pagination contracts. |

## iOS Suites

| Suite | Purpose |
| --- | --- |
| `ios` | Runs the full Xcode suite. |
| `ios:unit` | Runs iOS unit/model tests only. |
| `ios:ui` | Runs all iOS UI tests only. |
| `test:ios` | CareLoop-local package script that verifies/starts the API, then runs the full Xcode suite. |
| `test:ios:ui` | CareLoop-local package script that verifies/starts the API, then runs all iOS UI tests. |
| `test:ios:api` | CareLoop-local package script that verifies/starts the API, reseeds showcase data, and runs API-backed admin/persona journeys. |
| `ios:onboarding` | Onboarding, auth validation, keychain, circle directory. |
| `ios:personas` | Organizer, caregiver, care receiver dashboards and role switching. |
| `ios:tasks` | Task board, personal task board, recurrence model, completion flow. |
| `ios:reminders` | Reminder scheduling model, push deep-link state, pending/completed/wrong-circle UI deep links, snooze UI, rescheduled reminder copy, and organizer escalation activity timeline. |
| `ios:payments` | Paywall, StoreKit metadata, premium disclosure, premium locks. |

## Current Critical Journey Coverage

| Journey | Automated suites |
| --- | --- |
| Sign in / create account contract | `backend:auth`, `ios:onboarding` |
| Group list -> create/join -> group hub | `backend:circles`, `ios:onboarding`, `ios:personas` |
| Invite member / invite care receiver | `backend:circles`, `ios:personas`; focused iOS UI coverage for pending caregiver invite resend/revoke, direct care receiver invite acceptance, caregiver no-access default join, organizer caregiver receiver-access grant/revoke, and disabled expired/declined/revoked invite states |
| Create recurring task -> complete -> next occurrence | `backend:tasks`, focused iOS UI tests for premium recurring creation and next occurrence |
| Task detail status / comments | `backend:tasks`, focused iOS UI tests for detail status changes and comment add/delete |
| Task detail edit | Focused iOS UI test for organizer editing a task title from Task Detail |
| Task detail delete | Focused iOS UI test for organizer delete cancel/confirm from Task Detail |
| Task detail blocked actions | Focused iOS UI test for invited care receiver blocking edit/status/comment/snooze/delete actions |
| Task detail escalation | Focused iOS UI test for escalated task copy plus visible status/snooze recovery actions |
| Reminder -> snooze -> escalation -> deep link | `backend:reminders`, `ios:reminders`; backend verifies escalation fanout, legacy null-receiver escalation safety, and non-PII delivery summaries, and iOS verifies organizer Activity escalation timeline copy |
| Notification preferences | Backend `PATCH /users/:id/notification-preferences`, assignment/escalation delivery gates, daily digest opt-out test; `xcodebuild build-for-testing`; focused iOS UI `test_settingsNotificationPreferencesCanBeChanged` |
| Care receiver lifecycle and activation management | Backend receiver lifecycle, activation-conflict, proxy-attestation, and receiver-delete tests; focused iOS UI `test_organizerCanAddEditAndRemoveCareReceiverLocally`, `test_addSecondReceiverShowsPremiumGateBeforeForm`, `test_organizerChoosesReceiverActivationPath`, and `test_organizerSeesBlockedCareReceiverRemovalReason` |
| New task inactive receiver blocking | Backend inactive-receiver task-create rejection test; focused iOS UI `test_newTaskBlocksInactiveCareReceiverUntilActivation` |
| 50 dummy users / real-user simulation | `backend:scale` |
| One user across multiple circles in different roles | `backend:scale`, `ios:personas` |
| High-growth task/comment/invite/activity reads | Focused backend scale regression for opt-in cursor pagination and legacy array response compatibility |
| Delete circle/member/receiver scenarios | `backend:circles`; receiver removal confirmation and blocked-delete UI coverage; circle/member UI delete coverage remains in `testability-matrix.md` backlog |
| StoreKit product metadata | Backend entitlement metadata test; `xcodebuild build-for-testing`; focused iOS unit coverage in `CareLoopTests/SubscriptionManagerProductIdTests` for product IDs, fallback prices, and local StoreKit fixture parity |
| Premium restore and entitlement refresh | `xcodebuild build-for-testing`; focused iOS UI `test_organizerCanManagePremiumReceiverPlan` verifies the receiver-scoped restore CTA; purchase and restore reuse the shared receiver entitlement sync helper |
| Premium billing retry and refund states | Backend premium entitlement regression; `xcodebuild build-for-testing`; focused iOS model `test_careRecipient_exposesBillingRetryAndRefundedPremiumAsLockedButVisible`; focused iOS UI `test_organizerSeesPremiumBillingAndRefundStates` |
| Free receiver and premium capability gates | Backend cross-surface premium/free policy regression; `xcodebuild build-for-testing`; focused iOS UI `test_organizerCanOpenCareReceiverManagement`, `test_addSecondReceiverShowsPremiumGateBeforeForm`, and `test_insightsLockFreeReceiverBehindPremiumUpgrade` |
| App Store Server transaction verification readiness | Backend `app-store-server.test.js`; entitlement sync fail-closed route regression; live Apple calls remain external setup |
| Receiver adherence, missed-trend, caregiver-load, escalation, and premium-state reporting | Backend insights aggregation tests for scheduled/completed/on-time/late/missed adherence fields, daily due/completed/missed trend data, organizer-only caregiver load, escalation history/response timing, and caregiver privacy; `xcodebuild build-for-testing`; focused iOS model `CareLoopTests/CompletionInsightModelTests`; focused iOS UI `test_insightsShowPremiumReportSections` and `test_insightsLockFreeReceiverBehindPremiumUpgrade` |
| Demo showcase readiness | `npm run check:demo-showcase` validates four scenarios, launch personas, task/reminder/premium state mix, StoreKit product parity, and launcher contract; `npm run test:ios:api` validates API-backed admin/persona journeys after reseeding; `npm run careloop:demo:check` validates the one-command launcher contract without opening simulator windows; `npm run careloop:record-personas` records organizer, caregiver, and care receiver journeys; direct `node scripts/seed-demo-showcase.js` verifies the manifest can be emitted |
| Standalone build/test boundary | `npm run check:demo-showcase`, backend tests, and path resolver smoke validation verify CareLoop-local scripts can find the iOS app without Nexus-root launcher scripts |
| Standalone export readiness | `npm run check:standalone-export`; guarded temporary export validation with `npm run standalone:export -- --to .tmp/standalone-export --clean` |
| Release hygiene | `npm run check:ios-release-hygiene` validates iOS target membership and Debug-only demo/UI-test launch hooks; `npm run check:ios-release-artifact` scans the built Release `.app` for bundled demo data, mock accounts, local StoreKit fixtures, demo env keys, and UI-test launch args; Release simulator build verifies the app starts from production `AppState()` outside Debug |
| iOS API configuration | `npm run check:ios-release-hygiene` validates that `Info.plist` uses `CARELOOP_API_BASE_URL`, does not hardcode localhost, and does not ship a shared `API_KEY`; Debug points to the local API and Release uses a production placeholder until a hosted API URL is chosen |

## Notes

- Override simulator destination with `CARELOOP_XCODE_DESTINATION`, for example `CARELOOP_XCODE_DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro"`.
- Focused task-detail validation can be run with Xcode UI tests `test_taskDetailCanSnoozeReminder`, `test_taskDetailCanChangeStatusToDone`, `test_taskCommentsCanBeAddedAndDeleted`, `test_organizerCanCreateRecurringTaskForPremiumReceiver`, and `test_completingRecurringTaskCreatesNextOccurrence`.
- Focused task-edit validation can be run with Xcode UI test `test_organizerCanEditTaskTitleFromDetail`.
- Focused task-delete validation can be run with Xcode UI test `test_organizerCanCancelAndConfirmTaskDeleteFromDetail`.
- Focused task-block validation can be run with Xcode UI test `test_taskDetailBlocksActionsForInvitedReceiver`.
- Focused report validation can be run with backend test `GET /circles/:id/insights/completion`, Xcode model test `CareLoopTests/CompletionInsightModelTests`, and Xcode UI tests `CareLoopUITests/test_insightsShowPremiumReportSections` and `CareLoopUITests/test_insightsLockFreeReceiverBehindPremiumUpgrade`.
- Focused receiver-delete validation can be run with Xcode UI tests `test_organizerCanAddEditAndRemoveCareReceiverLocally` and `test_organizerSeesBlockedCareReceiverRemovalReason`.
- Focused StoreKit metadata validation can be run with backend test `validates premium entitlement sync source and App Store transaction identity` and Xcode unit test class `CareLoopTests/SubscriptionManagerProductIdTests`.
- Focused Premium restore validation can be run with `xcodebuild build-for-testing` and Xcode UI test `test_organizerCanManagePremiumReceiverPlan`.
- Focused Premium billing-state validation can be run with backend test `treats billing retry and refunded receiver entitlements as locked but visible`, Xcode model test `test_careRecipient_exposesBillingRetryAndRefundedPremiumAsLockedButVisible`, and Xcode UI test `test_organizerSeesPremiumBillingAndRefundStates`.
- Focused free/premium gate validation can be run with backend tests for add-receiver intent, recurring schedules, insights, and caregiver limits, plus Xcode UI tests `test_addSecondReceiverShowsPremiumGateBeforeForm`, `test_insightsLockFreeReceiverBehindPremiumUpgrade`, and `test_organizerCanOpenCareReceiverManagement`.
- Focused App Store Server verification readiness can be run with `node --test test/app-store-server.test.js` and backend route test `fails closed when App Store verification is enabled without server credentials`.
- Focused demo showcase readiness can be run from the CareLoop repo root with `npm run check:demo-showcase` and `node scripts/seed-demo-showcase.js > /tmp/careloop-demo-manifest-check.json`.
- Focused API-backed admin/persona validation can be run from the CareLoop repo root with `npm run test:ios:api`; use `npm run test:ios` for the full Xcode suite through the same API-aware runner.
- Focused scale-read validation can be run from the CareLoop repo root with `node --test --test-name-pattern "cursor pagination|50 users|isolates one account" test/sprint2.test.js`; it covers 50-user/multi-role isolation plus opt-in cursor pagination for tasks, comments, invitations, and events.
- Focused standalone export validation can be run from the CareLoop repo root with `npm run check:standalone-export`; use `npm run standalone:export -- --to .tmp/standalone-export --clean` for an ignored local copy test.
- Focused one-command demo launcher validation can be run from the CareLoop repo root with `npm run careloop:demo:check`; use `npm run careloop:demo` only when you intentionally want to seed data, start/reuse the API, and open simulator sessions.
- Focused persona video recording can be run from the CareLoop repo root with `npm run careloop:record-personas`. It seeds reserved-domain users, runs four Xcode UI journeys, and writes MP4 files under the printed `outputDir`.
- Focused release-hygiene validation can be run from the CareLoop repo root with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project ios/CareLoop.xcodeproj -scheme CareLoop -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`, then `npm run check:ios-release-artifact`.
- Focused task-escalation validation can be run with Xcode UI test `test_taskDetailShowsEscalationStateForOverdueTask`.
- Focused escalation fanout/timeline validation can be run with backend test `escalation fanout logs a sanitized timeline summary without blocking on disabled alerts` and Xcode UI test `test_organizerActivityShowsEscalationTimelineEntry`.
- Focused invite/access validation can be run with Xcode UI tests `test_organizerCanResendAndRevokePendingCaregiverInvite`, `test_careReceiverCanAcceptPendingInviteFromDirectory`, `test_caregiverAcceptsInviteWithNoReceiverAccessByDefault`, `test_organizerCanGrantAndRevokeCaregiverReceiverAccess`, and `test_inviteEdgeStatesDisableResponseActions`.
- Focused receiver lifecycle, activation, and proxy-attestation validation can be run with backend receiver tests in `test/sprint2.test.js` and Xcode UI tests `test_addSecondReceiverShowsPremiumGateBeforeForm`, `test_organizerCanAddEditAndRemoveCareReceiverLocally`, and `test_organizerChoosesReceiverActivationPath`.
- Focused inactive-receiver task-create validation can be run with backend `returns 400 when the care receiver has not accepted or been proxy-activated` and Xcode UI `test_newTaskBlocksInactiveCareReceiverUntilActivation`.
- Task Detail state-model validation can be run with Xcode unit test class `CareLoopTests/TaskDetailPresentationTests`.
- The `task-comments` UI fixture launches directly into the comments screen with local add/delete behavior so agents can validate comments without mutating a live backend.
- Physical-device only coverage still includes APNs delivery, real universal links, Sign in with Apple entitlement validation, and StoreKit sandbox purchase/restore.
- New phases must update this runbook and `testability-matrix.md` when adding or moving coverage.
