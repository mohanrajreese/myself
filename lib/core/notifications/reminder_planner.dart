import '../scheduling/occurrence_calculator.dart';
import '../scheduling/schedule_rule.dart';
import '../utils/local_date.dart';

/// What happens to a reminder that falls in quiet hours (§5.15E).
enum QuietBehaviour {
  defer('defer'),
  suppress('suppress'),
  bypass('bypass');

  const QuietBehaviour(this.code);
  final String code;
  static QuietBehaviour fromCode(String code) => values.firstWhere((b) => b.code == code);
}

/// A quiet period on the wall clock; may cross midnight (22:30–06:30).
final class QuietHours {
  const QuietHours({required this.start, required this.end});
  final int start;
  final int end;

  bool contains(int minute) =>
      start <= end ? minute >= start && minute < end : minute >= start || minute < end;
}

/// The planner's view of a reminder: no titles or text (privacy, §7.1).
final class PlannerReminder {
  const PlannerReminder({
    required this.id,
    required this.rule,
    this.quietBehaviour = QuietBehaviour.defer,
    this.alarm = false,
    this.activityId,
    this.onlyIfIncomplete = false,
    this.startDate,
    this.endDate,
  });

  final String id;
  final ScheduleRule rule;
  final QuietBehaviour quietBehaviour;

  /// Important alarm: exact timing, Important alarms channel.
  final bool alarm;
  final String? activityId;
  final bool onlyIfIncomplete;
  final LocalDate? startDate;
  final LocalDate? endDate;
}

final class PlannedOccurrence {
  const PlannedOccurrence({
    required this.reminderId,
    required this.local,
    required this.fireAt,
    required this.exact,
    this.deferred = false,
  });

  final String reminderId;

  /// The scheduled wall-clock time, before any quiet-hours deferral.
  final LocalOccurrence local;
  final DateTime fireAt;
  final bool exact;
  final bool deferred;

  /// Identifies the occurrence across re-plans, so scheduling is idempotent.
  String get key => '$reminderId@${local.date}T${_hhmm(local.minute)}';

  static String _hhmm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Applies quiet hours, start and end dates, "only if not done" and the
/// alarm budget to produce the occurrences to schedule (05 §A5). Pure.
class ReminderPlanner {
  const ReminderPlanner();

  static const _calc = OccurrenceCalculator();
  static const minimumIntervalWindow = Duration(hours: 48);

  /// [done] holds (activity id, local date) pairs already completed or
  /// skipped. Occurrences are planned from [now] for [days] days.
  List<PlannedOccurrence> plan(
    List<PlannerReminder> reminders, {
    required DateTime now,
    required TimeZoneRules zone,
    int days = 7,
    QuietHours? quietHours,
    Set<(String, LocalDate)> done = const {},
    int budget = 400,
  }) {
    final from = now.toUtc();
    final to = from.add(Duration(days: days));
    final out = <PlannedOccurrence>[];
    for (final r in reminders) {
      if (r.rule.problems.isNotEmpty) continue;
      final seen = <DateTime>{};
      final firstDay = LocalDate.fromDateTime(from.subtract(const Duration(hours: 15)));
      final lastDay = LocalDate.fromDateTime(to.add(const Duration(hours: 15)));
      for (final o in _calc.between(r.rule, firstDay, lastDay)) {
        if (r.startDate != null && o.date.isBefore(r.startDate!)) continue;
        if (r.endDate != null && o.date.isAfter(r.endDate!)) continue;
        if (r.onlyIfIncomplete && r.activityId != null && done.contains((r.activityId!, o.date)))
          continue;

        var fireLocal = o;
        var deferred = false;
        final behaviour = r.alarm && r.quietBehaviour == QuietBehaviour.defer
            ? QuietBehaviour.bypass
            : r.quietBehaviour;
        if (quietHours != null &&
            quietHours.contains(o.minute) &&
            behaviour != QuietBehaviour.bypass) {
          if (behaviour == QuietBehaviour.suppress) continue;
          final endDay = quietHours.start > quietHours.end && o.minute >= quietHours.start
              ? o.date.addDays(1)
              : o.date;
          fireLocal = LocalOccurrence(endDay, quietHours.end);
          deferred = true;
        }
        final fireAt = _calc.resolve(fireLocal, zone);
        if (fireAt.isBefore(from) || !fireAt.isBefore(to)) continue;
        if (!seen.add(fireAt)) continue; // deferred occurrences collapse
        out.add(
          PlannedOccurrence(
            reminderId: r.id,
            local: o,
            fireAt: fireAt,
            exact: r.alarm,
            deferred: deferred,
          ),
        );
      }
    }
    out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    if (out.length <= budget) return out;

    // Over budget: interval reminders keep only their first 48 hours.
    final intervalIds = {
      for (final r in reminders)
        if (r.rule is Interval) r.id,
    };
    final cutoff = from.add(minimumIntervalWindow);
    out.removeWhere((o) => intervalIds.contains(o.reminderId) && !o.fireAt.isBefore(cutoff));
    // Still over: the latest occurrences wait for the next top-up.
    return out.length <= budget ? out : out.sublist(0, budget);
  }
}
