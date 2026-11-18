# Sync and push (as built)

Design: `blueprint/03-database.md` §6 (protocol), §5.5 (Edge Functions); `blueprint/05-notifications-alarms-steps.md` (FCM).

## Sync

| Part | Where | Behaviour |
|---|---|---|
| Engine | `lib/core/sync/sync_engine.dart` | Push queued rows in table order (parents first), 100 per request, upsert on `id` (`user_id,log_date` for step totals). An outbox entry is removed only if the row is unchanged since it was read. Failures back off `min(2^n × 5 s, 1 h)` ± 20 % and store an error code only; an authentication failure pauses. Pull pages of 500 by `(server_updated_at, id)` with a 30-second overlap; a pulled row is skipped when the local copy is newer or waiting to be pushed; pulls never queue rows |
| Remote | `lib/core/sync/supabase_sync_remote.dart` | PostgREST with the user's session; RLS limits every call |
| Triggers | `lib/app/sync_controller.dart` | App start, return to the app, network back, Sync now; hourly WorkManager job with a network (`background.dart`) |
| First sign-in | Same | If the phone has no profile for the account, everything is pulled before onboarding decides; a returning user lands on Home |
| Status | Settings → Account and sync | Up to date, waiting (with count), syncing, restoring, problem (code), signed out, not set up |

The engine cannot import the private database (architecture test), and a widget test runs a full sync with private records present and checks that nothing private reaches the remote.

## Push (FCM)

| Part | Behaviour |
|---|---|
| Configuration | `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_SENDER_ID` in `env/<flavour>.json` (not committed). No `google-services.json`. Without them push is off and the screen says so |
| Token | Registered after sign-in in `device_notification_tokens` with the user's preferences; refreshed on rotation; deleted on sign-out and account deletion |
| Messages | Data-only `{type, id}`. Types: `account_security`, `sync_problem`, `backup_status`. The phone shows fixed text for each type, only if that preference is on; unknown types are ignored. Tapping opens Account and sync |
| Server | `supabase/functions/send-push`: callers must present the service-role key; reads the user's live tokens and preferences, sends through FCM HTTP v1 with a service account (`FIREBASE_SERVICE_ACCOUNT` secret), marks dead tokens revoked |

Not yet built: the server-side jobs that decide when to send (for example a daily check of `cloud_sync_metadata` for devices that have not synced). They need the owner's project and are listed in the Phase 6 report.

## Owner setup

```bash
supabase db push
```

```bash
supabase functions deploy delete-account
```

```bash
supabase functions deploy send-push
```

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
```
