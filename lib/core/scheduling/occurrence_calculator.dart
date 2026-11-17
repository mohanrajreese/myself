import '../utils/local_date.dart';
import 'schedule_rule.dart';

/// A wall-clock occurrence: a calendar day and minutes after midnight.
final class LocalOccurrence implements Comparable<LocalOccurrence> {
  const LocalOccurrence(this.date, this.minute);
  final LocalDate date;
  final int minute;

  @override
  int compareTo(LocalOccurrence other) {
    final byDate = date.compareTo(other.date);
    return byDate != 0 ? byDate : minute.compareTo(other.minute);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalOccurrence && other.date == date && other.minute == minute;
  @override
  int get hashCode => Object.hash(date, minute);

  @override
  String toString() =>
      '$date ${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

/// The UTC offset in force at an instant. Production code wraps the
/// `timezone` database; tests use fixed or synthetic zones.
abstract interface class TimeZoneRules {
  Duration offsetAt(DateTime instant);
}

/// Schedule rule + range → occurrences (05 §A3). Pure; no I/O.
class OccurrenceCalculator {
  const OccurrenceCalculator();

  /// Wall-clock occurrences on the days [from] to [to], both included,
  /// in order.
  List<LocalOccurrence> between(ScheduleRule rule, LocalDate from, LocalDate to) {
    final out = <LocalOccurrence>[];
    for (var day = from; !day.isAfter(to); day = day.addDays(1)) {
      for (final minute in timesOn(rule, day)) {
        out.add(LocalOccurrence(day, minute));
      }
    }
    return out;
  }

  /// Whether [rule] has at least one occurrence on [day]. A day without one
  /// is "not scheduled", never "missed" (§5.14).
  bool isScheduledOn(ScheduleRule rule, LocalDate day) => timesOn(rule, day).isNotEmpty;

  /// The sorted minutes after midnight at which [rule] occurs on [day].
  List<int> timesOn(ScheduleRule rule, LocalDate day) => switch (rule) {
    OneTime(:final date, :final time) => date == day ? [time] : const [],
    Daily(:final times) => times,
    Weekdays(:final weekdays, :final times) => weekdays.contains(day.weekday) ? times : const [],
    Weekly(:final everyWeeks, :final anchor, :final weekdays, :final times) =>
      weekdays.contains(day.weekday) &&
              _mondayOf(day).daysSince(_mondayOf(anchor)) ~/ 7 % everyWeeks == 0
          ? times
          : const [],
    Monthly() => _monthlyMatches(rule, day) ? rule.times : const [],
    EveryNDays(:final days, :final anchor, :final times) =>
      day.daysSince(anchor) % days == 0 ? times : const [],
    Interval(:final everyMinutes, :final start, :final end, :final weekdays) =>
      weekdays != null && !weekdays.contains(day.weekday)
          ? const []
          : [for (var m = start; m <= end; m += everyMinutes) m],
  };

  /// Occurrences as instants in [zone], from [from] (included) to [to]
  /// (excluded). A wall time that does not exist on a DST day moves to the
  /// first valid minute after the gap; one that occurs twice fires once, at
  /// the first.
  List<DateTime> instants(
    ScheduleRule rule, {
    required DateTime from,
    required DateTime to,
    required TimeZoneRules zone,
  }) {
    // Local days that can hold an instant in the range (offsets are within ±14 h).
    final firstDay = LocalDate.fromDateTime(from.toUtc().subtract(const Duration(hours: 15)));
    final lastDay = LocalDate.fromDateTime(to.toUtc().add(const Duration(hours: 15)));
    final seen = <DateTime>{};
    final out = <DateTime>[];
    for (final o in between(rule, firstDay, lastDay)) {
      final instant = resolve(o, zone);
      if (instant.isBefore(from) || !instant.isBefore(to)) continue;
      if (seen.add(instant)) out.add(instant);
    }
    out.sort();
    return out;
  }

  /// The instant at which wall-clock [o] happens in [zone].
  DateTime resolve(LocalOccurrence o, TimeZoneRules zone) {
    final wall = DateTime.utc(o.date.year, o.date.month, o.date.day, o.minute ~/ 60, o.minute % 60);
    final before = zone.offsetAt(wall.subtract(const Duration(days: 1)));
    final after = zone.offsetAt(wall.add(const Duration(days: 1)));
    final candidates = <DateTime>[
      for (final offset in {before, zone.offsetAt(wall), after})
        if (zone.offsetAt(wall.subtract(offset)) == offset) wall.subtract(offset),
    ]..sort();
    if (candidates.isNotEmpty) return candidates.first;

    // In a gap: find the first instant that uses the later offset.
    var low = wall.subtract(after > before ? after : before);
    var high = wall.subtract(after > before ? before : after);
    while (high.difference(low) > const Duration(minutes: 1)) {
      final mid = low.add(Duration(microseconds: high.difference(low).inMicroseconds ~/ 2));
      if (zone.offsetAt(mid) == after) {
        high = mid;
      } else {
        low = mid;
      }
    }
    final minuteMicros = const Duration(minutes: 1).inMicroseconds;
    final micros = high.microsecondsSinceEpoch;
    final rounded = (micros + minuteMicros - 1) ~/ minuteMicros * minuteMicros;
    return DateTime.fromMicrosecondsSinceEpoch(rounded, isUtc: true);
  }

  static LocalDate _mondayOf(LocalDate day) => day.addDays(1 - day.weekday);

  static bool _monthlyMatches(Monthly rule, LocalDate day) {
    final lastDay = DateTime.utc(day.year, day.month + 1, 0).day;
    if (rule.day case final d?) return day.day == (d > lastDay ? lastDay : d);
    if (day.weekday != rule.weekday) return false;
    final nth = rule.nth!;
    return nth == -1 ? day.day + 7 > lastDay : (day.day - 1) ~/ 7 + 1 == nth;
  }
}
