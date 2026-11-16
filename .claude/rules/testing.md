---
paths:
  - "test/**"
  - "integration_test/**"
  - "android/app/src/test/**"
---

# Testing rules

- Required cases per area are listed in `docs/blueprint/07-testing.md` §2–4. Cover the listed cases for the feature in hand; do not skim the whole file.
- Write the failing test before the code. Never skip, disable or loosen a test to get green.
- Time-dependent tests use a fake `Clock` and `fake_async`. No real sleeps.
- Database tests use in-memory Drift. Auth uses the fake `AuthRepository`. No test calls Google, Supabase production or FCM.
- Widget tests cover loading, empty, error and offline states, light and dark, and font scale 2.0.
- Tests that need a phone go in the device script, not in the automated suites.
