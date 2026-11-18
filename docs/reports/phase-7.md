# Phase 7 report: Quality and release

**Date:** 18 November 2026. **State:** every part of this phase that can be done without a phone or the owner's cloud projects is done and verified. The device test plan, the cloud setup and the release key are with the owner. The app is not called released until the device plan passes.

## 1. Tasks

| Task | Result |
|---|---|
| Q-01 Full regression | Analyse clean; 359 unit, 268 widget, 16 architecture and 3 performance tests pass; access-rule checks on local PostgreSQL pass; Edge Functions type-check and their test passes; debug APK, signed release APKs and AAB build |
| Q-02 Device script | Written: `docs/device_test_plan.md`. Covers the 19 blueprint tests with steps, 14 feature checks from earlier phases, and release-build checks (smoke test, cold start, long history, TalkBack, largest font). Not yet run |
| Q-03 Privacy audit | Release build audited (`docs/privacy_audit.md`): backups and cleartext off, no analytics, no secrets in the binary, logging limited to event codes. One change: FCM no longer creates a token on its own, and delivery-metrics export is explicitly off; a test guards both. Traffic capture, backup extraction and logcat review are in the device plan |
| Q-04 Performance | Three years of daily records (about 10,000 meal items, 6,500 water entries): month report 22 ms, year report 14 ms, encrypted export 0.4 s, on the build machine. Every log table's date-range query uses an index (query-plan test). Cold start and scrolling are measured on the phone (device plan, section C) |
| Q-05 Accessibility | Automated: 57 screens in light and dark (contrast, tap targets, labels) and at 2× text on a 320 dp phone; the private screens after unlocking. TalkBack and the largest system font are in the device plan |
| Q-06 Migrations | Every app-database version 1–8 upgrades to 9 and matches a fresh install, with a foreign-key check, plus data kept from v1 and v8. Private database v1→v2 |
| Q-07 Release build | Release signing reads `android/key.properties` (git-ignored). Without it the build stops with a message, so a release is never signed with the debug key. R8 code and resource shrinking with keep rules. Verified with a throwaway key, deleted afterwards: signed APK (83 MB, all CPU types), split APKs (arm64 30.5 MB) and AAB (78.5 MB); `apksigner` verifies |
| Q-08 Documentation | `docs/release.md` (key, fingerprint registration, build commands), `docs/device_test_plan.md`, `docs/privacy_audit.md`, status file, this report |

## 2. Verification

| Verified by automated tests | Verified on device | Implemented, device verification pending |
|---|---|---|
| Everything in §1 marked as built or run here; the whole automated suite; migrations; query plans and timings on the build machine; release-manifest audit; the release build signs | None yet (no phone available to the build environment) | Every item in `docs/device_test_plan.md`, the release build on a phone, cold start, TalkBack, sync and push against real projects |

## 3. Defects found in this phase

| Defect | Fix |
|---|---|
| The migration test still validated upgrades against version 8 after version 9 was added in Phase 6, so the v8→v9 step was only partly checked | Validates against the current version; a new test fails if a version is added without being covered |
| FCM would have created a device token at startup once Firebase is configured, before sign-in | `firebase_messaging_auto_init_enabled=false`; the token is created only when the app registers after sign-in |
| Build warning: `workmanager_android` still carried the legacy Kotlin Gradle Plugin line, which future Flutter versions will refuse to build | Built-in Kotlin switched on for the whole build; a patched copy of the plugin without that line in `third_party/workmanager_android` (see its `FITBUDDY_PATCH.md`), used through `dependency_overrides`. Debug and release builds now have no warnings |

## 4. Known limitations and risks

| Limit | Risk |
|---|---|
| No phone has run any build yet; every hardware, background and notification behaviour is unconfirmed | R-27 |
| The all-CPU APK is 83 MB because it carries three architectures; install the arm64 split APK (30.5 MB) | — |
| Timings above are from the build machine; a mid-range phone will be slower | — |

## 5. What the owner needs to do

1. **Cloud setup:**
   - Supabase: create the project, apply the migrations, deploy the two functions.
   - Google OAuth clients for the debug fingerprint and later the release fingerprint.
   - Firebase project, if you want push.

   Steps: README, `docs/sync_and_push.md`.
2. **Phone:** install the debug APK and work through `docs/device_test_plan.md`; send back the filled table.
3. **Release key:** create it, register its fingerprint, build the signed APK and repeat section C of the device plan on it (`docs/release.md`).

Failures from the device run come back to me as fixes. When the plan passes, the status file moves Phases 1–7 from "device verification pending" to "verified on device".
