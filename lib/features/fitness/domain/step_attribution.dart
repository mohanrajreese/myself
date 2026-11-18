import '../../../core/utils/local_date.dart';

/// One reading of the phone's cumulative step counter (05 §B3).
final class StepReading {
  const StepReading({
    required this.cumulativeSteps,
    required this.bootCount,
    required this.elapsedRealtimeMs,
    required this.wallTimeUtc,
    required this.utcOffsetSeconds,
  });

  /// Steps since the phone booted, as reported by the sensor.
  final int cumulativeSteps;
  final int bootCount;

  /// Milliseconds since boot when the reading was taken.
  final int elapsedRealtimeMs;
  final DateTime wallTimeUtc;

  /// The phone's UTC offset at the reading, so each period lands on the day
  /// it was on the phone's calendar.
  final int utcOffsetSeconds;

  DateTime get bootTime => wallTimeUtc.subtract(Duration(milliseconds: elapsedRealtimeMs));

  @override
  bool operator ==(Object other) =>
      other is StepReading &&
      other.cumulativeSteps == cumulativeSteps &&
      other.bootCount == bootCount &&
      other.elapsedRealtimeMs == elapsedRealtimeMs;
  @override
  int get hashCode => Object.hash(cumulativeSteps, bootCount, elapsedRealtimeMs);
}

/// A stretch of time whose steps are unknown (phone off, counter reset).
final class StepGap {
  const StepGap(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

/// Steps attributed to one local day.
final class DayStepTotal {
  DayStepTotal(this.date);
  final LocalDate date;
  int sensorSteps = 0;

  /// Part of [sensorSteps] whose day or count is not certain.
  int uncertainSteps = 0;
  final List<StepGap> gaps = [];
  DateTime? lastCollectedAt;

  bool get hasGap => gaps.isNotEmpty;
  bool get isUncertain => uncertainSteps > 0 || hasGap;
}

/// Ordered readings → daily totals (05 §B4). Pure. Never shows the
/// cumulative value as today, never subtracts across boots, never fills
/// unknown periods with estimates.
class StepAttributionEngine {
  const StepAttributionEngine();

  /// A period longer than this that crosses midnight is split by time and
  /// marked uncertain.
  static const shortSplit = Duration(minutes: 10);

  /// Sustained rates above this are physically implausible.
  static const maxStepsPerSecond = 5;

  Map<LocalDate, DayStepTotal> attribute(Iterable<StepReading> readings) {
    final sorted = readings.toSet().toList()
      ..sort((a, b) {
        final byBoot = a.bootCount.compareTo(b.bootCount);
        return byBoot != 0 ? byBoot : a.elapsedRealtimeMs.compareTo(b.elapsedRealtimeMs);
      });
    final days = <LocalDate, DayStepTotal>{};
    DayStepTotal dayOf(DateTime utc, int offsetS) {
      final date = LocalDate.ofInstant(utc, Duration(seconds: offsetS));
      return days.putIfAbsent(date, () => DayStepTotal(date));
    }

    for (var i = 1; i < sorted.length; i++) {
      final r1 = sorted[i - 1];
      final r2 = sorted[i];
      final DateTime start;
      final int steps;
      final int offset;
      var uncertain = false;
      if (r2.bootCount != r1.bootCount) {
        // Steps since the new boot; what happened before it is unknown.
        steps = r2.cumulativeSteps;
        final boot = r2.bootTime.isBefore(r1.wallTimeUtc) ? r1.wallTimeUtc : r2.bootTime;
        dayOf(r1.wallTimeUtc, r1.utcOffsetSeconds).gaps.add(StepGap(r1.wallTimeUtc, boot));
        start = boot;
        offset = r2.utcOffsetSeconds;
      } else if (r2.cumulativeSteps < r1.cumulativeSteps) {
        steps = r2.cumulativeSteps;
        start = r1.wallTimeUtc;
        offset = r1.utcOffsetSeconds;
        uncertain = true;
      } else {
        steps = r2.cumulativeSteps - r1.cumulativeSteps;
        start = r1.wallTimeUtc;
        offset = r1.utcOffsetSeconds;
      }
      final end = r2.wallTimeUtc.isBefore(start) ? start : r2.wallTimeUtc;
      final seconds = end.difference(start).inMilliseconds / 1000;
      if (steps > 0 && seconds > 0 && steps / seconds > maxStepsPerSecond) uncertain = true;
      _assign(steps, start, end, offset, uncertain, dayOf);
      final last = dayOf(r2.wallTimeUtc, r2.utcOffsetSeconds);
      if (last.lastCollectedAt == null || r2.wallTimeUtc.isAfter(last.lastCollectedAt!)) {
        last.lastCollectedAt = r2.wallTimeUtc;
      }
    }
    return days;
  }

  void _assign(
    int steps,
    DateTime start,
    DateTime end,
    int offsetS,
    bool uncertain,
    DayStepTotal Function(DateTime, int) dayOf,
  ) {
    if (steps == 0) return;
    final offset = Duration(seconds: offsetS);
    // Local-day segments of [start, end].
    final segments = <(DateTime, Duration)>[];
    var cursor = start;
    while (true) {
      final local = cursor.add(offset);
      final nextMidnight = DateTime.utc(local.year, local.month, local.day + 1).subtract(offset);
      if (!nextMidnight.isBefore(end)) {
        segments.add((cursor, end.difference(cursor)));
        break;
      }
      segments.add((cursor, nextMidnight.difference(cursor)));
      cursor = nextMidnight;
    }
    if (segments.length == 1) {
      final d = dayOf(start, offsetS)..sensorSteps += steps;
      if (uncertain) d.uncertainSteps += steps;
      return;
    }
    final total = end.difference(start).inMilliseconds;
    final splitUncertain = uncertain || end.difference(start) > shortSplit;
    // Largest-remainder split, so every step is kept.
    final exact = [for (final s in segments) steps * s.$2.inMilliseconds / total];
    final shares = [for (final e in exact) e.floor()];
    var left = steps - shares.fold(0, (a, b) => a + b);
    final order = List.generate(segments.length, (i) => i)
      ..sort((a, b) => (exact[b] - shares[b]).compareTo(exact[a] - shares[a]));
    for (final i in order) {
      if (left == 0) break;
      shares[i]++;
      left--;
    }
    for (var i = 0; i < segments.length; i++) {
      final d = dayOf(segments[i].$1, offsetS)..sensorSteps += shares[i];
      if (splitUncertain) d.uncertainSteps += shares[i];
    }
  }
}
