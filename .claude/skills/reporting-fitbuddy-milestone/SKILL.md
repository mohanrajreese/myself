---
name: reporting-fitbuddy-milestone
description: Use when all tasks of a FitBuddy phase are finished, when the owner asks for a phase or milestone completion report, or before asking for approval to start the next phase.
---

# Reporting a FitBuddy milestone

The report is evidence, not a summary. Gather each part from a command, then fill the template.

## Gather

```bash
flutter analyze | tail -n 3
flutter test -r failures-only | tail -n 5
git diff --stat <phase-start-commit>..HEAD | tail -n 1
git diff --name-status <phase-start-commit>..HEAD -- supabase/migrations drift_schemas
git diff <phase-start-commit>..HEAD -- android/app/src/main/AndroidManifest.xml | grep "uses-permission"
git diff <phase-start-commit>..HEAD -- pubspec.yaml | grep "^[+-] "
```

If analysis or any test fails, stop. Fix it before reporting; the next phase cannot start on failing tests.

## Write `docs/reports/phase-<n>.md`

Sections, in this order (PRD §13.5):

1. **Features completed** — task ID, one line each.
2. **Verification** — a table with three columns: verified by automated tests / verified on device / implemented, device verification pending.
3. **Files created or modified** — count and the main directories, not a full listing.
4. **Database changes** — Drift schema versions, Supabase migration files.
5. **Android permissions added.**
6. **Packages installed.**
7. **Tests executed and results** — suite, count, pass/fail, from the commands above.
8. **Known limitations** — platform limits met, with the risk ID from `08-risk-register.md`.
9. **Remaining tasks** — unfinished acceptance criteria and the device tests the owner must run (numbers from `07-testing.md` §6).

## Then

- Update the phase row and device backlog in `docs/implementation_status.md`.
- Commit and push.
- Tell the owner in at most ten lines: what works, what they must test on the phone, and that the next phase waits for their approval.
