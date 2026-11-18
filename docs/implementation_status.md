# Implementation Status

Resume point for every work session. Update it when a task changes state; keep it short.

**Legend:** ☐ not started · ◐ in progress · ☑ verified by automated tests · 📱 verified on device · ⏳ implemented, device verification pending · ✋ waiting for design approval

## Current position

| Item | Value |
|---|---|
| Phase | 7 — Quality and release: everything possible without a phone is done (18 Nov 2026); the device test plan and cloud setup are with the owner |
| Design canvas | https://claude.ai/artifact/NbteH4bFd6RxKXDceTkBz6 (Phase 1 approved 16 Nov 2026; Phase 2 screens approved 17 Nov 2026; Phase 3 screens approved 17 Nov 2026; Phase 4 screens approved 18 Nov 2026; Phase 5 screens approved 18 Nov 2026; Phase 6 screens approved 18 Nov 2026) |
| Blocked on | Owner's Supabase and Google OAuth setup for a phone build |
| Waiting on owner | Phone model; Supabase project (migrations, functions); Google OAuth clients (debug and release fingerprints); Firebase project; release keystore; running `docs/device_test_plan.md` |

## Phases

| Phase | Status | Report |
|---|---|---|
| 1 Foundation | ⏳ built, phone verification pending | [phase-1.md](reports/phase-1.md) |
| 2 Core tracking | ⏳ built, phone verification pending | [phase-2.md](reports/phase-2.md) |
| 3 Activities and reminders | ⏳ built, phone verification pending | [phase-3.md](reports/phase-3.md) |
| 4 Fitness | ⏳ built, phone verification pending | [phase-4.md](reports/phase-4.md) |
| 5 Lifestyle and privacy | ⏳ built, phone verification pending | [phase-5.md](reports/phase-5.md) |
| 6 Reports and synchronisation | ⏳ built, phone and cloud verification pending | [phase-6.md](reports/phase-6.md) |
| 7 Quality and release | ⏳ automated parts done; device run pending | [phase-7.md](reports/phase-7.md) |

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
| P-01 app lock | ☑ · ⏳ biometric, secure window | Salted PBKDF2 PIN hash, auto-lock, backoff; `LockGate` on every private route; PIN pad needs an explicit Unlock tap; fingerprint through `local_auth`; `FLAG_SECURE` while the lock is on |
| P-02 private habits | ☑ | Two seeded types and your own; record now or with details; weekly/monthly counts; history; delete; archive |
| P-03 private activities | ☑ | "Private" switch in the activity builder (C5) and an add button in the private space; yes/no or counted; log, history, archive |
| P-04 bowel | ☑ | Quick log, history, 7-day count, 30-day per-day average, consistency split, check-in reminder |
| P-05 sensitive reminders | ☑ logic · ⏳ delivery | Private store; title always "Praxis reminder", secret on the lock screen (tested) |
| P-06 hygiene | ☑ | Eight standard routines on request (seeded activities, `hygiene.*`), steps for skincare, mark all done. `hygiene_logs` table not created (03-database.md, changed 18 Nov 2026) |
| P-07 medication | ☑ | List, editor with schedule, taken/skipped/not marked, reminder from the notification records a dose |
| P-08 posture and recovery | ☑ | Rest day, soreness, recovery, notes; movement-break and posture reminders (Phase 3 reminders) |
| P-09, P-10 screen time | ☑ logic · ⏳ device | `UsagePlugin`, usage-access flow, day/week/month, most-used apps, daily target, one generic alert a day |
| P-11 privacy suite | ☑ | Outbox, allow-list, generic secret notifications, import boundaries; full-sync traffic check added in Phase 6 |
| P-12 progress photos | ☑ · ⏳ camera | Encrypted per file, grid, view, delete |
| P-13 | ☑ | Migration 9 not needed (no `hygiene_logs`); `privacy.md`; report. Device run pending |

| Schema v9 | ☑ | `local_sync_cursors`; upgrade from v1–v8 tested |
| R-01, R-03 reports and insights | ☑ | Per-day series per domain, averages over days with records, previous-period comparison, up to five descriptive insights (wording tested for causal terms) |
| R-02 Insights screens | ☑ | Day, week, month, custom; report per domain with chart and named gaps |
| R-04 private history | ☑ | Behind the lock; habits, bowel, medication, private activities |
| R-05, R-06 sync engine and restore | ☑ logic · ⏳ real project | Push, pull, backoff, local-wins, cursors, tombstones; returning user restored before onboarding |
| R-07 background sync and status | ☑ · ⏳ WorkManager | Start, resume, network back, Sync now, hourly job; Account and sync screen |
| R-08 FCM | ☑ logic · ⏳ delivery | Token lifecycle, preferences, foreground and background messages, tap opens Account and sync; needs the owner's Firebase project |
| R-09 migration 10 and Edge Functions | ☑ local · ⏳ deploy | Access-rule checks pass locally; functions type-checked and token signing tested with Deno; not deployed |
| R-10 export | ☑ · ⏳ save picker | JSON or CSV, date range, private data after PIN, photos, AES-256 passphrase |
| R-11 deletion | ☑ · ⏳ real project | Phone data, account (DELETE + same Google account), C11 now erases private data too |
| R-12 | ◐ | Report written; device tests 16–18 and cloud checks pending |

| Q-01 regression | ☑ | 646 Dart tests, access-rule checks, Deno test, analyze clean, debug and signed release builds |
| Q-02 device script | ⏳ | `docs/device_test_plan.md` written (19 blueprint tests, feature checks, release checks); run by the owner |
| Q-03 privacy audit | ☑ build · ⏳ device | Release manifest, binary secret scan, logging, sync traffic, push payload; FCM auto-init and delivery-metrics export turned off. Device steps in `docs/privacy_audit.md` |
| Q-04 performance | ☑ queries · ⏳ device | Three years of data: report month 22 ms, year 14 ms, export 0.4 s (build machine); all log tables use an index for date ranges. Cold start and scrolling are in the device plan |
| Q-05 accessibility | ☑ automated · ⏳ TalkBack | 57 screens in light and dark plus 2× text at 320 dp, private screens after unlock; TalkBack pass in the device plan |
| Q-06 migrations | ☑ | Every app-database version (1–8) upgrades to 9 and validates, with foreign-key checks and data from v1 and v8; private database v1→v2 |
| Q-07 release build | ☑ build · ⏳ phone | Signing from `android/key.properties`, R8 with keep rules; signed APK, split APKs and AAB built with a throwaway key (deleted); never signed with the debug key |
| Q-08 docs and report | ☑ | `docs/release.md`, `docs/device_test_plan.md`, `docs/privacy_audit.md`, Phase 7 report |

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
| App lock: private space absent from the app switcher, screenshots blocked, fingerprint unlock, auto-lock after time away | Open private space, press Recents, try a screenshot; leave for 2 min and return | Pending |
| Private and medication notifications show only "Praxis reminder" and nothing on the lock screen | Add a medicine at a time 2 min ahead, lock the phone | Pending |
| Screen time: usage access flow and totals against Digital Wellbeing | Grant access, compare one day | Pending |
| Progress photo camera and gallery | Add both; the stored file is not a readable image | Pending |
| Sync against the real project: offline records appear after reconnection, no duplicates; second install restores | Tests 16–17, plus a reinstall | Pending (needs Supabase project, migrations applied) |
| FCM foreground and background delivery, tap opens Account and sync, payload holds no health data | Test 18 | Pending (needs Firebase project and deployed send-push) |
| Export saved through the system picker and opened with 7-Zip using the passphrase | Export with and without passphrase | Pending |
| Account deletion removes the cloud rows | Delete account, then check the project tables | Pending |
