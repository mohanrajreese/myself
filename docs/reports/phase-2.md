# Phase 2 report — Core tracking

**Date:** 17 November 2026 · **State:** built and verified by automated tests; phone verification pending (needs the owner's Supabase and Google sign-in setup to install and sign in).

## 1. Features completed

| Task | Result |
|---|---|
| C-01 | Weight: add, edit, delete, kg/lb display, notes, current and target, 7-day change, 7/30/90/365-day chart, paged history |
| C-02 | Shared chart card, line and bar charts, range selector, text summary for screen readers |
| C-03 | Body measurements: built-in and custom types, cm/in entry, per-type history with chart and change since the previous entry |
| C-04 | Meal photos: camera or gallery, AES-256-GCM encrypted files in app-private storage, view, replace, remove; never synced |
| C-05 | Water: one-tap amounts, custom amount, goal ring, weekly and monthly charts against the goal, remove with confirmation |
| C-06 | Foods: create, edit, keep as saved, recents, own foods first in offline search; catalogue foods edited as the user's linked copy |
| C-07 | Meals: eight categories picked from the time of day, several items, household/serving/gram portions, snapshot values, photo, note, edit, duplicate, delete, unsaved-changes guard |
| C-08 | Saved meals: keep from a meal, log again in one tap, delete |
| C-09 | Nutrition summary: eaten vs targets (calories, protein, fibre, carbohydrates, fat), meal shares, 7-day averages |
| C-10 | Junk-food category per item, 7-day history counted once |
| C-11 | Sleep: night and nap, overnight times, quality, notes, 7- and 30-day averages, bedtime consistency |
| C-12 | Wellness check-ins: four 1–5 scales, several per day, history charts next to sleep |
| C-13 | Home: live water, calories, protein, fibre and sleep tiles; quick add for meal, water, weight and sleep; merged timeline |
| C-14 | Supabase migrations for measurements, nutrition, water, sleep, check-ins and catalogue links, with access-rule checks |
| C-15 | Paged weight history; indexes on the new tables; this report |
| C-16 | Bundled catalogues: USDA SR Legacy (7,793 foods) and INDB (1,014 Indian dishes as estimates, household servings, 34 flagged); credits on the About screen |
| D8 | Daily fibre target (14 g per 1,000 kcal, 25–40 g, editable) on Goals, Home and the summary |

## 2. Verification

| Verified by automated tests | Verified on device | Implemented, device verification pending |
|---|---|---|
| Calculations, repositories, outbox entries, schema upgrades v1→v4, catalogue import and search, every screen's main flows, accessibility checks on 30 screens in light and dark, 2× text at 320 dp, local access-rule checks | None yet | Camera and gallery picking, photo encryption with the Keystore-backed key, catalogue import time on the phone, all screens on the real device, Supabase migrations on a real project |

## 3. Files created or modified

103 files changed since the Phase 1 screens commit (`81e1935`). Main areas: `lib/features/{weight,body_measurements,sleep,wellness,water,nutrition,food_database,health_hub,dashboard}`, `lib/core/widgets` (charts, sheets, formatting), `lib/core/database`, `assets/catalogue`, `supabase/migrations`, `test/unit`, `test/widget`. Most added lines are the two bundled catalogue files.

## 4. Database changes

| Store | Change |
|---|---|
| Drift app database | Schema versions 2 (tracking tables), 3 (local catalogue, meal photo index), 4 (household servings, conflict flag, catalogue link). Dumps in `drift_schemas/app/` |
| Supabase | `20261117000100_body_measurements.sql`, `20261117000200_nutrition_and_water.sql`, `20261117000300_sleep_and_wellness.sql`, `20261117000400_food_catalogue_ref.sql` |
| Private database | Unchanged |

## 5. Android permissions added

None. The system camera and photo picker need no permission (08 §3).

## 6. Packages installed

`fl_chart` 1.3.1, `image_picker` 1.2.4. Font licence texts added as assets for the licences page.

## 7. Tests executed and results

| Suite | Count | Result |
|---|---|---|
| Unit (`test/unit`) | 190 | Pass |
| Widget, including accessibility (`test/widget`) | 124 | Pass |
| Architecture boundaries (`test/architecture`) | 15 | Pass |
| Supabase access rules (`supabase/tests/run_local.sh`, local PostgreSQL) | all checks | Pass |
| `flutter analyze` | — | No issues |
| `flutter build apk --debug` | — | Builds |

The new screen tests found and fixed three defects: a meal-type dropdown overflow, food search opening inside the Nutrition tab (duplicate page error when opened from Add meal), and a missing serving name shown as "Enter your name."

## 8. Known limitations

| Limit | Risk |
|---|---|
| INDB values are recipe estimates; 34 dishes have self-contradicting values and are flagged, not corrected | R-38 |
| INDB has no licence file; bundled by owner decision with attribution | R-38 |
| Photos are local only and grow with use; downscaled to 1600 px before encryption | R-33 |
| Sleep is entered by hand; no sensor tracking | — |
| Nothing could be checked on a phone from the cloud environment | R-27 |

## 9. Remaining tasks

- Owner: Supabase project, Google OAuth clients, then install the debug APK.
- Device tests: 16 (log everything offline) and 19 (sign-in, then airplane mode) from `07-testing.md` §6, plus the Phase 2 rows in the status file's device backlog (photo camera/gallery, data and photo survive a restart).
- Apply the Supabase migrations to the real project; sync of these tables arrives in Phase 6.
