---
name: checking-privacy-boundary
description: Use when FitBuddy changes touch private habits, bowel records, medication, screen time, sensitive reminders, sync, the outbox, Supabase sources, logging, notification content or push payloads, and before committing any such change.
---

# Checking the privacy boundary

PRD §7.1 data must not appear in any network request, outbox row, log line, push payload, notification preview or backup. Check all seven items; a clean result on one says nothing about the others.

## Checks

| # | Question | How to check |
|---|---|---|
| 1 | Does sync or network code import the private database? | `grep -rn "private_database\|/private/" lib/core/sync lib/core/networking $(git ls-files 'lib/**/*_remote_source.dart')` must print nothing |
| 2 | Is a private or `local_` table in the outbox allow-list? | Read the `CHECK` on `sync_outbox.entity_table`; compare with `docs/blueprint/03-database.md` §2 |
| 3 | Did a Supabase migration gain a private table or column? | `git diff --name-only -- supabase/migrations`, read each new file |
| 4 | Can a log line carry a record value? | `grep -rn "AppLogger\|debugPrint\|print(" <changed files>`; arguments must be event codes and counts only |
| 5 | Does a sensitive notification show real text? | Title and body generic, visibility secret, payload is an opaque ID |
| 6 | Does a push payload hold more than `{type, id}`? | Read `supabase/functions/send-push` and its test |
| 7 | Do the automated privacy tests pass? | `flutter test test/unit/privacy test/architecture -r failures-only` |

## If a check fails

Fix the code. Do not move the data to the synced tier, widen the allow-list, or weaken a test to pass. If the feature seems to need private data off the device, stop and ask the owner.

## Report

State each of the seven checks as passed or failed with the command output line that shows it.
