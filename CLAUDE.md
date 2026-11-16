# FitBuddy

Single-user Android health and lifestyle tracker. Flutter + Kotlin, Drift (encrypted, local-first), Supabase sync. Project root is the repository root.

**State:** read `docs/implementation_status.md` first. It is the resume point for every session.

## Where things are (read only the part you need)

| Need | Read |
|---|---|
| What to build next, task IDs, exit criteria | `docs/blueprint/06-milestones-and-tasks.md` (your phase's table only) |
| A PRD requirement | `docs/PRD.md` — grep the heading (`grep -n "^## 5.6" docs/PRD.md`), read that section only |
| Decisions already made (D1–D5, C1–C11) | `docs/blueprint/README.md` §2–3 |
| Layers, folders, permissions, sign-in, security | `docs/blueprint/01-architecture.md` |
| Packages and Kotlin plugins | `docs/blueprint/02-dependencies.md` |
| Tables, units, migrations, sync protocol | `docs/blueprint/03-database.md` |
| Tokens, components, screens, tone | `docs/blueprint/04-ui-ux-spec.md` |
| Reminders, steps, screen time, timers | `docs/blueprint/05-notifications-alarms-steps.md` |
| Required test cases, device script | `docs/blueprint/07-testing.md` |
| Platform limits and risks | `docs/blueprint/08-risk-register.md` |

## Rules that always apply

1. **The PRD is the source of truth.** Do not add features it does not ask for. Do not reopen a recorded decision; if one must change, ask the owner, then update `docs/blueprint/README.md`.
2. **No implementation before the owner approves the phase.** One phase at a time; never start the next while tests fail.
3. **No screen before its design is approved.** Show the owner the screen design on the design canvas (link in the status file) and wait for approval before writing any presentation code for it.
4. **Private data never leaves the device** (PRD §7.1). Sync, networking, logging and push code must not touch `PrivateDatabase`. See `.claude/rules/privacy.md`.
5. **Every visible control works.** No placeholder buttons, no example data shown as user data, no mock as a final implementation.
6. **Test with the feature.** Write the failing test first. "Done" means the PRD §11.5 definition, not "a screen exists".
7. **Report honestly in three states:** verified by automated tests / verified on device / implemented, device verification pending. Hardware features cannot be verified in the cloud environment.
8. **Secrets:** nothing but the Supabase URL and publishable key in the app. Never commit `env/*.json`, `google-services.json`, or a release keystore.
9. **Commit small, push often** to the working branch; the cloud workspace is ephemeral.

Path-specific rules load automatically from `.claude/rules/` when matching files are touched. Procedures are skills in `.claude/skills/`.

## Token economy

- Start from `docs/implementation_status.md` and one task row. Do not read whole documents "for context".
- Grep or glob before reading. Read files over 300 lines with `offset`/`limit`.
- Never open generated or vendored output: `*.g.dart`, `*.freezed.dart`, `lib/core/platform/generated/`, `build/`, `.dart_tool/`, `android/.gradle/`, `pubspec.lock`. Grep for the symbol instead.
- Run the narrowest check that proves the change: one test file while working, the full suite once before a commit.
- Keep command output short: `flutter test -r failures-only`, `./gradlew -q`, pipe long logs through `tail -n 40` or `grep`.
- Do not spawn subagents unless the owner asks.
- Do not restate the PRD or blueprint in replies or code comments; cite the section (`§5.6`, `03 §6.1`).
- Record progress in `docs/implementation_status.md`, not in long chat summaries. Replies: what changed, what was verified, what is blocked.

## Commands (available after task F-01)

```bash
flutter analyze
flutter test -r failures-only
flutter test test/unit/path_test.dart -r failures-only
dart run build_runner build --delete-conflicting-outputs
flutter build apk --debug --dart-define-from-file=env/dev.json
```
