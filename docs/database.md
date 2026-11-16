# Database (as built)

Design: [`blueprint/03-database.md`](blueprint/03-database.md). This file lists the schema versions and migrations that exist.

## Local (Drift)

Both files are encrypted with SQLite3MultipleCiphers using the SQLCipher scheme and a raw 256-bit key held in Android Keystore-backed storage. Each database has its own key.

| Database | File | Schema version | Tables |
|---|---|---|---|
| `AppDatabase` | `fitbuddy.sqlite` | 1 | `profiles`, `user_goals`, `nutrition_goals`, `weight_logs`, `sync_outbox`, `local_app_settings` |
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
| — | — | None yet (task F-14) |
