---
name: changing-fitbuddy-schema
description: Use when adding, altering or removing a table, column, index or constraint in FitBuddy's Drift databases or Supabase schema, or when a Drift migration test, schema dump check or RLS test fails.
---

# Changing the FitBuddy schema

A schema change touches up to six places. Missing one breaks sync, migrations or the privacy boundary.

## First decide the tier

| Data | Database | Synced |
|---|---|---|
| PRD §7.2 (profile, goals, weight, meals, water, step totals, workouts, ordinary activities, sleep, wellness, hygiene, ordinary reminders) | `AppDatabase`, plain name | Yes |
| Operational (step readings, timers, notification state, settings, routes, cursors) | `AppDatabase`, `local_` prefix | No |
| PRD §7.1 (private habits, bowel, medication, screen time, private activities, sensitive reminders, progress photos) | `PrivateDatabase` | Never |

Unsure which tier? Stop and ask. Default is never "synced".

## Checklist

| # | Step | Synced | Local | Private |
|---|---|---|---|---|
| 1 | Check the design in `docs/blueprint/03-database.md`; if it differs, update the doc in the same commit | ✔ | ✔ | ✔ |
| 2 | Drift table: integer base units, `CHECK` enums, foreign keys, indexes on `local_date` | ✔ | ✔ | ✔ |
| 3 | Bump that database's `schemaVersion`; add a step migration | ✔ | ✔ | ✔ |
| 4 | Export the schema dump to `drift_schemas/` and extend the migration test | ✔ | ✔ | ✔ |
| 5 | New SQL file in `supabase/migrations/` from the template in `03-database.md` §5.2 (RLS, four policies, triggers, composite FK for children) | ✔ | — | — |
| 6 | pgTAP test: other user blocked on all four operations | ✔ | — | — |
| 7 | Add the table to the outbox allow-list `CHECK` and to the sync table order (parents before children) | ✔ | — | — |
| 8 | DTO and mapper both ways; mapper round-trip test | ✔ | — | — |
| 9 | Confirm the table is **absent** from the outbox allow-list and from every remote source | — | ✔ | ✔ |

## Commands

```bash
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/app/
flutter test test/unit/database -r failures-only
supabase test db
```

## Never

- Edit an applied migration file.
- Use `REAL` or `double precision` for a quantity.
- Drop or rename a column without a data-preserving migration and a test that proves rows survive.
- Add a column for private data to Supabase.
