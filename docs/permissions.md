# Permissions and platform setup (as built)

Plan: [`blueprint/01-architecture.md`](blueprint/01-architecture.md) §2.1. A permission is listed here when it is added to the manifest.

## Manifest permissions

| Permission | Added in | Requested when | Feature |
|---|---|---|---|
| `INTERNET` | Phase 1 | — (normal permission) | Google sign-in, Supabase |
| `POST_NOTIFICATIONS` | Phase 3 | When the first reminder is saved or switched on, after a rationale; Android 13+ only shows a prompt. Denied: settings page opens and Habits shows a notice | Reminders |
| `SCHEDULE_EXACT_ALARM` | Phase 3 | Special access, only for reminders marked "Important alarm", after a rationale; Settings → Notifications and reminders shows the state. Denied: scheduled inexactly with "may be late" wording | Important alarms |
| `RECEIVE_BOOT_COMPLETED` | Phase 3 | — (normal permission) | Reschedule after reboot |
| `VIBRATE` | Phase 3 | — (normal permission) | Reminder vibration, test vibration |
| `ACTIVITY_RECOGNITION` | Phase 4 | When the user turns step counting on, after an explanation. Refused: manual logging stays available | Steps |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_HEALTH` | Phase 4 | — (normal). Used only when the user turns on continuous counting | Steps |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | Phase 4 | At the start of a GPS workout, after an explanation; while in use only. Never for manual logging | GPS walks, runs, rides |
| `FOREGROUND_SERVICE_LOCATION` | Phase 4 | — (normal). Keeps a GPS workout going with the screen off | GPS workouts |
| `PACKAGE_USAGE_STATS` | Phase 5 | Special access, granted by the user on Android's usage-access page, opened from Screen time after an explanation. Refused: Screen time shows the explanation and the button again | Screen time |
| `com.google.android.c2dm.permission.RECEIVE`, `WAKE_LOCK` | Phase 6 (merged by `firebase_messaging`) | — (normal). Only used when push is configured | Push messages |
| `USE_BIOMETRIC` | Phase 5 | — (normal). Fingerprint is offered only after the user turns it on in App lock | App lock |

Merged in by libraries, not requested from the user: `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SHORT_SERVICE`, `BIND_JOB_SERVICE` and `DUMP` (WorkManager), `USE_BIOMETRIC`/`USE_FINGERPRINT` (app lock library). Picking a sound file and saving an export use Android's document pickers, so no storage permission is needed.

Never declared: `USE_EXACT_ALARM`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (the app only opens the battery-optimisation list), `USE_FULL_SCREEN_INTENT` (the lock-screen alarm display is not built). The manifest test enforces the allow-list.

## Debug signing key (for the Google Cloud Android OAuth client)

| | |
|---|---|
| Package | `com.mysticstack.fitbuddy` |
| Keystore | `android/app/debug.keystore` (alias `androiddebugkey`, standard debug passwords) |
| SHA-1 | `8D:7F:CD:51:E4:28:0F:61:6B:2B:53:C4:78:C7:83:5A:B1:72:DC:99` |
| SHA-256 | `D6:79:6B:53:CA:CF:FB:39:EE:16:47:DC:25:F9:3A:41:91:FE:DF:64:D5:F7:B1:4D:9C:1A:B2:DB:8D:7F:34:C1` |

This key signs debug builds only. The release key is created by the owner in Phase 7 and is never committed.
