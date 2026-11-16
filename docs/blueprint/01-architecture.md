# 01 — Architecture

## 1. Intent

FitBuddy is a single-user Android app for daily health, fitness, nutrition, routine and digital-wellbeing tracking (§1.1). The architecture serves four properties the PRD ranks above everything else:

1. **Logging is instant and never lost.** Every write lands in the local database first (§6.1, §9).
2. **Sensitive records cannot leave the phone.** This is enforced by structure, not by discipline (§7).
3. **Reminders and steps behave honestly.** They work offline, recover from reboot, and report uncertainty instead of hiding it (§5.6, §5.15).
4. **Features are replaceable and testable.** UI never touches storage or platform APIs directly (§2.2).

**Goals:** §1.2. **Non-goals:** §1.3 (no social, medical, multi-user, wearable or commercial features).
**Anti-goals:** a private record appearing in any network request, log, push payload or notification preview; a step total that is silently invented; a button that does nothing; a habit screen that makes a missed day feel like failure.

## 2. Toolchain and project configuration

Versions are resolved when implementation starts (§2.1). Constraints that are already known:

| Area | Setting | Reason |
|---|---|---|
| Flutter channel | stable, version recorded in `README.md` and pinned in CI | Reproducible builds |
| Dart | sound null safety, `strict-casts`, `strict-inference`, `strict-raw-types` | Catch type errors at analysis time |
| Lints | `flutter_lints` plus project rules in `analysis_options.yaml` | Consistent code |
| Application ID / namespace | `com.mysticstack.fitbuddy` | From the PRD's Kotlin path (§2.3) |
| `compileSdk` | 37 | Required by the notification plugin |
| `targetSdk` | 37 | Current platform behaviour is what gets tested |
| `minSdk` | 29 (Android 10), pending decision D1 | `ACTIVITY_RECOGNITION` became a runtime permission in API 29; one code path for permissions |
| Build system | Gradle Kotlin DSL, AGP 9.1.1 or newer, built-in Kotlin, JDK 17+ | Required by current plugins |
| Java/Kotlin target | 17, core-library desugaring enabled | Required by the notification plugin |
| Main activity | `FlutterFragmentActivity` | Required by biometric prompt |
| Build flavours | `dev` and `prod`, configured through `--dart-define-from-file=env/<flavour>.json` (git-ignored) | No keys in source (§13.2) |
| SQLite build | `hooks.user_defines.sqlite3.source: sqlite3mc` in `pubspec.yaml` | Encrypted database (§2.1) |
| Backups | `android:allowBackup="false"`, `dataExtractionRules` excluding all app data from cloud backup and device transfer | §7.3 |
| Firebase | `firebase_messaging` only. Analytics collection deactivated in the manifest. No Crashlytics, no Analytics SDK | §5.12, §7.3 |
| Orientation | Portrait | Phone-first personal app |

### 2.1 Manifest permissions

Each permission is requested in context, when the user turns on the feature that needs it (§4.1 Screen 5). Nothing is requested at first launch.

| Permission | Kind | Requested when | Feature |
|---|---|---|---|
| `INTERNET` | normal | — | Supabase, FCM |
| `POST_NOTIFICATIONS` | runtime (API 33+) | First reminder is created, or step tracking is enabled | §5.15 |
| `SCHEDULE_EXACT_ALARM` | special access (off by default on Android 14+) | User marks a reminder as an exact alarm | §5.15G |
| `USE_FULL_SCREEN_INTENT` | special access on Android 14+ | User enables the lock-screen alarm display | §5.15B |
| `RECEIVE_BOOT_COMPLETED` | normal | — | Alarm and step recovery |
| `VIBRATE` | normal | — | §5.15F |
| `ACTIVITY_RECOGNITION` | runtime | User enables step tracking | §5.6 |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_HEALTH` | normal | — | Continuous step collection |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | runtime, while-in-use only | User starts a GPS workout | §5.7 |
| `FOREGROUND_SERVICE_LOCATION` | normal | — | GPS workout with screen off |
| `PACKAGE_USAGE_STATS` | special access | User opens Digital Wellbeing | §5.17 |
| `USE_BIOMETRIC` | normal | User enables biometric unlock | App lock |

Deliberately **not** declared: `USE_EXACT_ALARM` (reserved for alarm-clock apps), `ACCESS_BACKGROUND_LOCATION`, `CAMERA` and media-read permissions (the system camera and photo picker need none), `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (the app links to the system settings page instead), `SYSTEM_ALERT_WINDOW`.

### 2.2 Broadcast receivers and services (Kotlin)

| Component | Trigger | Action |
|---|---|---|
| `SystemEventReceiver` | `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `TIMEZONE_CHANGED`, `TIME_SET`, exact-alarm permission state change | Records a step reading, restarts step collection if enabled, enqueues the reminder re-plan worker |
| `StepCollectionService` | Started by the user enabling continuous tracking, and by boot | Foreground service of type `health` |
| `StepSnapshotWorker` | Periodic WorkManager job | One sensor reading when the service is not running |
| `WorkoutLocationService` | User starts a GPS workout | Foreground service of type `location` |
| Plugin receivers | Notification plugin's boot and action receivers, FCM service | Per plugin documentation |

## 3. Layering

Feature-first clean architecture (§2.2). Four layers inside every feature:

```text
presentation  ->  application  ->  domain  <-  data
(screens,         (Riverpod        (entities,    (Drift DAOs, Supabase
 widgets,          notifiers,       repository    sources, platform
 forms)            use cases)       interfaces,   channels, DTOs,
                                    rules)        mappers)
```

### 3.1 Dependency rules

| Rule | Enforcement |
|---|---|
| `domain` imports only Dart core and other `domain` code. No Flutter, Drift, Supabase or plugin imports | Import-boundary test |
| `presentation` talks to `application` only. No Drift, Supabase or `MethodChannel` in widgets | Import-boundary test |
| `data` implements `domain` repository interfaces | Code review, tests against interfaces |
| A feature imports another feature only through that feature's `domain` | Import-boundary test |
| `core/sync` and every Supabase source may not import the private database | Import-boundary test (privacy-critical) |
| Platform calls go through typed channel interfaces in `core/platform` | Pigeon-generated APIs |

The import-boundary test is a plain Dart test that parses `import` lines under `lib/` and fails on a violation. It needs no extra lint tooling.

### 3.2 Conventions

| Concern | Convention |
|---|---|
| State | Riverpod with code generation. `AsyncNotifier` for screen state, plain providers for repositories and use cases. Reads are Drift `watch` streams, so the UI updates when data changes |
| Errors | Repositories return `Result<T, Failure>`. `Failure` is a sealed class (`ValidationFailure`, `StorageFailure`, `PermissionFailure`, `PlatformFailure`, `NetworkFailure`, `AuthFailure`). Exceptions do not cross the data layer |
| Time | `Clock` is injected everywhere. `DateTime.now()` is banned outside `core/utils/clock.dart` (import-boundary test) so midnight, DST and timezone cases are testable |
| Dates | `LocalDate` value type for calendar days. Instants are UTC. Each log stores instant, local date and IANA timezone (§6.4) |
| Quantities | Integer base units (grams, millimetres, millilitres, milligrams, thousandths of a kilocalorie, seconds, metres). No floating point in stored or summed values (§6.4) |
| IDs | UUID v7 generated on the device, so creates are idempotent when synced |
| Navigation | GoRouter with `StatefulShellRoute.indexedStack` (six branches). Redirects handle onboarding and the app lock |
| Logging | One `AppLogger`. It accepts event codes and non-personal fields only. Free-text and record values are never logged (§7.3) |
| Text | All user-visible strings in ARB files (`flutter_localizations`), English only in v1 |

## 4. Folder structure

The PRD's suggested tree (§2.3) is kept. Additions are marked `+`.

```text
(repo root)
├── android/app/src/main/
│   ├── AndroidManifest.xml
│   ├── res/xml/data_extraction_rules.xml               +
│   └── kotlin/com/mysticstack/fitbuddy/
│       ├── MainActivity.kt
│       ├── StepCounterPlugin.kt
│       ├── ScreenTimePlugin.kt
│       ├── AlarmPlugin.kt
│       ├── SecurityPlugin.kt                           + FLAG_SECURE
│       ├── SoundPlugin.kt                              + system sounds, picker, test playback
│       ├── steps/  StepCollectionService.kt, StepSnapshotWorker.kt,
│       │           StepBufferStore.kt, BootSession.kt  +
│       ├── location/ WorkoutLocationService.kt         +
│       └── system/ SystemEventReceiver.kt              +
├── android/app/src/test/kotlin/...                     + JVM unit tests
├── assets/  icons/  illustrations/  fonts/  sounds/  seed/ (exercise list) +
├── env/  dev.example.json  prod.example.json           + (real files git-ignored)
├── pigeons/  step_counter.dart  screen_time.dart  alarm.dart  security.dart  sound.dart  +
├── lib/
│   ├── main.dart
│   ├── app/  app.dart  router.dart  theme.dart  app_config.dart  bootstrap.dart +
│   ├── core/
│   │   ├── database/      app_database.dart, private_database.dart, tables/, daos/,
│   │   │                  converters/, migrations/, schema dumps
│   │   ├── encryption/    key_store.dart, file_cipher.dart, pin_hasher.dart
│   │   ├── networking/    supabase_client_provider.dart, connectivity_service.dart
│   │   ├── sync/          outbox, sync_engine, pushers, pullers, conflict policy
│   │   ├── notifications/ scheduler, planner, channels, action handler, fcm, history
│   │   ├── permissions/   permission_service.dart, rationale models
│   │   ├── platform/      generated Pigeon APIs and their Dart wrappers
│   │   ├── security/      app_lock_controller.dart, lock_gate.dart            +
│   │   ├── scheduling/    schedule_rule.dart, occurrence_calculator.dart      +
│   │   ├── units/         quantity types, conversions, formatters             +
│   │   ├── errors/        failure.dart, result.dart
│   │   ├── utils/         clock.dart, local_date.dart, logger.dart
│   │   └── widgets/       design-system components (see 04-ui-ux-spec.md)
│   ├── features/
│   │   ├── onboarding/  profile/  dashboard/  weight/  body_measurements/
│   │   ├── nutrition/  food_database/  water/
│   │   ├── fitness/  (overview, steps, walking, running, cycling)
│   │   ├── workouts/ (gym sessions, exercise library, templates, records)
│   │   ├── sleep/  wellness/  bowel/  private_habits/  hygiene/
│   │   ├── activities/  reminders/  timers/  screen_time/
│   │   ├── medication/  recovery/  insights/  settings/
│   │   └── auth/                                                              +
│   │   each: presentation/  application/  domain/  data/
│   ├── l10n/                                                                  +
│   └── shared/  models/  widgets/  extensions/
├── supabase/  migrations/  functions/ (delete-account, send-push)  tests/ (pgTAP) +  seed.sql
├── test/  unit/  widget/  integration/  architecture/ (import-boundary tests) +
├── integration_test/                                                          +
├── drift_schemas/  (versioned schema dumps for migration tests)               +
└── docs/  PRD.md  architecture.md  database.md  permissions.md  notifications.md
           step_tracking.md  privacy.md  implementation_status.md  device_test_plan.md +
           blueprint/
```

## 5. Data boundaries

Three tiers. The tier of a table is fixed by which database file it lives in.

| Tier | Where | Contents | Leaves the device |
|---|---|---|---|
| **Synced** | `fitbuddy.db`, tables without the `local_` prefix | Profile, goals, weight, measurements, meals, foods, water, daily step totals, workouts, ordinary activities, sleep, wellness, hygiene, ordinary reminders (§7.2) | Yes, to the signed-in user's rows in Supabase |
| **Local operational** | `fitbuddy.db`, `local_` prefix | Raw step readings, timer sessions, notification state, app settings, sync bookkeeping, GPS route points, meal photo index, recovery logs | Never |
| **Private** | `fitbuddy_private.db` | Private habits, bowel records, private activities, sensitive reminders, medication, screen time and per-app usage, progress photo index (§7.1) | Never |

### 5.1 How "never" is enforced

Five independent barriers. A leak requires all of them to fail.

1. **Separate database class.** The sync engine receives only `AppDatabase`. `PrivateDatabase` is a different type in a different file, and the import-boundary test fails the build if anything under `core/sync`, `core/networking` or any `*_remote_source.dart` imports it.
2. **Outbox allow-list.** `sync_outbox.entity_table` has a `CHECK` constraint listing the synced tables. A row for any other table cannot be inserted.
3. **No outbox in the private database.** The table does not exist there.
4. **Server schema.** Supabase has no tables or columns for private data, so there is nowhere to put it.
5. **Tests.** A privacy test exercises every private feature against a recording HTTP client and asserts that no request was made and that no private table name or field appears in any outbox row, log line or push payload (see 07-testing.md §7).

### 5.2 Approaches considered: storage isolation

| Option | Trade-off | Verdict |
|---|---|---|
| One encrypted database, allow-list only | Simplest. But one coding mistake in a query or sync mapper can reach private rows | Rejected |
| **Two encrypted databases** | Private data is unreachable from sync code by construction. Costs: no SQL joins across the two; reports on private data are separate queries | **Chosen** |
| Plain main database, encrypted private database | Weight, meals and sleep would sit unencrypted. Encrypting both costs almost nothing | Rejected |

## 6. Security architecture

| Concern | Design |
|---|---|
| Database encryption | Both databases use SQLite3MultipleCiphers, each with its own random 256-bit key. A start-up assertion (`PRAGMA cipher`) proves the encrypted build is loaded |
| Key storage | `flutter_secure_storage` (Android Keystore-backed). Keys are not tied to biometric enrolment, so adding a fingerprint does not destroy data |
| App lock | PIN stored as a salted slow hash in secure storage. Optional biometric unlock (`local_auth`). Auto-lock on background after a configurable delay |
| Protected modules | Private habits, bowel records and private activities always sit behind the lock (§5.11, §5.12). Medication and screen time can be added to the lock in Settings |
| App-switcher and screenshots | `FLAG_SECURE` is set while a protected screen is visible, and for the whole app when the lock is enabled (§7.3) |
| Notifications from sensitive modules | Generic title ("FitBuddy reminder"), `VISIBILITY_SECRET`, no record text. The real title stays in the private database (§3.4 rule 14) |
| Private text fields | Keyboard suggestions and personalised learning disabled |
| Photos | Stored in app-private storage, encrypted per file |
| Session tokens | Supabase session kept in secure storage, not shared preferences |
| Secrets | Only the Supabase URL and publishable key are in the app. The service-role key and FCM credentials live in Supabase function secrets (§6.5) |
| Export | Zip of JSON and CSV. Optional passphrase encryption. Private data is included only after unlock and an explicit tick box (§7.3) |
| Deletion | Local: delete both database files and their keys. Cloud: `delete-account` function removes the auth user, cascading to every row |
| Transport | HTTPS only; cleartext traffic disabled in the network security config |

## 7. Synchronisation

Detailed protocol in 03-database.md §6. Summary:

1. A repository write is one Drift transaction: change the row, and upsert one outbox entry keyed by `(table, row id)`.
2. The sync engine runs when the app is open and connected, on connectivity regained, and from a periodic WorkManager job.
3. **Push:** send the row's current state as an upsert keyed by its UUID. Repeating a push is harmless.
4. **Pull:** for each table, fetch rows changed on the server since the saved cursor.
5. **Conflicts:** last write wins per row, by client `updated_at`, enforced on the server by a trigger that ignores older writes.
6. **Deletes:** soft delete (`deleted_at`). Tombstones sync like any other change.
7. **Failures:** exponential backoff with jitter. An entry stays in the outbox until the server confirms it (§9).
8. **Status:** pending count, last successful sync and last error are shown in Settings and as a small indicator on Home.

### 7.1 Approaches considered: sync

| Option | Trade-off | Verdict |
|---|---|---|
| **Outbox with per-row last-write-wins** | Small, fully testable, matches §6.7 item by item | **Chosen** |
| Hosted sync service (PowerSync, ElectricSQL) | Less code, but adds a vendor the PRD does not name | Rejected |
| CRDT merge | Solves concurrent multi-device edits, which a single-user app does not have | Rejected |

## 8. Background execution map

Four places run Dart or Kotlin without the UI. All database access from Dart goes through one shared Drift isolate, so there is a single writer.

| Context | Runs | Touches |
|---|---|---|
| UI isolate | Everything interactive | Both databases |
| WorkManager Dart task | Sync, reminder top-up, step ingest, screen-time roll-up | Both databases (never sync on the private one) |
| Notification action isolate | Complete, Snooze, Skip | Activity log, notification state |
| FCM background isolate | Data-only push handling | Settings, notification display |
| Kotlin service / worker / receiver | Step sensor readings | Native step buffer only (no Drift, no encryption keys) |
