import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/local_date.dart';

enum SleepKind {
  night('night'),
  nap('nap');

  const SleepKind(this.code);
  final String code;

  static SleepKind fromCode(String code) => code == 'nap' ? SleepKind.nap : SleepKind.night;
}

/// A recorded sleep, in the user's wall-clock time.
@immutable
final class SleepPeriod {
  const SleepPeriod({required this.kind, required this.start, required this.end});

  final SleepKind kind;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  /// The day this sleep counts towards: the day the user woke up.
  LocalDate get wakeDate => LocalDate.fromDateTime(end);
}

ValidationFailure? validateSleep(DateTime start, DateTime end) {
  if (!end.isAfter(start)) return const ValidationFailure('endAt', 'end_before_start');
  if (end.difference(start) > const Duration(hours: 24)) {
    return const ValidationFailure('endAt', 'too_long');
  }
  return null;
}

/// Mean night sleep per day that has a night record. Naps are not counted.
Duration? averageNightLength(Iterable<SleepPeriod> periods) {
  final perDay = <LocalDate, Duration>{};
  for (final period in periods.where((p) => p.kind == SleepKind.night)) {
    perDay.update(period.wakeDate, (d) => d + period.duration, ifAbsent: () => period.duration);
  }
  if (perDay.isEmpty) return null;
  final totalSeconds = perDay.values.fold<int>(0, (sum, d) => sum + d.inSeconds);
  return Duration(seconds: (totalSeconds / perDay.length).round());
}

typedef SleepConsistency = ({
  int usualBedtimeMinutes,
  int usualWakeMinutes,
  int bedtimeSpreadMinutes,
  int wakeSpreadMinutes,
});

/// Usual bedtime and wake-up time (minutes after midnight) and how much each
/// varies on average. Times are averaged on the clock face, so 23:30 and
/// 00:30 average to midnight. Null with fewer than two nights.
SleepConsistency? sleepConsistency(Iterable<SleepPeriod> periods) {
  final nights = periods.where((p) => p.kind == SleepKind.night).toList();
  if (nights.length < 2) return null;
  final beds = [for (final n in nights) n.start.hour * 60 + n.start.minute];
  final wakes = [for (final n in nights) n.end.hour * 60 + n.end.minute];
  final bed = _clockMean(beds);
  final wake = _clockMean(wakes);
  return (
    usualBedtimeMinutes: bed,
    usualWakeMinutes: wake,
    bedtimeSpreadMinutes: _meanDeviation(beds, bed),
    wakeSpreadMinutes: _meanDeviation(wakes, wake),
  );
}

const _day = 1440;

int _clockMean(List<int> minutes) {
  var x = 0.0;
  var y = 0.0;
  for (final m in minutes) {
    final angle = 2 * math.pi * m / _day;
    x += math.cos(angle);
    y += math.sin(angle);
  }
  final mean = (math.atan2(y, x) / (2 * math.pi) * _day).round();
  return (mean % _day + _day) % _day;
}

int _meanDeviation(List<int> minutes, int centre) {
  var total = 0;
  for (final m in minutes) {
    final diff = (m - centre).abs() % _day;
    total += math.min(diff, _day - diff);
  }
  return (total / minutes.length).round();
}
