# 05 — Notifications, Alarms, Step Counting, Screen Time, Timers

The subsystems that depend most on Android behaviour. Everything marked **(device)** must be confirmed on a physical phone before it is reported as working (§5.6, §13.2).

---

## Part A — Reminders and alarms (§5.15, §8)

### A1. Two independent systems

| System | Works offline | Used for |
|---|---|---|
| Local scheduling and notifications | Yes | Every routine, activity, water, workout, sleep, medication, posture and custom reminder |
| FCM remote push | No | Account and security events, sync problems, backup status, future server reminders. Never health data (§5.15I) |

Local reminders never depend on FCM.

### A2. Approaches considered

| Option | Trade-off | Verdict |
|---|---|---|
| OS-level repeating alarms (one repeating schedule per reminder) | Least code. Cannot apply quiet hours, skip, "only if incomplete", or correct DST handling; §8 forbids fixed-interval repetition | Rejected |
| **Rolling window of one-shot occurrences**, computed in Dart from calendar rules, delivered by `flutter_local_notifications`, with a thin Kotlin plugin for capability checks and system events | Every occurrence is individually planned, cancellable and recorded. Needs a top-up job to keep the window full | **Chosen** |
| Fully custom Kotlin alarm and notification engine | Maximum control (for example swipe-dismiss callbacks). Much more native code and device testing | Kept as fallback if device testing exposes a gap in the plugin |

### A3. Components (§8)

| Service | Responsibility |
|---|---|
| `ReminderRepository` | CRUD for `reminders` (main) and `local_sensitive_reminders` (private) behind one interface |
| `OccurrenceCalculator` (pure Dart) | Schedule rule + timezone + range → list of local date-times. No I/O |
| `ReminderPlanner` (pure Dart) | Applies quiet hours, start/end dates, conditions and the alarm budget to produce the desired set of occurrences |
| `ReminderScheduler` | Compares the desired set with `local_notification_state`, schedules the missing, cancels the obsolete |
| `LocalNotificationService` | Wraps the plugin: channels, show, schedule, cancel |
| `AndroidAlarmService` | Wraps `AlarmPlugin`: exact-alarm capability, full-screen capability, battery-optimisation state, settings intents |
| `NotificationActionHandler` | Complete, Snooze, Skip, Dismiss, Open; runs in a background isolate when the app is closed |
| `NotificationPermissionService` | `POST_NOTIFICATIONS` status, rationale flow, channel-disabled detection |
| `NotificationHistoryRepository` | Reads `local_notification_state` for the notification centre |
| `FcmService` | Token lifecycle and message handling |

### A4. Schedule rules

One sealed type, stored as JSON, shared by activities, reminders and medication.

| Rule | Fields | PRD type |
|---|---|---|
| `OneTime` | date, time | One-time |
| `Daily` | times[] | Daily, multiple daily times |
| `Weekdays` | weekdays[], times[] | Selected weekdays |
| `Weekly` | every N weeks, weekdays[], times[] | Weekly |
| `Monthly` | day of month or nth weekday, times[] | Custom recurrence |
| `EveryNDays` | N, anchor date, times[] | Custom recurrence |
| `Interval` | every N minutes between a start and end time of day, optional weekdays | Interval (water, stand-up) |

All rules are evaluated on the local calendar in the device's current timezone. A 07:00 reminder is 07:00 wall-clock time before and after a DST change or a trip. A time that does not exist on a DST day moves to the next valid minute; a time that occurs twice fires once.

### A5. Planning and scheduling

**Window.** For each enabled reminder, plan occurrences for the next 7 days. If the total exceeds the alarm budget (400, safely under Android's 500-per-app limit), high-frequency interval reminders are shortened first, never below 48 hours.

**Triggers for re-planning** (all idempotent):

| Trigger | Source |
|---|---|
| Reminder created, edited, enabled, disabled, deleted | Repository |
| Activity completed or skipped (cancels today's "if incomplete" occurrences) | Activity repository |
| App start and resume | Bootstrap |
| Device boot, app update | `SystemEventReceiver` → worker |
| Timezone or clock change | `SystemEventReceiver` → worker |
| Exact-alarm access granted or revoked | `SystemEventReceiver` → worker |
| Top-up | WorkManager, about every 6 hours |
| Quiet hours changed | Settings |

**Algorithm.** desired = planner output; existing = `local_notification_state` rows with status `scheduled` or `snoozed`. Schedule `desired − existing`, cancel `existing − desired`, leave the intersection alone. Because occurrences are keyed by `(reminder, local date-time)`, running it twice changes nothing, so a timezone change or reboot cannot produce duplicates (§8).

**Identifiers.** Android needs a 32-bit integer per notification. Each planned occurrence is given the next value from a persistent counter and stored in `local_notification_state`, so the same occurrence always maps to the same ID and can be cancelled exactly (§5.15G).

**Lifecycle rules (§8).**

| Event | Steps |
|---|---|
| Create | Save locally → validate rule → plan → schedule → record state |
| Edit | Cancel that reminder's pending occurrences → save → plan → schedule |
| Delete or disable | Cancel pending occurrences → mark state rows cancelled |
| Reboot | Plugin restores its saved alarms; the worker then re-plans to repair anything missed |
| Timezone change | Re-plan; matching occurrences are kept, others replaced |

### A6. Exact and inexact delivery (§5.15G)

| Reminder setting | Access granted | Delivery |
|---|---|---|
| Normal | — | Inexact, allowed while idle. Android may shift it by some minutes, more in Doze |
| Exact alarm (user choice per reminder; default for medication and "Important alarms") | Yes | Exact, allowed while idle |
| Exact alarm | No | Falls back to inexact, and the reminder shows "may be delayed" with a link to grant access |

The app asks for exact-alarm access only when the user turns on an exact reminder, and only after a sheet explaining why. Android 14 and later deny this access by default.

### A7. Channels (§5.15H)

| Channel | Importance | Default sound | Lock-screen visibility |
|---|---|---|---|
| Important alarms | High, alarm audio usage, repeats until acted on | Alarm sound | Public (generic if sensitive) |
| Daily routines | Default | Notification sound | Public |
| Hydration | Low | None | Public |
| Fitness | Default | Notification sound | Public |
| Medication | High | Notification sound | Secret, generic text |
| Sleep | Default | Notification sound | Public |
| System notifications | Low | None | Public |
| Step tracking (ongoing) | Low | None | Public |

Android does not let an app change a channel's sound, vibration or importance after creation. To honour in-app sound choices (§5.15F), channels are versioned: choosing a new sound creates `routines_v2`, moves pending notifications to it, and deletes `routines_v1`. A reminder with its own sound gets a dedicated channel, grouped under its category. The settings screen also links to the system channel page and detects channels the user has disabled.

Sound sources: system notification and alarm sounds listed through `RingtoneManager`, the system sound picker, or a user-picked file copied into app storage. "Test sound" and "Test vibration" play immediately through `SoundPlugin`.

### A8. Actions (§5.15C, D)

Android displays at most three buttons.

| Reminder type | Buttons | Tap on body | Swipe away |
|---|---|---|---|
| Linked to an activity | Complete · Snooze · Skip | Opens the activity | Dismiss: nothing is logged |
| Not linked | Snooze · Dismiss | Opens the reminder | Dismiss |
| Medication | Taken · Snooze · Skip | Opens medication (after unlock if locked) | Dismiss |

| Action | Effect |
|---|---|
| Complete / Taken | Writes a completed log with `source = notification`; cancels the notification and today's remaining "if incomplete" occurrences |
| Snooze | Schedules a one-shot at now + the reminder's default (5, 10, 15 or 30 minutes, or a custom value). Other durations are chosen by opening the reminder. Snooze count is recorded |
| Skip | Writes a skipped log; the activity shows "skipped", not "missed" |
| Dismiss | Records `dismissed`. **Never** marks the activity complete (§5.15C) |

A swipe is not reported to the app by the plugin, so a swiped notification simply stays "delivered, no action" in history **(device)**.

### A9. Quiet hours (§5.15E)

One user-defined period, which may cross midnight (for example 22:30–06:30). Applied when planning:

| Reminder's quiet-hour behaviour | Result for an occurrence inside the period |
|---|---|
| Defer (default) | Moved to the end of the period; several deferred occurrences of one reminder collapse into one |
| Suppress | Not scheduled |
| Bypass (Important alarms, medication by default) | Scheduled as normal |

### A10. Reboot, force-stop and honesty (§5.15J)

| Situation | What happens | What the UI says |
|---|---|---|
| Reboot | Alarms are restored after the first unlock (app storage is unavailable before it) | "After a restart, reminders resume once you unlock your phone" |
| App force-stopped by the user or a battery manager | Android cancels the app's alarms and delivers no broadcasts until the app is opened | Status screen warns when battery optimisation is likely to interfere and links to the setting |
| Do Not Disturb, silent mode, channel disabled | Cannot be overridden | Stated on the reminder settings screen; disabled channels are flagged |
| Notifications permission denied | Reminders are saved but cannot show | Banner with a button to open settings |

### A11. FCM (§5.15I)

| Aspect | Design |
|---|---|
| Token registration | After sign-in and notification permission, the token is upserted to `device_notification_tokens` |
| Refresh | `onTokenRefresh` replaces the stored token |
| Invalidation | Sign-out and account deletion delete the token locally and mark it revoked on the server; the server also revokes tokens FCM reports as unregistered |
| Payload | Data-only: `{type, id}`. Text is produced on the device from the type code |
| Foreground | Shown as a local notification on the System channel, or as an in-app banner |
| Background | Top-level handler; may trigger a sync; shows a System-channel notification |
| Tap | Routed by type through GoRouter |
| Preferences | Per-type switches in Settings, enforced on the device and mirrored to the server |
| Server | `send-push` Edge Function using the FCM HTTP v1 API with credentials in function secrets |

---

## Part B — Step counting (§5.6)

### B1. The core problem

`TYPE_STEP_COUNTER` reports the number of steps since the last reboot, not today's steps. It resets to zero on reboot, and it delivers values only to a registered listener. The design therefore records timestamped readings, identifies which boot each belongs to, and derives daily totals from differences.

### B2. Approaches considered

| Option | Trade-off | Verdict |
|---|---|---|
| Read the sensor only while the app is open | Simplest. Midnight boundaries are guesses and a reboot loses everything since the last open | Rejected as the only source |
| Periodic background snapshots (WorkManager) | No persistent notification. Android may delay jobs by hours in Doze, so boundaries are approximate | Used as the fallback |
| **Foreground service with snapshot worker and boundary flushes** | Best accuracy. Needs an ongoing notification and is still subject to manufacturer battery managers | **Chosen**, as an opt-in "continuous tracking" mode |

If the user declines the ongoing notification, the app runs on snapshots plus foreground reads and labels the result accordingly.

### B3. Native collection (Kotlin)

| Component | Behaviour |
|---|---|
| `StepCollectionService` | Foreground service, type `health`. Registers the sensor listener with batching to save power. Writes a reading every 5 minutes when steps changed, at local midnight (scheduled wake-up), on `ACTION_SHUTDOWN`, and on timezone or clock change. Ongoing low-importance, silent notification with today's count. Returns `START_STICKY` |
| `StepSnapshotWorker` | Periodic job (15-minute minimum interval, subject to system deferral). Registers the listener, waits for one value, stores it, unregisters |
| `SystemEventReceiver` | On boot: stores a reading and restarts the service if continuous tracking is on |
| `StepBufferStore` | Small framework-SQLite file. The service and worker write here, so collection needs no Flutter engine and no database key |
| `BootSession` | Reads `Settings.Global.BOOT_COUNT`; derives boot time from wall clock minus elapsed realtime |

Each reading holds: cumulative steps, boot count, elapsed realtime, wall-clock UTC time, timezone ID, UTC offset, and source.

The service is started only when `ACTIVITY_RECOGNITION` is granted (Android 14+ throws otherwise) and only from a context Android allows (app in foreground, or boot). If the system kills it, the worker keeps taking snapshots and the app restarts the service when next opened.

### B4. Ingest and attribution (Dart)

`StepIngestor` drains the buffer into `local_step_readings` and acknowledges it. `StepAttributionEngine` is a pure function from ordered readings to daily totals, recomputing only affected days.

For each consecutive pair of readings `r1`, `r2`:

| Case | Steps counted | Period | Flag |
|---|---|---|---|
| Same boot, `r2 ≥ r1` | `r2 − r1` | `r1.time → r2.time` | — |
| Different boot | `r2` (steps since that boot) | `boot time → r2.time` | Gap `r1.time → boot time` marked uncertain; steps taken then are unknown unless a shutdown reading exists |
| Same boot, `r2 < r1` (sensor anomaly) | `r2` | `r1.time → r2.time` | Uncertain |
| Implausible rate (sustained above 5 steps per second) | As computed | — | Uncertain |

Assigning a period to days:

| Period | Rule |
|---|---|
| Within one local day | All steps to that day |
| Crosses midnight, 10 minutes or shorter | Split in proportion to time on each side |
| Crosses midnight, longer than 10 minutes | Split in proportion to time, and the steps are added to `uncertain_steps` on both days |

The local day of an instant is computed from the UTC offset recorded with the reading, so a timezone change mid-day attributes each period to the day it was on the phone's calendar at that moment. A reading is forced at the change to keep the boundary tight.

**What is never done:** the cumulative sensor value is never shown as "today"; readings from different boots are never subtracted; unknown periods are never filled with estimates presented as measurements.

### B5. Required behaviours (§5.6)

| Requirement | Handling |
|---|---|
| Sensor availability | Checked on entry; no sensor → "This phone has no step counter" state with manual entry only |
| Permission | Requested when the user enables step tracking |
| Persist readings | Native buffer, then `local_step_readings` |
| Reboot reset | Boot count per reading |
| Midnight | Service flush at midnight; proportional split with uncertainty otherwise |
| Missing intervals | Recorded as gaps; shown on the day |
| Timezone change | Forced reading; per-reading offset |
| App restart | Foreground read on start; ingest of the buffer |
| Permission revoked | Collection stops; status shows "Permission needed"; history is kept |
| Manual correction | Stored separately as `manual_adjustment`, displayed as "Adjusted by you: +500" |
| Sync | `local_step_daily` → `step_logs`, one row per day. Raw readings never sync (§6.6) |
| Workout steps | Never added to the daily total (§5.7) |

### B6. Step dashboard

Today's steps, goal, percentage, remaining, weekly average, monthly trend, last successful collection time, sensor status (active, snapshots only, permission needed, unsupported, paused by system). A day with uncertain steps shows "≈" and an explanation on tap.

### B7. Honest limits (device)

| Limit | Statement in the app and docs |
|---|---|
| Some phones only count while a listener is registered | Continuous tracking is recommended; without it, steps taken while the app is closed may be undercounted on some phones |
| Battery managers may stop the service | Status shows when collection was interrupted and how to exempt the app |
| Steps between the last reading and a shutdown may be lost | A shutdown reading is attempted, but Android does not guarantee it |

No claim of uninterrupted counting is made until the device tests in 07-testing.md pass on your phone.

---

## Part C — Screen time (§5.17)

| Aspect | Design |
|---|---|
| Access | Usage Access is a special setting. A rationale sheet explains it, then opens the system page; the app re-checks on return |
| Source | `UsageStatsManager.queryEvents`, pairing activity-resumed and activity-paused events per package to compute foreground time for an exact local-day range |
| Why events | The system's pre-aggregated daily buckets do not line up with the user's local day |
| Retention | The system keeps events for only a few days, so a daily WorkManager job (and every visit to the screen) rolls completed days into `local_screen_time_daily` and `local_screen_time_apps` |
| Reports | Total per day, per app, most used, daily and weekly reports, monthly trends |
| Targets and alerts | Per-app and total daily targets. Optional alerts are checked by the periodic job (roughly every 15 minutes, so an alert can be late). The app does not block other apps |
| Privacy | Private database only. No package names in logs or sync |
| Honesty | The screen states that figures come from Android usage statistics and can differ from the Digital Wellbeing app; it does not claim to read Digital Wellbeing's data |

---

## Part D — Stopwatch and timers (§5.16)

State machine: `Ready → Running → Paused → Running → Completed`, with `Cancelled` reachable from Running and Paused.

| Aspect | Design |
|---|---|
| Persistence | Each transition is a row in `local_timer_events`. Elapsed time = accumulated seconds + (now − last resume). No ticking counter is stored |
| App restart | The session is rebuilt from its rows; a running timer continues with the correct elapsed time |
| Countdown completion | An exact one-shot notification is scheduled for the expected end, cancelled on pause, rescheduled on resume |
| Completed | Optionally creates an activity log with the duration (`source = timer`) |
| Cancelled | Creates no log and does not count as completed |
| Rest timer | The same engine, started from a gym set |
