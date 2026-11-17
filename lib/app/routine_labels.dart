/// Display names and badges for activities and reminders.
library;

import 'package:material_ui/material_ui.dart';

import '../core/widgets/fb_format.dart';
import '../core/scheduling/schedule_rule.dart';
import '../core/widgets/l10n.dart';
import '../core/widgets/tokens.dart';
import '../features/activities/domain/activity.dart';
import '../features/activities/domain/activity_day.dart';

String minuteLabel(BuildContext context, int minute) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

String trackingTypeName(AppLocalizations l, TrackingType t) => switch (t) {
  TrackingType.boolean => l.trackBoolean,
  TrackingType.count => l.trackCount,
  TrackingType.numeric => l.trackNumeric,
  TrackingType.duration => l.trackDuration,
  TrackingType.stopwatch => l.trackStopwatch,
  TrackingType.eventLog => l.trackEventLog,
  TrackingType.checklist => l.trackChecklist,
};

String trackingTypeHelp(AppLocalizations l, TrackingType t) => switch (t) {
  TrackingType.boolean => l.trackBooleanHelp,
  TrackingType.count => l.trackCountHelp,
  TrackingType.numeric => l.trackNumericHelp,
  TrackingType.duration => l.trackDurationHelp,
  TrackingType.stopwatch => l.trackStopwatchHelp,
  TrackingType.eventLog => l.trackEventLogHelp,
  TrackingType.checklist => l.trackChecklistHelp,
};

const activityCategories = ['health', 'hygiene', 'movement', 'mind', 'home', 'work', 'other'];

String categoryName(AppLocalizations l, String code) => switch (code) {
  'health' => l.catHealth,
  'hygiene' => l.catHygiene,
  'movement' => l.catMovement,
  'mind' => l.catMind,
  'home' => l.catHome,
  'work' => l.catWork,
  _ => l.catOther,
};

const activityIcons = <String, IconData>{
  'check': Icons.check_circle_outline_rounded,
  'walk': Icons.directions_walk_rounded,
  'water': Icons.water_drop_outlined,
  'brush': Icons.clean_hands_outlined,
  'pill': Icons.medication_outlined,
  'bed': Icons.bedtime_outlined,
  'book': Icons.menu_book_outlined,
  'run': Icons.directions_run_rounded,
  'yoga': Icons.self_improvement_rounded,
  'food': Icons.restaurant_outlined,
  'skin': Icons.face_retouching_natural_outlined,
  'home': Icons.home_outlined,
};

IconData activityIcon(String key) => activityIcons[key] ?? Icons.check_circle_outline_rounded;

String weekdayShort(BuildContext context, int isoWeekday) =>
    MaterialLocalizations.of(context).narrowWeekdays[isoWeekday % 7];

String weekdaysLabel(BuildContext context, Set<int> days) {
  final l = context.l10n;
  if (days.length == 7) return l.everyDay;
  if (days.length == 5 && days.containsAll({1, 2, 3, 4, 5})) return l.weekdaysOnly;
  if (days.length == 2 && days.containsAll({6, 7})) return l.weekendsOnly;
  final names = MaterialLocalizations.of(context);
  final sorted = days.toList()..sort();
  return sorted
      .map(
        (d) => names.formatMediumDate(DateTime(2026, 11, 15 + d)).split(',').first.split(' ').first,
      )
      .join(', ');
}

/// "Daily · 7:00 AM", "Every 90 min, 8:00 AM–8:00 PM", …
String scheduleSummary(BuildContext context, ScheduleRule rule) {
  final l = context.l10n;
  String times(List<int> ts) => ts.map((t) => minuteLabel(context, t)).join(', ');
  return switch (rule) {
    OneTime(:final date, :final time) => l.scheduleOnce(
      context.shortDate(date),
      minuteLabel(context, time),
    ),
    Daily(times: final ts) => l.scheduleDaily(times(ts)),
    Weekdays(:final weekdays, times: final ts) =>
      '${weekdaysLabel(context, weekdays)} · ${times(ts)}',
    Weekly(:final everyWeeks, :final weekdays, times: final ts) => l.scheduleEveryWeeks(
      everyWeeks,
      weekdaysLabel(context, weekdays),
      times(ts),
    ),
    Monthly(:final day, :final nth, times: final ts) =>
      day != null
          ? l.scheduleMonthlyDay(day, times(ts))
          : l.scheduleMonthlyNth(nth ?? 1, times(ts)),
    EveryNDays(:final days, times: final ts) => l.scheduleEveryDays(days, times(ts)),
    IntervalRule(:final everyMinutes, :final start, :final end, :final weekdays) =>
      l.scheduleInterval(everyMinutes, minuteLabel(context, start), minuteLabel(context, end)) +
          (weekdays == null ? '' : ' · ${weekdaysLabel(context, weekdays)}'),
  };
}

/// Icon plus word for a scheduled occurrence; never colour alone (04 §1.1).
class SlotBadge extends StatelessWidget {
  const SlotBadge(this.state, {this.text, super.key});
  final SlotState? state;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final (IconData icon, Color color, String label) = switch (state) {
      SlotState.done => (Icons.check_rounded, c.success, l.stateDone),
      SlotState.partial => (Icons.timelapse_rounded, c.textSecondary, l.statePartial),
      SlotState.due => (Icons.schedule_rounded, c.primary, l.stateDue),
      SlotState.missed => (Icons.radio_button_unchecked_rounded, c.textSecondary, l.stateMissed),
      SlotState.skipped => (Icons.redo_rounded, c.textSecondary, l.stateSkipped),
      null => (Icons.remove_rounded, c.textSecondary, l.stateNotScheduled),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: FbSpace.xs),
        Flexible(
          child: Text(
            text ?? label,
            style: context.text.caption.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
