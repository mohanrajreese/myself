# Implementation Status

Resume point for every work session. Update it when a task changes state; keep it short.

**Legend:** ☐ not started · ◐ in progress · ☑ verified by automated tests · 📱 verified on device · ⏳ implemented, device verification pending · ✋ waiting for design approval

## Current position

| Item | Value |
|---|---|
| Phase | 1 — Foundation (approved 16 Nov 2026) |
| Design canvas | https://claude.ai/artifact/NbteH4bFd6RxKXDceTkBz6 (Phase 1 screens, awaiting owner approval) |
| Blocked on | Design approval for screen tasks; owner's Supabase and Google OAuth setup for a phone build |
| Waiting on owner | Phone model; Supabase project; Google OAuth clients; Firebase project (Phase 6) |

## Phases

| Phase | Status | Report |
|---|---|---|
| 1 Foundation | ◐ | — |
| 2 Core tracking | ☐ | — |
| 3 Activities and reminders | ☐ | — |
| 4 Fitness | ☐ | — |
| 5 Lifestyle and privacy | ☐ | — |
| 6 Reports and synchronisation | ☐ | — |
| 7 Quality and release | ☐ | — |

## Task log

Task definitions are in `docs/blueprint/06-milestones-and-tasks.md`.

| Task | State | Notes (one line) |
|---|---|---|
| F-00 | ☑ | PRD, rules, skills, README, docs skeleton |
| F-01 | ☑ | Flutter 3.50 project, AGP 9.3.1, SDK 37/29, debug keystore; debug APK builds |
| F-02 | ☑ | All planned plugins built together once; `flutter_timezone` dropped (fails on AGP 9); `firebase_core` and `workmanager_android` build but warn about old Kotlin setup; later-phase plugins removed from pubspec until needed |
| F-03 | ☑ | Lint settings, boundary rules with tests, CI workflow (CI run itself not yet observed) |
| F-04 | ☑ | Clock, LocalDate, Result/Failure, redacting logger, unit conversions (36 tests) |
| F-05 | ⏳ | Two encrypted Drift databases, key manager, schema v1 dumps (17 tests on the build machine); opening on the phone not yet verified |
| F-06 | ⏳ | Backups off, extraction rules, cleartext off, analytics deactivated (manifest tests); `adb backup` check pending |
| F-10 | ☑ | Settings, profile, effective-dated goals and weight repositories with validation (data layer only; screens wait for design approval) |
| F-11 | ☑ | Every synced write and its outbox entry share one transaction; one entry per row |
| — | ⏳ | Device timezone through a Pigeon/Kotlin call (Dart wrapper tested; Kotlin side builds, not run on a phone) |
| F-14 | ◐ | Migrations for profiles, goals and weight written and checked on a local PostgreSQL (35 checks); not applied to a real Supabase project yet |
| F-07, F-08, F-09, F-12, F-13, F-14a, F-15 | ✋ | Designs published on the canvas |

## Device verification backlog

Features implemented but not yet confirmed on the phone. Test numbers refer to `docs/blueprint/07-testing.md` §6.

| Feature | Device tests | Result |
|---|---|---|
| Encrypted databases open and persist across restarts | Launch, add data, force-stop, relaunch | Pending |
| Backup exclusion | `adb backup` yields no app data | Pending |
