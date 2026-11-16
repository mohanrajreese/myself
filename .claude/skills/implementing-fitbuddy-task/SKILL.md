---
name: implementing-fitbuddy-task
description: Use when starting, resuming or finishing any FitBuddy task ID (F-, C-, A-, S-, P-, R-, Q-) from the milestone checklist, or when asked to continue the current phase or build a FitBuddy feature.
---

# Implementing a FitBuddy task

One task at a time, smallest complete slice, tests first, status file updated.

## Steps

1. **Locate.** Read `docs/implementation_status.md`. Confirm the phase is approved and the previous phase has no failing tests. If not, stop and ask.
2. **Scope.** Read the task's row in `docs/blueprint/06-milestones-and-tasks.md`, then only the PRD section it cites (`grep -n "^## 5.9" docs/PRD.md`) and the blueprint section for that area. Nothing else.
3. **Mark** the task ◐ in the status file.
4. **List** the files to create per layer: `domain` (entity, repository interface, rules) → `data` (table/DAO, mapper, repository) → `application` (providers, use cases) → `presentation` (screen, widgets).
5. **Test first.** For each behaviour, write the failing test, run that file, see it fail for the right reason, then write the code. Required cases: `docs/blueprint/07-testing.md` §2–3, the row for this area.
6. **Schema or native work?** Use `changing-fitbuddy-schema` or `adding-android-capability`.
7. **Verify.** `flutter analyze`, then `flutter test -r failures-only` (full suite, once). Paste nothing longer than the failure summary.
8. **Check the definition of done** (below). Anything missing means the task stays ◐.
9. **Record.** Status file: ☑, or ⏳ if a device test is still owed (add it to the device backlog). Update the matching `docs/*.md` only if behaviour or schema changed.
10. **Commit and push.** One task, one commit: `F-05: encrypted Drift databases`.

## Definition of done (PRD §11.5)

| Check | Evidence |
|---|---|
| UI, logic and persistence implemented | Feature works end to end from the screen |
| Loading, empty, error, offline, validation states | Widget tests |
| Permissions handled, including denial | Widget or unit tests |
| Works offline where applicable | Test with no network source |
| Unit and widget tests pass | Full suite output |
| Every control does something | No-op control test |
| Docs and status updated | Diff |

## Stop and ask when

- The task needs a decision not in `docs/blueprint/README.md` §2–3.
- A platform restriction conflicts with the PRD (add it to `08-risk-register.md` §3).
- The task would need a feature the PRD does not describe.
