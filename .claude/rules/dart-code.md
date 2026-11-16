---
paths:
  - "lib/**/*.dart"
  - "test/**/*.dart"
---

# Dart code rules

- Feature layout: `lib/features/<feature>/{presentation,application,domain,data}`.
- `domain` imports Dart core and other `domain` only. No Flutter, Drift, Supabase or plugin imports.
- `presentation` calls `application` only. No Drift, Supabase or `MethodChannel` in widgets.
- One feature may import another feature's `domain`, nothing else from it.
- Repositories return `Result<T, Failure>`. Exceptions do not cross the data layer.
- Time comes from the injected `Clock`. `DateTime.now()` is allowed only in `lib/core/utils/clock.dart`.
- Calendar days are `LocalDate`; instants are UTC; logs store instant, local date and IANA timezone.
- Quantities are integers in base units (g, mm, ml, mg, kcal-milli, s, m). No `double` in stored or summed values. Units table: `docs/blueprint/03-database.md` §1.1.
- IDs are UUID v7 generated on the device.
- Log through `AppLogger` with event codes only. Never log record values or free text.
- User-visible strings go in ARB files.
- These rules are enforced by tests under `test/architecture/`. If one fails, fix the code, not the test.
