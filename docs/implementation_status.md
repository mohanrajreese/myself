# Implementation Status

Resume point for every work session. Update it when a task changes state; keep it short.

**Legend:** ☐ not started · ◐ in progress · ☑ verified by automated tests · 📱 verified on device · ⏳ implemented, device verification pending · ✋ waiting for design approval

## Current position

| Item | Value |
|---|---|
| Phase | 2 — Core tracking (approved 17 Nov 2026); Phase 1 built, phone verification pending |
| Design canvas | https://claude.ai/artifact/NbteH4bFd6RxKXDceTkBz6 (Phase 1 approved 16 Nov 2026; Phase 2 screens approved 17 Nov 2026) |
| Blocked on | Owner's Supabase and Google OAuth setup for a phone build |
| Waiting on owner | Phone model; Supabase project; Google OAuth clients; Firebase project (Phase 6) |

## Phases

| Phase | Status | Report |
|---|---|---|
| 1 Foundation | ⏳ built, phone verification pending | [phase-1.md](reports/phase-1.md) |
| 2 Core tracking | ⏳ built, phone verification pending | — |
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
| F-14 | ◐ | Migrations written and checked on a local PostgreSQL (35 checks); not applied to a real Supabase project |
| F-07, F-08, F-09 | ☑ | Tokens, themes, fonts, components, router with six tabs |
| F-12, F-13 | ⏳ | Onboarding and Settings editing; screen tests pass; not seen on a phone |
| F-14a | ⏳ | Google sign-in and account binding; logic and screens tested with a fake; real sign-in unverified |
| F-15 | ⏳ | Home with targets, weight quick add, timeline, customisation |
| D7 | ☑ | Targets calculated from weight |
| F-16 | ☑ | Docs updated; report in `docs/reports/phase-1.md` |
| Schema v3 | ☑ | Catalogue table and meal photo index (local only); upgrades from v1 and v2 tested |
| C-14 | ☑ | Supabase migrations for measurements, water, foods, meals, saved meals, sleep, check-ins; 84 access-rule checks pass locally; not applied to a real project |
| Schema v2 | ☑ | Phase 2 tables added locally with an upgrade from version 1, tested with rows preserved |
| Calculations | ☑ | Nutrition totals, scaling, meal shares, averages; sleep averages and consistency; weight change (29 tests) |
| Storage: water, sleep | ☑ | Repositories with outbox, validation and tests |
| Storage: water, sleep, check-ins, measurements, weight edit and paging | ☑ | Repositories with outbox, validation and tests |
| Storage: foods, meals (snapshot items), duplicate, saved meals, junk history | ☑ | Tested, including "editing a food never changes past meals" |
| C-04 meal photos | ☑ | AES-256-GCM encrypted files, local index, never synced; key in Keystore-backed storage (phone pending) |
| C-16 food catalogue | ☑ | USDA (7,793 foods) and INDB (all 1,014 Indian dishes, estimates, household servings; 34 flagged as self-contradicting); any catalogue food editable as the user's own linked copy bundled and imported at start-up; search tested. Owner chose to add INDB without a licence file (17 Nov 2026). Credits on the About screen (Settings → About) |
| C-01 to C-13 screens | ☑ | Health tab, weight (chart, edit, delete, paging), measurements (custom types, history), sleep, check-in and history, water, food diary, add/edit meal (portions, photo, saved meal, duplicate, discard), food search and editor, saved meals, summary; About. Widget tests in `test/widget/health_test.dart`, `nutrition_test.dart`; all 30 screens pass contrast, tap-target, label and 2× text checks in light and dark |
| D8 fibre target | ☑ | Goals, Home tile and nutrition summary |
| Home in Phase 2 | ☑ | Live water, calories, protein, fibre and sleep tiles; quick add for meal, water, weight, sleep; timeline merges all of them |

## Device verification backlog

Features implemented but not yet confirmed on the phone. Test numbers refer to `docs/blueprint/07-testing.md` §6.

| Feature | Device tests | Result |
|---|---|---|
| Encrypted databases open and persist across restarts | Launch, add data, force-stop, relaunch | Pending |
| Backup exclusion | `adb backup` yields no app data | Pending |
| Google sign-in, onboarding, Home | Fresh install, sign in, finish onboarding, relaunch in airplane mode (test 19) | Pending |
| Timezone through Kotlin | Weight entry shows the phone's timezone in the database | Pending |
| Phase 2 tracking screens | Log water, a meal with a camera photo, sleep, a check-in; restart; values and photo still there | Pending |
| Meal photo camera and gallery | Take a photo and pick one; the stored file is not a readable image | Pending |
