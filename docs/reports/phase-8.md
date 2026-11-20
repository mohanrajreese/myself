# Phase 8 report — Money (PRD §5.21)

Date: 20 Nov 2026. Branch `dev/bold-galileo-ssmrkj`. Designs approved 20 Nov 2026 (two late boards, recurring expenses and categories, approved the same day).

## 1. Features completed

| Task | What |
|---|---|
| M-01 | App database v10: finance categories, debts, debt payments, recurring expenses, expenses, budgets, local receipt index |
| M-02 | Supabase migration 11 with owner-only access rules, owner-scoped foreign keys, EMI all-or-none, first reminder ≥ 7 days |
| M-03 | `DriftMoneyRepository`: seeded categories with fixed ids, outbox in every write, rupee amounts in paise |
| M-04 | Expenses: add/edit sheet, list with search and filters, encrypted receipt photo, meal link; categories add/archive/restore |
| M-05 | Budgets: overall and per category, effective-dated (a zero row ends a budget from a month on) |
| M-06 | Debts: I owe / owed to me, four kinds, payments ledger, outstanding, settle, delete |
| M-07 | EMI loans and reminders (7/10/14/30 days, 1 day, due day, 09:00; Paid/Snooze/Skip); recurring expenses with reminders and one-tap Paid |
| M-08 | Meal Cost and Paid with; deleting a meal asks about its expense |
| M-09 | Analysis for a month or custom range; descriptive facts only |
| M-10 | Money tab in place of Insights; Insights row in Settings; export and erase include Money |
| M-11 | Tests, accessibility sweep, docs, this report |

## 2. Verification

| Verified by automated tests | Verified on device | Implemented, device verification pending |
|---|---|---|
| Schema v10 migration from every earlier version with foreign-key checks; access rules for all six tables (local Postgres) | — | Supabase migration 11 on the owner's project |
| Repository: paise, validation, outbox, budgets, past instalments, payments with expenses, archive guard | — | — |
| EMI and recurring reminder plan, Paid/Skip/Snooze, no amount in notification text | — | Delivery at 09:00, buttons from the lock screen (tests 10–14 pattern) |
| Meal cost link and delete prompt; Money screens: add/edit/delete expense, budget, home loan with 38 past EMIs and Mark paid, analysis, recurring, categories | — | Receipt camera and gallery; stored receipt is not a readable image |
| Accessibility: 8 Money screens and Insights in light and dark, 2× text at 320 dp | — | TalkBack pass |
| Debug APK builds | — | Install and run |

## 3. Files created or modified

81 files compared with the phase start (`02e07dd`): `lib/features/money` (domain, data, presentation), `lib/app` (providers, reminder source, meal cost, router, bootstrap, erase), `lib/core/database`, `lib/core/units/rupees.dart`, meal form and settings screen, ARB strings, `supabase/`, tests under `test/unit/money`, `test/unit/notifications`, `test/widget`. Formatting of four files from the 18 Nov rename was also corrected so CI's format check passes.

## 4. Database changes

- Drift: app database 9 → 10 (`drift_schemas/app/drift_schema_v10.json`).
- Supabase: `supabase/migrations/20261120000900_money.sql`; `combined_migrations.sql` regenerated.

## 5. Android permissions added

None.

## 6. Packages installed

None.

## 7. Tests executed and results

| Suite | Result |
|---|---|
| `flutter analyze` | No issues |
| `dart format --set-exit-if-changed` (CI rule, width 100) | 0 files changed |
| `flutter test` | 725 passed, 1 skipped, 0 failed |
| `supabase/tests/run_local.sh` | ALL CHECKS PASSED |
| `flutter build apk --debug` | Built |

## 8. Known limitations

- Notifications never show the amount (owner decision, 20 Nov 2026); the plugin cannot post a separate lock-screen version (R-24 side-channel barrier holds).
- Reminders beyond the seven-day window are planned by the top-up job; exact time depends on the phone's alarm permission (R-10, R-11).
- Six bottom tabs remain (R-15); Money replaced Insights rather than adding a seventh.
- Remaining by EMI is EMI × instalments left; the bank's figure, with interest, may differ (stated on screen).
- Phone and cloud checks cannot run here (R-27, R-28).

## 9. Remaining tasks

- Apply migration 11 to the Supabase project (with the other migrations) and run a sync of Money data.
- Device: add a loan due in 7 days and confirm the 09:00 reminder, Paid recording the instalment and expense, and no amount on the lock screen; add a recurring expense due tomorrow; attach a receipt photo; follow `docs/device_test_plan.md` tests 10–14 for buttons and snooze.
