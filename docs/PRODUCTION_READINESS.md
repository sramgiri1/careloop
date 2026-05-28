# CareLoop Production Readiness

This document tracks the concrete path from local app readiness to production launch. Medication-specific product work remains on hold until product, legal, and liability approval.

## Current State

- Backend, iOS app, tests, demo data, and release hygiene checks can run from CareLoop-local scripts.
- Standalone export tooling exists for creating a clean app-only repo/folder.
- Standalone repository exists and has been pushed to GitHub.
- Supabase production migrations have been applied successfully with `sslmode=require`.
- Railway config-as-code is present for Railpack, `npm start`, `/health`, restart policy, and the Railway-provided `PORT`.
- Production env validation is available via `npm run check:production-env -- --env-file .env.prod` and fails without printing secret values.
- iOS API configuration is build-setting driven: Debug uses the local API, Release no longer hardcodes localhost, and the shared `API_KEY` has been removed from the app plist.
- Apple/App Store setup, APNs, OAuth credentials, live email sender validation, and physical-device validation are not complete.

## Internal Work We Can Do Now

1. **K2A standalone export tooling.** Complete.
   - Command: `npm run standalone:export -- --to /path/to/careloop --clean`
   - Dry-run check: `npm run check:standalone-export`
   - Excludes `.env`, `.env.prod`, `.tmp`, `node_modules`, `.DS_Store`, `NEXUS_*.md`, Xcode user state, demo videos, Nexus OS, dashboard, reports, and roadmap files.
2. **K2B standalone repo extraction.**
   - Needs target GitHub repo or local destination from owner.
   - After export, run `npm install`, `npm test`, `npm run check:demo-showcase`, and iOS build/test from the extracted repo.
3. **J2 scheduler/queue readiness.**
   - Make reminder, snooze, escalation, digest, and archive jobs safe for multiple API instances.
   - Add idempotent claim/retry tests.
4. **J3 load-shape validation.**
   - Add large seed profiles and query-plan checks for dashboard, task board, activity, invitations, reminders, and insights.
5. **J4 privacy/data lifecycle.**
   - Define export/delete/retention behavior for accounts, events, invites, comments, reminders, push tokens, and reset codes.
6. **J5 observability.**
   - Add request timing, error-rate, job-lag, and failed-delivery telemetry without logging care details.
7. **K3A Railway/API deployment hardening.** Complete.
   - `railway.json` pins the deploy contract for the standalone repo.
   - `src/lib/env.js` validates production-only required values and partial provider configs.
   - `scripts/check-production-env.js` checks local or Railway-style env without exposing secret values.
8. **K3B local release-config cleanup.** Complete.
   - `Info.plist` uses `CARELOOP_API_BASE_URL` instead of a hardcoded API origin.
   - The stale shared `API_KEY` was removed from iOS.
   - `npm run check:ios-release-hygiene` fails if localhost/shared-key config reappears in shipping iOS configuration.

## External Setup Needed From Owner

| Area | Needed |
| --- | --- |
| Standalone repository | GitHub repo URL/name, preferred visibility, and whether to preserve commit history or export as a clean first commit. |
| Backend hosting | Preferred provider: Supabase + Render/Fly/Railway/AWS/GCP, staging/prod domains, deployment ownership, and billing access. |
| Database | Hosted Postgres/Supabase project, backup policy, and encryption-at-rest confirmation. Production migrations are already applied to the provided Supabase URL. |
| Email | Resend account/API key, verified sending domain, sender address, and support/contact address. |
| Push notifications | Apple Developer team, APNs key/certificate, bundle ID, and production push entitlement. |
| App Store | App Store Connect app record, subscription group, monthly/yearly product setup, sandbox testers, server API issuer/key/private key. |
| Auth providers | Google/Facebook/Apple client IDs, secrets where applicable, redirect/callback URLs, and approved app configuration. |
| Legal/privacy | Final app name/entity, privacy policy, terms, support email, data retention/delete/export policy, and incident-response owner. |
| Monitoring | Preferred error monitoring/logging provider, alert emails/channels, uptime checks, and on-call owner. |
| Beta devices | Physical iPhones/users for TestFlight, APNs, StoreKit sandbox, Sign in with Apple, and notification tap validation. |

## Production Exit Criteria

- Standalone repo builds/tests without Nexus workspace files.
- Backend staging and production deploy through repeatable CI/CD.
- Prisma migrations deploy safely to staging/prod.
- `npm run check:production-env -- --env-file .env.prod` passes with no production-blocking errors.
- Production API config replaces localhost in Release builds.
- iOS Release config must replace `https://api.careloop.example` with the selected hosted API origin before TestFlight.
- StoreKit purchase, restore, refund/revocation state, and App Store transaction verification pass with sandbox testers.
- APNs delivery, notification tap deep links, and reminder escalation pass on physical devices.
- OAuth provider callbacks pass on physical devices.
- No real secrets or PII appear in source, demo fixtures, logs, reports, or event payloads.
- Account export/delete and data retention policy are implemented or explicitly blocked before public launch.
- TestFlight beta completes without P0/P1 issues.

## First Production Track Recommendation

1. Export the standalone repo once the owner gives a target destination.
2. Run all local backend and iOS checks from the extracted repo.
3. Set up staging backend and hosted Postgres.
4. Replace Release API config with staging/prod environment configuration.
5. Start Apple/App Store/APNs/OAuth setup in parallel because those are the longest external lead-time items.
