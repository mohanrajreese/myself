# 02 — Dependencies and Native Integrations

Versions are **not** pinned here (§2.1). The "Seen" column is the newest release on pub.dev on 16 November 2026, shown only as evidence that the package is alive. Exact versions are chosen when `pubspec.yaml` is created and are locked by `pubspec.lock`.

## 1. Runtime packages

| Purpose | Package | Seen | Notes |
|---|---|---|---|
| State management | `flutter_riverpod`, `riverpod_annotation` | 3.5.0 / 4.0.8 | §2.1 |
| Navigation | `go_router` | 18.1.4 | §2.1 |
| Local database | `drift`, `drift_flutter` | 2.35.4 / 0.3.1 | §2.1 |
| SQLite with encryption | `sqlite3` with hook option `source: sqlite3mc` | 3.9.1 | Replaces the end-of-life `sqlcipher_flutter_libs` |
| Secure storage | `flutter_secure_storage` | 11.2.0 | Database keys, PIN hash, Supabase session |
| Backend | `supabase_flutter` | 2.18.3 | Auth, PostgREST, Edge Function calls |
| Sign in with Google | `google_sign_in` | 7.2.0 | Native account chooser through Credential Manager; returns the ID token given to Supabase |
| Push | `firebase_core`, `firebase_messaging` | 5.1.0 / 17.0.1 | No Analytics, no Crashlytics |
| Local notifications | `flutter_local_notifications` | 23.0.2 | Channels, scheduling, actions, boot reschedule |
| Timezones | `timezone` | 0.11.2 | Calendar-rule scheduling, DST. The device's timezone ID comes from a small Kotlin call (see rejected packages) |
| Background work | `workmanager` | 0.10.10 | Sync, reminder top-up, roll-ups |
| Charts | `fl_chart` | 1.3.1 | §2.1 |
| Connectivity | `connectivity_plus` | 7.3.2 | §2.1 |
| Runtime permissions | `permission_handler` | 13.0.2 | Notifications, activity recognition, location |
| Biometric unlock | `local_auth` | 3.0.2 | App lock |
| GPS | `geolocator` | 14.1.2 | Optional workout routes |
| Photos | `image_picker` | 1.2.4 | System camera and photo picker, no storage permission |
| Files and sharing | `path_provider`, `share_plus`, `file_picker` | 2.1.6 / 13.3.1 / 13.3.3 | Export, import of a custom sound |
| Export formats | `archive`, `csv` | 4.7.1 / 8.0.0 | Secure export (§7.3) |
| Cryptography | `cryptography` | 2.9.0 | File encryption, PIN hashing, export passphrase |
| IDs, dates, helpers | `uuid`, `intl`, `clock`, `collection`, `meta`, `path` | — | |
| Immutable models | `freezed_annotation`, `json_annotation` | 3.1.0 | Entities, DTOs, schedule rules |
| App info | `package_info_plus` | 10.2.2 | Version shown in Settings, sent with FCM token |
| Localisation | `flutter_localizations` (SDK) | — | ARB strings |

## 2. Development packages

| Purpose | Package | Seen |
|---|---|---|
| Code generation | `build_runner`, `drift_dev`, `riverpod_generator`, `freezed`, `json_serializable` | 2.17.1 / 2.35.3 / 4.0.10 / 4.0.3 / 6.15.2 |
| Typed platform channels | `pigeon` | 30.0.2 |
| Lints | `flutter_lints` | 6.0.0 |
| Tests | `flutter_test`, `integration_test` (SDK), `mocktail`, `fake_async` | — / — / 1.0.5 / 1.3.3 |

## 3. Packages considered and rejected

| Package | Reason |
|---|---|
| `sqlcipher_flutter_libs`, `sqlite3_flutter_libs` | End-of-life; superseded by the `sqlite3` build hook |
| `flutter_timezone` | Still applies Kotlin Gradle Plugin 1.7.10; fails to build with AGP 9 (found in the F-02 smoke build) |
| `android_alarm_manager_plus` | The notification plugin already schedules through `AlarmManager`; a second scheduler would create two sources of truth |
| `flutter_foreground_task`, step-counter plugins | The PRD assigns step collection to Kotlin (§5.6) and the service must run without a Flutter engine |
| `usage_stats` plugin | The PRD assigns screen time to Kotlin (§5.17); a small first-party plugin gives control over event-based aggregation |
| `rrule` | The PRD's recurrence types are a small closed set; a first-party calculator is easier to test for DST and quiet hours |
| `google_fonts` | Fetches fonts at runtime; fonts are bundled so the app is fully offline |
| `firebase_analytics`, `firebase_crashlytics`, any analytics SDK | §5.12 and §7.3 forbid sensitive data in analytics and crash logs; simplest guarantee is to ship none |
| Map packages (`google_maps_flutter`, `flutter_map`) | The PRD asks for an optional GPS route, not a map; a drawn route line needs no provider or API key |
| Hosted sync SDKs | Adds a vendor the PRD does not name |
| `shared_preferences` (direct use) | Settings live in `local_app_settings` so they are encrypted and migrate with the database |

## 4. Native Android integrations (Kotlin)

All channels are declared with Pigeon so both sides are type-checked.

| Plugin | Android APIs | Dart-facing operations |
|---|---|---|
| `StepCounterPlugin` | `SensorManager`, `Sensor.TYPE_STEP_COUNTER`, `Settings.Global.BOOT_COUNT`, foreground service (`health`), WorkManager, framework SQLite for the buffer | sensor status, read once, start/stop continuous collection, drain buffer, acknowledge buffer, collection state stream |
| `ScreenTimePlugin` | `UsageStatsManager.queryEvents`, `AppOpsManager` (access check), `PackageManager` (labels, icons) | has access, open access settings, usage for a time range (per package) |
| `AlarmPlugin` | `AlarmManager.canScheduleExactAlarms`, settings intents, `NotificationManager.canUseFullScreenIntent`, `PowerManager.isIgnoringBatteryOptimizations` | capability checks, open the matching settings page, system-event stream (boot, timezone, time, permission change) |
| `SoundPlugin` | `RingtoneManager`, `MediaPlayer`/`Ringtone`, `Vibrator`, `FileProvider` | list system sounds, open the system sound picker, register a custom sound file, test sound, test vibration |
| `SecurityPlugin` | `WindowManager.LayoutParams.FLAG_SECURE` | set secure window on/off |
| `WorkoutLocationService` | Foreground service (`location`) hosting the location stream | started and stopped through `geolocator`'s foreground configuration where sufficient; own service only if device testing shows it is needed |

Native dependencies (Gradle): `androidx.work:work-runtime-ktx`, `androidx.core:core-ktx`, `com.android.tools:desugar_jdk_libs`, the Firebase BoM brought in by the Flutter plugins, and `junit` plus `robolectric` for JVM tests.

## 5. External services

| Service | Use | Supplied by |
|---|---|---|
| Supabase project | Auth with the Google provider, PostgreSQL, Edge Functions (`delete-account`, `send-push`) | You (URL, publishable key). Service-role key and FCM service account are stored as function secrets, never in the app |
| Google Cloud OAuth | Web client (ID and secret configured in Supabase) and Android client (package name plus signing-key SHA-1) | You. Client IDs are not secrets; the Web client secret lives only in Supabase |
| Firebase project | Cloud Messaging only | You (`google-services.json`, git-ignored with an example file) |
| Supabase CLI | Applying SQL migrations, running pgTAP tests, deploying functions | Installed in the dev environment at Phase 1 |

## 6. Bundled assets

| Asset | Source | Licence check |
|---|---|---|
| Fonts: Inter (text, numerals), Plus Jakarta Sans (headings) | Bundled files | SIL Open Font Licence; licence files shipped in `assets/fonts/` |
| Icons | Material Symbols plus a small custom set in `assets/icons/` | Apache 2.0 / first-party |
| Exercise seed list | First-party JSON in `assets/seed/` | First-party |
| Food catalogue | Dataset chosen under decision D3 (09-food-dataset-options.md), converted at build time | Per dataset; attribution shown in About |
| Reminder sounds | System sounds by default; any bundled sound must be first-party or CC0 | Verified before adding |
