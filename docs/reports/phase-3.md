# Phase 3 report — Activities and reminders

**Date:** 17 November 2026 · **State:** built and verified by automated tests; everything that depends on Android delivering notifications is pending a phone run (needs the owner's Supabase and Google sign-in setup to install and sign in).

## 1. Features completed

| Task | Result |
|---|---|
| A-01 | Schedule rules (one-time, daily, selected days, every N weeks, monthly, every N days, interval) stored as JSON; wall-clock evaluation with DST gaps moved forward and repeated times firing once |
| A-02 | Activity builder: name, description, category, icon, seven tracking types, essential/optional, target and unit, checklist steps, schedule, reminder times, stopwatch option, Home visibility, archive state, sort order |
| A-03 | Edit, duplicate, archive, restore, delete (with confirmation), reschedule (past days keep their old rule), change priority, permitted tracking-type changes, history |
| A-04 | Logging per tracking type; several occurrences a day; Done, Due, Not logged, Skipped and Not scheduled are distinct, each with an icon and a word; no streaks |
| A-05 | Home "Essential today" with Done, Snooze and open; quick add gains Activity |
| A-06 | Notification permission asked in context after a rationale; denial notice; seven channels |
| A-07 | Reminders: all types and presets; title, description, repeat, sound (channel), vibration, snooze default, normal or important alarm, quiet-hour behaviour, linked activity, "only if not done" |
| A-08 | Planner and scheduler: rolling 7-day window, stable notification ids, diffing against stored state, 400 budget, serialised re-plans |
| A-09 | Exact-alarm capability check, rationale, settings page, inexact fallback |
| A-10 | Complete, Snooze, Skip from the notification, in the app and in a background isolate; tapping opens the activity; dismissing completes nothing |
| A-11 | Snooze 5, 10, 15, 30 minutes or a custom number |
| A-12 | Quiet hours, including overnight periods; per reminder: wait, skip or ring anyway |
| A-13 | Channel sound and vibration through Android's channel settings, test sound, test vibration |
| A-14 | Recovery: plugin boot receiver, `SystemEventReceiver`, WorkManager top-up every 6 hours, re-plan on start, resume and return from settings |
| A-15 | "Only if not done" reminders; water, workout, sleep and posture presets |
| A-16 | Notification history (30 days, no text stored) and limitation notices |
| A-17 | Stopwatch and timer: state machine from timestamps, persistence, history, completion notification, activity log on finish; cancel logs nothing |
| A-18 | Supabase migrations for activities and reminders with access-rule checks; `notifications.md`; this report |

## 2. Verification

| Verified by automated tests | Verified on device | Implemented, device verification pending |
|---|---|---|
| Scheduling and DST, planner, scheduler diffing and idempotence, timezone change, exact fallback, notification button logic, "only if not done", snooze, quiet hours, activity rules and storage, timer state machine and storage, every Phase 3 screen's main flows, accessibility checks on 39 screens in light and dark plus 2× text at 320 dp, manifest allow-list, local access-rule checks | None yet | Notifications appearing on time, buttons from the notification shade with the app closed, exact-alarm access, battery-optimisation state, disabled-channel detection, test sound and vibration, reboot recovery, WorkManager top-up, timer notification |

## 3. Files created or modified

66 files since the end of the Phase 3 storage work, plus the earlier Phase 3 commits. Main areas: `lib/core/scheduling`, `lib/core/notifications`, `lib/core/platform` (`AlarmApi`), `lib/features/{activities,reminders,timers}`, `lib/app/routine*`, `android/app/src/main` (manifest, `AlarmPlugin.kt`, `SystemEventReceiver.kt`), `supabase/migrations`, `test/unit/{scheduling,activities,timers,reminders,notifications}`, `test/widget/habits_test.dart`.

## 4. Database changes

| Store | Change |
|---|---|
| Drift app database | v5: `activity_definitions`, `activity_logs` (synced), `local_timer_sessions`, `local_timer_events` (local). v6: `reminders` (synced), `local_notification_state` (local). Dumps in `drift_schemas/app/` |
| Supabase | `20261117000500_activities.sql`, `20261117000600_reminders.sql` |
| Private database | Unchanged. Private activities and sensitive reminders arrive in Phase 5 |

## 5. Android permissions added

`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`. Receivers: the notification plugin's three, and `SystemEventReceiver`. Details in `docs/permissions.md`.

## 6. Packages installed

`flutter_local_notifications` 23.0.2, `timezone` 0.11.2, `workmanager` 0.10.10.

## 7. Tests executed and results

| Suite | Count | Result |
|---|---|---|
| Unit | 278 | Pass |
| Widget, including accessibility | 164 | Pass |
| Architecture boundaries and manifest | 15 | Pass |
| Supabase access rules (local PostgreSQL) | all checks | Pass |
| `flutter analyze` | — | No issues |
| `flutter build apk --debug` | — | Builds |

Defects found and fixed by the new tests: concurrent re-plans could give two notifications the same id (re-plans now run one at a time); a layout overflow in the shared settings row and in the activity filter chips; a save error shown off-screen in the builder; the reminder editor reading text during start-up.

## 8. Known limitations

| Limit | Risk |
|---|---|
| Exact alarms need special access from Android 12 and are off by default from 14; the fallback can be minutes late | R-04 |
| Doze, battery saver and manufacturer battery managers can delay reminders | R-02, R-05 |
| After a force-stop, nothing is delivered until the app is opened; after a reboot, not until first unlock | R-06 |
| Three notification buttons only; swiping a notification away is not reported | R-11 |
| A channel's sound is fixed once created; sound is changed in Android's channel settings, not in the app | R-08 |
| No in-app system-sound picker or custom sound file yet | A-13 partial |
| The WorkManager plugin writes a timestamp-only marker file to the app's private temp folder | — |

## 9. Remaining tasks

- Owner: Supabase project and Google OAuth clients, then install the debug APK.
- Device tests 10–15 (`blueprint/07-testing.md` §6) and the Phase 3 rows in the status file's device backlog. These are Phase 3's exit criteria.
- Phase 4 (Fitness) waits for approval; its screens go to the design canvas first.
