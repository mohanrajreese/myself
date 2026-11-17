# Database (as built)

Design: [`blueprint/03-database.md`](blueprint/03-database.md). This file lists the schema versions and migrations that exist.

## Local (Drift)

Both files are encrypted with SQLite3MultipleCiphers using the SQLCipher scheme and a raw 256-bit key held in Android Keystore-backed storage. Each database has its own key.

| Database | File | Schema version | Tables |
|---|---|---|---|
| `AppDatabase` | `fitbuddy.sqlite` | 3 | v1: `profiles`, `user_goals`, `nutrition_goals`, `weight_logs`, `sync_outbox`, `local_app_settings`. v2 adds `body_measurements`, `water_logs`, `food_items`, `meal_logs`, `meal_food_items`, `saved_meals`, `sleep_logs`, `daily_health_checkins`. v3 adds local-only `local_food_catalogue` and `local_meal_photos` |
| `PrivateDatabase` | `fitbuddy_private.sqlite` | 1 | None yet (Phase 5) |

Schema dumps: `drift_schemas/app/`, `drift_schemas/private/`.

### Deviations from the blueprint

| Item | Blueprint | As built | Reason |
|---|---|---|---|
| Outbox allow-list | `CHECK` constraint on `sync_outbox.entity_table` | Two triggers, rebuilt from `syncedTableNames` on every open | SQLite cannot alter a `CHECK`; a trigger gives the same guarantee without rebuilding the table each time a synced table is added |
| Nutrition goal columns | Energy and protein required | All nullable | Calories and protein start unset (design canvas, Goals step) |
| File names | `fitbuddy.db` | `fitbuddy.sqlite` | Default naming of the database package |

## Supabase migrations

| File | Applied to project | Contents |
|---|---|---|
| `20261116000100_helpers.sql` | Not yet (needs the owner's project) | `set_server_updated_at()`, `reject_stale_write()` |
| `20261116000200_profiles_and_goals.sql` | Not yet | `profiles`, `user_goals`, `nutrition_goals` with RLS and triggers |
| `20261116000300_weight_logs.sql` | Not yet | `weight_logs` with RLS and triggers |
| `20261117000100_body_measurements.sql` | Not yet | `body_measurements` |
| `20261117000200_nutrition_and_water.sql` | Not yet | `water_logs`, `food_items`, `meal_logs`, `meal_food_items` (owner-scoped foreign keys), `saved_meals` |
| `20261117000300_sleep_and_wellness.sql` | Not yet | `sleep_logs`, `daily_health_checkins` |

Checked with `bash supabase/tests/run_local.sh`: applies every migration to a throwaway local PostgreSQL 16 with a small stand-in for Supabase's `auth` schema and roles, then runs `supabase/tests/rls_checks.sql` (84 checks: owner access, other-user and anonymous denial on all four operations, constraints, last-write-wins, account-deletion cascade). Not yet run against a real Supabase project.

### Deviation from the blueprint

| Item | Blueprint | As built | Reason |
|---|---|---|---|
| RLS tests | pgTAP through the Supabase CLI | Plain SQL assertions run with `psql` | Runs anywhere PostgreSQL is installed, including against a test project; no extension needed |
| `weight_logs` migration | Phase 2 | Phase 1 | Onboarding records the first weight |
| Table grants | Supabase defaults | `anon` revoked, `authenticated` granted explicitly | Does not depend on project default privileges |

## Food catalogue

`assets/catalogue/usda_sr_legacy.json` is built by `python3 -I tool/build_food_catalogue.py <SR Legacy CSV zip> <out.json>` from the USDA FoodData Central SR Legacy download (public domain, CC0 1.0). 7,793 foods, values per 100 g converted to integer base units. Imported into `local_food_catalogue` on first start and again only when the file's `version` changes. `assets/catalogue/indb.json` (980 Indian dishes) is built the same way from INDB.xlsx with `indb` as the first argument. Sources, terms and the exclusion rule: `assets/catalogue/SOURCES.md`.
