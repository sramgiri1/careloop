# CareLoop Visual QA

Date: 2026-05-17
Device: iPhone 17 Pro simulator

## Screens Reviewed

| Screen | Screenshot | Result | Notes |
| --- | --- | --- | --- |
| Circle directory | `screenshots/circle-directory.png` | Pass after polish | Circle name, care receiver summary, active status, and role are readable without the truncation seen in the earlier mockup. Create and join actions are separated and easier to scan. |
| Care organizer home | `screenshots/organizer-home.png` | Pass | Persona-specific dashboard hierarchy is clearer than the original mockup, with summary metrics and receiver context visible above the fold. |
| Caregiver home | `screenshots/caregiver-home.png` | Pass | Role-specific color, copy, and task summary distinguish caregiver mode from organizer mode. |
| Care receiver home | `screenshots/receiver-home.png` | Pass after polish | Primary task card and complete action are prominent. The receiver hero now fills the content column consistently. |

## UX Improvements Made

- Moved circle role/status chips below the circle subtitle so long circle names and care receiver names get the primary horizontal space.
- Expanded the care receiver hero card to the full content width for a more stable and polished layout.
- Preserved separate create and join paths, which avoids hiding invitation entry behind a generic plus action.

## Remaining Visual QA Gaps

- Task board, task detail, and recurring task creation need simulator screenshots across organizer, caregiver, and care receiver roles.
- People/access management needs screenshots for invite pending, accepted, declined, blocked, and role-change states.
- Delete circle and remove member flows need destructive-action visual review.
- Payment/paywall screens need device-level review once StoreKit/Apple Pay configuration is connected.
- Empty, loading, error, and offline states need their own visual pass before release.
