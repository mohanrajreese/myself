import '../../../core/scheduling/occurrence_calculator.dart';
import '../../../core/utils/local_date.dart';
import 'activity.dart';

/// One scheduled occurrence's state. Distinct by design (§3.4 rule 12).
enum SlotState { done, partial, due, missed, skipped }

/// A whole day's state for an activity.
enum DayState { done, inProgress, due, missed, skipped, notScheduled }

typedef Now = ({LocalDate date, int minute});

final class Slot {
  const Slot({
    required this.minute,
    required this.state,
    required this.logs,
    this.progressMilli = 0,
  });
  final int minute;
  final SlotState state;
  final List<ActivityLog> logs;

  /// Sum of the amounts logged against this slot (counts, numbers, durations).
  final int progressMilli;
}

/// What happened to [activity] on [date]: its scheduled slots, each answered
/// by logs, plus any logs made on a day it was not scheduled.
final class ActivityDay {
  const ActivityDay._(this.activity, this.date, this.slots, this.extraLogs);

  final Activity activity;
  final LocalDate date;
  final List<Slot> slots;
  final List<ActivityLog> extraLogs;

  static const _calc = OccurrenceCalculator();

  /// [logs] are this activity's logs for [date]; [now] is the current local
  /// date and minute, which decides between "due" and "not logged".
  factory ActivityDay.of(
    Activity activity,
    LocalDate date,
    List<ActivityLog> logs, {
    required Now now,
  }) {
    final rule = activity.ruleOn(date);
    final times = rule == null ? const <int>[] : _calc.timesOn(rule, date);
    final byLog = <int, List<ActivityLog>>{for (final t in times) t: []};
    final unassigned = <ActivityLog>[];
    for (final log in logs.where((l) => l.localDate == date)) {
      final slot = log.scheduledSlot;
      if (slot != null && byLog.containsKey(slot)) {
        byLog[slot]!.add(log);
      } else {
        unassigned.add(log);
      }
    }
    // Unslotted logs answer the earliest slot that is not yet satisfied.
    final extra = <ActivityLog>[];
    for (final log in unassigned) {
      final open = times.where((t) => !_satisfied(activity, byLog[t]!)).firstOrNull;
      if (open != null) {
        byLog[open]!.add(log);
      } else if (times.isNotEmpty) {
        byLog[times.last]!.add(log);
      } else {
        extra.add(log);
      }
    }
    final slots = [for (final t in times) _slot(activity, date, t, byLog[t]!, now)];
    return ActivityDay._(activity, date, slots, extra);
  }

  bool get scheduled => slots.isNotEmpty;
  int get doneCount => slots.where((s) => s.state == SlotState.done).length;

  DayState get summary {
    if (slots.isEmpty) return DayState.notScheduled;
    final states = slots.map((s) => s.state).toSet();
    if (states.every((s) => s == SlotState.done)) return DayState.done;
    if (states.every((s) => s == SlotState.skipped)) return DayState.skipped;
    if (states.contains(SlotState.due)) return doneCount > 0 ? DayState.inProgress : DayState.due;
    if (doneCount > 0 || states.contains(SlotState.partial)) return DayState.inProgress;
    if (states.contains(SlotState.missed)) return DayState.missed;
    return DayState.skipped;
  }

  static bool _satisfied(Activity a, List<ActivityLog> logs) {
    if (logs.any((l) => l.status == ActivityLogStatus.skipped)) return true;
    final done = logs.where((l) => l.status == ActivityLogStatus.completed).toList();
    if (done.isEmpty) return false;
    if (a.trackingType == TrackingType.checklist) {
      final ticked = {for (final l in done) ...?l.checklistDone};
      return a.checklistItems.every((i) => ticked.contains(i.id));
    }
    final target = a.targetMilli;
    if (target == null || !a.trackingType.hasAmount) return true;
    return done.fold(0, (sum, l) => sum + l.amountMilli(a.trackingType)) >= target;
  }

  static Slot _slot(Activity a, LocalDate date, int minute, List<ActivityLog> logs, Now now) {
    final done = logs.where((l) => l.status == ActivityLogStatus.completed).toList();
    final progress = done.fold(0, (sum, l) => sum + l.amountMilli(a.trackingType));
    final passed = date.isBefore(now.date) || (date == now.date && minute < now.minute);
    final SlotState state;
    if (done.isNotEmpty && _satisfied(a, done)) {
      state = SlotState.done;
    } else if (logs.any((l) => l.status == ActivityLogStatus.skipped)) {
      state = SlotState.skipped;
    } else if (!passed) {
      state = SlotState.due;
    } else {
      state = done.isEmpty ? SlotState.missed : SlotState.partial;
    }
    return Slot(minute: minute, state: state, logs: logs, progressMilli: progress);
  }
}
