# 04 — UI/UX Design Specification

Direction: premium, modern, minimal wellness app (§3.1). Material 3 with custom FitBuddy styling. Light and dark themes. The reference designs from product planning are inspiration only.

## 1. Design tokens

All styling comes from tokens exposed through `ThemeExtension`s. A widget test fails if a feature file contains a literal `Color(0x…)`, a literal font size, or a literal `EdgeInsets` value outside the scale.

### 1.1 Colour

Starting values. Each foreground/background pair is checked for WCAG AA contrast by an automated test before it is accepted; values that fail are adjusted.

| Token | Light | Dark | Use |
|---|---|---|---|
| `primary` | `#0F766E` | `#5EC9BD` | Main actions, progress, selected navigation |
| `onPrimary` | `#FFFFFF` | `#00201C` | |
| `primaryContainer` | `#D5F0EC` | `#0B4F49` | Tinted cards, chips |
| `secondary` | `#48688C` | `#A9C4E4` | Secondary data series, links |
| `success` | `#2E7D4F` | `#7FD3A0` | Completed states |
| `warning` | `#B26A00` | `#F2B866` | Approaching limits, uncertain data |
| `error` | `#BA1A1A` | `#FFB4AB` | Errors, destructive actions |
| `background` | `#F6F7F5` | `#0F1514` | Page |
| `surface` | `#FFFFFF` | `#171E1D` | Cards, sheets |
| `surfaceVariant` | `#EDF0EE` | `#222B2A` | Input fills, skeletons |
| `outline` | `#D5DAD7` | `#34403E` | Hairline borders |
| `textPrimary` | `#141A19` | `#E7EDEB` | |
| `textSecondary` | `#55605E` | `#A3AFAC` | |
| `textDisabled` | `#9AA4A1` | `#66716F` | |

Status colours are never the only signal: every state also has an icon or label.

Chart series use a fixed ordered palette (teal, blue, amber, violet, rose) taken from the tokens, validated for colour-blind separation.

### 1.2 Typography

| Style | Font | Size / line height | Weight | Use |
|---|---|---|---|---|
| `displayMetric` | Inter, tabular figures | 40 / 44 | 700 | Hero numbers (steps, weight) |
| `headline` | Plus Jakarta Sans | 24 / 30 | 700 | Screen titles |
| `title` | Plus Jakarta Sans | 18 / 24 | 600 | Card and section titles |
| `metric` | Inter, tabular figures | 22 / 26 | 600 | Card numbers |
| `body` | Inter | 16 / 24 | 400 | Text |
| `bodySmall` | Inter | 14 / 20 | 400 | Secondary text |
| `label` | Inter | 12 / 16 | 600 | Chips, navigation, axis labels |

Text follows the system font scale. Layouts are tested at 1.0, 1.3 and 2.0.

### 1.3 Space, shape, elevation, motion

| Token | Values |
|---|---|
| Spacing | 4, 8, 12, 16, 20, 24, 32, 40. Screen side padding 16. Card padding 16. Gap between cards 12 |
| Radius | 8 (inputs, chips), 16 (cards), 24 (sheets, hero cards), full (pills, rings) |
| Elevation | Cards are flat with a 1 px `outline` border and one soft shadow level. Only sheets and dialogs are raised |
| Touch target | At least 48 × 48 dp |
| Motion | 150 ms (press, toggle), 250 ms (cards, sheets), 400 ms (progress rings, chart entry). Standard Material easing. Disabled when the system "remove animations" setting is on |
| Icons | Material Symbols, rounded, 24 dp, one weight throughout |

## 2. Component library (`core/widgets`)

Every component has a widget test, semantic labels, and light/dark golden images.

| Group | Components |
|---|---|
| Layout | `FbScaffold` (title, actions, offline strip), `FbCard`, `SectionHeader`, `FbBottomSheet`, `FbBottomNav` |
| Metrics | `MetricCard` (label, value, unit, trend), `ProgressRing`, `ProgressBar`, `StatTile`, `TrendChip` (neutral wording, no red/green judgement on weight) |
| Logging | `QuickAddRow` (preset chips plus custom), `NumberStepper`, `UnitNumberField` (value with unit switch), `RatingScale` (1–5), `DateTimeField`, `DurationField`, `MealCategoryPicker` |
| Lists | `TimelineItem`, `ActivityTile` (states: completed, pending, missed, skipped, not scheduled), `LogListItem` (swipe to edit/delete), `ReorderableCardList`, paged list with load-more |
| Charts | `ChartCard` wrapping `fl_chart` line and bar charts with shared axes, tooltips, empty state; `RangeSelector` (7 d / 30 d / 90 d / 1 y / custom) |
| States | `LoadingSkeleton`, `EmptyState` (illustration, one sentence, one action), `ErrorState` (message, retry), `OfflineBanner`, `SyncStatusPill` |
| Feedback | `FbSnackbar` (with Undo where a change is reversible), `ConfirmDialog` (destructive style), `SaveConfirmation` |
| Permissions | `PermissionRationaleSheet` (what, why, what happens if declined, button to continue), `CapabilityNotice` (honest limitation text) |
| Security | `LockGate` (wraps protected routes), `PinPad`, `SensitiveText` (hidden until unlocked) |
| Forms | `FbForm` with validation messages under fields and draft auto-save (§3.4 rule 4) |

## 3. Global screen requirements (§3.3)

Every feature screen is built from one template that makes the required states impossible to forget:

| State | Behaviour |
|---|---|
| Loading | Skeleton in the shape of the content; no full-screen spinner |
| Empty | Explains what will appear and offers the action that fills it |
| Error | Plain-language message and Retry; data already on screen stays |
| Success | Snackbar confirmation; Undo for deletes |
| Offline | Thin strip under the app bar; all local actions keep working |
| Validation | Inline, on blur and on submit; the first invalid field is focused |
| Destructive action | Confirmation dialog naming what will be deleted |

No control is shipped without a working action (§3.3, §13.2). A widget test taps every interactive element on each screen and fails on a no-op.

## 4. Navigation

Bottom navigation with six destinations (§3.2). Six exceeds Material's usual maximum of five, so labels are single short words, and the bar is tested at 320 dp width and at font scale 2.0 (see risk R-15).

```text
Home ─┬─ Profile & Settings ─ Goals · Units · Notifications · Quiet hours · App lock
      │                        Sync & account · Permissions & system status
      │                        Digital wellbeing · Export · Delete data · About
      ├─ Notification centre (history)
      ├─ Digital wellbeing
      ├─ Customise dashboard
      └─ Quick actions sheet

Fitness ── Overview · Steps · Walking · Running · Cycling · Gym · History · Records
           └ Workout session · Exercise library · Templates · GPS tracking

Nutrition ─ Diary · Add meal · Food search · Custom food · Saved meals
            Summary · Junk-food history · Water

Health ─── Weight · Body measurements · Sleep · Wellness check-ins
           Bowel records (locked)

Habits ─── Today's routines · Activity list · Activity builder · Reminders
           Timers · Hygiene · Medication · Recovery · Private habits (locked)

Insights ─ Daily · Weekly · Monthly · Custom range
           Weight · Nutrition · Fitness · Sleep · Habits · Records
```

Route guards: onboarding not finished → onboarding; protected route while locked → lock screen, then the requested route.

## 5. Screen inventory

### 5.1 Onboarding (§4.1)

| Step | Content | Notes |
|---|---|---|
| 1 Welcome | Logo, two-line introduction, Get Started | |
| 2 Profile | Name, date of birth, height, current weight, units | Units chosen first so fields show the right unit. Only name is required |
| 3 Goals | Target weight, steps, calories, protein, water, optional fitness goals | Sensible defaults pre-filled; every field skippable |
| 4 Routines | Wake-up time, sleep target, workout days, reminder preferences | |
| 5 Permissions | One card per permission explaining why and when it will be asked | Nothing is requested here (§4.1) |
| 6 Summary | Review with Edit links per section; Finish | Optional "Back up and sync" sign-in offered after Finish (decision D2) |

Progress is saved per step; closing the app resumes where the user stopped.

### 5.2 Home (§4.2)

```text
┌────────────────────────────────────────┐
│ Good morning, {name}         🔔   (👤) │
│ Monday 16 November                     │
├────────────────────────────────────────┤
│  ◯ 4,312        ◯ 1.25 L     ◯ 1,180   │
│  steps          water        kcal      │
│  of 8,000       of 3 L       of 2,100  │
│  Protein 62/140 g · Sleep 7 h 05 · Gym │
├────────────────────────────────────────┤
│ Essential today                    3/5 │
│ ☑ Morning brushing                     │
│ ☐ Bathing                 [Done] [⏰]  │
│ ☐ Evening skincare         due 9:30 PM │
├────────────────────────────────────────┤
│ + Meal  + Water  + Weight  + Workout   │
│ + Activity  + Sleep                    │
├────────────────────────────────────────┤
│ Today                                  │
│ 07:00  Wake up                         │
│ 07:15  Water 250 ml                    │
│ 08:00  Breakfast · 420 kcal            │
└────────────────────────────────────────┘
│ Home  Fitness  Nutrition  Health  Habits  Insights │
```

| Element | Behaviour |
|---|---|
| Daily progress | Steps, water, calories, protein, sleep, workout. Loads from the local database first |
| Essential activities | Today's scheduled essential activities with Mark complete, Snooze, open details |
| Timeline | Everything logged today in time order; private records never appear |
| Quick actions | Meal, water, weight, workout, activity, sleep. Each opens a bottom sheet, saves in one or two taps |
| Customise | Reorder and hide cards, choose metrics; stored in `local_app_settings` |
| Indicators | Notification bell with unread count, sync pill, step-sensor status when attention is needed |

### 5.3 Fitness (§4.3, §5.6–5.8)

| Screen | Key content |
|---|---|
| Overview | Today's steps ring, this week's workouts, shortcuts to start each workout type |
| Steps | Today, goal, percentage, remaining, weekly average, monthly trend, last collection time, sensor status, uncertainty note when applicable, labelled manual adjustment |
| Walking / Running / Cycling | Manual entry form; optional "Track with GPS" (permission asked here); history; records |
| Gym | Start empty workout or from template; live session with exercises, sets, rest timer; reorder; duplicate |
| Exercise library | Search, filter by muscle group and equipment, custom exercise form |
| History | Paged list across workout types, filters |
| Records | Per exercise and per activity type, with the rule that produced each record shown |

### 5.4 Nutrition (§4.4, §5.4–5.5)

| Screen | Key content |
|---|---|
| Diary | Day selector, meals grouped by category, calories and macros against targets, remaining calories |
| Add meal | Category defaults from the time of day; add items by search, recent, saved food, saved meal, or custom; quantity and unit; optional photo and notes; duplicate a past meal |
| Food search | Instant local search over the user's foods and recents; works offline |
| Custom food | Name, serving, calories, macros, category, junk-food category |
| Saved meals | Create from a logged meal; one tap to log again |
| Summary | Calories, protein, carbohydrate, fat, fibre, meal distribution, weekly averages |
| Junk-food history | Filtered view of diary items by junk category; no separate calorie count |
| Water | Quick-add chips (user-editable), custom amount, today's progress, history, weekly and monthly charts, reminder shortcut |

### 5.5 Health (§4.5, §5.2, §5.3, §5.9–5.11)

| Screen | Key content |
|---|---|
| Weight | Current, target, change over the selected range, chart (7 d / 30 d / 90 d / 1 y), list with edit and delete. Copy describes change without claiming fat loss |
| Body measurements | Latest value per type, comparison chart, custom types, private progress photos (locked) |
| Sleep | Add night or nap, overnight editing across dates, weekly and monthly averages, bedtime and wake-time consistency |
| Wellness | 1–5 scales for energy, mood, stress, wellness; several check-ins per day; trends beside sleep and activity |
| Bowel records | Behind the lock. Quick log, history, frequency report, gentle reminder setting. No pressure language |

### 5.6 Habits (§4.6, §5.12–5.16, §5.18–5.19)

| Screen | Key content |
|---|---|
| Today | Scheduled activities with status; unscheduled activities are shown as "not scheduled", never "missed" |
| Activity list | Active and archived; reorder; duplicate; archive; restore; delete |
| Activity builder | Name, description, category, icon, tracking type, priority, target, schedule, reminders, stopwatch, dashboard visibility, private switch |
| Activity detail | History, streak-free consistency view, log entry appropriate to the tracking type |
| Reminders | List by type, create and edit, sound and vibration, snooze, quiet-hour behaviour, test |
| Timers | Stopwatch and countdown, running sessions survive app restarts, history |
| Hygiene | Bath, head wash, brushing, flossing, mouthwash, skincare routines with editable steps |
| Medication | Name, dosage as entered, schedule, taken/missed, history. No dosing advice |
| Recovery | Rest day, soreness and recovery ratings, notes, movement-break reminders |
| Private habits | Behind the lock. Record occurrence, count, note, weekly and monthly trends, custom private types |

### 5.7 Insights (§4.7, §5.20)

| Screen | Key content |
|---|---|
| Daily / Weekly / Monthly / Custom | Report cards per domain for the chosen range, each with a comparison to the previous equal period |
| Domain reports | Weight, measurements, calories and macros, water, steps, walking, running, cycling, gym progression, sleep, wellness, habit completion, junk food, screen time |
| Private history | Shown only after unlock, computed on the device |
| Insight sentences | Descriptive and data-based, for example "Your average daily steps increased by 1,200 compared with the previous week." No causal or diagnostic claims |

### 5.8 Settings

Profile and goals · units · notification channels, sounds and quiet hours · app lock · account and sync status · permissions and system status (each permission, exact-alarm access, battery optimisation, step sensor, last collection, with honest limitation text) · digital wellbeing · export · delete local data · delete account · licences.

## 6. UX rules (§3.4) and how they are met

| # | Rule | Implementation |
|---|---|---|
| 1 | Few taps | Quick-action sheets; water in one tap; repeat-last-meal; workout from template |
| 2 | Quick-add | `QuickAddRow` for water, weight (± 0.1), counts |
| 3 | Optional fields stay optional | Only the minimum is validated; optional fields collapsed under "More" |
| 4 | Preserve interrupted input | Form drafts auto-saved to settings and restored |
| 5 | Sensible defaults | Time = now; meal category from time of day; last-used units and quantities |
| 6 | Clear save confirmation | Snackbar with Undo |
| 7 | Easy history editing | Every list item opens the same form used to create it |
| 8 | Consistent dates and times | One formatter; device locale and 12/24-hour setting |
| 9 | Not too many metrics | Home shows six; the rest sit in their tabs |
| 10 | Customisable dashboard | Reorder, hide, choose metrics |
| 11 | Missed is not failure | Neutral colour and wording; no streak-loss messages |
| 12 | Four distinct states | `ActivityTile` has completed, missed, skipped, not scheduled |
| 13 | Confirm deletes | `ConfirmDialog` |
| 14 | Sensitive notifications hidden | Generic text and secret lock-screen visibility |

## 7. Tone of voice

| Context | Do | Don't |
|---|---|---|
| Missed activity | "Not logged" | "You failed", "Streak broken" |
| Weight change | "Down 0.6 kg since Monday" | "You lost 0.6 kg of fat" |
| Bowel reminder | "Routine check-in" | Anything urging the user to go or to strain |
| Insights | "increased", "compared with" | "because", "caused", "you should" |
| Platform limits | "Android may delay this reminder when battery saver is on" | "Guaranteed" |
| Medication | Show exactly what the user entered | Suggest or alter a dose |

## 8. Accessibility (§10)

| Requirement | Check |
|---|---|
| Font scaling | No clipped or overlapping text at scale 2.0 on a 320 dp-wide screen |
| Semantics | Every control has a label; charts expose a text summary; progress rings announce value and goal |
| Contrast | Token pairs meet AA (4.5:1 text, 3:1 large text and graphics), tested automatically |
| Touch targets | Flutter's tap-target guideline test on every screen |
| Errors | Announced to screen readers and tied to their field |
