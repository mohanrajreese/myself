# Notifications (as built)

Design: `blueprint/05-notifications-alarms-steps.md` Part A. States: ☑ automated tests · 📱 on device · ⏳ device verification pending.

## Pieces

| Piece | Where | State |
|---|---|---|
| Schedule rules and occurrence calculator (seven rule types, DST gap and overlap) | `lib/core/scheduling/` | ☑ |
| Planner: 7-day window, quiet hours (wait / skip / ring anyway), "only if not done", start and end dates, budget 400 with interval reminders shortened first | `lib/core/scheduling/reminder_planner.dart` | ☑ |
| Scheduler: diffs the plan with `local_notification_state`; stable ids; idempotent; timezone change moves to the same wall-clock time | `lib/core/notifications/reminder_scheduler.dart` | ☑ (logic) · ⏳ (Android delivery) |
| Re-plan triggers: reminder or activity change, app start and resume, quiet hours change, WorkManager top-up every 6 hours, return from settings | `lib/app/reminder_service.dart`, `background.dart`, `reminder_lifecycle.dart` | ☑ (calls) · ⏳ (background run) |
| Reboot and app update: the notification plugin's boot receiver restores pending notifications; `SystemEventReceiver` notes the event | Manifest, `SystemEventReceiver.kt` | ⏳ |
| Channels: Important alarms, Daily routines, Hydration, Fitness, Medication, Sleep, System (ids versioned `_v1`) | `lib/core/notifications/local_notification_gateway.dart` | ⏳ |
| Buttons: Complete, Snooze, Skip (three, Android's limit, C9); tapping opens the linked activity; swiping does nothing | Gateway, `background.dart` (app closed), `ReminderService.handle` | ☑ (logic) · ⏳ (from the shade) |
| Snooze presets 5/10/15/30 min and custom; default per reminder | Snooze sheet, reminder editor | ☑ |
| Exact alarms: capability check, rationale, settings page, inexact fallback | `AlarmPlugin.kt`, `routine_actions.dart` | ☑ (fallback logic) · ⏳ |
| Battery optimisation state and settings page; disabled-channel detection; test sound; test vibration | `AlarmPlugin.kt` | ⏳ |
| Notification history (30 days, no text stored) | Habits → Reminders → Notification history | ☑ |
| Timer "finished" notification (id 900) | Timer screen | ⏳ |

## Honest limits shown in the app

Do Not Disturb, silent mode, a channel switched off, battery saver and manufacturer battery managers can delay or silence reminders. Force-stopping the app cancels them until it is opened. Swiping a notification away is not reported by the plugin (R-11). Sound per channel is changed in Android's channel settings (a channel's sound is fixed once created, R-08); the app opens that page and plays a test.

## Not built in Phase 3

Custom sound files and an in-app system-sound picker (the channel settings page covers sound choice), the lock-screen full-screen alarm, and FCM (Phase 6).
