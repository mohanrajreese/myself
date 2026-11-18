# Phase 5 report: Lifestyle and privacy

**Date:** 18 November 2026. **State:** built and verified by automated tests. Fingerprint unlock, the screenshot block, notification appearance, usage access and the camera still need a phone run. That run needs the owner's Supabase and Google sign-in setup so the app can be installed and signed in.

## 1. Features completed

| Task | Result |
|---|---|
| P-01 | App lock in Settings. The PIN (4–8 digits) is kept only as a salted PBKDF2 hash. Fingerprint unlock is optional. The app locks immediately or after 1, 5 or 15 minutes away. After 5 wrong PINs the wait grows. `LockGate` guards every private route, and screenshots are blocked while the lock is on |
| P-02 | Private habits: the two seeded types plus your own. Record now or with time, count and note. Weekly and monthly counts, history, delete, archive |
| P-03 | Private activities: the activity builder has a "Private" switch (C5, chosen once), and the private space has its own Add button. Each is yes/no or counted, with log, history and archive |
| P-04 | Bowel log: quick log (consistency, straining, pain, bleeding, time), history, 7-day count, 30-day daily average, consistency split, and an optional check-in reminder |
| P-05 | Sensitive reminders are stored in the private database. Every private and medication notification says only "Praxis reminder" and is hidden on the lock screen |
| P-06 | Hygiene: "Add the standard routines" creates 8 routines (bath, head wash, morning and night brushing, floss, mouthwash, morning and evening skincare with steps). Mark all done, and each routine is edited like any activity |
| P-07 | Medication and supplements: list, editor (name, dose in your own words, schedule, remind, active, notes, delete) and today's doses with Taken or Skip. Completing a dose from the notification records it |
| P-08 | Posture and recovery: rest day, soreness, recovery and notes. Switches for movement-break and posture reminders, plus recent history |
| P-09, P-10 | Screen time: usage-access explanation and settings page, rechecked on return. Today, week and month views, most-used apps, a daily target and one generic alert a day |
| P-11 | Privacy checks: private tables never enter the outbox, the private activity switch writes nothing to synced tables, notifications are generic and secret, and import boundaries hold. The recording-HTTP-client test waits for the Phase 6 sync engine |
| P-12 | Progress photos: camera or gallery, each file encrypted, shown in a grid, viewable and deletable, never synced |
| P-13 | Supabase migration 9 is not needed (decision below). `privacy.md`, `permissions.md` and this report updated |

Habits gains a fourth tab, **More**, which links to Hygiene, Medication, Recovery, Screen time and the Private space.

## 2. Verification

| Verified by automated tests | Verified on device | Implemented, device verification pending |
|---|---|---|
| PIN hashing and lock rules; the gate on every private route; wrong PIN refused; correct PIN opens; Lock relocks. Private habit, bowel, medication, hygiene, recovery and screen-time flows. Private records stay out of the outbox. Medication reminders are generic and secret with no name. Accessibility (contrast, tap targets, labels) on the 7 new public screens in light and dark, and on the 5 private screens after unlocking. 2× text on a 320 dp phone for all of them | None yet | Fingerprint prompt, `FLAG_SECURE` (app-switcher preview and screenshots), lock-screen appearance of notifications, usage-access page and totals compared with Digital Wellbeing, camera and gallery for progress photos |

## 3. Files created or modified

The Phase 5 data layer was committed as `bfc2936`. The screens commit adds 16 files (+2,904 lines): `lib/features/{private_space,medication,recovery,screen_time}/presentation`, `lib/app/routine/{hygiene_screen,habits_screen}.dart`, the router, routes, strings, `test/widget/lifestyle_test.dart` and the accessibility list. The activity builder gained the Private switch.

## 4. Database changes

| Store | Change |
|---|---|
| Private database | v2: private activity definitions and logs, private habit logs, bowel logs, medications and dose logs, sensitive reminders, daily and per-app screen time, progress photos |
| App database | v8: `local_recovery_logs` (local only) |
| Supabase | None. `hygiene_logs` is dropped because hygiene routines are ordinary activities (`03-database.md`, changed 18 Nov 2026), so migration 9 is not needed |

## 5. Android permissions added

`PACKAGE_USAGE_STATS` (special access, granted by the user) and `USE_BIOMETRIC`. Details are in `docs/permissions.md`.

## 6. Packages installed

`local_auth` (fingerprint). The usage and secure-window plugins are our own Kotlin.

## 7. Tests executed and results

| Suite | Count | Result |
|---|---|---|
| Unit | 319 | Pass |
| Widget, including accessibility | 231 | Pass |
| Architecture boundaries and manifest | 15 | Pass |
| `flutter analyze` | — | No issues |
| `flutter build apk --debug` | — | Builds |

The new tests found one defect, now fixed. The lock screen tried the PIN automatically from the 4th digit, and every silent try counted as a wrong PIN. Mistyping one 8-digit PIN therefore triggered the 30-second wait. The PIN pad now has an Unlock key, and only that key makes a try.

## 8. Known limitations

| Limit | Risk |
|---|---|
| Screen-time totals come from Android usage events and can differ from Digital Wellbeing | R-13 |
| Some phones ignore the secret visibility on the lock screen; the title is generic regardless | R-24 |
| A forgotten PIN cannot be recovered; reinstalling removes private records (by design, they are never backed up) | — |
| The private-space and medication reminder editors offer one daily time; other repeat rules are available through regular reminders only | — |
| Only the Android 10 phone is available for testing | R-37 |

## 9. Remaining tasks

- Owner: set up the Supabase project and Google OAuth clients, then install the debug APK.
- Device checks for Phase 5 (rows in the status file's device backlog). These are Phase 5's exit criteria: private screens absent from the app switcher, and sensitive notifications showing no content.
- The recording-HTTP-client privacy test arrives with the Phase 6 sync engine.
- Phase 6 (Reports and synchronisation) waits for approval. Its screens go to the design canvas first.
