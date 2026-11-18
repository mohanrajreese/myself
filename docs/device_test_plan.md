# Device test plan (Phase 7, task Q-02)

This is the run sheet for checking Praxis on the phone. Source list: `blueprint/07-testing.md` §6, plus the device backlog in `implementation_status.md`. Fill in **Result** (pass / fail / partly) and **Notes**, then send the sheet back. I will turn failures into fixes.

| Phone model | Android version | Battery saver | Manufacturer battery manager | App version / build | Date |
|---|---|---|---|---|---|
| | | | | | |

## 0. Preparation

1. Make sure the cloud project and Google sign-in are set up (`docs/sync_and_push.md`, README "Setup"). Firebase is optional; without it, test 18 is skipped.
2. Build and install the debug APK for tests 1–19:

```bash
flutter build apk --debug --dart-define-from-file=env/dev.json
```

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

3. For the final release check (section C), install the signed release APK instead (`docs/release.md`).
4. Keep a second device or a laptop browser open on the Supabase dashboard for the sync checks.

## A. Blueprint tests

| # | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| 1 | Fitness → Steps. Note the sensor status | "Counting" or the no-sensor explanation, matching the phone | | |
| 2 | Turn on step counting and allow activity recognition. Then Android Settings → Apps → Praxis → Permissions → Physical activity → Don't allow. Reopen Steps | Counting starts. After revoking, it says permission is needed and earlier days are still shown | | |
| 3 | Grant again. With Steps open, walk 200 counted steps | Today's count rises by about 200 (sensor tolerance) | | |
| 4 | Lock the phone, walk 200 steps, unlock and open Steps | Steps added; "last reading" time has moved | | |
| 5 | Turn on continuous counting. Swipe the app away, walk 200 steps, reopen. Repeat with continuous counting off | On: steps recorded. Off: steps recorded at the next reading, or the gap is shown as uncertain | | |
| 6 | Note today's total. Reboot, walk 200 steps, reopen | Total = before + about 200; never negative or doubled; a gap note if one was missed | | |
| 7 | Walk across midnight (or set a reminder for 23:55 and walk until 00:05) | Steps split between the two days | | |
| 8 | Set a reminder for a fixed time. Change the phone's timezone (Settings → System → Date & time), wait past the reminder's new local time | Steps neither lost nor doubled; the reminder fires once at the new wall-clock time | | |
| 9 | Battery saver on for a few hours of normal use | Note what happened; the app's status is honest about any gap | | |
| 10 | Deny notifications (Android Settings → Apps → Praxis → Notifications off). Create a reminder | Reminder saved; Habits shows a banner explaining; no crash | | |
| 11 | Revoke "Alarms & reminders" special access. Create an "Important alarm" reminder 2 minutes ahead | Fires (perhaps a little late); the app says it may be delayed | | |
| 12 | Android Settings → Apps → Praxis → Notifications → turn off the "Hydration" category | Settings → Notifications and reminders flags the turned-off category | | |
| 13 | Create five reminders, each two minutes apart | Each fires once with the right title | | |
| 14 | When one fires, press Snooze (5 min); next time choose a custom snooze | Fires again at the chosen times; Notification history shows the snoozes | | |
| 15 | Create two reminders 5 and 10 minutes ahead. Reboot and unlock | Both fire after the first unlock | | |
| 16 | Airplane mode on. Log weight, a meal with a photo, water, a workout, sleep, a check-in, an activity | Everything saves and shows on Home and in its screen | | |
| 17 | Airplane mode off. Settings → Account and sync → Sync now. Check the Supabase tables | "Up to date"; each record appears exactly once in the cloud | | |
| 18 | (Firebase set up) Send a test from the server: `send-push` with `{"user_id": "<your id>", "type": "sync_problem"}`, once with the app open and once with it closed. Tap the notification | Fixed text "Some changes have not synced…"; tap opens Account and sync; the payload in the function logs holds only the type | | |
| 19 | Uninstall. Install again, sign in with Google, then airplane mode on and reopen the app | Signed in and your records return (from test 17); the app opens and logs offline | | |

## B. Feature checks from earlier phases

| Area | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| Encryption at rest | Settings → About shows the build. With `adb shell run-as com.mysticstack.fitbuddy ls files` (debug build) find the `.sqlite` files and copy one out | The file does not open in a SQLite viewer | | |
| Backups | `adb backup -f fb.ab com.mysticstack.fitbuddy` | Empty or refused | | |
| Meal and progress photos | Add one from the camera and one from the gallery for each | Shown in the app; the stored `.bin` files are not readable images | | |
| Reminders overnight | Leave a 07:00 reminder overnight with the phone idle | Fires at 07:00 (or within a few minutes in Doze) | | |
| Notification buttons with the app closed | Swipe the app away; press Complete on a reminder | The activity shows as done when the app opens | | |
| Stopwatch | Start one, swipe the app away, restart the phone, reopen | The elapsed time is right | | |
| GPS walk | Start a GPS walk, screen off, walk about 1 km | Route drawn; distance roughly right; a notification while recording | | |
| App lock | Turn on the lock with a PIN and fingerprint. Open Private space, press Recents, try a screenshot. Leave for 2 minutes, come back | The preview is blank; the screenshot is refused; it asks for the PIN or fingerprint again | | |
| Private notifications | Add a medicine for 2 minutes ahead and lock the phone | Lock screen shows only "Praxis reminder" or nothing; Taken records the dose | | |
| Screen time | Allow usage access from the Screen time screen; use a few apps; compare one day with Digital Wellbeing | Totals within a reasonable margin (the app explains differences) | | |
| Export | Export JSON with a passphrase; open it on a computer with 7-Zip | Opens only with the passphrase; contains your records | | |
| Delete phone data | Settings → Delete data or account → Delete phone data | Back at sign-in; signing in again restores synced records only | | |
| Delete account | Delete account, keeping records on the phone | Cloud tables for the account are empty; the phone keeps its records, signed out | | |
| Manufacturer battery manager | Repeat test 4 and the overnight reminder with default settings, then with Praxis exempted | Note the difference | | |

## C. Release build

| Check | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| Release install | Install the signed release APK for your phone's ABI (`docs/release.md`) | Opens; sign-in works (the release key's fingerprint must be registered with Google, see `docs/release.md`) | | |
| Smoke test | Repeat tests 3, 13, 16, 17 and the app-lock check on the release build | Same results as debug | | |
| Cold start | Force-stop, then open the app 5 times and time each until Home appears | Note the times (aim: under 2 seconds) | | |
| Long history | After a few weeks of use, scroll Weight and Workout history and open Insights → Month | Smooth scrolling, no long waits | | |
| Screen reader | Turn on TalkBack and go through Home, a log sheet, Insights and the lock screen | Every control is announced with a name; no unlabelled buttons | | |
| Font size | Android display size and font size at the largest settings | Nothing cut off or overlapping | | |
