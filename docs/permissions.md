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

Merged in by libraries, not requested from the user: `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SHORT_SERVICE`, `BIND_JOB_SERVICE` and `DUMP` (WorkManager), `USE_BIOMETRIC`/`USE_FINGERPRINT` (app lock library). Picking a sound file uses Android's document picker, so no storage permission is needed.

Never declared: `USE_EXACT_ALARM`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (the app only opens the battery-optimisation list), `USE_FULL_SCREEN_INTENT` (the lock-screen alarm display is not built). The manifest test enforces the allow-list.

## Debug signing key (for the Google Cloud Android OAuth client)

| | |
|---|---|
| Package | `com.mysticstack.fitbuddy` |
| Keystore | `android/app/debug.keystore` (alias `androiddebugkey`, standard debug passwords) |
| SHA-1 | `8D:7F:CD:51:E4:28:0F:61:6B:2B:53:C4:78:C7:83:5A:B1:72:DC:99` |
| SHA-256 | `D6:79:6B:53:CA:CF:FB:39:EE:16:47:DC:25:F9:3A:41:91:FE:DF:64:D5:F7:B1:4D:9C:1A:B2:DB:8D:7F:34:C1` |

This key signs debug builds only. The release key is created by the owner in Phase 7 and is never committed.
