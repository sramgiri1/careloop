# CareLoop Premium Phase Plan

**Status:** Active implementation contract for receiver-scoped premium implementation.
**Branch:** `codex/careloop-premium-phases`
**Updated:** 2026-05-17

This plan turns the locked PRD decisions into small implementation phases. Each phase must update automated tests, focused suite metadata, demo data when relevant, Nexus project status, and git before the next phase begins.

## Locked Premium Decisions

- Premium is purchased per care receiver, not per Care Circle and not per caregiver seat.
- A free Care Circle supports exactly one active care receiver.
- Adding a second care receiver triggers an upgrade choice sheet before the add form opens.
- If the organizer declines that upgrade prompt, return to the previous screen with no draft receiver.
- Care Organizers see receiver plan state on the circle dashboard and in Care Receiver Management.
- Compact receiver cards use an icon-only visual premium/free indicator with full accessibility labels.
- Care Receivers see only their own premium/free badge and no billing controls.
- Caregivers may view premium value and pricing context but cannot purchase.
- Caregivers can send an in-app `Ask organizer to upgrade` request.
- Caregiver upgrade requests appear only in Care Receiver Management.
- Upgrade requests are informational only; purchase remains a deliberate organizer action.
- Multiple caregiver requests collapse into one row per receiver with count and latest requester.
- Upgrade requests auto-dismiss after 7 days.
- Each caregiver can request premium once per receiver lifetime.
- Expired or failed premium keeps existing data visible and blocks only new premium actions.

## Phase P1: Premium Decisions And Contracts

**Status:** Complete.

**Goal:** Make premium scope and implementation phases explicit for agents, tests, and Command Center before behavior changes.

**Deliverables**

- Update PRD monetization and roadmap sections with the locked receiver-scoped decisions.
- Add this Nexus-readable implementation plan.
- Update CareLoop project status and roadmap metadata so Command Center shows the premium phase.
- Add a docs validation check for the premium plan and PRD decisions.
- Add premium-plan test suite metadata so Nexus can recommend the right checks.

**Tests**

- `npm run check:careloop-premium-phase-plan`
- `node scripts/check-project-test-suites.js`
- `node scripts/check-test-selection-preview.js`
- `git diff --check`

## Phase P2: Receiver Plan Visibility

**Status:** Complete.

**Goal:** Make plan state obvious without turning billing into dashboard clutter.

**Deliverables**

- Added icon-only premium/free status to dashboard receiver cards with accessibility labels.
- Added plan status and upgrade action to Care Receiver Management.
- Kept Care Receiver persona limited to badge-only visibility.
- Kept Caregiver persona without billing controls.
- Dashboard receiver summaries now include inactive/invited receivers so plan state is visible before activation.

**Tests**

- `scripts/careloop-test-runner.sh ios:personas`
- `scripts/careloop-test-runner.sh ios:payments`

## Phase P3: Add Second Receiver Gate

**Status:** Complete.

**Goal:** Enforce the free-tier receiver limit at the first honest decision point.

**Deliverables**

- Backend blocks a second free receiver unless the caller provides the premium add-receiver intent.
- iOS shows a choice sheet when `Add Care Receiver` is tapped after the free receiver already exists.
- Declining the prompt keeps the user in Care Receiver Management with no draft receiver.
- Choosing upgrade opens the receiver add form with receiver-scoped premium intent.

**Tests**

- `scripts/careloop-test-runner.sh backend:circles`
- `scripts/careloop-test-runner.sh ios:personas`

## Phase P4: Caregiver Upgrade Request

**Status:** Complete.

**Goal:** Let caregivers signal premium need without giving them billing authority.

**Deliverables**

- Added backend model/API for caregiver premium requests.
- Enforced one request per caregiver per receiver lifetime.
- Added recent request summaries that auto-expire from organizer visibility after 7 days.
- Added caregiver locked-feature state with `Ask organizer to upgrade`.
- Ensured caregiver locked recurring task flow never shows a purchase CTA.

**Tests**

- `scripts/careloop-test-runner.sh backend:circles`
- `scripts/careloop-test-runner.sh ios:payments`

## Phase P5: Organizer Request Visibility

**Status:** Complete.

**Goal:** Surface upgrade demand where organizers manage receiver access and plans.

**Deliverables**

- Show collapsed upgrade request rows in Care Receiver Management.
- One row per receiver, with request count and latest requester.
- Request rows are informational and do not purchase directly.
- Added iOS API/model support for fetching receiver-scoped request summaries.
- Added UI-test fixture coverage for organizer-visible request summaries.

**Tests**

- `scripts/careloop-test-runner.sh ios:personas`
- Focused Xcode UI test: `CareLoopUITests/test_organizerCanOpenCareReceiverManagement`

## Phase P6: Purchase Success And Management UX

**Status:** Complete.

**Goal:** Make payment completion trustworthy and receiver-specific.

**Deliverables**

- Added receiver-scoped success state after purchase/restore entitlement sync.
- Success state confirms receiver-only scope, unlocked features, and renewal details.
- Added `Continue` and `Manage plan` actions to the success state.
- Added receiver-specific premium management screen with App Store manage/restore actions.
- Added above-fold Care Receiver Management entry for active receiver plans.
- Preserved expired/billing-failure copy that existing data remains visible and only new premium actions are blocked.

**Tests**

- `scripts/careloop-test-runner.sh ios:payments`
- Focused Xcode UI tests:
  - `CareLoopUITests/test_organizerCanOpenReceiverPremiumPaywall`
  - `CareLoopUITests/test_organizerCanManagePremiumReceiverPlan`

## Phase P7: Premium Enforcement Sweep

**Status:** Complete.

**Goal:** Make all premium gates consistent and server-backed.

**Deliverables**

- Confirmed premium gates for additional care receivers, unlimited caregivers, recurring tasks, and premium insights remain server-backed.
- Added expired-entitlement regression coverage proving existing receiver data remains visible.
- Added backend coverage proving expired entitlements still block recurring tasks, premium insights, and additional caregiver grants.
- Added iOS model coverage and copy for expired/revoked receiver Premium states so users see why premium actions are locked.

**Tests**

- `scripts/careloop-test-runner.sh backend:circles`
- `scripts/careloop-test-runner.sh ios:payments`

## Phase P8: Demo And StoreKit Hardening

**Status:** Complete.

**Goal:** Make the investor/demo path and sandbox billing path representative.

**Deliverables**

- Updated the single-command demo seed with free, premium, expired, and request-pending receiver states across four real-world care scenarios.
- Kept the existing `npm run careloop:demo` launcher as the one-command room demo entry.
- Added local StoreKit configuration for monthly and yearly receiver Premium products.
- Added a demo-readiness contract check that validates the demo command, showcase seed, and StoreKit product IDs.
- Documented first-run demo setup, StoreKit scheme configuration, App Store Connect product setup, sandbox testers, and physical-device purchase/restore requirements.

**Tests**

- `npm run check:careloop-demo-readiness`
- `scripts/careloop-test-runner.sh docs:demo`
- `scripts/careloop-test-runner.sh ios:payments`

## Phase Completion Rule

Every phase must end with:

- focused automated tests passing
- relevant smoke suite passing
- PRD/status/demo docs updated
- commit and push to the active branch
