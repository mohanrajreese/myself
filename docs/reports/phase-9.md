# Phase 9 report — Money additions (PRD §5.22)

Date: 23 Nov 2026. Branch `dev/bold-galileo-ssmrkj`. Plan and designs approved 23 Nov 2026 (boards P9LoanDetail, P9Schedule, P9LoanChanges, P9CreditCard, P9Income, P9Split, P9Alerts).

## 1. Features completed

| Task | What |
|---|---|
| N-01 | App database v11 and Supabase migration 12: loan changes, instalment skips, card statements, income, expense splits; card, due-reminder, income-kind and card-link columns; local budget-alert log |
| N-02 | Overdue instalments: "! Overdue" label and banner, Skip (recorded, undoable), daily 09:00 reminder until Paid or Skipped |
| N-03 | Repayment schedule (reducing balance): interest, principal and balance per instalment; dates and EMIs only without a rate |
| N-04 | Part-payment (fewer EMIs or lower EMI, with preview), rate/EMI change from an instalment, balance correction; only later instalments change |
| N-05 | Credit cards: limit, statement and due days, statements, paid/left/minimum, spending since the statement, card on expenses, due reminders whose Paid pays what is left |
| N-06 | Personal-debt due reminders: on the day, plus 1 or 7 days before |
| N-07 | Budget alerts at a chosen first threshold (50–90%) and 100%, once per month; Money settings |
| N-08 | Income: sources, add/edit/delete, recurring income with Received; Income / Spent / Saved on the Money tab and in Analysis |
| N-09 | Bill splitting: equally or by amount; shares become Owed-to-me debts; edits update unpaid shares; deleting asks about the debts |
| N-10 | Screens per the approved boards; export, deletion and erase include the new tables |
| N-11 | Tests, docs, this report |

## 2. Verification

| Verified by automated tests | Verified on device | Implemented, device verification pending |
|---|---|---|
| Schema v11 migration from every earlier version; access rules, cascades and account deletion for the new tables (local Postgres) | — | Supabase migration 12 on the owner's project |
| Schedule engine: payoff, part-payments both ways, rate change, correction, skips, overdue | — | — |
| Reminders: overdue daily, Skip records a skip, card due and Paid, personal due dates, recurring income Received; no amounts in text | — | Delivery and buttons on the phone |
| Budget alerts once per threshold per month, settings | — | Notification appearance |
| Repository: part-payment with payment and expense, splits, income, statements | — | — |
| Widgets: overdue and skip, schedule, part-payment, credit card statement, income and saved, split, settings; accessibility for Money screens incl. income and settings | — | TalkBack |
| Debug APK builds | — | Install and run |

## 3. Files created or modified

48 files since the plan commit (`1600bad`): `lib/features/money` (loans engine, card/income/split domain, repository, nine presentation files), `lib/app` (providers, reminder source, budget alerts), `lib/core/database`, ARB strings, `supabase/`, tests under `test/unit/money`, `test/unit/notifications`, `test/widget`. Also `.mcp.json` (Supabase MCP server, owner's request).

## 4. Database changes

- Drift: app database 10 → 11 (`drift_schemas/app/drift_schema_v11.json`).
- Supabase: `supabase/migrations/20261123001000_money_additions.sql`; `combined_migrations.sql` regenerated.

## 5. Android permissions added

None.

## 6. Packages installed

None.

## 7. Tests executed and results

| Suite | Result |
|---|---|
| `flutter analyze` | No issues |
| `dart format --set-exit-if-changed` (CI rule) | 0 files changed |
| `flutter test` | 759 passed, 1 skipped, 0 failed |
| `supabase/tests/run_local.sh` | ALL CHECKS PASSED |
| `flutter build apk --debug` | Built |

## 8. Known limitations

- Loan figures are estimates (reducing balance, monthly rate = annual ÷ 12); the bank's statement may differ, and a correction re-anchors them.
- Budget alerts are checked while the app runs (any change to this month's spending); an expense recorded from a notification while the app is closed alerts the next time the app opens.
- Card "unused limit" is an estimate (limit − left on statement − spending since).
- No amounts in any notification (owner, 20 Nov 2026). Reminder delivery depends on exact-alarm permission (R-10, R-11).
- Phone and cloud checks cannot run here (R-27, R-28).

## 9. Remaining tasks

- Apply migrations 11 and 12 to the Supabase project.
- Device: a loan with a past-due EMI shows Overdue and reminds at 09:00 next day; Skip from the notification; a card statement due reminder and Paid; a personal debt due reminder; a budget crossing 80%; recurring salary Received; a split expense creates the debts.
