# 07 — Testing Requirements

Tests are written with each feature, not after it (§13.2). A phase closes only when its suites pass (§13.4).

## 1. Test layers

| Layer | Tool | Runs in | Covers |
|---|---|---|---|
| Unit (Dart) | `flutter_test`, `mocktail`, `fake_async`, in-memory Drift | Cloud dev environment, CI | Domain rules, calculators, repositories, sync engine, planners |
| Architecture | Plain Dart tests over `lib/` imports and the manifest | Cloud, CI | Layer boundaries, privacy boundaries, banned APIs, manifest hardening |
| Widget | `flutter_test`, golden images | Cloud, CI | Screens, components, states, accessibility guidelines |
| Migration | Drift schema verifier against committed schema dumps | Cloud, CI | Every local schema version upgrades correctly |
| Database policy | pgTAP through the Supabase CLI | Local Supabase stack or a dedicated test project | Row Level Security, constraints, triggers |
| Kotlin unit | JUnit, Robolectric | Cloud, CI | Buffer store, boot-session logic, usage-event pairing |
| Integration | `integration_test` | Physical device (or emulator where one is available) | End-to-end flows through the real app |
| Physical device | Scripted manual tests | Your phone | Sensors, alarms, reboot, permissions, battery behaviour, FCM |

**Limit of the cloud environment:** it has no phone or emulator. The last two layers are run by you with the script in §6; results are recorded in `docs/implementation_status.md`.

## 2. Unit tests (§11.1)

| Area | Cases |
|---|---|
| Calories and macros | Totals per item, meal and day; quantity scaling; integer arithmetic with no drift across 1,000 items; remaining against target; optional targets absent |
| Meal calculations | Snapshot unaffected by later food edit; duplicate meal; saved-meal expansion; junk item counted once in daily totals |
| Water | Daily total; quick-add; edits and deletes; day boundary at local midnight |
| Weight | Change over 7/30/90 days; kg/lb round trip; several entries in one day; single fluctuation not labelled as fat loss |
| Units | Every conversion round-trips within display precision |
| Goals | A goal change does not alter how earlier days are evaluated |
| Steps | Same-boot difference; cumulative value never used as a daily total; first reading of the day; goal percentage and remaining |
| Step reset | Reboot between readings; reboot with a shutdown reading; several reboots in a day; decreasing value within a boot |
| Midnight | Reading exactly at midnight; short period across midnight; long period across midnight marks both days uncertain |
| Step timezone | Timezone moves forward and back mid-day; DST day of 23 and 25 hours |
| Step gaps | Missing interval flagged; permission revoked and restored; manual adjustment kept separate |
| Workouts | Session duration; pace and speed; set ordering; template instantiation; duplicate workout |
| Personal records | Each rule in 06 §Phase 4; mixed kg/lb entries; no cross-exercise comparison; deleted set recalculates the record |
| Timers | Every legal transition; illegal transitions rejected; elapsed time across pause and resume; recovery from persisted events; cancelled creates no log |
| Recurrence | Each rule type; month ends; leap day; DST gap and overlap; timezone change; start and end dates |
| Quiet hours | Period crossing midnight; defer, suppress, bypass; collapse of several deferred occurrences |
| Reminder planning | Window size; alarm budget; idempotent re-plan; edit replaces; disable cancels; "if incomplete" cancelled on completion; stable IDs |
| Notification actions | Complete writes a log; skip writes skipped; dismiss writes nothing to the activity; snooze schedules and counts |
| Activity status | Completed, missed, skipped, not scheduled; schedule change does not rewrite earlier days; multiple occurrences per day |
| Sleep | Overnight duration; attribution to wake date; nap; consistency metrics |
| Sync | Outbox coalescing; push success and failure; backoff schedule with jitter bounds; retry after connectivity; row changed during push stays queued; pull applies, skips newer local, skips pending; tombstones; idempotent replay; account switch |
| Validation | Each form's limits and required fields |
| Insights | Period comparison arithmetic; empty periods; wording contains no causal terms |
| Screen time | Event pairing; app left in foreground across midnight; missing pause event |
| Security | PIN hash verify and reject; lock timeout; key creation and reuse |

## 3. Widget tests (§11.2)

| Screen | Cases |
|---|---|
| Onboarding | Step order; validation; skip optional fields; resume after restart; edit from summary |
| Dashboard | Loading, empty and populated; quick actions open and save; essential activity complete and snooze; customise order and visibility |
| Weight entry | Add, edit, delete with confirmation; unit switch; chart range |
| Meal entry | Add items; quantity change updates totals; photo optional; draft restored |
| Food search | Results while typing; recents; empty result offers custom food |
| Water quick-add | One tap updates progress; custom amount; undo |
| Workout session | Add exercise; add and remove sets; reorder; rest timer; finish |
| Custom activities | Each tracking type's builder and logger; archive and restore |
| Reminder configuration | Each rule type; sound, vibration, snooze, quiet-hour options; exact-alarm rationale shown when needed |
| Notification settings | Permission denied banner; channel list; test sound; limitation text present |
| Reports | Range switch; empty range; chart summaries for screen readers |
| Private module access | Locked route shows lock; wrong PIN rejected; unlock reveals; auto-lock |

Applied to every screen: loading, empty, error and offline states; no-op control check; light and dark goldens; font scale 1.0, 1.3 and 2.0; tap-target and contrast guideline checks.

## 4. Migration and database tests

| Suite | Cases |
|---|---|
| Drift migrations | For each database, from every past version to current: schema equals a fresh install; sample rows survive; foreign keys valid |
| Drift constraints | Outbox rejects a table outside the allow-list; enumeration and range checks; cascade behaviour |
| Encryption | Database file does not contain the SQLite header or known plaintext; opening with the wrong key fails; cipher pragma present |
| pgTAP: RLS | For every table: user A cannot select, insert, update or delete user B's rows; anonymous role can do nothing; child row cannot reference another user's parent |
| pgTAP: triggers | Stale update ignored; `server_updated_at` advances; `step_logs` unique per user and date; account deletion cascades |

## 5. Integration tests

Run on a device with a local or test Supabase project.

| Flow | Steps |
|---|---|
| First run | Install → onboarding → dashboard shows profile and goals |
| A day of logging | Weight, three meals, water, workout, sleep, check-in → dashboard and daily report agree |
| Offline then online | Log with networking off → reconnect → rows in Supabase, no duplicates, outbox empty |
| Restore | Reinstall → sign in → synced data restored, private data absent |
| Reminder round trip | Create reminder → notification → complete from notification → activity shows completed |
| Timer persistence | Start timer → kill app → reopen → elapsed time correct |
| Lock | Enable lock → background → return → locked; private screens not in recents |

## 6. Physical-device test script (§11.3)

Recorded per device: model, Android version, battery-saver state, result, notes. Detailed steps are written into `docs/device_test_plan.md` in the phase that introduces each feature.

| # | Test | Expected |
|---|---|---|
| 1 | Step sensor present / absent | Sensor status correct; unsupported state on a phone without the sensor |
| 2 | Grant, then revoke activity recognition | Collection starts; after revoke, status shows permission needed and history is kept |
| 3 | Walk 200 counted steps with the app open | Count within the sensor's tolerance; dashboard updates |
| 4 | Walk with the app in the background | Steps recorded; last collection time advances |
| 5 | Swipe the app away, walk, reopen | Steps recorded (continuous mode); gap flagged otherwise |
| 6 | Reboot mid-day, walk, reopen | Day total = before + after; no negative or doubled count; gap noted |
| 7 | Walk across midnight | Each day gets its own steps |
| 8 | Change timezone | No lost or duplicated steps; reminders move to the new wall-clock time once |
| 9 | Battery saver on | Behaviour recorded; status honest about any interruption |
| 10 | Notification permission denied | Reminders saved; banner explains; no crash |
| 11 | Exact-alarm access denied | Reminder fires inexactly; "may be delayed" shown |
| 12 | Channel disabled in system settings | App flags the disabled channel |
| 13 | Five alarms within ten minutes | Each fires once, with the right content |
| 14 | Snooze 5 minutes, then custom | Re-fires at the chosen time; snooze recorded |
| 15 | Reboot with pending alarms | Alarms fire after first unlock |
| 16 | Log everything offline | All saved and visible |
| 17 | Reconnect | Sync completes; no duplicates |
| 18 | FCM with app in foreground and background | Delivered; tap opens the right screen; payload has no health data |

Additional checks on your specific phone: manufacturer battery manager with default settings and with the app exempted; reminders overnight in Doze; lock-screen appearance of a sensitive reminder; usage access grant and a comparison of totals with the system's own screen-time figure.

## 7. Privacy tests (§11.4)

| Check | Method |
|---|---|
| Private habits, bowel, medication and screen-time details never sync | Automated: exercise every private feature against a recording HTTP client with sync enabled; assert zero requests contain private table names, field names or seeded marker values |
| Outbox cannot hold private data | Automated: constraint test; private database has no outbox table |
| Sync code cannot reach the private database | Automated: import-boundary test |
| Sensitive data encrypted | Automated: file inspection for marker values; on device: copy the app data with a debug build and confirm it is unreadable |
| Logs clean | Automated: run private flows with log capture; assert no marker values. On device: `logcat` review |
| Sensitive notifications protected | Automated: notification details for sensitive reminders have generic text and secret visibility. On device: lock-screen check |
| App switcher | On device: private screen not visible in recents with the lock enabled |
| Push payloads | Automated: `send-push` unit test rejects payloads with fields other than type and ID |
| Backups | Automated: manifest test (backup off, extraction rules). On device: `adb backup` yields no app data |
| RLS | pgTAP suite |
| Logout | Session and FCM token removed; synced data stays on device unless the user chooses to remove it; private data untouched |
| Account deletion | Cloud rows gone (verified by query); local behaviour as chosen by the user |

## 8. Continuous integration

On every push: format check, static analysis, architecture tests, unit and widget tests, Drift schema check (dump matches code), Kotlin unit tests, debug APK build. pgTAP runs when files under `supabase/` change.

## 9. Reporting

Each phase report (§13.5) lists tests executed and results, and separates three states: **verified by automated tests**, **verified on device**, and **implemented, device verification pending**. Nothing in the third state is called complete.
