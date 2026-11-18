# Architecture (as built)

Design and rationale: [`blueprint/01-architecture.md`](blueprint/01-architecture.md). This file records what exists in the code and any deviation from the design.

## Built so far

| Area | State |
|---|---|
| Flutter project | Created at the repository root, Android only |
| Android build | AGP 9.3.1, built-in Kotlin, `compileSdk`/`targetSdk` 37, `minSdk` 29, core-library desugaring |
| SQLite | SQLite3MultipleCiphers bundled through the `sqlite3` build hook (`libsqlite3mc.so` confirmed in the debug APK) |
| Signing | Project debug keystore `android/app/debug.keystore` |
| Core | `Clock`, `LocalDate`, `Result`/`Failure`, redacting `AppLogger`, integer unit conversions, UUID v7 ids |
| Databases | `AppDatabase` and `PrivateDatabase`, encrypted, schema v1; outbox allow-list triggers |
| Data layer | Settings, profile, goals (effective-dated) and weight repositories; each synced write queues an outbox entry in the same transaction |
| Platform channel | `SystemInfoApi.timeZoneId` (Pigeon) |
| Boundary tests | `test/architecture/`: layer rules, privacy rule, injected clock, manifest hardening |
| App | Theme and tokens, components, router, sign-in, onboarding, Home, Settings (Phase 1 screens) |
| Strings | `lib/l10n/app_en.arb`, generated with `flutter gen-l10n` |

## Deviations from the blueprint

| Item | Blueprint | As built | Reason |
|---|---|---|---|
| Timezone ID | `flutter_timezone` package | Own Kotlin call through a Pigeon API | The package still applies Kotlin Gradle Plugin 1.7.10 and does not build with AGP 9 |
| Riverpod providers | Code-generated | Hand-written, with all repository providers in `lib/app/providers.dart` | One composition root keeps features from importing each other; no generator needed |
| Material library | `package:flutter/material.dart` | `package:material_ui/material_ui.dart` | Flutter 3.47+ moved Material into its own package |
| Touch targets | 44 dp on the design canvas | 48 dp | Android accessibility guideline, enforced by tests |
| Bottom navigation text | Follows system text size | Capped at 1.15× | Six labels cannot grow without clipping; screen-reader labels are unaffected |
| Feature-to-feature navigation | — | Through routes only (for example Home opens the weight sheet by path) | Keeps the "another feature only through its domain" rule |
| Firebase configuration | `google-services.json` and the Google Services Gradle plugin | The four Firebase client values passed with `--dart-define-from-file` and `Firebase.initializeApp(options:)` | Same values the JSON file would carry, kept with the other build settings in the untracked env file; no Gradle plugin to maintain under AGP 9. Push stays off when they are absent |
| Pull cursors | Not in the table list | `local_sync_cursors` (app database v9) | Needed by the pull protocol in 03 §6.2 |
| `workmanager_android` | Package from pub.dev | Patched copy in `third_party/workmanager_android` (one Gradle change), with built-in Kotlin on (`android.builtInKotlin=true`) | The published 0.10.9 still names the legacy Kotlin Gradle Plugin, which Flutter flags as a future build failure. Remove the copy when a release drops the line (`FITBUDDY_PATCH.md`) |
