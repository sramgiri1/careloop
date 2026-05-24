# CareLoop

> Coordinate aging parent care without the group text chaos.

Stack: Node.js 20, Fastify 4, Prisma 5, PostgreSQL (Supabase), Resend, APNs, iOS 16+ SwiftUI

Status: Scale/data hardening Phase J1 complete; shared care calendar, release setup, and remaining data-readiness work remain next
Agents: ATLAS, PRISM, CORE, SWIFT, BEACON, CANVAS

⚠️  COMPLIANCE: FTC Health Breach Notification Rule applies.
    Clinic integration PERMANENTLY OFF ROADMAP (triggers HIPAA).
    AES-256 encryption required in Supabase before adding real data.
    Read docs/incident-response.md before sprint begins.

## Current Implementation

- CareLoop uses a Node.js/Fastify backend with Prisma models for users, circles, members, care receivers, receiver access, tasks, reminders, events, and receiver-scoped premium entitlements.
- The iOS app is SwiftUI on iOS 16+, with StoreKit 2 for App Store subscriptions and server-side entitlement sync.
- Premium is purchased per care receiver. It does not unlock the whole circle or caregiver seats globally.
- Free care circles support one active care receiver and one caregiver for that receiver.
- Premium care receivers unlock recurring routines, insights, unlimited caregivers, and advanced coordination for that receiver only.
- Expired or revoked Premium keeps existing care data visible and blocks only new premium-only actions.
- Dedicated medication-management features are on hold pending product, legal, and liability approval. Generic care tasks may cover real-world support such as prescription pickup, but the app must not claim dose scheduling, adherence, refill tracking, or medication advice.

## Focused Validation

Use these CareLoop-local scripts from the CareLoop API folder:

```bash
npm run test:smoke
npm test
npm run check:demo-showcase
npm run check:production-env -- --env-file .env.prod
npm run test:ios:api
npm run test:ios
```

For high-growth backend read-path validation:

```bash
node --test --test-name-pattern "cursor pagination|50 users|isolates one account" test/sprint2.test.js
```

For release hygiene:

```bash
npm run check:ios-release-hygiene
npm run check:ios-release-artifact
```

## Room Demo

The single-command demo launcher is available from the CareLoop API folder:

```bash
npm run careloop:demo
```

It seeds four showcase circles and opens simulator sessions for organizer, caregiver, and care receiver personas:

- Aging parent support: premium yearly receiver plus proxy-active second receiver.
- Post-surgery recovery: free receiver with pending caregiver upgrade requests.
- Postpartum/newborn support: premium yearly receiver with recurring routines.
- Memory care/home safety: expired monthly Premium state with existing history still visible.

If the simulator app has not been built or installed yet, run once with:

```bash
CARELOOP_DEMO_FORCE_BUILD=1 CARELOOP_DEMO_FORCE_INSTALL=1 npm run careloop:demo
```

## Persona Demo Recordings

Generate end-to-end simulator videos for realistic app usage with:

```bash
npm run careloop:record-personas
```

The command seeds realistic reserved-domain users and care scenarios, starts/reuses the local API, runs Xcode UI journeys, and writes MP4 files under the printed `outputDir`. Current recordings cover:

- Anita Ramgiri, organizer for Ramgiri Family Care.
- Arjun Shah, caregiver for Shah New Parent Support.
- Elena Morris, care receiver for Morris Recovery Plan.
- Emma Wilson, caregiver for Wilson Memory Care.

## StoreKit Local Config

Local StoreKit products live at:

```text
ios/CareLoop/Configuration/CareLoop.storekit
```

## Standalone Build/Test Layout

CareLoop can now run without Nexus-root scripts. The supported standalone layouts are:

- Backend folder: this package, containing `package.json`, `src`, `prisma`, `scripts`, `test`, and `docs`.
- iOS folder: set `CARELOOP_IOS_ROOT=/absolute/path/to/careloop-ios`, or place the iOS project at `./ios`, `../careloop-ios`, or `../ios`.

Recommended extraction layout:

```text
careloop/
  package.json
  src/
  prisma/
  scripts/
  test/
  docs/
  ios/
    CareLoop.xcodeproj
    CareLoop/
    CareLoopTests/
    CareLoopUITests/
```

Standalone commands:

```bash
npm install
npm test
npm run check:demo-showcase
npm run check:standalone-export
npm run test:ios:api
CARELOOP_DEMO_FORCE_BUILD=1 CARELOOP_DEMO_FORCE_INSTALL=1 npm run careloop:demo
```

Create a standalone app-only export after choosing a destination:

```bash
npm run standalone:export -- --to /absolute/path/to/careloop --clean
```

See `docs/STANDALONE_BUILD_TEST.md` and `docs/PRODUCTION_READINESS.md` before moving the export into a new repository.

## Railway Deployment

Railway deployment config lives in `railway.json` and uses Railpack, `npm start`, `/health`, and the Railway-provided `PORT`. Do not commit `.env` or `.env.prod`; configure secrets in Railway service variables.

Minimum production variables:

```text
NODE_ENV=production
DATABASE_URL=postgresql://...supabase.co:5432/postgres?sslmode=require
AUTH_TOKEN_SECRET=32-plus-character-secret
PUBLIC_API_BASE_URL=https://your-railway-domain.up.railway.app
DAILY_DIGEST_HOUR=8
REMINDER_ESCALATION_MINUTES=30
```

Email, push, OAuth, and App Store verification can be added when credentials are available. Until then, `npm run check:production-env` reports them as warnings instead of printing secret values.

The product IDs must stay aligned with `SubscriptionManager` and App Store Connect:

- `com.careloop.ios.premium.monthly`
- `com.careloop.ios.premium.yearly`

Local fallback prices are centralized in `SubscriptionManager` and must match `CareLoop.storekit`:

- Monthly: `$4.99`
- Yearly: `$49.99`

External setup still required before production billing validation:

- App Store Connect subscription group and product creation using the exact IDs above.
- Xcode scheme StoreKit Configuration set to `CareLoop.storekit` for local purchase simulation.
- Sandbox tester accounts for physical-device/TestFlight purchase and restore validation.

Server-side App Store transaction verification is ready behind `APP_STORE_SERVER_API_ENABLED=true`. Required production/sandbox environment variables:

- `APP_STORE_SERVER_ENVIRONMENT`: `sandbox` or `production`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `APP_STORE_BUNDLE_ID`

When verification is disabled, local/demo entitlement sync keeps using product and transaction identity validation only. When enabled but misconfigured, entitlement sync fails closed instead of granting Premium.
