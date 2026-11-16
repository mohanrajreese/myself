# FitBuddy — Implementation Blueprint

**Status:** awaiting implementation approval. No application code has been written.
**Source of truth:** FitBuddy PRD v2.0 (16 November 2026). Section references such as "§5.6" point into the PRD.
**Prepared:** 16 November 2026

| # | Document | Covers |
|---|---|---|
| 1 | [01-architecture.md](01-architecture.md) | Repository analysis, toolchain and Android configuration, layering rules, folder structure, data boundaries, sync, security, approaches considered |
| 2 | [02-dependencies.md](02-dependencies.md) | Flutter packages, native Android integrations, external services |
| 3 | [03-database.md](03-database.md) | Drift schema (two databases), Supabase PostgreSQL schema, SQL migration plan, RLS, sync protocol |
| 4 | [04-ui-ux-spec.md](04-ui-ux-spec.md) | Design tokens, component library, navigation map, screen inventory, UX rules |
| 5 | [05-notifications-alarms-steps.md](05-notifications-alarms-steps.md) | Reminder/alarm engine, FCM, step counting, screen time, timers |
| 6 | [06-milestones-and-tasks.md](06-milestones-and-tasks.md) | Seven phases, task checklist, acceptance criteria, PRD traceability matrix |
| 7 | [07-testing.md](07-testing.md) | Unit, widget, integration, migration, RLS, privacy and physical-device test plans |
| 8 | [08-risk-register.md](08-risk-register.md) | Android platform limitations and implementation risks |

---

## 1. What the repository contains today

| Finding | Detail |
|---|---|
| Repository | `mohanrajreese/myself`, branch `dev/bold-galileo-ssmrkj` |
| Contents | **Empty.** No commits, no files, no Flutter project, no Android project, no default branch |
| Consequence | Everything is greenfield. There is no existing Flutter/Android setup to conform to, and nothing to migrate |
| PRD in repo | Not present. It must be committed as `docs/PRD.md` so later work sessions can read it (task F-00) |

Toolchain facts checked on 16 November 2026 (recorded for orientation only; versions are re-resolved when implementation begins, per §2.1):

| Item | Current |
|---|---|
| Flutter stable | 3.50.0 (Dart 3.14.0) |
| Newest Android platform | API 37 (Android 17) |
| `flutter_local_notifications` | requires `compileSdk 37`, AGP 9.1.1 or newer, core-library desugaring |
| AGP 9 | uses built-in Kotlin; the separate `kotlin-android` plugin is no longer applied |
| `sqlcipher_flutter_libs`, `sqlite3_flutter_libs` | **end-of-life.** Encryption now comes from the `sqlite3` package's build hook (`source: sqlite3mc`) |

## 2. Decisions that need your answer

These change what gets built. Each has a recommended default, which is what the blueprint assumes.

| # | Decision | Recommended default | Why it matters |
|---|---|---|---|
| D1 | **Your phone model and Android version** | — (needed) | Sets `minSdk`, tells us which manufacturer battery manager we are up against, and whether the step sensor exists. Blueprint assumes `minSdk 29` (Android 10) |
| D2 | **Sign-in model** | App works fully without an account. Sign-in (email and password) is offered at the end of onboarding and in Settings, and turns sync on | The PRD's onboarding has no sign-in screen, but sync needs Supabase Auth. A mandatory sign-in would block offline first use |
| D3 | **Starter food catalogue** | None bundled. Food diary runs on custom foods, saved foods, saved meals and recents | The PRD names no nutrition data source, and I will not invent nutrition values. If you want a catalogue, name the dataset (and confirm its licence) and it becomes a Phase 2 task |
| D4 | **Project location in the repo** | Flutter project at the repository root | The repo is called `myself`, not `fitbuddy`. If it will hold other things, say so and the project goes in `fitbuddy/` |
| D5 | **Distribution** | Personal sideloaded APK (plus a signed AAB build) | Google Play would add policy declarations for usage access, exact alarms and the health foreground service |

## 3. Calls I made where the PRD is silent

Stated so you can overrule them. None adds a feature; each fills a gap the PRD leaves open.

| # | Gap | Call | Reason |
|---|---|---|---|
| C1 | PRD lists `workout_exercises` but no exercise-library table | Add cloud table `exercises` | Custom exercises (§5.8) must exist for workouts to reference them |
| C2 | Meal and progress photos have no storage defined | Local-only, encrypted files. No Supabase Storage in v1 | §5.3 calls progress photos "private". No bucket is specified |
| C3 | GPS routes have no storage defined | Route points local-only; only distance, duration and pace sync | A route reveals home location. Drawn as a line without map tiles, so no map provider or API key is introduced |
| C4 | Recovery and posture records (§5.19) appear in neither table list | Local-only table `local_recovery_logs` | Conservative default. Can be moved to cloud later |
| C5 | §6.3 and §7.1 mention private activity definitions, but §5.14 has no "private" option | A "Private" switch when creating an activity. It cannot be changed afterwards | Moving records between stores would mean uploading or un-uploading history |
| C6 | Medication needs definitions as well as logs | Add `local_medications` beside `local_medication_logs` | A log needs something to refer to |
| C7 | Saved meals and workout templates need item storage | Stored as a JSON document inside `saved_meals` / `workout_templates` | Templates are copied on use; no extra tables needed |
| C8 | App lock mechanism is unspecified | App PIN (hashed) with optional biometric unlock | Works on a phone with no screen lock, and does not lose data when fingerprints change |
| C9 | Android shows at most three notification buttons; §5.15C lists five actions | Buttons: Complete, Snooze, Skip. Tap opens the activity. Dismiss is the swipe (or a button on reminders with no activity) | Platform limit |
| C10 | Exercise library needs starting content | A seeded list of common exercises (name, category, muscle group, equipment, instructions) | Reference data, not user data. Custom exercises remain available |

## 4. What I need from you before specific tasks

| Needed | For | Blocks |
|---|---|---|
| A Supabase project (URL and publishable key), and a way to apply migrations | Auth, sync | Phase 1 Supabase tasks, Phase 6 |
| A Firebase project (`google-services.json`; a service account for the server function) | FCM | Phase 6 push tasks |
| A physical Android phone and someone to run the device test script | §11.3 device tests | Sign-off of Phases 3, 4, 5 and 7 |
| A release keystore (created by you, kept out of the repo) | Signed APK/AAB | Phase 7 |

**What cannot be verified from this cloud environment:** there is no phone, sensor, or emulator here. I can build the app and run static analysis, unit tests, widget tests and Kotlin JVM tests. Step counting, alarms, reboot recovery, usage access, FCM delivery and manufacturer battery behaviour can only be confirmed on your device. Features that depend on them will be reported as "implemented, device verification pending" until you run the script in [07-testing.md](07-testing.md) §6.

## 5. Approval

Implementation of Phase 1 starts only after you approve this blueprint (with any changes to D1–D5 and C1–C10).
