# FITBUDDY
## Complete Product Requirements Document (PRD)

**Version:** 2.0  
**Date:** 16 November 2026  
**Platform:** Android mobile application  
**Product category:** Personal Health, Fitness, Nutrition & Lifestyle  
**Application name:** Praxis  
**Technology:** Flutter, Dart, Kotlin, Supabase  
**Primary database:** Drift / SQLite  
**Cloud database:** Supabase PostgreSQL  
**Target user:** Single individual (personal-use application)  
**Development approach:** Feature-first architecture, local-first data, iterative implementation

---

# PART 1 — PRODUCT DEFINITION

## 1.1 Product vision

Praxis is a personal health and lifestyle management application that brings daily health tracking, fitness, nutrition, sleep, personal habits, reminders and digital wellbeing into one application.

The application should help users:

- Understand their daily activities.
- Monitor weight and physical progress.
- Track food consumption and nutrition.
- Count steps automatically.
- Record workouts and improve fitness.
- Monitor sleep and daily wellness.
- Build consistent personal routines.
- Receive reminders and alarm notifications.
- Understand their screen-time habits.
- Maintain private health and personal records.
- Review their progress through meaningful reports.

Praxis should not feel like a traditional medical application or a complicated spreadsheet.

It should feel like a modern personal wellness assistant that the user can open several times a day to record activities and understand progress.

## 1.2 Product goals

1. Make everyday activity logging extremely easy.
2. Reduce manual work through automatic tracking where technically possible.
3. Provide useful reminders without overwhelming the user.
4. Display important information through clear dashboards.
5. Make fitness progression measurable.
6. Keep sensitive personal information private.
7. Work offline for core tracking features.
8. Synchronize eligible records securely.
9. Provide useful historical reports.
10. Maintain an attractive, consistent and intuitive user experience.

## 1.3 Non-goals

The initial application is not intended to be:

- A social fitness network.
- A public community application.
- A medical diagnosis application.
- A smartwatch operating system.
- A calorie prescription or medical treatment application.
- A multi-user family management system.
- A subscription-based commercial product.

These are outside the initial release scope.

---

# PART 2 — PLATFORM AND TECHNICAL STACK

## 2.1 Technology decisions

| Layer | Technology |
|---|---|
| Mobile UI | Flutter |
| Language | Dart |
| Android native features | Kotlin |
| Design system | Material 3 with custom Praxis styling |
| State management | Riverpod |
| Navigation | GoRouter |
| Local database | Drift + SQLite |
| Local encryption | SQLCipher-compatible SQLite |
| Secure storage | flutter_secure_storage / Android Keystore |
| Backend | Supabase |
| Database | PostgreSQL |
| Authentication | Supabase Auth |
| Server functions | Supabase Edge Functions |
| Remote push notifications | Firebase Cloud Messaging |
| Local notifications | flutter_local_notifications |
| Android alarms | Android AlarmManager APIs |
| Step counter | Android SensorManager |
| Screen-time tracking | Android UsageStatsManager |
| Charts | fl_chart |
| Connectivity | connectivity_plus |
| Background synchronization | WorkManager-compatible scheduling |
| Testing | flutter_test and integration_test |

Package versions must be selected from currently maintained compatible releases when implementation begins. Do not hardcode outdated package versions from this document.

## 2.2 Architecture

Use feature-first clean architecture.

Each feature should contain:

- Presentation layer.
- Application layer.
- Domain layer.
- Data layer.

Responsibilities:

**Presentation**
- Screens.
- Widgets.
- Forms.
- UI state.
- User interactions.

**Application**
- Providers.
- Controllers.
- Use cases.
- Feature workflows.

**Domain**
- Entities.
- Repository interfaces.
- Business rules.
- Validation.

**Data**
- Drift data sources.
- Supabase data sources.
- Platform channel integrations.
- Repository implementations.
- DTOs and mappers.

UI widgets must never directly communicate with Supabase, SQLite or Android native APIs.

Use repository interfaces to keep storage implementations replaceable and testable.

## 2.3 Suggested project structure

```text
fitbuddy/
│
├── android/
│   └── app/
│       └── src/main/kotlin/com/mysticstack/fitbuddy/
│           ├── MainActivity.kt
│           ├── StepCounterPlugin.kt
│           ├── ScreenTimePlugin.kt
│           └── AlarmPlugin.kt
│
├── assets/
│   ├── icons/
│   ├── illustrations/
│   ├── fonts/
│   └── sounds/
│
├── lib/
│   ├── main.dart
│   │
│   ├── app/
│   │   ├── app.dart
│   │   ├── router.dart
│   │   ├── theme.dart
│   │   └── app_config.dart
│   │
│   ├── core/
│   │   ├── database/
│   │   ├── encryption/
│   │   ├── networking/
│   │   ├── sync/
│   │   ├── notifications/
│   │   ├── permissions/
│   │   ├── platform/
│   │   ├── errors/
│   │   ├── utils/
│   │   └── widgets/
│   │
│   ├── features/
│   │   ├── onboarding/
│   │   ├── profile/
│   │   ├── dashboard/
│   │   ├── weight/
│   │   ├── body_measurements/
│   │   ├── nutrition/
│   │   ├── food_database/
│   │   ├── water/
│   │   ├── fitness/
│   │   ├── workouts/
│   │   ├── sleep/
│   │   ├── wellness/
│   │   ├── bowel/
│   │   ├── private_habits/
│   │   ├── hygiene/
│   │   ├── activities/
│   │   ├── reminders/
│   │   ├── timers/
│   │   ├── screen_time/
│   │   ├── medication/
│   │   ├── recovery/
│   │   ├── insights/
│   │   └── settings/
│   │
│   └── shared/
│       ├── models/
│       ├── widgets/
│       └── extensions/
│
├── supabase/
│   ├── migrations/
│   ├── functions/
│   └── seed.sql
│
├── test/
│   ├── unit/
│   ├── widget/
│   └── integration/
│
└── docs/
    ├── architecture.md
    ├── database.md
    ├── permissions.md
    ├── notifications.md
    └── implementation_status.md
```

---

# PART 3 — UX AND UI DESIGN REQUIREMENTS

## 3.1 Design direction

Create a premium, modern, minimal wellness application.

The design should be visually polished, easy to understand and focused on everyday use.

Design references are the modern wellness, nutrition and habit-tracking interfaces shared during product planning. Use them as inspiration, not as templates to copy.

### Visual principles

- Clean and uncluttered layouts.
- Consistent spacing.
- Rounded cards.
- Clear typography hierarchy.
- Subtle shadows and borders.
- Meaningful charts.
- Restrained use of colours.
- Consistent iconography.
- Smooth transitions.
- Minimal unnecessary decoration.

### Suggested design palette

| Purpose | Suggested colour |
|---|---|
| Primary | Deep teal / emerald |
| Secondary | Muted blue |
| Success | Green |
| Warning | Amber |
| Error | Red |
| Background | Soft neutral |
| Surface | White / dark surface |
| Text | High-contrast neutral |

Use theme tokens rather than hardcoding colours inside individual widgets.

Provide both light and dark themes.

## 3.2 Navigation

Use a bottom navigation bar with six primary destinations.

1. Home
2. Fitness
3. Nutrition
4. Health
5. Habits
6. Insights

Settings should be accessed from the Home/profile area.

Digital wellbeing should be accessible from the Home screen and Settings rather than adding another bottom navigation item.

## 3.3 Global UI requirements

Every feature screen must support:

- Loading state.
- Empty state.
- Error state.
- Success feedback.
- Offline state where relevant.
- Input validation.
- Accessible labels.
- Appropriate touch targets.
- Confirmation before destructive actions.

Do not use placeholder buttons that have no working functionality.

Every visible control must perform its stated action.

## 3.4 UX rules

1. Common actions should require as few taps as possible.
2. Prefer quick-add controls for frequently recorded values.
3. Do not force users to fill optional fields.
4. Preserve entered data when a form is interrupted.
5. Use sensible defaults.
6. Provide clear save confirmation.
7. Make editing historical records straightforward.
8. Show dates and times consistently.
9. Avoid displaying too many metrics on one screen.
10. Let users customize dashboard cards.
11. Do not make missed habits feel like failures.
12. Distinguish completed, missed, skipped and not scheduled activities.
13. Provide confirmation before deleting historical data.
14. Do not make sensitive modules visible in notification previews.

---

# PART 4 — APPLICATION SCREENS

## 4.1 Onboarding

Create a multi-step onboarding flow.

### Screen 1: Welcome
- Praxis logo.
- Short product introduction.
- Get Started button.

### Screen 2: Personal profile
- Name.
- Date of birth.
- Height.
- Current weight.
- Preferred measurement units.

### Screen 3: Personal goals
- Target weight.
- Daily step target.
- Daily calorie target.
- Protein target.
- Water target.
- Optional fitness goals.

### Screen 4: Daily routines
- Wake-up time.
- Sleep target.
- Preferred workout days.
- Optional reminder preferences.

### Screen 5: Permissions explanation
Explain why Praxis may need:
- Activity recognition.
- Notifications.
- Exact alarm access where necessary.
- Usage access.
- Location for optional GPS workouts.
- Camera/photo access for progress photos.

Ask for each permission contextually, when the user enables the corresponding feature.

Do not request all permissions immediately on the first launch.

### Screen 6: Complete setup
Show a summary of profile and goals.

Allow editing before completion.

## 4.2 Home dashboard

This is the most important screen.

### Header

Display:
- Greeting.
- Current date.
- Profile/settings shortcut.
- Notification indicator.

### Daily progress section

Show:
- Step progress.
- Water progress.
- Calorie intake.
- Protein intake.
- Sleep summary.
- Workout summary.

### Essential activities

Display scheduled essential activities for today.

Example:
- Morning brushing.
- Bathing.
- Walking.
- Evening skincare.

Actions:
- Mark complete.
- Snooze reminder.
- Open activity details.

### Today's timeline

Display recorded activities chronologically.

Example:
- 7:00 AM — Wake up.
- 7:15 AM — Water 250 ml.
- 7:30 AM — Brushing.
- 8:00 AM — Breakfast.
- 9:00 AM — Walking.

### Quick actions

Provide quick access to:
- Add meal.
- Add water.
- Add weight.
- Log workout.
- Log activity.
- Add sleep record.

### Dashboard customization

Allow the user to:
- Reorder cards.
- Hide cards.
- Select preferred metrics.
- Configure dashboard layout.

## 4.3 Fitness screens

Create separate screens or tabs for:

- Overview.
- Steps.
- Walking.
- Running.
- Cycling.
- Gym.
- Workout history.
- Personal records.

## 4.4 Nutrition screens

Provide:
- Food diary.
- Add meal.
- Food search.
- Custom food.
- Saved meals.
- Nutrition summary.
- Junk-food history.
- Water tracking.

## 4.5 Health screens

Provide:
- Weight history.
- Body measurements.
- Sleep history.
- Wellness check-ins.
- Bowel records in a protected local-only section.

## 4.6 Habits screens

Provide:
- Daily routines.
- Activity list.
- Custom activity builder.
- Reminder management.
- Stopwatch and timers.
- Hygiene routines.
- Private habit module behind app lock.
- Medication and recovery records.

## 4.7 Insights screens

Provide:
- Daily report.
- Weekly report.
- Monthly report.
- Weight chart.
- Nutrition charts.
- Fitness charts.
- Sleep trends.
- Habit consistency.
- Personal records.
- Custom date-range filtering.

---

# PART 5 — FUNCTIONAL REQUIREMENTS

## 5.1 User profile and goals

Fields:

- Name.
- Date of birth.
- Height.
- Current weight.
- Target weight.
- Daily calories.
- Daily protein.
- Daily carbohydrates (optional target).
- Daily fat (optional target).
- Daily fibre (optional target).
- Daily water.
- Daily steps.
- Timezone.
- Preferred units.

Users must be able to edit goals at any time.

Changing a goal must not alter historical records.

## 5.2 Weight tracking

Requirements:

- Add weight.
- Edit weight.
- Delete weight.
- Record date and time.
- Display current weight.
- Display target weight.
- Calculate change over time.
- Display 7-day, 30-day, 90-day and yearly charts.
- Support kg and lb.
- Optional measurement notes.

Example:

User records 91.8 kg on Monday and 91.2 kg on Friday.

The application displays the historical change without incorrectly treating a single fluctuation as guaranteed fat loss.

## 5.3 Body measurements

Support:

- Waist.
- Chest.
- Hips.
- Neck.
- Arms.
- Thighs.
- Optional body-fat percentage.

Allow custom measurement types.

Support:
- Measurement history.
- Comparison charts.
- Optional private progress photos.

## 5.4 Nutrition and food diary

### Meal categories

- Early morning.
- Breakfast.
- Mid-morning.
- Lunch.
- Evening snack.
- Dinner.
- Late-night.
- Other.

### Meal record

Each meal can contain multiple food items.

Each item supports:

- Food name.
- Quantity.
- Unit.
- Serving weight.
- Calories.
- Protein.
- Carbohydrates.
- Fat.
- Fibre.
- Optional photo.
- Optional notes.

Store food values as snapshots in meal records so editing the food database later does not unexpectedly rewrite old meals.

### Food database

Support:
- Search.
- Custom food creation.
- Food categories.
- Saved foods.
- Saved meals.
- Recently consumed foods.
- Duplicate meal.
- Edit food values.

Food search should be responsive and usable offline for previously cached foods.

### Nutrition summary

Display:
- Calories consumed.
- Calories remaining against target.
- Protein.
- Carbohydrates.
- Fat.
- Fibre.
- Meal distribution.
- Weekly averages.

### Junk-food tracking

Categories:
- Fast food.
- Fried snacks.
- Sweets.
- Sugary drinks.
- Packaged snacks.
- Other.

Junk food should also be part of the regular food diary when applicable. Its calories must only be counted once.

## 5.5 Water tracking

Support:
- Quick-add quantities.
- Custom quantities.
- Daily goal.
- Daily progress.
- Historical records.
- Water reminders.
- Weekly and monthly charts.

Example:

A user taps +250 ml.

The dashboard immediately updates the total.

## 5.6 Phone-only automatic step counting

The initial release must use the Android phone's built-in step counter.

### Technical integration

Use:
- Kotlin.
- Android SensorManager.
- Sensor.TYPE_STEP_COUNTER.

### Required behaviour

- Detect sensor availability.
- Request ACTIVITY_RECOGNITION permission.
- Collect cumulative readings.
- Persist readings locally.
- Calculate daily steps.
- Handle sensor counter reset after reboot.
- Handle midnight boundaries.
- Handle missing collection intervals.
- Handle timezone changes.
- Handle app restart.
- Handle permission revocation.
- Display daily total.
- Display daily goal.
- Sync daily totals to Supabase.

### Critical step attribution requirement

TYPE_STEP_COUNTER returns a cumulative value since the last reboot while the sensor is active. It is not a daily counter.

The implementation must not simply use the current cumulative sensor value as today's steps.

Maintain a persistent collection strategy and daily baseline data.

For dependable collection while the app is not visible, evaluate a properly configured Android foreground service with the applicable activity-recognition foreground-service permissions and an ongoing notification.

Do not claim uninterrupted background counting without testing on physical hardware.

If collection is interrupted, the app must identify uncertain periods rather than silently inventing daily steps.

Support manual step correction as an explicitly labelled user adjustment.

If the phone does not support the required sensor, show an understandable unsupported-device state.

### Step dashboard

Display:
- Today's steps.
- Goal.
- Percentage completed.
- Remaining steps.
- Weekly average.
- Monthly trend.
- Last successful collection time.
- Sensor status.

## 5.7 Walking, running and cycling

### Walking

- Distance.
- Duration.
- Pace.
- Start time.
- End time.
- Optional GPS route.
- Notes.

### Running

- Distance.
- Duration.
- Average pace.
- Speed.
- Optional GPS route.
- Personal records.

### Cycling

- Distance.
- Duration.
- Average speed.
- Optional GPS route.
- Personal records.

Support manual entry and optional GPS-based tracking.

Do not require GPS permission for manual activity logging.

Automatic step totals and workout steps must not be added together to create inflated daily totals.

## 5.8 Gym workout tracking

### Exercise library

Fields:
- Exercise name.
- Category.
- Muscle group.
- Equipment.
- Instructions.
- Custom exercise flag.

### Workout session

Fields:
- Workout name.
- Start time.
- End time.
- Duration.
- Notes.
- Exercise list.

### Exercise sets

Fields:
- Exercise.
- Set number.
- Repetitions.
- Weight.
- Optional distance.
- Optional duration.
- Rest duration.

Example:

Bench press:

- 40 kg × 12.
- 40 kg × 10.
- 45 kg × 8.

### Workout features

- Create workout.
- Edit workout.
- Duplicate workout.
- Save workout templates.
- Add/remove exercises.
- Reorder exercises.
- Add/remove sets.
- Rest timer.
- Workout history.
- Exercise progression charts.
- Personal records.

### Personal records

Calculate:
- Highest load.
- Highest repetitions at a given load.
- Longest duration.
- Longest distance.
- Fastest pace.

Use clearly defined record rules and never compare incompatible exercise variations or units.

## 5.9 Sleep tracking

Support manual records:

- Bedtime.
- Wake-up time.
- Total sleep.
- Sleep quality (1–5).
- Optional notes.
- Nap start.
- Nap end.
- Nap duration.

Display:
- Daily history.
- Weekly average.
- Monthly average.
- Bedtime consistency.
- Wake-up consistency.

Allow editing of overnight records across calendar dates.

Do not claim automatic sleep-stage measurement in the initial version.

## 5.10 Daily health check-in

Fields:

- Energy: 1–5.
- Mood: 1–5.
- Stress: 1–5.
- General wellness: 1–5.
- Optional notes.

Allow one or more check-ins daily.

Display trends and allow comparisons with sleep and activity records.

## 5.11 Bowel movement tracking

Local-only and encrypted.

Fields:
- Date/time.
- Count.
- Consistency: hard, normal, loose.
- Straining.
- Optional pain.
- Optional bleeding.
- Optional notes.

Provide:
- Quick logging.
- History.
- Frequency reports.
- Gentle routine reminders.

Never pressure the user to have a bowel movement or encourage straining or prolonged sitting.

## 5.12 Private habits

Local-only and encrypted.

Initial habit types:
- Porn consumption.
- Masturbation.

Support:
- Record occurrence.
- Count.
- Date/time.
- Optional note.
- Weekly and monthly trends.
- Private activity history.

Allow custom private habit types.

Require app lock before opening the private module.

Sensitive data must not be included in:
- Supabase requests.
- Sync outbox.
- FCM messages.
- Analytics.
- Crash logs.
- Ordinary notifications.

## 5.13 Bathing, dental and skincare

Support separate records for:

- Full-body bath.
- Head wash.
- Morning brushing.
- Night brushing.
- Flossing.
- Mouthwash.
- Morning skincare.
- Evening skincare.

Allow custom routine steps.

Example:

Morning skincare:
1. Face wash.
2. Serum.
3. Moisturizer.
4. Sunscreen.

The user can mark each step individually or complete the routine.

Bathing and head wash must be tracked independently.

## 5.14 Dynamic activity builder

This is a core feature.

Users must be able to create new activities without changing the application code.

### Activity configuration

- Name.
- Description.
- Category.
- Icon.
- Tracking type.
- Essential/optional priority.
- Target.
- Schedule.
- Repeat days.
- Reminder times.
- Stopwatch option.
- Dashboard visibility.
- Active/archive status.
- Sort order.

### Tracking types

- Boolean.
- Count.
- Numeric.
- Duration.
- Stopwatch.
- Event log.
- Checklist.

### Activity actions

- Create.
- Edit.
- Duplicate.
- Archive.
- Restore.
- Delete.
- Reschedule.
- Change priority.
- Change tracking type where historical data remains valid.
- View history.

Support multiple occurrences in one day.

Do not treat an activity as missed if it was not scheduled.

## 5.15 Reminder, alarm and notification system

This is a critical application subsystem.

Implement two separate systems:

1. Local notifications and alarm scheduling.
2. Remote push notifications using FCM.

Daily routine reminders must work without internet.

### A. Reminder types

- One-time.
- Daily.
- Multiple daily times.
- Selected weekdays.
- Weekly.
- Custom recurrence.
- Interval.
- Activity-specific.
- Incomplete-activity reminders.
- Medication reminders.
- Water reminders.
- Workout reminders.
- Sleep reminders.
- Custom reminders.

### B. Alarm-style alerts

Users should configure:

- Reminder title.
- Description.
- Date.
- Time.
- Repeat.
- Sound.
- Vibration.
- Snooze.
- Priority.
- Quiet-hour behaviour.
- Associated activity.

### C. Notification actions

Support:
- Mark complete.
- Snooze.
- Dismiss.
- Skip.
- Open activity.

Dismissing a notification must not automatically mark its activity complete.

### D. Snooze

Preset options:
- 5 minutes.
- 10 minutes.
- 15 minutes.
- 30 minutes.

Allow a custom snooze duration.

### E. Quiet hours

Allow a user-defined quiet period.

Example: 10:30 PM–6:30 AM.

Ordinary reminders should be deferred or suppressed according to the user's preference.

### F. Sound and vibration

Support:
- Default sound.
- Available system sounds.
- Custom sound selection where supported.
- Vibration on/off.
- Per-notification-channel configuration.
- Test sound action.

Respect Android notification channel settings and device restrictions.

### G. Exact alarms

Use exact alarms only when genuinely required.

Implement:
- Exact-alarm capability checks.
- Special access explanation.
- Graceful fallback when denied.
- Alarm rescheduling.
- Stable notification identifiers.
- Cancellation of obsolete schedules.
- Reboot recovery.
- Timezone and daylight-saving adjustments.

Do not request special exact-alarm access without explaining the need.

### H. Android notification channels

Create separate channels:

- Important alarms.
- Daily routines.
- Hydration.
- Fitness.
- Medication.
- Sleep.
- System notifications.

### I. Firebase push notifications

FCM should support server-triggered events such as:
- Account/security events.
- Important cloud synchronization issues.
- Backup status.
- Future server-side reminders.

Requirements:
- Token registration.
- Token refresh.
- Token invalidation.
- Foreground handling.
- Background handling.
- Notification tap handling.
- User notification preferences.
- Secure backend delivery.

Do not place sensitive health information in remote push payloads.

Local reminders must not rely on FCM.

### J. Permissions and limitations

Handle:
- POST_NOTIFICATIONS.
- Exact-alarm special access when required.
- RECEIVE_BOOT_COMPLETED.
- Applicable foreground-service permissions.
- Notification channels.
- Sound permissions/settings where relevant.

The app cannot guarantee alarms will override:
- Do Not Disturb.
- Device silent mode.
- User-disabled channels.
- Android restrictions.
- Manufacturer battery management.

Explain limitations honestly in the UI.

## 5.16 Stopwatch and timers

Support:
- Start.
- Pause.
- Resume.
- Finish.
- Cancel.
- Persistent sessions.
- Historical sessions.
- Configurable duration.
- Optional notification when complete.

State machine:

Ready → Running → Paused → Running → Completed.

A completed timer can create an activity log.

Cancelled sessions must not count as completed activities.

Persist timestamps and state transitions, not just a continuously changing timer value.

## 5.17 Digital wellbeing

Local-only by default.

Use Android UsageStatsManager.

Requirements:
- Usage Access permission.
- Total daily screen time.
- Individual app usage.
- Most-used applications.
- Daily and weekly reports.
- Monthly trends.
- Personal app usage targets.
- Optional usage alerts.

The app must not claim to access Digital Wellbeing's private database.

Underlying usage statistics can differ from Digital Wellbeing because of Android aggregation and device-specific behaviour.

Never upload detailed package-level usage data to Supabase.

## 5.18 Medication and supplements

Support:
- Name.
- User-entered dosage.
- Schedule.
- Reminder time.
- Taken/missed status.
- Notes.
- History.

Keep medication records local-only by default.

Do not prescribe medication or change doses.

## 5.19 Posture and recovery

Support:
- Sitting reminders.
- Stand-up reminders.
- Movement breaks.
- Rest-day tracking.
- Recovery notes.
- Muscle soreness rating.
- Recovery rating.

## 5.20 Reports and insights

Provide:
- Daily.
- Weekly.
- Monthly.
- Custom date range.

Reports:
- Weight.
- Body measurements.
- Calories.
- Protein.
- Carbohydrates.
- Fat.
- Fibre.
- Water.
- Steps.
- Walking.
- Running.
- Cycling.
- Gym progression.
- Sleep.
- Wellness.
- Habit completion.
- Junk food.
- Screen time.
- Private habit history locally.

Insights must be descriptive, data-based and non-diagnostic.

Example:

"Your average daily steps increased by 1,200 compared with the previous week."

Avoid claims that one activity caused another health outcome.

---

# PART 6 — DATABASE AND DATA MODEL

## 6.1 Storage strategy

Use Drift for local persistence.

Use Supabase for selected cloud-synced records.

The local database is the primary write source.

Every action must be persisted locally before background synchronization.

## 6.2 Cloud tables

Create the following PostgreSQL tables:

### User and configuration
- profiles
- user_goals

### Activities
- activity_definitions
- activity_logs

### Body tracking
- weight_logs
- body_measurements

### Nutrition
- food_items
- meal_logs
- meal_food_items
- nutrition_goals
- saved_meals

### Hydration
- water_logs

### Fitness
- step_logs
- workout_sessions
- workout_exercises
- exercise_sets
- workout_templates

### Sleep and wellness
- sleep_logs
- daily_health_checkins

### Hygiene
- hygiene_logs

### Reminders
- reminders
- device_notification_tokens

### Synchronization
- sync_outbox (local implementation)
- cloud_sync_metadata

## 6.3 Local-only tables

- local_private_activity_definitions
- local_private_activity_logs
- local_bowel_logs
- local_private_habit_logs
- local_screen_time_daily
- local_screen_time_apps
- local_timer_sessions
- local_medication_logs
- local_sensitive_reminders
- local_step_readings
- local_step_daily
- local_notification_state
- local_app_settings

## 6.4 Common database conventions

Use:
- UUID primary keys.
- UTC timestamps for cloud event timestamps.
- Local calendar dates for daily aggregates.
- Explicit timezone identifiers.
- Foreign keys.
- Unique constraints.
- Appropriate indexes.
- Created and updated timestamps.
- Soft deletion where synchronization requires it.

Store measurement units explicitly or normalize to a documented base unit.

Avoid floating-point rounding errors in nutrition and measurement calculations. Use suitable numeric representations.

## 6.5 Row Level Security

Enable RLS on every user-owned cloud table.

Standard ownership policy:

`auth.uid() = user_id`

Implement appropriate SELECT, INSERT, UPDATE and DELETE policies.

Never rely on client-side filtering as the only authorization mechanism.

Do not expose the Supabase service-role key in the mobile application.

## 6.6 Step table

`step_logs` fields:

- id.
- user_id.
- log_date.
- steps.
- source.
- timezone.
- collected_at.
- updated_at.

Unique constraint:

`(user_id, log_date)`.

Sync daily aggregates only.

Do not sync raw sensor readings.

## 6.7 Sync architecture

Implement:
- Local-first persistence.
- Outbox queue.
- Idempotent operations.
- Retry with exponential backoff.
- Conflict resolution.
- Tombstones.
- Connectivity recovery.
- User-scoped synchronization.
- Sync status.

Private local-only tables must never enter the sync outbox.

---

# PART 7 — SECURITY AND PRIVACY

## 7.1 Local-only classification

The following must remain local-only by default:

- Porn consumption.
- Masturbation.
- Bowel movement details.
- Bowel symptom notes.
- Detailed screen time.
- Individual app usage.
- Private activity definitions and logs.
- Sensitive reminders.
- Medication and supplement records.

## 7.2 Cloud-synced classification

The following may be synchronized:

- Profile.
- Goals.
- Weight.
- Body measurements.
- Meals.
- Food records.
- Water.
- Daily step totals.
- Ordinary workouts.
- Ordinary activities.
- Sleep.
- Daily wellness.
- Hygiene records.
- Ordinary reminder configuration.

## 7.3 Security requirements

- Encrypt sensitive local records.
- Protect database encryption keys with Android Keystore-backed secure storage.
- Exclude sensitive records and keys from insecure backups.
- No sensitive data in logs.
- No sensitive data in analytics.
- No sensitive data in push payloads.
- Require app authentication for protected modules.
- Secure export.
- Secure deletion.
- HTTPS.
- Supabase RLS.
- Secure FCM credential management.

If the app lock is enabled, private data must not become visible through notifications or app-switcher previews.

---

# PART 8 — NOTIFICATION TECHNICAL DESIGN

Implement notification functionality as an independent subsystem.

Recommended services:

- ReminderRepository.
- ReminderScheduler.
- LocalNotificationService.
- AndroidAlarmService.
- NotificationActionHandler.
- FcmService.
- NotificationPermissionService.
- NotificationHistoryRepository.

## Scheduling rules

When a reminder is created:
1. Save locally.
2. Validate recurrence.
3. Generate a stable schedule identifier.
4. Schedule the next occurrence.
5. Record scheduling state.

When edited:
1. Cancel the previous schedule.
2. Save the new configuration.
3. Schedule the replacement.

When deleted or disabled:
1. Cancel pending alarms.
2. Remove associated scheduled state.

After reboot:
1. Load active reminder definitions.
2. Recalculate upcoming schedules.
3. Restore required alarms.

When timezone changes:
1. Recalculate local scheduled times.
2. Avoid duplicate notifications.

Recurring schedules must be calculated from calendar rules, not repeated fixed millisecond intervals.

---

# PART 9 — OFFLINE AND SYNCHRONIZATION REQUIREMENTS

Core functionality must work without internet.

Offline features:
- Weight.
- Meals.
- Water.
- Workout logs.
- Activity logs.
- Sleep.
- Health check-in.
- Private tracking.
- Local reminders.
- Local reports.
- Step collection when supported.

When internet returns:
- Synchronize eligible records.
- Retry failures.
- Avoid duplicate records.
- Display sync status.
- Preserve unsynchronized records after errors.

The user should never lose a record merely because a network request failed.

---

# PART 10 — PERFORMANCE AND RELIABILITY

## Performance

- Dashboard must load from local data first.
- Quick logging must feel immediate.
- Database queries must be indexed.
- Reports must use date-range filtering.
- Large histories must be paginated.
- Background work must not block the UI.

## Reliability

- Preserve records across app restarts.
- Recover timers from persisted state.
- Restore reminders after reboot where supported.
- Handle missing permissions.
- Handle sensor resets.
- Handle timezone changes.
- Handle database migrations safely.
- Retry failed synchronization.

## Accessibility

- Support system font scaling.
- Use semantic labels.
- Maintain readable contrast.
- Use accessible touch targets.
- Provide meaningful error messages.

---

# PART 11 — TESTING AND ACCEPTANCE CRITERIA

## 11.1 Unit tests

Test:
- Calorie and macro totals.
- Meal calculations.
- Water totals.
- Weight changes.
- Step calculations.
- Step counter reset handling.
- Midnight boundaries.
- Workout progression.
- Personal record calculations.
- Timer state transitions.
- Reminder recurrence.
- Quiet hours.
- Synchronization retries.
- Data validation.

## 11.2 Widget tests

Test:
- Onboarding.
- Dashboard.
- Weight entry.
- Meal entry.
- Food search.
- Water quick-add.
- Workout session.
- Custom activities.
- Reminder configuration.
- Notification settings.
- Reports.
- Private module access.

## 11.3 Physical-device tests

Test on real Android devices:

1. Supported and unsupported step sensors.
2. Permission grant and revocation.
3. App open during walking.
4. App in background.
5. Process termination.
6. Device reboot.
7. Midnight step attribution.
8. Timezone changes.
9. Battery-saving mode.
10. Notification permission denied.
11. Exact-alarm access denied.
12. Notification channel disabled.
13. Multiple alarms.
14. Snooze behaviour.
15. Reboot alarm recovery.
16. Offline logging.
17. Network reconnection.
18. FCM foreground and background delivery.

## 11.4 Privacy tests

Verify:
- Private habits never sync.
- Bowel records never sync.
- Screen-time details never sync.
- Medication records remain local by default.
- Sensitive data is encrypted.
- Sensitive notifications are protected.
- RLS blocks unauthorized access.
- Logout and account deletion work correctly.

## 11.5 Definition of Done

A feature is complete only when:

- UI is implemented.
- Business logic is implemented.
- Data persistence works.
- Error states are handled.
- Permission handling is implemented.
- Offline behaviour is verified where applicable.
- Unit tests pass.
- Widget/integration tests pass where applicable.
- Documentation is updated.
- Acceptance criteria are satisfied.

Do not mark a feature complete merely because a screen has been created.

---

# PART 12 — IMPLEMENTATION ROADMAP

Implement the application in controlled milestones.

## Phase 1 — Foundation

- Flutter setup.
- Material 3 theme.
- Navigation.
- Riverpod.
- Supabase.
- Drift.
- Encryption.
- Onboarding.
- Profile.
- Dashboard skeleton.

**Deliverable:** Functional application foundation.

## Phase 2 — Core tracking

- Weight.
- Body measurements.
- Water.
- Nutrition.
- Food database.
- Sleep.
- Wellness.

**Deliverable:** Core personal health tracking.

## Phase 3 — Activities and reminders

- Dynamic activity builder.
- Essential and optional activities.
- Schedules.
- Local notification engine.
- Alarm-style alerts.
- Snooze and dismiss.
- Sound and vibration.
- Quiet hours.
- Reboot recovery.
- Stopwatch and timers.

**Deliverable:** Complete daily routine management.

## Phase 4 — Fitness

- Android step counter.
- Kotlin integration.
- Background collection.
- Walking.
- Running.
- Cycling.
- Gym exercises.
- Workout templates.
- Sets and reps.
- Personal records.

**Deliverable:** Fitness and workout tracking.

## Phase 5 — Lifestyle and privacy

- Bowel tracking.
- Private habits.
- Bathing.
- Dental care.
- Skincare.
- Medication.
- Recovery.
- Screen-time tracking.
- App lock.

**Deliverable:** Complete personal lifestyle tracking.

## Phase 6 — Reports and synchronization

- Daily reports.
- Weekly reports.
- Monthly reports.
- Charts.
- Insights.
- Sync outbox.
- Supabase sync.
- FCM.
- Export and deletion.

**Deliverable:** Full reporting and cloud integration.

## Phase 7 — Quality and release

- Full regression testing.
- Device testing.
- Privacy audit.
- Performance optimization.
- Database migration verification.
- Signed APK/AAB.
- Release documentation.

**Deliverable:** Stable Praxis Android release.

---

# PART 13 — DEVELOPMENT AGENT INSTRUCTIONS

This PRD is the single source of truth for product requirements.

The coding agent must follow these instructions.

## 13.1 Before implementation

1. Read the entire PRD.
2. Inspect the existing repository before changing anything.
3. Identify the current Flutter and Android setup.
4. Create a technical implementation plan.
5. Identify required permissions.
6. Identify database migrations.
7. Identify dependencies.
8. Break the work into testable tasks.
9. Report any technical limitation or conflict with Android platform restrictions.

Do not begin by generating the entire application in one large code operation.

## 13.2 Implementation rules

- Follow the specified architecture.
- Use Flutter and Kotlin for the agreed responsibilities.
- Use SQL-first Supabase migrations.
- Use Drift migrations for local schema changes.
- Never put Supabase queries directly in widgets.
- Never put secrets in client code.
- Never upload local-only data.
- Do not invent requirements.
- Do not create non-functional placeholder buttons.
- Do not hardcode example data as actual user data.
- Preserve historical records.
- Write tests with each feature.
- Keep code modular.
- Use reusable widgets.
- Handle permissions and platform failures.
- Verify Android functionality on physical devices.

## 13.3 Documentation requirements

Maintain:

- README.md.
- docs/architecture.md.
- docs/database.md.
- docs/permissions.md.
- docs/notifications.md.
- docs/step_tracking.md.
- docs/privacy.md.
- docs/implementation_status.md.

Update implementation status after every completed milestone.

## 13.4 Agent workflow

For each milestone:

1. Read applicable requirements.
2. List implementation tasks.
3. Identify dependencies.
4. Implement the smallest complete feature.
5. Write tests.
6. Run tests.
7. Fix failures.
8. Verify UI.
9. Update documentation.
10. Report completed and remaining acceptance criteria.

Do not move to the next milestone if critical tests are failing.

## 13.5 Completion report

At the end of each milestone, report:

- Features completed.
- Files created or modified.
- Database changes.
- Android permissions added.
- Packages installed.
- Tests executed.
- Test results.
- Known limitations.
- Remaining tasks.

---

# PART 14 — FINAL PRODUCT SUCCESS CRITERIA

Praxis v1 is successful when the user can:

1. Open one dashboard and understand their day.
2. Record food, weight and water quickly.
3. Track daily steps using the Android phone.
4. Record walking, running, cycling and gym sessions.
5. Monitor workout improvements.
6. Track sleep and daily wellness.
7. Create custom routines and activities.
8. Receive reliable, appropriately configured local reminders.
9. Use alarms and snooze controls.
10. Track personal habits privately.
11. Monitor detailed screen time locally.
12. Review daily, weekly and monthly reports.
13. Use core features without internet.
14. Synchronize eligible information securely.
15. Maintain control over personal data.

**Final product principle:**

Praxis must be useful in everyday life, not just attractive in screenshots.

Prioritize accurate tracking, easy logging, excellent UX, reliable reminders, privacy and meaningful progress reports over unnecessary complexity.

---

**END OF FITBUDDY PRD v2.0**
