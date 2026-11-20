# 03 — Database Design

Two local Drift databases and one Supabase PostgreSQL schema. The local database is the primary write source (§6.1).

| Store | File / location | Encrypted | Contents |
|---|---|---|---|
| `AppDatabase` | `fitbuddy.db` | Yes | Synced tables and local operational tables |
| `PrivateDatabase` | `fitbuddy_private.db` | Yes, separate key | Everything in §7.1 |
| Native step buffer | `step_buffer.db` (Android framework SQLite) | No | Raw sensor readings waiting to be ingested. Not sensitive; excluded from backup |
| Supabase | PostgreSQL, schema `public` | Server-managed | Mirror of the synced tables, per user |

Tables marked **†** are not named in the PRD and exist because a named requirement needs them (see README §3).

## 1. Conventions (§6.4)

| Topic | Rule |
|---|---|
| Primary keys | UUID v7 text locally, `uuid` in PostgreSQL, generated on the device |
| Instants | UTC. Drift stores ISO-8601 text; PostgreSQL uses `timestamptz` |
| Calendar days | `local_date` as `YYYY-MM-DD` (`date` in PostgreSQL), the user's local day when the event happened |
| Timezone | `tz` holds the IANA identifier in effect when the record was made |
| Audit columns | `created_at`, `updated_at` (set by the device), `deleted_at` (tombstone, null when live) |
| Server column | `server_updated_at timestamptz` set by trigger; used only as the pull cursor |
| Owner | Cloud tables have `user_id uuid not null default auth.uid()`. Local tables have no `user_id`; the device is bound to one account (stored in settings) |
| Numbers | Integers in base units. No `REAL`/`float` for quantities |
| Entered unit | Where the user picks a unit, `entry_unit` records it so values display as entered |
| Enumerations | Text with a `CHECK` constraint in both databases |
| Foreign keys | Declared and enforced in both databases (`PRAGMA foreign_keys = ON`) |
| Indexes | Every log table: `(local_date)` locally, `(user_id, local_date)` and `(user_id, server_updated_at, id)` in the cloud |
| JSON | Used only for documents that are read and written whole (schedule rules, checklist items, template contents). Each has a `v` field and a typed Dart model |

### 1.1 Base units

| Quantity | Column suffix | Unit | Example |
|---|---|---|---|
| Body weight, lifted load | `_g` | gram | 91.8 kg = `91800` |
| Height | `_mm` | millimetre | 172.5 cm = `1725` |
| Water | `_ml` | millilitre | `250` |
| Protein, carbohydrate, fat, fibre, serving weight | `_mg` | milligram | 12.5 g = `12500` |
| Energy | `_kcal_milli` | thousandth of a kilocalorie | 156.4 kcal = `156400` |
| Food quantity, body measurements, generic numeric values | `_milli` | thousandth of the stated unit | 1.5 servings = `1500` |
| Distance | `_m` | metre | 5.2 km = `5200` |
| Duration | `_s` | second | |
| Coordinates | `_e7` | degrees × 10⁷ | |

Conversions (kg/lb, cm/in, ml/fl oz, km/mi) live in `core/units` and are covered by round-trip tests.

## 2. Synced tables

Present in `AppDatabase` and in Supabase with the same columns, plus `user_id` and `server_updated_at` in the cloud. All have `id`, `created_at`, `updated_at`, `deleted_at` unless noted. "Log columns" means `occurred_at`, `local_date`, `tz`, `notes`.

### 2.1 User and configuration

| Table | Columns | Notes |
|---|---|---|
| `profiles` | `display_name`, `date_of_birth`, `height_mm`, `weight_unit` (kg/lb), `length_unit` (cm/in), `volume_unit` (ml/fl_oz), `distance_unit` (km/mi), `timezone`, `wake_time`, `workout_days` (ISO weekdays), `custom_measurement_types` (JSON), `onboarding_completed_at` | One row. Cloud PK is `id = auth.uid()`. Current weight is the latest `weight_logs` row, not a profile field |
| `user_goals` | `effective_from` (date), `target_weight_g`, `daily_steps`, `daily_water_ml`, `sleep_target_min`, `fitness_goals` (JSON list of text) | A goal change inserts a new row, so history is judged against the goal of its day (§5.1) |
| `nutrition_goals` | `effective_from`, `energy_kcal_milli`, `protein_mg`, `carbs_mg?`, `fat_mg?`, `fibre_mg?` | Same effective-dating |

### 2.2 Activities

| Table | Columns | Notes |
|---|---|---|
| `activity_definitions` | `name`, `description`, `category`, `icon_key`, `tracking_type` (boolean/count/numeric/duration/stopwatch/event_log/checklist), `priority` (essential/optional), `target_milli?`, `target_unit?`, `schedule` (JSON rule), `schedule_history` (JSON list of `{effective_from, rule}`), `stopwatch_enabled`, `show_on_dashboard`, `checklist_items` (JSON), `status` (active/archived), `sort_order`, `system_key?` | `system_key` marks seeded routines such as `hygiene.brushing_morning`. `schedule_history` keeps "missed" and "not scheduled" correct for past days after a reschedule (§5.14) |
| `activity_logs` | `activity_definition_id` → definitions, `status` (completed/skipped), log columns, `scheduled_slot?`, `count_value?`, `numeric_value_milli?`, `unit?`, `duration_s?`, `checklist_state?` (JSON), `source` (manual/notification/timer) | Several rows per day allowed. "Missed" is derived, never stored |
| `hygiene_logs` | *Not created (changed 18 Nov 2026).* Hygiene routines are seeded `activity_definitions` with `system_key` `hygiene.*` and checklist steps, so their records are ordinary `activity_logs` with `checklist_state`; bath and head wash are separate activities | §5.13 |

### 2.3 Body

| Table | Columns | Notes |
|---|---|---|
| `weight_logs` | `weight_g`, `entry_unit`, log columns | |
| `body_measurements` | `measurement_type` (waist/chest/hips/neck/arm/thigh/body_fat/`custom:<key>`), `value_milli`, `unit` (cm/percent), `entry_unit` (cm/in/percent), log columns | `value_milli` is thousandths of `unit`: 86.5 cm = `86500`, 21.5 % = `21500`. Photos are local-only |

### 2.4 Nutrition and hydration

| Table | Columns | Notes |
|---|---|---|
| `food_items` | `name`, `brand?`, `category`, `serving_label`, `serving_qty_milli`, `serving_unit`, `serving_weight_mg?`, `energy_kcal_milli`, `protein_mg`, `carbs_mg`, `fat_mg`, `fibre_mg`, `junk_category?`, `is_saved`, `use_count`, `last_used_at?` | Editing a food never changes past meals |
| `meal_logs` | `meal_category` (early_morning/breakfast/mid_morning/lunch/evening_snack/dinner/late_night/other), log columns, `has_photo` | |
| `meal_food_items` | `meal_log_id` → meal_logs, `food_item_id?` → food_items (set null on delete), **snapshot:** `food_name`, `quantity_milli`, `unit`, `serving_weight_mg?`, `energy_kcal_milli`, `protein_mg`, `carbs_mg`, `fat_mg`, `fibre_mg`, `junk_category?`, `item_notes?`, `sort_order` | Snapshot values are the totals for the quantity eaten (§5.4). Junk food is a flag on the diary row, so its calories are counted once |
| `saved_meals` | `name`, `meal_category?`, `items` (JSON snapshot list), `use_count`, `last_used_at?` | |
| `water_logs` | `amount_ml`, `occurred_at`, `local_date`, `tz` | |

### 2.5 Fitness

| Table | Columns | Notes |
|---|---|---|
| `step_logs` | `log_date`, `steps`, `source` (phone_sensor/phone_sensor_adjusted/manual), `timezone`, `collected_at`, `updated_at` | Exactly §6.6. Cloud unique `(user_id, log_date)`. Daily totals only |
| `exercises` † | `name`, `category`, `muscle_group`, `equipment`, `instructions`, `is_custom`, `measurement_kind` (weight_reps/reps_only/duration/distance_duration), `system_key?`, `archived` | Seeded rows use deterministic IDs. `measurement_kind` decides which record rules apply |
| `workout_sessions` | `kind` (gym/walk/run/cycle), `name`, `started_at`, `ended_at?`, `duration_s`, `local_date`, `tz`, `distance_m?`, `steps?`, `entry_mode` (manual/gps), `has_route`, `template_id?`, `notes` | `steps` is informational and never added to daily totals (§5.7). Pace and speed are derived |
| `workout_exercises` | `session_id` → workout_sessions, `exercise_id` → exercises, `sort_order`, `notes` | |
| `exercise_sets` | `workout_exercise_id` → workout_exercises, `set_number`, `reps?`, `load_g?`, `entry_unit?`, `distance_m?`, `duration_s?`, `rest_s?`, `completed_at?` | |
| `workout_templates` | `name`, `exercises` (JSON: exercise IDs with planned sets), `last_used_at?` | |

### 2.6 Sleep and wellness

| Table | Columns | Notes |
|---|---|---|
| `sleep_logs` | `kind` (night/nap), `start_at`, `end_at`, `duration_s`, `quality?` (1–5), `notes`, `local_date`, `tz` | `local_date` is the wake-up date, so an overnight sleep belongs to one day (§5.9) |
| `daily_health_checkins` | `energy`, `mood`, `stress`, `wellness` (each 1–5), log columns | Several per day allowed |

### 2.7 Reminders and devices

| Table | Columns | Notes |
|---|---|---|
| `reminders` | `kind` (custom/activity/water/workout/sleep/posture), `title`, `description`, `activity_definition_id?`, `schedule` (JSON rule), `condition` (always/if_incomplete), `channel_key`, `sound_key?`, `vibrate`, `snooze_default_min`, `priority` (normal/alarm), `quiet_hours_behaviour` (defer/suppress/bypass), `exact`, `enabled`, `start_date?`, `end_date?` | Ordinary reminders only (§7.2) |
| `device_notification_tokens` | `fcm_token` (unique), `device_label`, `app_version`, `last_seen_at`, `revoked_at?` | Cloud-only in practice; the device keeps its own token in settings |
| `cloud_sync_metadata` | `device_id`, `last_push_at`, `last_pull_at`, `schema_version`, `app_version` | One row per device. Used for sync status and backup-status pushes |

### 2.8 Money (PRD §5.21)

| Table | Columns | Notes |
|---|---|---|
| `finance_categories` | `name`, `system_key?`, `icon_key`, `archived`, `sort_order` | Seeded defaults with fixed ids (like exercises, C10); own categories added |
| `expenses` | `amount_paise` (> 0), `category_id`, `method` (cash/upi/debit_card/credit_card/net_banking/other), `occurred_at`, `local_date`, `tz`, `note?`, `meal_log_id?`, `debt_payment_id?`, `has_receipt` | `meal_log_id` and `debt_payment_id` are owner-scoped composite foreign keys, set null on delete |
| `budgets` | `effective_from`, `category_id?` (null = overall), `amount_paise` | Effective-dated, like goals; the row in force on a month is the latest whose `effective_from` is on or before its first day |
| `debts` | `direction` (i_owe/owed_to_me), `counterparty`, `kind` (personal/bank_loan/credit_card/other), `principal_paise`, `interest_rate_bp?`, `start_date`, `due_date?`, `emi_paise?`, `emi_day?` (1–28), `emi_count?`, `first_emi_date?`, `status` (open/settled), `notes?` | EMI fields all set or all null (`CHECK`) |
| `debt_payments` | `debt_id`, `amount_paise`, `paid_at`, `local_date`, `tz`, `instalment_no?`, `note?` | Child of `debts`; outstanding = principal − sum of payments |

| `recurring_expenses` | `name`, `amount_paise`, `category_id`, `method`, `schedule` (JSON rule), `remind`, `active` | Rent and similar; Paid on its reminder records an expense with `recurring_expense_id` |

**Reminders (changed 20 Nov 2026, during the build):** EMI and recurring-expense reminders are not rows in `reminders`. They are derived on the phone from `debts` (next unpaid instalment; `remind`, `remind_days_before` 7–30, default 7) and `recurring_expenses` at each re-plan, and scheduled with the ordinary reminders. This avoids rebuilding `reminders` (SQLite cannot alter a `CHECK`) and its cloud table, and an instalment paid early cancels its remaining reminders automatically. Receipt photos: local-only `local_expense_receipts` (encrypted files, like `local_meal_photos`).

## 3. Local operational tables (`AppDatabase`, never synced)

| Table | Columns | Purpose |
|---|---|---|
| `sync_outbox` | `seq` (autoincrement), `entity_table` (CHECK allow-list), `entity_id`, `enqueued_at`, `attempts`, `next_attempt_at`, `last_error_code?`, unique `(entity_table, entity_id)` | §6.7. One entry per changed row; payload is read from the row when sent |
| `local_sync_cursors` | `table_name` (PK), `cursor_ts`, `cursor_id`, `last_pulled_at` | Pull position per table |
| `local_step_readings` | `id`, `cumulative_steps`, `boot_count`, `elapsed_realtime_ms`, `wall_time_utc`, `tz`, `utc_offset_s`, `source` (service/worker/foreground/shutdown/boot/time_change) | Raw readings (§5.6). Pruned after 60 days |
| `local_step_daily` | `local_date` (PK), `sensor_steps`, `manual_adjustment`, `uncertain_steps`, `gap_count`, `tz`, `last_collected_at`, `computed_at` | Daily total = `sensor_steps + manual_adjustment`. Source of `step_logs` |
| `local_timer_sessions` | `id`, `kind` (stopwatch/countdown/rest), `activity_definition_id?`, `workout_session_id?`, `target_duration_s?`, `state` (ready/running/paused/completed/cancelled), `accumulated_ms` (milliseconds, so pauses inside a second are not lost), `last_resumed_at?`, `started_at?`, `ended_at?`, `activity_log_id?`, `notification_id?` | §5.16 |
| `local_timer_events` † | `id`, `session_id`, `type` (start/pause/resume/finish/cancel), `at` | State transitions, so elapsed time is always recomputable |
| `local_notification_state` | `notification_id` (int PK), `reminder_store` (main/private), `reminder_id`, `occurrence_at`, `occurrence_local`, `channel_id`, `mode` (exact/inexact), `status` (scheduled/snoozed/completed/skipped/dismissed/cancelled/expired), `snooze_count`, `acted_at?` | Stable notification identifiers and history (§5.15G, §8). Holds no titles or text |
| `local_app_settings` | `key` (PK), `value_json`, `updated_at` | Dashboard layout, quiet hours, channel sound versions, bound account, lock settings, FCM token, snooze presets |
| `local_workout_route_points` † | `session_id`, `seq`, `lat_e7`, `lon_e7`, `accuracy_dm`, `recorded_at` | Optional GPS route |
| `local_meal_photos` † | `id`, `meal_log_id`, `file_name`, `taken_at` | Index of encrypted photo files |
| `local_recovery_logs` † | `id`, `local_date`, `is_rest_day`, `soreness?` (1–5), `recovery?` (1–5), `notes` | §5.19 |
| `local_food_catalogue` † | `id`, `name`, `category`, `serving_label`, `serving_weight_mg?`, `energy_kcal_milli`, `protein_mg`, `carbs_mg`, `fat_mg`, `fibre_mg`, `source`, `is_estimate`, plus a full-text index on `name` | Read-only reference foods (decision D3). Present only if a dataset is chosen |

## 4. Private tables (`PrivateDatabase`, never synced)

| Table | Columns | Purpose |
|---|---|---|
| `local_private_activity_definitions` | Same shape as `activity_definitions`, plus `kind` (activity/habit) | Private activities and private habit types. Seeded habit types: porn consumption, masturbation (§5.12) |
| `local_private_activity_logs` | Same shape as `activity_logs` | Logs for private activities |
| `local_private_habit_logs` | `id`, `definition_id`, `count`, `occurred_at`, `local_date`, `tz`, `note` | §5.12 |
| `local_bowel_logs` | `id`, `occurred_at`, `local_date`, `tz`, `count`, `consistency` (hard/normal/loose), `straining`, `pain?`, `bleeding?`, `notes` | §5.11 |
| `local_medications` † | `id`, `name`, `dosage_text`, `schedule` (JSON), `notes`, `active` | §5.18. Dosage is free text entered by the user; the app never interprets it |
| `local_medication_logs` | `id`, `medication_id`, `scheduled_for?`, `status` (taken/missed/skipped), `acted_at`, `notes` | |
| `local_sensitive_reminders` | Same shape as `reminders`, plus `owner_type` (bowel/medication/private_activity/custom), `owner_id?` | Text stays here; the scheduler only sees an opaque ID |
| `local_screen_time_daily` | `local_date` (PK), `total_ms`, `is_partial`, `computed_at` | §5.17 |
| `local_screen_time_apps` | `local_date`, `package_name`, `app_label`, `foreground_ms`, PK `(local_date, package_name)` | |
| `local_app_usage_targets` † | `package_name` (PK, or `*` for total), `daily_limit_min`, `alert_enabled` | Personal usage targets and alerts |
| `local_progress_photos` † | `id`, `taken_at`, `local_date`, `file_name`, `note` | Index of encrypted photo files |

## 5. Supabase schema and migrations

SQL-first (§13.2). One file per logical step in `supabase/migrations/`, applied with the Supabase CLI. Files are never edited after they have been applied; changes are new files.

### 5.1 Migration plan

| Order | File | Contents | Phase |
|---|---|---|---|
| 1 | `…_extensions_and_helpers.sql` | Trigger functions `set_server_updated_at()` and `reject_stale_write()`, helper to attach both to a table | 1 |
| 2 | `…_profiles_and_goals.sql` | `profiles`, `user_goals`, `nutrition_goals` | 1 |
| 2a | `…_weight_logs.sql` | `weight_logs` (moved from Phase 2: onboarding records the first weight) | 1 |
| 3 | `…_body.sql` | `body_measurements` | 2 |
| 4 | `…_nutrition.sql` | `food_items`, `meal_logs`, `meal_food_items`, `saved_meals`, `water_logs` | 2 |
| 5 | `…_sleep_wellness.sql` | `sleep_logs`, `daily_health_checkins` | 2 |
| 6 | `…_activities.sql` | `activity_definitions`, `activity_logs` | 3 |
| 7 | `…_reminders.sql` | `reminders` | 3 |
| 8 | `…_fitness.sql` | `step_logs`, `exercises`, `workout_sessions`, `workout_exercises`, `exercise_sets`, `workout_templates` | 4 |
| 9 | `…_hygiene.sql` | `hygiene_logs` | 5 |
| 10 | `…_devices_and_sync.sql` | `device_notification_tokens`, `cloud_sync_metadata` | 6 |
| 11 | `…_money.sql` | `finance_categories`, `debts`, `debt_payments`, `recurring_expenses`, `expenses`, `budgets` | 8 |

`supabase/seed.sql` holds only development fixtures for local testing. It never runs against the real project.

### 5.2 Table template

Every user-owned table follows this pattern. Shown for `weight_logs`.

```sql
create table public.weight_logs (
  id                uuid primary key,
  user_id           uuid not null default auth.uid()
                      references auth.users (id) on delete cascade,
  weight_g          integer not null check (weight_g between 1000 and 700000),
  entry_unit        text not null check (entry_unit in ('kg', 'lb')),
  occurred_at       timestamptz not null,
  local_date        date not null,
  tz                text not null,
  notes             text,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index weight_logs_user_date_idx   on public.weight_logs (user_id, local_date);
create index weight_logs_user_cursor_idx on public.weight_logs (user_id, server_updated_at, id);

alter table public.weight_logs enable row level security;

create policy weight_logs_select on public.weight_logs for select to authenticated
  using ((select auth.uid()) = user_id);
create policy weight_logs_insert on public.weight_logs for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy weight_logs_update on public.weight_logs for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy weight_logs_delete on public.weight_logs for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger weight_logs_stale  before update on public.weight_logs
  for each row execute function public.reject_stale_write();
create trigger weight_logs_cursor before insert or update on public.weight_logs
  for each row execute function public.set_server_updated_at();
```

### 5.3 Shared functions

```sql
-- Pull cursor: always the server's clock, never the device's.
create function public.set_server_updated_at() returns trigger
language plpgsql as $$
begin
  new.server_updated_at := now();
  return new;
end $$;

-- Last write wins: an update older than the stored row is ignored.
create function public.reject_stale_write() returns trigger
language plpgsql as $$
begin
  if new.updated_at < old.updated_at then
    return null;
  end if;
  return new;
end $$;
```

### 5.4 Rules applied to every table

| Rule | Detail |
|---|---|
| Row Level Security | Enabled on every table. Four policies each (select, insert, update, delete), `to authenticated`, ownership test `(select auth.uid()) = user_id` (§6.5). No policy for `anon` |
| Child rows | Child tables carry `user_id` and reference the parent with a composite foreign key `(parent_id, user_id) → parent (id, user_id)`. A child can never point at another user's parent, even if an ID is guessed |
| Cascades | `auth.users` deletion cascades to every table, which is what account deletion relies on |
| `step_logs` | `unique (user_id, log_date)`; pushes upsert on that key |
| `profiles` | Primary key `id` references `auth.users (id)`; policies test `id` |
| Checks | Range checks on ratings (1–5), non-negative quantities, enumeration values |
| Service-role key | Used only inside Edge Functions. Never in the app (§6.5) |

### 5.5 Edge Functions

| Function | Caller | Does |
|---|---|---|
| `delete-account` | The signed-in user | Verifies the JWT, deletes the auth user with the service role; cascades remove all rows and tokens |
| `send-push` | Server-side only (database webhook or scheduled job) | Sends a data-only FCM message (type code, no health data) to the user's tokens; marks unregistered tokens as revoked (§5.15I) |

## 6. Sync protocol (§6.7)

### 6.1 Push

1. Repository transaction: write the row, set `updated_at`, upsert the outbox entry for `(table, id)` and reset its backoff.
2. Engine takes due outbox entries in `seq` order, parents before children (table order is fixed: definitions before logs, sessions before exercises before sets).
3. For each entry, read the current row and send `upsert` on `id` (on `(user_id, log_date)` for `step_logs`). Batches of up to 100 rows per table.
4. Success: delete the outbox entry **only if** the row's `updated_at` still equals the value that was sent. If the row changed meanwhile, the entry stays.
5. Failure: `attempts += 1`, `next_attempt_at = now + min(2^attempts × 5 s, 1 h) ± 20 % jitter`, store an error code (never the payload). Authentication failures pause the engine until the session is refreshed.

### 6.2 Pull

1. Per table: `server_updated_at > cursor` ordered by `(server_updated_at, id)`, pages of 500, overlapping the last 30 seconds to cover late-committing transactions.
2. Apply each row locally unless the local row has a newer `updated_at` or a pending outbox entry (the local change wins and will be pushed).
3. Applying a pulled row does not create an outbox entry.
4. Save the cursor after each page.

### 6.3 Properties

| Property | How |
|---|---|
| Idempotent | Device-generated IDs and upserts; a repeated push changes nothing |
| No lost records | A row leaves the outbox only on confirmed success; local data is never deleted because a request failed (§9) |
| Conflict resolution | Per-row last write wins on `updated_at`, enforced on the server |
| Tombstones | Deletes are `deleted_at` updates. Locally, tombstones that are synced and older than 90 days are purged |
| User scoping | The device is bound to one account. Signing in as a different account offers an export, then erases both local databases before binding (call C11) |
| First sign-in | Sign-in precedes onboarding, so the device is empty: a full pull runs first. A completed profile means a returning user and onboarding is skipped |
| Privacy | The engine has no reference to `PrivateDatabase` (01-architecture.md §5.1) |

## 7. Drift migrations

| Practice | Detail |
|---|---|
| Versioning | Each database has its own `schemaVersion`. Every change adds a step-by-step migration |
| Schema dumps | After each schema change, the schema is exported to `drift_schemas/` and committed |
| Migration tests | Generated tests open every historical version, migrate to current, and verify the result matches a fresh database, with data-preservation checks for populated tables (§10) |
| Safety | Migrations run inside a transaction with foreign keys checked afterwards. A failed migration leaves the old database intact and shows an error screen with an export option |
| Performance | Write-ahead logging, a busy timeout, and one shared database isolate for all Dart contexts |

## 8. Data lifecycle

| Data | Retention |
|---|---|
| Raw step readings | 60 days, then pruned; daily totals are permanent |
| Native step buffer | Emptied on each ingest |
| Notification state | 90 days of history |
| Per-app screen time | Kept until the user clears it (system events are only available for a few days, so this is the only long-term copy) |
| Synced tombstones | Purged locally 90 days after confirmed sync |
| Everything else | Kept until the user deletes it |
