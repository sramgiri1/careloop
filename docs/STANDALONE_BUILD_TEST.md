# CareLoop Standalone Build And Test

CareLoop is now prepared to run without Nexus-root scripts. Keep the app code, app tests, demo data, and release checks inside the CareLoop package plus the iOS project.

## Supported Layouts

Preferred standalone repo layout:

```text
careloop/
  package.json
  package-lock.json
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

The current Nexus workspace layout is still supported during migration:

```text
projects/
  careloop/
  careloop-ios/
```

If the iOS app lives somewhere else, set:

```bash
export CARELOOP_IOS_ROOT=/absolute/path/to/careloop-ios
```

## Standalone Commands

Run from the CareLoop API package folder:

```bash
npm install
npm test
npm run check:demo-showcase
npm run check:standalone-export
npm run check:ios-release-hygiene
npm run test:ios:api
```

Create a clean app-only export when a target folder or repository has been chosen:

```bash
npm run standalone:export -- --to /absolute/path/to/careloop --clean
```

The export includes backend source, Prisma schema/migrations, app scripts, tests, docs, and the iOS app under `ios/`. It excludes `.env`, `.env.prod`, `.tmp`, `node_modules`, `.DS_Store`, `NEXUS_*.md`, Xcode user state, demo videos, Nexus OS, dashboard, reports, roadmap, and generated simulator artifacts.

The room demo no longer depends on a Nexus-root launcher:

```bash
npm run careloop:demo
```

For a fresh simulator build and install:

```bash
CARELOOP_DEMO_FORCE_BUILD=1 CARELOOP_DEMO_FORCE_INSTALL=1 npm run careloop:demo
```

## Migration Rules

- Do not copy `node_modules`, `.tmp`, simulator output, recordings, or local generated artifacts.
- Do not copy real `.env` values into a new repo. Start from `.env.example` and recreate secrets through the deployment environment.
- Keep backend tests in `test/` and iOS tests in `ios/CareLoopTests` and `ios/CareLoopUITests`.
- Keep demo-only launch hooks DEBUG-gated and continue running `npm run check:ios-release-hygiene` before release work.
- Keep medication-specific product work on hold until product/legal/liability approval.

## What Still Belongs Outside The Shipping App

- Nexus command-center status, OS roadmap, and founder handoff files.
- Demo recordings and simulator runtime outputs.
- Local-only `.env` secrets and test database files.
- Any external App Store Connect, APNs, OAuth, or hosted database credentials.
