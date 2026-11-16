---
paths:
  - "lib/core/database/**"
  - "supabase/migrations/**"
  - "supabase/tests/**"
  - "drift_schemas/**"
---

# Database rules

- Schema design is fixed in `docs/blueprint/03-database.md`. Follow its column names and units; use the `changing-fitbuddy-schema` skill for every change.
- Supabase migrations are SQL files, one logical step each, never edited after being applied. A change is a new file.
- Every cloud table: `user_id default auth.uid()`, RLS enabled, four policies with `(select auth.uid()) = user_id`, stale-write and cursor triggers, `unique (id, user_id)`. Child tables use the composite foreign key. Template: `03-database.md` §5.2.
- Every Drift schema change bumps `schemaVersion`, adds a step migration, exports a schema dump to `drift_schemas/`, and extends the migration test.
- Synced tables have `id`, `created_at`, `updated_at`, `deleted_at`. Deletes are tombstones.
- A repository write and its outbox entry are one transaction.
- Never use `REAL`/`double precision` for a quantity.
