# Privacy audit (Phase 7, task Q-03)

**Date:** 18 November 2026. Covers what can be checked without a phone; the device steps below are for the owner.

## Checked in the build environment

| Check | Method | Result |
|---|---|---|
| Backups and device transfer | Release merged manifest | `allowBackup="false"`, `fullBackupContent="false"`, `dataExtractionRules` exclude everything |
| Cleartext traffic | Release merged manifest, network security config | `usesCleartextTraffic="false"`; `cleartextTrafficPermitted="false"` |
| Analytics | Release merged manifest, packages | No analytics or crash SDK; `firebase_analytics_collection_deactivated=true` |
| FCM telemetry and tokens | Release merged manifest | `firebase_messaging_auto_init_enabled=false` (no token before the app registers after sign-in), `delivery_metrics_exported_to_big_query_enabled=false`. Added in this audit; manifest test guards both |
| Secrets in the binary | `strings` on the release `libapp.so` | No service-role key, secret key, private key or JWT. The text `sb_secret_` is the Supabase library's key-prefix constant, not a key |
| Exported components | Release merged manifest | `MainActivity`, plus plugin components that Android requires to be exported (FCM receiver, WorkManager job service and diagnostics receiver, which is protected by `DUMP`, Google sign-in revocation service, profile installer). None of ours |
| Logging | Code review of `lib/` and the Kotlin sources | Logger writes event codes and error types only; release builds discard logs; no Kotlin logging |
| Sync traffic | Automated test with a recording remote | A full sync with private records present writes only synced tables and no private text |
| Push payload | Code review and tests | Server sends `{type, id}`; the phone shows fixed text by type |
| Private data in notifications | Automated tests | Generic title, secret visibility |
| Import boundaries | Architecture tests | Sync and network code cannot import the private database |

## Owner steps on the phone (device test script, Q-02)

1. **Traffic capture.** Install HTTP Toolkit or mitmproxy with its certificate as a user CA. The release build trusts only system CAs, so use a debug build for this step, or add a debug-only network config. Use the app for a day: log private habits, bowel, medication, screen time, then Sync now. Confirm requests go only to the Supabase project host, Google sign-in and FCM, and that no request body contains private text.
2. **Backup extraction.** `adb backup -f fb.ab com.mysticstack.fitbuddy` should produce an empty archive. On Android 12+ also check Settings → System → Backup shows nothing for FitBuddy.
3. **App switcher and screenshots.** With the app lock on, open the private space and press Recents; the preview is blank. A screenshot is refused.
4. **Lock screen.** Medication and private reminders show "FitBuddy reminder" only, and nothing while locked.
5. **Logs.** `adb logcat --pid=$(adb shell pidof com.mysticstack.fitbuddy)` while using private screens: no record values, names or notes.
