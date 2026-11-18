# Phase 4 report — Fitness

**Date:** 18 November 2026 · **State:** built and verified by automated tests; everything that depends on the step sensor, GPS or Android background behaviour is pending a phone run (needs the owner's Supabase and Google sign-in setup to install and sign in).

## 1. Features completed

| Task | Result |
|---|---|
| S-01 | `StepApi` (Pigeon): sensor present, permission, prompt, one reading now |
| S-02 | Native buffer (framework SQLite, no Flutter engine or key), boot count per reading, 15-minute snapshot job |
| S-03 | Opt-in continuous counting: foreground service (type `health`) with 5-minute, midnight, shutdown and time-change readings; boot reading and restart |
| S-04 | Step ingest and attribution: baseline first reading, never subtracting across boots, reboot gaps, uncertain spans, midnight split, per-reading offsets |
| S-05 | Steps dashboard: today, goal, percentage, remaining, 7-day average, monthly change, week and month charts, uncertain days explained, last reading, sensor status, continuous switch, labelled adjustment; intro, refusal and no-sensor states |
| S-06 | Walk, run, ride by hand: start, end, distance, notes; pace or speed; edit; delete |
| S-07 | Optional GPS: explanation then while-in-use permission, foreground notification, accuracy and jitter filtering, pause, route drawn as a line without map tiles and kept on the phone (C3) |
| S-08 | Exercise library: 37 seeded exercises with fixed ids (C10) and your own, with edit and archive |
| S-09 | Gym workout: add, remove and reorder exercises; add, edit, complete and remove sets; rest timer |
| S-10 | Duplicate, templates (save, start from, delete), workout history with filters |
| S-11 | Personal records per the blueprint rules; best-set progression chart per exercise |
| S-12 | Fitness overview; Home steps tile live; quick add Workout |
| S-13 | Supabase migration for the six synced fitness tables with access-rule checks; `step_tracking.md`; this report |

## 2. Verification

| Verified by automated tests | Verified on device | Implemented, device verification pending |
|---|---|---|
| Step attribution (reboot, midnight, gaps, timezone change, anomalies), ingest and adjustments, workout storage and rules, GPS track maths, every Phase 4 screen's main flows with fake sensor and location, accessibility checks on 45 screens in light and dark, and (now for real) 2× text on a 320 dp phone, manifest allow-list, local access-rule checks | None yet | Step sensor reads, snapshot job, continuous service, boot and midnight readings, permission prompts, GPS fixes and the foreground location notification, route accuracy |

## 3. Files created or modified

67 files since the Phase 4 designs. Main areas: `lib/features/fitness/{domain,data,presentation}`, `lib/core/platform` (`StepApi`, location), `android/app/src/main/kotlin/.../steps/`, `lib/core/database/tables/fitness_tables.dart`, `supabase/migrations`, `test/unit/fitness`, `test/widget/fitness_test.dart`.

## 4. Database changes

| Store | Change |
|---|---|
| Drift app database | v7: `step_logs`, `exercises`, `workout_sessions`, `workout_exercises`, `exercise_sets`, `workout_templates` (synced); `local_step_readings`, `local_step_daily`, `local_workout_route_points` (local) |
| Supabase | `20261118000700_fitness.sql` (one step total per day; child tables tied to their owner) |
| Native | `step_buffer.db` (framework SQLite, excluded from backup) |

## 5. Android permissions added

`ACTIVITY_RECOGNITION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_HEALTH`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `FOREGROUND_SERVICE_LOCATION`. No background location. Details in `docs/permissions.md`.

## 6. Packages installed

`geolocator_android` 5.2.1 and `geolocator_platform_interface` 4.4.1 (the full `geolocator` package conflicts with `connectivity_plus`); `androidx.work:work-runtime-ktx` 2.10.1 (native).

## 7. Tests executed and results

| Suite | Count | Result |
|---|---|---|
| Unit | 309 | Pass |
| Widget, including accessibility | 199 | Pass |
| Architecture boundaries and manifest | 15 | Pass |
| Supabase access rules (local PostgreSQL) | all checks | Pass |
| `flutter analyze` | — | No issues |
| `flutter build apk --debug` | — | Builds |

**Correction to earlier reports.** The accessibility suite's "no overflow at double text size on a small phone" check, written in Phase 1, pumped Home only and never opened the screen it named. The Phase 2 and 3 reports therefore overstated that check. It now opens each screen; it found overflows on 7 earlier screens (edit goals, add water, add meal, nutrition summary, Habits activities, reminder editor, sound picker), all fixed.

## 8. Known limitations

| Limit | Risk |
|---|---|
| Some phones count only while a listener is registered; without continuous counting, steps may be missed until the next snapshot | R-01 |
| Battery managers may stop the service or delay snapshots | R-02 |
| Android 12+ forbids starting the service from the background; it starts from the app or at boot | R-03 |
| Steps just before a sudden power-off can be lost | R-18 |
| GPS drains battery and is inaccurate indoors; fixes worse than 50 m are ignored | R-16 |
| Only the Android 10 phone is available for testing; Android 14 foreground-service rules are implemented from documentation | R-37 |

## 9. Remaining tasks

- Owner: Supabase project and Google OAuth clients, then install the debug APK.
- Device tests 1–9 (`blueprint/07-testing.md` §6) and a 1 km GPS walk with the screen off. These are Phase 4's exit criteria.
- Phase 5 (Lifestyle and privacy) waits for approval; its screens go to the design canvas first.
