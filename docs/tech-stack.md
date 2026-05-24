# CareLoop — Technology Stack Decision

**Status:** Approved  
**Applies to:** Sprints 1–4

---

## Summary

Use a custom CareLoop backend with Supabase Postgres as the database and Prisma as the data layer. Keep Fastify as the API server and use CareLoop-owned password/OAuth bearer-token auth for the current standalone build. Use Resend for email, APNs for push, and keep background jobs in-process with `node-cron` through the first public launch.

This preserves what already exists, minimizes migration work, and gives a realistic path from local testing to public release without introducing extra vendors too early.

---

## Stack Decisions

### Core Backend and Database

| Layer          | Decision                    |
|----------------|-----------------------------|
| Database       | Supabase Postgres           |
| ORM / schema   | Prisma                      |
| API server     | Fastify                     |
| Runtime/hosting| Node.js on Railway |

Matches the current repo. Keeps SQL ownership. Avoids rewriting business logic around Supabase RPC or Firebase-style patterns.

### Authentication and User Management

| Layer          | Decision                                      |
|----------------|-----------------------------------------------|
| Auth provider  | CareLoop backend auth with optional Google/Facebook/Apple OAuth |
| Sign-in method | Email/password now; OAuth enabled when provider credentials are configured |
| Session model  | Backend issues CareLoop bearer tokens signed with `AUTH_TOKEN_SECRET` |
| User management| CareLoop `User` table plus `AuthIdentity` records for social providers |

This matches the current code and avoids introducing a second auth provider while the app is being production-hardened. Supabase remains the database provider, not the auth authority, unless a future migration is explicitly planned and tested.

**Sprint rollout:**
- Current standalone build: authenticated bearer tokens for app traffic
- Provider credentials: Google/Facebook/Apple social login remains disabled until production callback URLs and app credentials are configured

### Authorization

- AuthZ model: CareLoop authorization stays in the Fastify backend via `CircleMember.role`
- Read protection: require authenticated user + membership check on all circle-scoped GET endpoints by launch (Sprint 3)
- Supabase handles identity; Fastify handles circle/task permissions

### iOS Payments and Subscriptions

| Layer                | Decision                                           |
|----------------------|----------------------------------------------------|
| In-app purchase      | StoreKit 2 (iOS 15+)                               |
| Subscription type    | Auto-renewing subscriptions (monthly + annual)     |
| Payment collection   | Apple handles all payment data (no Stripe/direct)  |
| Entitlement state    | `SubscriptionManager` singleton + server-side sync |
| Receipt verification | `Transaction.currentEntitlements` async sequence   |
| Restore purchases    | `AppStore.sync()` + entitlement refresh            |
| Subscription mgmt UI | `AppStore.showManageSubscriptions(in:)`            |

**Product IDs registered in App Store Connect:**

- `com.careloop.ios.premium.monthly`
- `com.careloop.ios.premium.yearly`

StoreKit 2 is the only compliant payment path for iOS App Store subscriptions. Apple collects and stores all credit card and billing address data. The app collects only name and email at sign-up, and stores Apple transaction ID and expiry for server-side entitlement verification.

**Delivered in Sprint 4 (2026-05-01):**

- `CareLoop/App/SubscriptionManager.swift` — `@MainActor ObservableObject` singleton; manages product loading, purchase, restore, entitlement sync, and transaction observer
- `CareLoop/Views/PaywallView.swift` — full dark-navy paywall with plan selector, trial-aware CTA, compliant disclosure text, and App Store Settings cancel instructions

### Notifications and Messaging

| Service  | Decision              |
|----------|-----------------------|
| Email    | Resend                |
| Push     | APNs directly         |
| Scheduler| `node-cron` in-process|

Resend is already wired. APNs is mandatory for native iOS push. `node-cron` is sufficient for Sprint 1–3 scale. No queue system until multiple worker instances are needed.

### Analytics and Event Logging

| Purpose            | Tool                |
|--------------------|---------------------|
| Product events     | CareLoop `Event` table |
| Operational analytics | PostHog          |

Own event table is useful for product logic and audit. PostHog is better for funnels, retention, and usage analysis. Add PostHog when external beta testing begins.

### Monitoring and Reliability

| Purpose         | Tool                         |
|-----------------|------------------------------|
| Error tracking  | Sentry                       |
| Logs            | Platform logs (Railway/Render)|
| Uptime / health | `/health` + platform monitoring |

Enough for early production without building observability infrastructure. Add Sentry when external beta testing begins.

### File Storage

No storage product in v1. The current product does not need uploads. Add storage only when attachments exist.

### Admin / Internal Tools

- DB inspection: Prisma Studio during development
- Light admin ops: Supabase dashboard for DB/auth inspection
- No launch-time user-management admin console is planned; circle and member management use the existing app and backend flows

---

## Data Model Changes Required

| Field         | Model | Sprint | Notes                                      |
|---------------|-------|--------|--------------------------------------------|
| `authUserId`  | User  | 3      | Links CareLoop User to Supabase Auth identity |
| `messageId`   | DigestLog | 2 | Stores Resend email ID for digest open tracking correlation |

---

## Hosting and Environments

| Resource  | Decision                              |
|-----------|---------------------------------------|
| Database  | Supabase project (careloop-dev + careloop-prod) |
| API       | Railway with `railway.json`, `/health`, and Railway-provided `PORT` |
| iOS       | Xcode / TestFlight                    |
| Secrets   | Platform env vars + Xcode config separation for dev/prod |

Maintain separate `local`, `staging`, and `production` env values before beta.

---

## Decisions Locked

- Keep Prisma as the single schema source of truth
- Do not move business logic into Supabase Edge Functions or database triggers for v1
- Keep the current Fastify REST structure; do not replace it with Supabase client-side table access
- Use Resend (not SendGrid or SES) for launch
- Use direct APNs (not Firebase Cloud Messaging) — product is iOS-only
- Use `node-cron` through the first public launch; no queue system yet
- Add PostHog + Sentry when external beta testing begins, not for local-only investor testing
