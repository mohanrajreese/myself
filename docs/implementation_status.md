# Implementation Status

Resume point for every work session. Update it when a task changes state; keep it short.

**Legend:** ☐ not started · ◐ in progress · ☑ verified by automated tests · 📱 verified on device · ⏳ implemented, device verification pending · ✋ waiting for design approval

## Current position

| Item | Value |
|---|---|
| Phase | 5 — Lifestyle and privacy (approved 18 Nov 2026); Phases 1–4 phone verification pending |
| Design canvas | https://claude.ai/artifact/NbteH4bFd6RxKXDceTkBz6 (Phase 1 approved 16 Nov 2026; Phase 2 screens approved 17 Nov 2026; Phase 3 screens approved 17 Nov 2026; Phase 4 screens approved 18 Nov 2026; Phase 5 screens approved 18 Nov 2026) |
| Blocked on | Owner's Supabase and Google OAuth setup for a phone build |
| Waiting on owner | Phone model; Supabase project; Google OAuth clients; Firebase project (Phase 6) |

## Phases

| Phase | Status | Report |
|---|---|---|
| 1 Foundation | ⏳ built, phone verification pending | [phase-1.md](reports/phase-1.md) |
| 2 Core tracking | ⏳ built, phone verification pending | [phase-2.md](reports/phase-2.md) |
| 3 Activities and reminders | ⏳ built, phone verification pending | [phase-3.md](reports/phase-3.md) |
| 4 Fitness | ⏳ built, phone verification pending | [phase-4.md](reports/phase-4.md) |
| 5 Lifestyle and privacy | ◐ | — |
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
| A-01 schedule rules | ☑ | Seven rule types; DST gap and overlap |
| Schema v5, v6 | ☑ | Activities, logs, reminders (synced; Supabase migrations and access-rule checks); timers and notification state (local); upgrades from v1–v5 tested |
| A-02 to A-05 activities | ☑ | Builder with every field, edit, duplicate, archive, restore, delete, reschedule, priority, permitted type changes, history; logging per type, several per day; five states; Home essentials with Done, Snooze, open |
| A-06 permission and channels | ⏳ | Rationale then prompt; denial notice; seven channels |
| A-07 reminders | ☑ | All types and presets; title, description, repeat, sound (channel), vibration, snooze, priority, quiet-hour behaviour, linked activity, "only if not done" |
| A-08 planner and scheduler | ☑ logic · ⏳ delivery | Rolling 7-day window, stable ids, diffing, budget; serialised re-plans |
| A-09 exact alarms | ⏳ | `AlarmPlugin` capability, rationale, settings page, inexact fallback |
| A-10 notification actions | ☑ logic · ⏳ | Complete, Snooze, Skip in foreground and background isolate |
| A-11 snooze | ☑ | 5/10/15/30 min and custom |
| A-12 quiet hours | ☑ | Wait, skip, ring anyway; overnight periods |
| A-13 sound and vibration | ☑ choice · ⏳ playback | In-app picker: default, the phone's notification sounds, or a sound file (Android document picker, copied into private storage); a channel per sound; test sound and vibration |
| A-14 recovery | ⏳ | Plugin boot receiver, SystemEventReceiver, WorkManager top-up every 6 h, re-plan on start and resume |
| A-15 "if not done" and presets | ☑ | Water, workout, sleep and posture presets |
| A-16 notification centre | ☑ | 30-day history; limitation notices on Habits and in Settings |
| A-17 stopwatch and timers | ☑ · ⏳ notification | State machine, persistence, history, completion notification, activity log on finish, cancel logs nothing |
| A-18 migrations, docs, report | ☑ | Device test run pending |
| Schema v7 | ☑ | Steps, exercises, workouts, sets, templates (synced; Supabase migration and access-rule checks); step readings, daily workings, route points (local); upgrades from v1–v6 tested |
| S-01 to S-03 native steps | ⏳ | `StepApi`, buffer, one-shot read, snapshot worker, opt-in foreground service, boot reading |
| S-04 ingest and attribution | ☑ | Engine (10 tests) and repository |
| S-05 step dashboard | ☑ · ⏳ sensor | All dashboard items, states for intro, refusal and no sensor, labelled adjustment |
| S-06 walk, run, ride | ☑ | Manual entry with pace or speed, edit, delete, history |
| S-07 GPS | ☑ logic · ⏳ | While-in-use permission with explanation, foreground notification, accuracy and jitter filter, pause, route line kept on the phone |
| S-08 exercise library | ☑ | 37 seeded exercises with fixed ids; your own exercises, edit, archive |
| S-09 gym session | ☑ | Add, remove, reorder exercises; add, edit, remove sets; rest timer; finish |
| S-10 duplicate, templates, history | ☑ | |
| S-11 records and progression | ☑ | Blueprint rules; per-exercise chart |
| S-12 overview and Home | ☑ | Fitness overview; Home steps tile live; quick add Workout |
| S-13 migration, docs, report | ☑ | Device run pending |
| Accessibility | ☑ | The 2×-text check now opens each screen (it only checked Home before); 7 earlier screens fixed |
| Phase 5 schema | ☑ | Private database v2 (all §7.1 tables; none on the sync allow-list, tested); app database v8 recovery logs; upgrades tested |
| P-01 lock logic | ☑ | Salted PBKDF2 PIN hash in Keystore-backed storage, settings, auto-lock after time away, growing wait after 5 wrong PINs (7 tests). Lock screen, biometric and secure window follow design approval |
| Phase 5 screens | ◐ | Designs approved 18 Nov 2026 |

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
| Reminders deliver and buttons work | Tests 10–14 in `blueprint/07-testing.md` §6 | Pending |
| Reminders survive a reboot | Test 15 | Pending |
| Background WorkManager top-up and button presses with the app closed | Leave the phone overnight with reminders; press Complete from the shade with the app swiped away | Pending |
| Stopwatch survives the app being closed and the phone restarting | Start, swipe away, restart phone, reopen | Pending |
| Steps counted, reboot, midnight, timezone, battery saver | Tests 1–9 in `blueprint/07-testing.md` §6 | Pending |
| GPS workout with the screen off; route drawn; distance plausible | Walk 1 km with GPS, screen off | Pending |
