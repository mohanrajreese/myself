# Phase 1 report — Foundation

**Date:** 16 November 2026 · **State:** built and verified by automated tests; phone verification pending (needs the owner's Supabase and Google sign-in setup).

## 1. Features completed

| Task | Result |
|---|---|
| F-00 | PRD, agent rules and skills, README, documentation skeleton |
| F-01 | Flutter 3.50 Android project, `minSdk 29`, `targetSdk 37`, project debug keystore |
| F-02 | Every planned plugin built together once; `flutter_timezone` replaced by a Kotlin call |
| F-03 | Lint settings, architecture and privacy boundary tests, CI |
| F-04 | Clock, calendar date, result/failure types, redacting logger, integer unit conversions |
| F-05 | Two encrypted databases with separate keys; key manager; schema version 1 |
| F-06 | Backups, device transfer and cleartext traffic disabled; analytics deactivated |
| F-07 | Design tokens, light and dark themes, bundled fonts |
| F-08 | Component set: cards, fields, pickers, segmented control, chips, switches, progress, states, step scaffold |
| F-09 | Router with six tabs, route rule for sign-in and onboarding, sheet routes |
| F-10 | Settings, profile, effective-dated goals and weight storage |
| F-11 | Outbox entry written in the same transaction as every synced change |
| F-12 | Onboarding: profile, goals, daily routine, permissions explained, summary; resumable |
| F-13 | Profile, goals and daily-routine editing from Settings; history kept on goal change |
| F-14 | Supabase migrations for profiles, goals and weight, with access rules (not yet applied to a project) |
| F-14a | Mandatory Google sign-in, account binding, offline gate, sign-out, different-account erase |
| F-15 | Home: greeting, targets, weight quick add, timeline, customisable sections |
| D7 | Calories, protein and water pre-filled from body weight, editable, with a recalculate action |

## 2. Verification

| Verified by automated tests | Verified on device | Implemented, device verification pending |
|---|---|---|
| Unit conversions, dates, logger redaction | — | App launch and navigation on Android 10 |
| Database encryption, key handling, outbox allow-list (on the build machine) | — | Encrypted databases opening and persisting on the phone |
| Layer and privacy boundaries; manifest hardening | — | `adb backup` returns no app data |
| Profile, goals, weight, settings storage | — | Google sign-in with a real account (device test 19) |
| Sign-in state: bind, sign out, same account, different account | — | Reopening offline after sign-in (device test 19) |
| Weight-based target calculation | — | Timezone read through the Kotlin call |
| Onboarding flow, validation, resume, summary edit | — | Keystore-backed key storage surviving restarts |
| Home, quick add, tabs, Settings, theme, Home customisation | — | Look and feel on the real screen |
| Contrast, 48 dp tap targets, labels, double text size on 320 dp, both themes | — | |
| Supabase access rules, on a local PostgreSQL | — | Same rules on the real Supabase project |

## 3. Files

166 files, about 13,500 lines added. Main areas: `lib/core` (database, encryption, units, widgets), `lib/features` (auth, onboarding, profile, weight, dashboard, settings), `lib/app`, `test`, `supabase`, `android`, `docs`.

## 4. Database changes

| Store | Change |
|---|---|
| `AppDatabase` | Schema version 1: `profiles`, `user_goals`, `nutrition_goals`, `weight_logs`, `sync_outbox`, `local_app_settings` |
| `PrivateDatabase` | Schema version 1, no tables yet |
| Supabase | `20261116000100_helpers.sql`, `20261116000200_profiles_and_goals.sql`, `20261116000300_weight_logs.sql` |

## 5. Android permissions added

`INTERNET` only.

## 6. Packages installed

Runtime: `material_ui`, `flutter_riverpod`, `go_router`, `drift`, `drift_flutter`, `sqlite3` (SQLite3MultipleCiphers build), `flutter_secure_storage`, `supabase_flutter`, `google_sign_in`, `connectivity_plus`, `path_provider`, `cryptography`, `uuid`, `intl`, `clock`, `collection`, `meta`, `path`, `freezed_annotation`, `json_annotation`, `package_info_plus`, `flutter_localizations`.

Development: `build_runner`, `drift_dev`, `freezed`, `json_serializable`, `pigeon`, `mocktail`, `fake_async`, `flutter_lints`.

## 7. Tests executed

| Suite | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` (unit, architecture, widget, accessibility) | 176 passed, 0 failed; the on-demand visual render file is skipped |
| `bash supabase/tests/run_local.sh` | 35 checks passed |
| `flutter build apk --debug` | Built |
| Visual renders (`test/visual`) | 11 screens rendered with the real fonts and compared by eye with the design canvas |

## 8. Known limitations

| Limitation | Risk |
|---|---|
| Nothing has run on a phone. Sign-in, secure storage, the Kotlin timezone call and backups are unverified there | R-27, R-35 |
| Only an Android 10 phone is available, so Android 12–14 behaviour stays unverified | R-37 |
| The Google button uses a plain "G" mark, not Google's official button artwork | — |
| A returning user on a new install repeats onboarding; restoring from the cloud arrives with sync in Phase 6 | — |
| The "sign in again to resume sync" banner arrives with sync in Phase 6 | — |
| Home cards for water, calories, protein, sleep and steps show targets only; logging arrives in Phases 2 and 4 | — |
| The notification bell and the "create a routine" button from the design are left out until Phase 3, so no control is dead | — |
| `firebase_core` and `workmanager_android` build but warn about an old Kotlin setup | R-20 |
| Tap targets are 48 dp, not the 44 dp drawn on the canvas (Android guideline) | — |

## 9. Remaining

| Item | Needs |
|---|---|
| Apply the three migrations and run `rls_checks.sql` on the real project | Supabase project and a way to apply migrations |
| Build with `env/dev.json` and run device tests: first launch, sign-in, onboarding, restart, airplane-mode relaunch (test 19), `adb backup` | Supabase URL and key, Google Web and Android OAuth clients, the phone |
| Replace the "G" mark with Google's official sign-in button | Decision or asset |
| Confirm INDB data licence before Phase 2 task C-16 | Owner or further research |
