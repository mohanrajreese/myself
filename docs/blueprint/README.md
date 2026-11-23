# Praxis — Implementation Blueprint

**Status:** Phase 1 approved and in progress (16 November 2026). Progress is tracked in [`docs/implementation_status.md`](../implementation_status.md).
**Source of truth:** [`docs/PRD.md`](../PRD.md) (Praxis PRD v2.0, 16 November 2026). References such as "§5.6" point into the PRD.
**Prepared:** 16 November 2026

| # | Document | Covers |
|---|---|---|
| 1 | [01-architecture.md](01-architecture.md) | Toolchain and Android configuration, layering rules, folder structure, data boundaries, sign-in, sync, security |
| 2 | [02-dependencies.md](02-dependencies.md) | Flutter packages, native Android integrations, external services |
| 3 | [03-database.md](03-database.md) | Drift schema (two databases), Supabase PostgreSQL schema, SQL migration plan, RLS, sync protocol |
| 4 | [04-ui-ux-spec.md](04-ui-ux-spec.md) | Design tokens, component library, navigation map, screen inventory, UX rules |
| 5 | [05-notifications-alarms-steps.md](05-notifications-alarms-steps.md) | Reminder/alarm engine, FCM, step counting, screen time, timers |
| 6 | [06-milestones-and-tasks.md](06-milestones-and-tasks.md) | Seven phases, task checklist, acceptance criteria, PRD traceability matrix |
| 7 | [07-testing.md](07-testing.md) | Unit, widget, integration, migration, RLS, privacy and physical-device test plans |
| 8 | [08-risk-register.md](08-risk-register.md) | Android platform limitations and implementation risks |
| 9 | [09-food-dataset-options.md](09-food-dataset-options.md) | Candidate food datasets, licences, recommendation (decision D3) |

Agent rules and skills for working in this repository are in `CLAUDE.md`, `.claude/rules/` and `.claude/skills/`.

---

## 1. Repository state

| Finding | Detail |
|---|---|
| Repository | `mohanrajreese/myself`, branch `dev/bold-galileo-ssmrkj` |
| Contents before this work | Empty: no commits, no Flutter or Android project, no default branch |
| Now | PRD, this blueprint, agent rules and skills. Still no application code |

Toolchain facts checked on 16 November 2026 (orientation only; versions are re-resolved when implementation begins, per §2.1):

| Item | Current |
|---|---|
| Flutter stable | 3.50.0 (Dart 3.14.0) |
| Newest Android platform | API 37 (Android 17) |
| `flutter_local_notifications` | requires `compileSdk 37`, AGP 9.1.1 or newer, core-library desugaring |
| AGP 9 | uses built-in Kotlin; the separate `kotlin-android` plugin is no longer applied |
| `sqlcipher_flutter_libs`, `sqlite3_flutter_libs` | **end-of-life.** Encryption now comes from the `sqlite3` package's build hook (`source: sqlite3mc`) |

## 2. Decisions

| # | Decision | Outcome | Status |
|---|---|---|---|
| D1 | Phone and Android version | **Android 10.** `minSdk 29`. Phone model still unknown (wanted for battery-manager guidance, not blocking) | Decided |
| D2 | Sign-in model | **No sign-in screen; anonymous cloud user** (revised by the owner, 23 Nov 2026). The app opens straight into onboarding with a device account; when online it creates a Supabase anonymous user, moves the profile to that user's id, and syncs as before. Needs "Allow anonymous sign-ins" on the Supabase project. A reinstall starts a new cloud user (no restore without a linked sign-in). Deleting the cloud copy is confirmed by typing DELETE. Was: mandatory Google sign-in (01-architecture.md §7); that code is kept but not reachable | Decided |
| D3 | Starter food catalogue | **INDB plus a USDA subset**, bundled read-only. INDB's data licence is confirmed before its file enters the repository (09-food-dataset-options.md §5) | Decided |
| D4 | Project location | Flutter project at the repository root | Decided |
| D5 | Distribution | Personal sideloaded APK (plus a signed AAB build). No Play Store work | Decided |
| D7 | Starting targets | **Calories, protein and water are pre-filled from body weight** on the Goals step (per-kilogram rules of thumb, shown as editable estimates). This overrides the PRD's "no calorie prescription" non-goal (§1.3) by owner decision. Rules: `lib/features/profile/domain/goal_suggestions.dart` | Decided |
| D8 | Fibre target | **A daily fibre target is part of the goals** (owner request, 17 Nov 2026), pre-filled at 14 g per 1,000 kcal of the calorie estimate, 25–40 g, editable. Shown on Home and in the nutrition summary | Decided |
| D6 | Screen design review | **Every screen's design is shown to the owner and approved before the screen is built.** Designs live on the design canvas linked from the status file | Decided |
| D9 | Money module (PRD §5.21, addendum v2.1) | **Expenses, budgets, debts with EMI reminders, analysis and a food link**, as a **bottom tab in place of Insights**, which moves to the profile menu; nothing on Home; EMI reminders start at least 7 days before the due date; no bill splitting; EMI and recurring notifications never carry the amount (owner, 20 Nov 2026) | Decided |
| D10 | Money privacy tier | **Synced** like ordinary records (§7.2), not behind the app lock; receipt photos stay on the phone (owner, 20 Nov 2026) | Decided |
| D11 | Currency | **Indian rupees only**, stored as integer paise (owner, 20 Nov 2026; confirmed 23 Nov 2026) | Decided |
| D12 | Money additions (PRD §5.22, addendum v2.2) | Overdue EMIs, loan schedule, part-payments, rate changes, balance corrections, credit-card statements, personal-debt and budget alerts, income and savings, and **bill splitting returns** (reverses D9's "no split"); bank SMS, bank linking, other currencies and investments stay out (owner, 23 Nov 2026) | Decided |

### Consequences of D1 and D2 worth knowing

| Consequence | Detail |
|---|---|
| First launch needs internet | Sign-in cannot happen offline. After the first sign-in the app works fully offline (§9), even if the session later expires |
| Google Play services required | Sign in with Google uses the phone's Google account through Play services |
| A fixed debug signing key is needed | Google only issues a sign-in token to builds signed with a registered key. A project debug keystore is committed so every debug build has the same fingerprint |
| Newer-Android behaviour cannot be checked on your phone | Exact-alarm denial, notification permission and foreground-service typing only exist on Android 12–14 and later. They are implemented from the documentation and version-gated, and verified only if a newer phone or emulator becomes available |

## 3. Calls made where the PRD is silent

None adds a feature; each fills a gap the PRD leaves open. Overrule any of them.

| # | Gap | Call | Reason |
|---|---|---|---|
| C1 | PRD lists `workout_exercises` but no exercise-library table | Add cloud table `exercises` | Custom exercises (§5.8) must exist for workouts to reference them |
| C2 | Meal and progress photos have no storage defined | Local-only, encrypted files. No Supabase Storage in v1 | §5.3 calls progress photos "private". No bucket is specified |
| C3 | GPS routes have no storage defined | Route points local-only; only distance, duration and pace sync | A route reveals home location. Drawn as a line without map tiles, so no map provider or API key is introduced |
| C4 | Recovery and posture records (§5.19) appear in neither table list | Local-only table `local_recovery_logs` | Conservative default. Can be moved to cloud later |
| C5 | §6.3 and §7.1 mention private activity definitions, but §5.14 has no "private" option | A "Private" switch when creating an activity. It cannot be changed afterwards | Moving records between stores would mean uploading or un-uploading history |
| C6 | Medication needs definitions as well as logs | Add `local_medications` beside `local_medication_logs` | A log needs something to refer to |
| C7 | Saved meals and workout templates need item storage | Stored as a JSON document inside `saved_meals` / `workout_templates` | Templates are copied on use; no extra tables needed |
| C8 | App lock mechanism is unspecified | App PIN (hashed) with optional biometric unlock | Works on a phone with no screen lock, and does not lose data when fingerprints change |
| C9 | Android shows at most three notification buttons; §5.15C lists five actions | Buttons: Complete, Snooze, Skip. Tap opens the activity. Dismiss is the swipe (or a button on reminders with no activity) | Platform limit |
| C10 | Exercise library needs starting content | A seeded list of common exercises (name, category, muscle group, equipment, instructions) | Reference data, not user data. Custom exercises remain available |
| C11 | Signing in on a phone that already holds another account's data | Offer an export, then erase all local Praxis data (both databases) before binding the new account | Single-user app; one device holds one person's data |

## 4. What is needed from the owner

| Needed | For | Blocks |
|---|---|---|
| Supabase project: URL, publishable key, Google provider enabled | Sign-in, sync | Running the app on a phone at all (sign-in is the first screen) |
| Google Cloud OAuth clients: one **Web** client (ID and secret go into Supabase), one **Android** client for `com.mysticstack.fitbuddy` with the debug key's SHA-1 (and later the release key's) | Sign in with Google | Same |
| A way to apply migrations (Supabase access token for the CLI, or run `supabase db push` yourself) | Database schema | Sync, RLS tests |
| Firebase project (`google-services.json`; a service account for the server function) | FCM | Phase 6 push tasks |
| Physical Android phone and someone to run the device test script | §11.3 device tests | Sign-off of Phases 3, 4, 5 and 7 |
| Release keystore (created by you, kept out of the repo) | Signed APK/AAB | Phase 7 |

Automated tests use a fake sign-in, so development and CI do not need these credentials. A phone build does.

**What cannot be verified from the cloud development environment:** there is no phone, sensor or emulator. Builds, static analysis, unit tests, widget tests and Kotlin JVM tests run there. Step counting, alarms, reboot recovery, usage access, Google sign-in, FCM delivery and manufacturer battery behaviour can only be confirmed on the phone. Features that depend on them are reported as "implemented, device verification pending" until the script in [07-testing.md](07-testing.md) §6 has been run.

## 5. Approval

Phase 1 was approved on 16 November 2026. Each later phase needs its own go-ahead, and each screen needs design approval first (D6).
