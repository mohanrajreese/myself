# 06 — Milestones and Implementation Task Checklist

The seven phases are the PRD's (§12). Each phase follows the agent workflow in §13.4 and ends with the completion report in §13.5. A phase is not started while critical tests of the previous phase are failing.

**Definition of done for every task (§11.5):** UI, logic and persistence implemented; error, empty, loading and offline states handled; permissions handled; unit and widget tests passing; documentation updated. Tasks that touch Android hardware or system services add: device test passed on a physical phone.

Task status is tracked in `docs/implementation_status.md`.

---

## Phase 1 — Foundation

**Deliverable:** a running app with theme, navigation, encrypted storage, onboarding, profile and a dashboard skeleton.

Screen tasks (F-07, F-08, F-09, F-12, F-13, F-14a, F-15) wait for design approval (decision D6); the others do not.

| ID | Task | Verified by |
|---|---|---|
| F-00 | Create `README.md` and the documentation skeleton (§13.3). (`docs/PRD.md`, agent rules and skills are already committed) | Review |
| F-01 | Install the toolchain; create the Flutter project (`com.mysticstack.fitbuddy`); Gradle Kotlin DSL, SDK levels, desugaring, flavours, committed debug keystore, `.gitignore`, env example files | Debug APK builds |
| F-02 | Dependency smoke build: add every planned plugin and confirm the Android build succeeds | Debug APK builds |
| F-03 | Analysis options, import-boundary tests, CI workflow (analyse, test, build) | CI green |
| F-04 | Core utilities: `Clock`, `LocalDate`, `Result`/`Failure`, logger with redaction, unit types and conversions | Unit tests |
| F-05 | Key management and both encrypted Drift databases; cipher assertion; shared database isolate; first schema dump | Unit tests; encrypted-file test |
| F-06 | Manifest hardening: backups off, data-extraction rules, network security config, analytics deactivated | Manifest test |
| F-07 | Design tokens, light and dark themes, bundled fonts, contrast test | Widget and golden tests |
| F-08 | Component library, first set: scaffold, cards, states, fields, dialogs, snackbars, bottom navigation | Widget and golden tests |
| F-09 | GoRouter shell with six tabs and Settings; route guards | Widget tests |
| F-10 | `local_app_settings` repository; tables `profiles`, `user_goals`, `nutrition_goals` with effective-dating | Unit tests |
| F-11 | Outbox table with allow-list constraint; repository base class that writes row and outbox entry in one transaction | Unit tests |
| F-12 | Onboarding flow, sign-in then five steps, resumable; creates profile, goals and first weight entry; skipped for a returning user | Widget tests |
| F-13 | Profile and goals screens; goal change keeps history | Unit and widget tests |
| F-14 | Supabase: project configuration, first two migrations, RLS tests | pgTAP |
| F-14a | Auth feature: `AuthRepository` with fake; mandatory Sign in with Google; account binding; offline gate; expired-session banner; sign out; different-account erase flow | Unit and widget tests; device sign-in |
| F-15 | Dashboard skeleton: header, empty progress cards, quick-action sheet shell, customisation storage | Widget tests |
| F-16 | Documentation: `architecture.md`, `database.md`, `permissions.md`, `privacy.md`; Phase 1 report | Review |

**Exit criteria:** fresh install → Google sign-in → onboarding → dashboard; app reopens offline; data survives restart; database files are unreadable without the key; all tests green. Device sign-in needs the owner's Supabase and Google OAuth setup; until then it is "implemented, device verification pending".

---

## Phase 2 — Core tracking

**Deliverable:** weight, measurements, water, nutrition, food database, sleep and wellness, all working offline.

| ID | Task | PRD |
|---|---|---|
| C-01 | Weight: add, edit, delete, kg/lb, notes, current and target, change over time, 7/30/90-day and yearly charts | §5.2 |
| C-02 | Chart components and range selector | §4.7 |
| C-03 | Body measurements: built-in and custom types, history, comparison charts | §5.3 |
| C-04 | Encrypted photo file storage; attach, view and remove a meal photo | §5.4 |
| C-05 | Water: quick-add, custom amount, goal, progress, history, weekly and monthly charts | §5.5 |
| C-06 | Food items: custom food, categories, saved foods, recents, edit, offline search | §5.4 |
| C-07 | Meal logging: eight categories, multiple items, quantity and unit, snapshot values, photo, notes, edit, delete, duplicate | §5.4 |
| C-08 | Saved meals: create from a meal, log again | §5.4 |
| C-09 | Nutrition summary: consumed, remaining, macros, meal distribution, weekly averages | §5.4 |
| C-10 | Junk-food categories and history, counted once | §5.4 |
| C-11 | Sleep: night and nap records, overnight editing, quality, averages, consistency | §5.9 |
| C-12 | Wellness check-ins: four scales, several per day, trends | §5.10 |
| C-13 | Dashboard: live progress cards, today's timeline, working quick actions | §4.2 |
| C-14 | Supabase migrations 3–5 with RLS tests | §6.2 |
| C-15 | History pagination and indexes; Phase 2 report and docs | §10 |
| C-16 | Food catalogue: build-time import of the chosen dataset, read-only table with full-text search, source and estimate labels, attribution in About (needs decision D3) | §5.4 |

**Exit criteria:** every record type can be created, edited and deleted offline; totals match hand-calculated fixtures; the dashboard reflects a new entry immediately.

---

## Phase 3 — Activities and reminders

**Deliverable:** complete daily routine management with reliable local reminders.

| ID | Task | PRD |
|---|---|---|
| A-01 | Schedule rule model and `OccurrenceCalculator` (all rule types, DST, timezone) | §5.15A, §8 |
| A-02 | Activity definitions: builder with all configuration fields and seven tracking types | §5.14 |
| A-03 | Activity actions: edit, duplicate, archive, restore, delete, reschedule, change priority, permitted tracking-type changes, history | §5.14 |
| A-04 | Activity logging per tracking type; multiple occurrences per day; completed, missed, skipped, not scheduled | §5.14, §3.4 |
| A-05 | Essential activities on the dashboard with complete, snooze, open | §4.2 |
| A-06 | Notification permission flow; channels; versioned channel sounds | §5.15H, J |
| A-07 | Reminder repository and editor: all reminder types and alarm-style options | §5.15A, B |
| A-08 | `ReminderPlanner` and `ReminderScheduler`: rolling window, stable IDs, diffing, alarm budget | §5.15G, §8 |
| A-09 | Exact-alarm capability, rationale, fallback (`AlarmPlugin`) | §5.15G |
| A-10 | Notification actions in foreground and background isolates | §5.15C |
| A-11 | Snooze presets and custom duration | §5.15D |
| A-12 | Quiet hours: defer, suppress, bypass | §5.15E |
| A-13 | Sound and vibration: system sounds, custom sound, test actions (`SoundPlugin`) | §5.15F |
| A-14 | Recovery after reboot, app update, timezone and clock change (`SystemEventReceiver`, top-up worker) | §5.15G, §8 |
| A-15 | "If incomplete" reminders; water, workout and sleep reminder presets | §5.15A |
| A-16 | Notification centre (history) and limitation notices | §5.15J |
| A-17 | Stopwatch and timers: state machine, persistence, completion notification, activity log on completion | §5.16 |
| A-18 | Supabase migrations 6–7 with RLS tests; `notifications.md`; device test run; Phase 3 report | §13.3 |

**Exit criteria:** device tests 10–15 in 07-testing.md pass on your phone; recurrence and quiet-hour unit tests green.

---

## Phase 4 — Fitness

**Deliverable:** step counting and workout tracking.

| ID | Task | PRD |
|---|---|---|
| S-01 | `StepCounterPlugin`: sensor status, permission, single read | §5.6 |
| S-02 | Native buffer, boot session, snapshot worker | §5.6 |
| S-03 | Foreground service with midnight, shutdown and time-change flushes; boot restart | §5.6 |
| S-04 | `StepIngestor` and `StepAttributionEngine` | §5.6 |
| S-05 | Step dashboard, sensor status, uncertainty display, unsupported state, manual adjustment | §5.6 |
| S-06 | Walking, running, cycling: manual entry, pace and speed, history | §5.7 |
| S-07 | Optional GPS tracking with location permission, foreground service, route line | §5.7 |
| S-08 | Exercise library with seed list and custom exercises | §5.8 |
| S-09 | Gym session: create, edit, add/remove/reorder exercises, sets, rest timer | §5.8 |
| S-10 | Duplicate workout, templates, workout history | §5.8 |
| S-11 | Personal records with documented rules; exercise progression charts | §5.8 |
| S-12 | Fitness overview; dashboard step and workout cards | §4.2, §4.3 |
| S-13 | Supabase migration 8 with RLS tests; `step_tracking.md`; device test run; Phase 4 report | §13.3 |

**Personal record rules (S-11).** Records are per exercise and never cross exercises or measurement kinds. Loads are compared in grams regardless of entry unit.

| Record | Rule |
|---|---|
| Highest load | Greatest `load_g` in any completed set with at least one repetition |
| Most repetitions at a load | For each distinct load, greatest `reps` |
| Longest duration | Greatest `duration_s` (duration exercises; per session for walk, run, cycle) |
| Longest distance | Greatest `distance_m` per session, per activity type |
| Fastest pace | Lowest seconds per kilometre for sessions of at least 1 km, per activity type |

**Exit criteria:** device tests 1–9 pass on your phone; attribution unit tests cover reboot, midnight, gaps and timezone change.

---

## Phase 5 — Lifestyle and privacy

**Deliverable:** private and lifestyle tracking behind an app lock.

| ID | Task | PRD |
|---|---|---|
| P-01 | App lock: PIN, biometric unlock, auto-lock, `LockGate`, secure window flag | §7.3 |
| P-02 | Private habits: seeded and custom types, record, count, note, history, trends | §5.12 |
| P-03 | Private activities through the activity builder's private switch | §6.3 |
| P-04 | Bowel tracking: quick log, history, frequency report, gentle reminder | §5.11 |
| P-05 | Sensitive reminders: private storage, generic notifications, secret visibility | §3.4, §7.3 |
| P-06 | Hygiene routines: bath, head wash, dental, skincare, custom steps | §5.13 |
| P-07 | Medication and supplements: definitions, schedule, reminders, taken/missed, history | §5.18 |
| P-08 | Posture and recovery: sitting, stand-up and movement reminders, rest days, ratings | §5.19 |
| P-09 | `ScreenTimePlugin`, usage-access flow, daily roll-up | §5.17 |
| P-10 | Screen-time reports, targets, optional alerts | §5.17 |
| P-11 | Privacy test suite: recording HTTP client, outbox, logs, notifications | §11.4 |
| P-12 | Private progress photos for body measurements, behind the lock | §5.3 |
| P-13 | Supabase migration 9 (`hygiene_logs`) with RLS tests; `privacy.md`; device test run; Phase 5 report | §13.3 |

**Exit criteria:** every privacy test green; private screens absent from the app switcher; sensitive notifications show no content.

---

## Phase 6 — Reports and synchronisation

**Deliverable:** reporting and cloud integration.

| ID | Task | PRD |
|---|---|---|
| R-01 | Report queries per domain with date-range filtering | §5.20 |
| R-02 | Daily, weekly, monthly and custom-range report screens | §4.7 |
| R-03 | Insight sentences: period comparisons, descriptive only | §5.20 |
| R-04 | Private history report, on device, after unlock | §5.20 |
| R-05 | Sync engine: push, pull, backoff, conflict policy, tombstones, connectivity recovery | §6.7, §9 |
| R-06 | Initial pull and restore for a returning user; upload of everything queued since Phase 1 | §6.7 |
| R-07 | Background sync job; sync status UI | §9 |
| R-08 | FCM: token lifecycle, foreground, background, tap handling, preferences | §5.15I |
| R-09 | `send-push` and `delete-account` Edge Functions; migration 10 | §5.15I, §7.3 |
| R-10 | Export: JSON and CSV, optional passphrase, private data opt-in | §7.3 |
| R-11 | Deletion: local data, account, logout behaviour | §7.3, §11.4 |
| R-12 | Device tests 16–18; Phase 6 report | §11.3 |

**Exit criteria:** records created offline appear in Supabase after reconnection with no duplicates; a second install restores synced data; RLS tests green; private tables confirmed absent from all traffic.

---

## Phase 7 — Quality and release

**Deliverable:** stable signed release.

| ID | Task | PRD |
|---|---|---|
| Q-01 | Full regression: all automated suites | §12 |
| Q-02 | Full physical-device script (all 18 items) | §11.3 |
| Q-03 | Privacy audit: traffic capture, backup extraction attempt, log review | §11.4 |
| Q-04 | Performance: cold start, dashboard load, large-history scrolling, query plans | §10 |
| Q-05 | Accessibility pass: font scale, screen reader, contrast, tap targets | §10 |
| Q-06 | Database migration verification across all schema versions | §10 |
| Q-07 | Release build: shrinking rules, signing configuration, signed APK and AAB | §12 |
| Q-08 | Release documentation; final status update | §13.3 |

---

## Phase 8 — Money (PRD §5.21, addendum v2.1; proposed)

**Deliverable:** expenses, budgets, debts and EMI reminders with analysis, reached from a Home card.

| ID | Task | PRD |
|---|---|---|
| M-01 | Schema: app database v10 (five synced tables, receipt index), `reminders` kinds and `debt_id`; Supabase migration 11 with access-rule checks; outbox allow-list | §5.21, §6.2 |
| M-02 | Rupee amounts: integer paise, parsing and Indian grouping (₹1,23,456.50), tests | §5.21 |
| M-03 | Categories (seeded, own, archive) and payment methods | §5.21A |
| M-04 | Expenses: add, edit, delete, search and filter, receipt photo (encrypted, local) | §5.21A |
| M-05 | Budgets: overall and per category, effective-dated; progress | §5.21B |
| M-06 | Debts: both directions, kinds, payments ledger, outstanding, settle | §5.21C |
| M-07 | EMI loans: schedule, instalments paid and left, EMI reminders with Paid/Snooze/Skip recording payment and expense; recurring expenses | §5.21C, §5.15 |
| M-08 | Food link: meal cost field, link expense to meal, delete prompt | §5.21E |
| M-09 | Analysis: month and custom range, categories, methods, trend, budget, EMI share, debts summary, food spending; descriptive sentences | §5.21D |
| M-10 | Home Money card; export and deletion include Money; sync tables ordered | §5.21, §7.3 |
| M-11 | Widget and accessibility tests, device tests, docs, Phase 8 report | §11 |

**Exit criteria:** an expense, a debt and an EMI recorded offline sync with no duplicates; an EMI reminder's Paid records both the instalment and the expense; budgets never change past months.

---

## PRD traceability

Every functional section of the PRD maps to at least one task.

| PRD | Requirement | Tasks |
|---|---|---|
| §3.1 | Design system, light and dark | F-07, F-08 |
| §3.2 | Six-tab navigation, Settings from Home | F-09 |
| §3.3 | Global states, no placeholder controls | F-08, all feature tasks |
| §3.4 | UX rules | F-08, A-04, P-05 |
| §4.1 | Onboarding (with mandatory sign-in, decision D2) | F-12, F-14a |
| §4.2 | Home dashboard | F-15, C-13, A-05, S-12 |
| §4.3–4.7 | Tab screens | Feature tasks per tab |
| §5.1 | Profile and goals | F-10, F-13 |
| §5.2 | Weight | C-01 |
| §5.3 | Body measurements, photos | C-03, P-12 |
| §5.4 | Nutrition, food database, junk food | C-04, C-06 – C-10, C-16 |
| §5.5 | Water | C-05, A-15 |
| §5.6 | Step counting | S-01 – S-05 |
| §5.7 | Walking, running, cycling | S-06, S-07 |
| §5.8 | Gym, templates, records | S-08 – S-11 |
| §5.9 | Sleep | C-11 |
| §5.10 | Health check-in | C-12 |
| §5.11 | Bowel tracking | P-04 |
| §5.12 | Private habits | P-02, P-03 |
| §5.13 | Bathing, dental, skincare | P-06 |
| §5.14 | Activity builder | A-02 – A-04 |
| §5.15 | Reminders, alarms, FCM | A-06 – A-16, R-08, R-09 |
| §5.16 | Stopwatch and timers | A-17 |
| §5.17 | Digital wellbeing | P-09, P-10 |
| §5.18 | Medication | P-07 |
| §5.19 | Posture and recovery | P-08 |
| §5.20 | Reports and insights | R-01 – R-04 |
| §6 | Database, RLS, sync | F-05, F-10, F-11, F-14, C-14, A-18, S-13, P-13, R-05 – R-09 |
| §7 | Security and privacy | F-05, F-06, P-01, P-05, P-11, R-10, R-11 |
| §8 | Notification technical design | A-07 – A-14 |
| §9 | Offline and sync | F-11, R-05 – R-07 |
| §10 | Performance, reliability, accessibility | C-15, Q-04 – Q-06 |
| §11 | Testing | Every task; P-11, Q-01 – Q-03 |
| §13.3 | Documentation | F-00, F-16, and each phase report |

## Two ordering notes

| Note | Reason |
|---|---|
| The outbox is written from Phase 1 (F-11), although the sync engine arrives in Phase 6 | Everything logged before Phase 6 is then uploaded the first time sync is switched on, with no backfill step |
| Supabase and sign-in are in Phase 1 (F-14, F-14a) | The PRD lists Supabase under Phase 1, and sign-in is now the first screen. Code and automated tests use a fake sign-in and need no credentials; running on a phone needs the owner's Supabase and Google OAuth setup |
