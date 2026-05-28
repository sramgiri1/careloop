# CareLoop Brand Inventory

Updated: 2026-04-26

Canonical iOS brand assets are stored in `ios/CareLoop/Resources/Assets.xcassets/`.

Assets:
- `CareLoopIcon.imageset`
  - Source: supplied logo sheet from `Screenshot 2026-04-26 at 8.10.33 PM.png`
  - Usage: compact icon, onboarding hero mark, app icon master
- `CareLoopWordmarkLight.imageset`
  - Usage: light surfaces and navigation brand banner
- `CareLoopWordmarkDark.imageset`
  - Usage: dark surfaces
- `AppIcon.appiconset/AppIcon-1024.png`
  - Synced to the current CareLoop icon mark
- `GoogleLogo.imageset`
  - Usage: sign-in provider button
- `FacebookLogo.imageset`
  - Usage: sign-in provider button

Implementation:
- Shared SwiftUI brand component: `CareLoop/Views/Shared/CareLoopBrand.swift`
- Onboarding uses the canonical icon asset instead of an SF Symbol or generated mark.
- App screens use the shared brand banner to keep the same wordmark treatment across screens.

Current screen coverage:
- Onboarding
- Join Circle
- Task list
- Settings
- Notifications permission
- Circle settings
- Circle members
- New task
- Task detail
- Terms & Conditions
