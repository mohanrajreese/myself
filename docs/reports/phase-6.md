# Phase 6 report: Reports and synchronisation

**Date:** 18 November 2026. **State:** built and verified by automated tests. The cloud and push parts can't be verified until the owner's Supabase and Firebase projects exist: sync against a real project, Edge Function deployment, push delivery, and the device tests.

## 1. Features completed

| Task | Result |
|---|---|
| R-01 | Report queries for steps, weight, measurements, calories and macros, water, sleep, wellness, walks, runs, rides, gym sessions, new personal records, essential-activity completion, junk food and screen time. Values are per day; a day without records counts as missing, never as zero |
| R-02 | **Insights tab**: Day, Week, Month or Custom, with arrows to step between periods; each card is compared with the previous period. There is a report screen per domain (chart, this period beside the previous one, days without records named) and a custom range sheet with presets |
| R-03 | Up to five descriptive sentences, chosen by size of change. Small changes and measures missing from either period are left out. A test checks the wording has no causal or advice terms |
| R-04 | Private history behind the lock: private habit counts, bowel frequency and consistency, doses taken or skipped per medicine, private activity logs, each compared with the period before |
| R-05 | Sync engine as specified in 03 §6:<br>• Pushes parents before children; an outbox entry is removed only if its row is unchanged.<br>• Retries with backoff and stores an error code only; pauses on an authentication failure.<br>• Pulls by cursor with a 30-second overlap; a newer or still-queued local row wins.<br>• Deleted records travel as tombstones.<br>• Upserts step totals on `(user_id, log_date)` |
| R-06 | On a returning user's first sign-in on a phone, records are pulled before onboarding decides, so the user lands on Home. Everything queued since Phase 1 uploads on the first sync |
| R-07 | Sync runs when the app starts, when you return to it, when the network comes back, on Sync now, and hourly in the background when there is a network. **Account and sync** screen shows the status, what is backed up, and push preferences |
| R-08 | Push (FCM):<br>• Token registered with preferences, refreshed, and removed on sign-out and account deletion.<br>• Messages are data-only, and the phone shows fixed text by message type.<br>• Messages arrive in the foreground and the background; tapping one opens Account and sync.<br>• Firebase is configured from the env file (see §8) |
| R-09 | Migration 10: `device_notification_tokens` (with preferences) and `cloud_sync_metadata`, plus access-rule checks. Edge Functions `delete-account` and `send-push`, type-checked and tested in CI |
| R-10 | **Export**:<br>• JSON or CSV, everything or a date range (child rows follow their parent's date).<br>• Private data only after the PIN; photos optional.<br>• AES-256 passphrase on by default.<br>• Saved through Android's save picker; the app keeps no copy |
| R-11 | **Delete phone data** erases both databases, photos, scheduled notifications and the app lock, then signs you out. **Delete account** asks you to type DELETE and sign in with the same Google account, then removes the cloud account; you choose whether this phone keeps its records. Signing in as another account (C11) now also erases private data, which it previously missed |
| R-12 | This report. Device tests 16–18 and the cloud checks are pending (§9) |

Settings has a new **Your data** section: Account and sync, Export, and Delete data or account.

## 2. Verification

| Verified by automated tests | Verified on device | Implemented, device verification pending |
|---|---|---|
| Sync engine (15 tests: idempotence, backoff, rows changed while sending, authentication pause, local-wins, paging and cursors, tombstones, JSON and boolean types). Offline waiting, first-sign-in restore, problem state. Push token lifecycle, preferences, generic text, unknown and switched-off types. Full sync with private records sends nothing private. Report queries and insight rules. Insights, report and private-history screens. Export round-trip with passphrase, CSV quoting, ranges. Deletion of phone data and account. Accessibility on 6 new screens (light and dark) and 2× text. Migration 10 access rules on local PostgreSQL. Edge Function type-check and token-signing test | None yet | Sync against a real Supabase project; deployed Edge Functions; FCM delivery in the foreground and background; the hourly background job; the save picker; account deletion in the cloud |

## 3. Files created or modified

69 files since the Phase 6 designs. Most added lines are generated: the schema dump, migration test helpers and Pigeon output. Main areas: `lib/core/sync`, `lib/app/{sync_controller,push_controller,account_actions,insights_providers,export_providers}.dart`, `lib/features/{insights,data_export}`, `lib/features/settings/presentation/{account_sync_screen,data_screens}.dart`, `pigeons/export.dart` and `ExportPlugin.kt`, `supabase/migrations/20261118000800_devices_and_sync.sql`, `supabase/functions/`, `test/unit/{sync,insights,export}`, and `test/widget/{sync,insights,data}_test.dart`.

## 4. Database changes

| Store | Change |
|---|---|
| App database | v9: `local_sync_cursors` |
| Private database | Unchanged |
| Supabase | `20261118000800_devices_and_sync.sql`. Migration 9 (`hygiene_logs`) is not needed |

## 5. Android permissions added

None requested from the user. `firebase_messaging` merges `com.google.android.c2dm.permission.RECEIVE` and `WAKE_LOCK`. Saving an export uses the system document picker and needs no storage permission.

## 6. Packages installed

`firebase_core` 5.2, `firebase_messaging` 17.1 and `archive` 4.7 (writes AES-256 encrypted zips). Deno 2 is used for the Edge Functions in CI only.

## 7. Tests executed and results

| Suite | Count | Result |
|---|---|---|
| Unit | 357 | Pass |
| Widget, including accessibility | 268 | Pass |
| Architecture boundaries and manifest | 15 | Pass |
| Supabase access rules (local PostgreSQL) | all checks | Pass |
| Edge Functions (Deno check and test) | 1 test | Pass |
| `flutter analyze` | — | No issues |
| `flutter build apk --debug` | — | Builds |

The new tests found and fixed these defects:
- Sync was attempted while offline, before the first network reading arrived.
- Insight cards were not read as one label by screen readers.
- The account-deletion choices hid their touch feedback.
- Deleting phone data did not sign out, because the provider had lost its reference across the async erase.
- C11 left private data in place when another account signed in.
- The Delete screen reached into the auth feature's internals, breaking the architecture rules.

## 8. Decisions and deviations

| Item | Detail |
|---|---|
| Firebase configuration | Four client values in the untracked env file instead of a `google-services.json` and its Gradle plugin. These are client identifiers, not secrets; sending needs the server's service account. Push stays off without them. Recorded in `docs/architecture.md` |
| Token on sign-out | The token row is deleted rather than marked revoked, so another account can register the same phone later. `revoked_at` is set by `send-push` when FCM reports a dead token |
| When to send push | `send-push` sends whatever it is asked to. The server jobs that decide when (for example, a daily check for devices that haven't synced) are not built; they need the real project |

## 9. Known limitations

| Limit | Risk |
|---|---|
| Nothing has run against a real Supabase or Firebase project | R-27 |
| Background sync depends on WorkManager and can be delayed by battery management | R-02 |
| Last write wins per row; edits made on two phones to the same record keep only the later one | — |
| Large exports with many photos are built in memory | R-33 |

## 10. Remaining tasks

- **Owner setup:**
  - Supabase project: apply the migrations and deploy both functions (`docs/sync_and_push.md`).
  - Google OAuth clients.
  - Firebase project and service-account secret.
  - Install the debug APK.
- **Device tests** 16, 17, 18 and the Phase 6 rows in the status file's device backlog. These are Phase 6's exit criteria: no duplicates after reconnecting, a second install restores, push delivery.
- **Phase 7** (Quality and release) waits for approval.
