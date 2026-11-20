/// Cardio and strength calculations (§5.7, §5.8). Integer base units:
/// metres, seconds, grams.
library;

enum CardioKind { walk, run, cycle }

/// Seconds per kilometre; null without distance or time.
int? paceSecondsPerKm({required int distanceM, required int durationS}) =>
    distanceM <= 0 || durationS <= 0 ? null : (durationS * 1000 / distanceM).round();

/// Metres per hour (km/h × 1000); null without distance or time.
int? speedMetresPerHour({required int distanceM, required int durationS}) =>
    distanceM <= 0 || durationS <= 0 ? null : (distanceM * 3600 / durationS).round();

/// Checks a manual cardio entry; codes for the UI.
List<String> cardioProblems({
  required int distanceM,
  required int durationS,
  required DateTime start,
  required DateTime now,
}) => [
  if (durationS <= 0) 'duration_required',
  if (durationS > 24 * 3600) 'duration_too_long',
  if (distanceM < 0 || distanceM > 500000) 'distance_out_of_range',
  if (start.isAfter(now)) 'in_future',
];

/// One completed set.
final class SetRecordInput {
  const SetRecordInput({
    required this.sessionId,
    required this.at,
    this.loadG,
    this.reps,
    this.durationS,
    this.distanceM,
  });
  final String sessionId;
  final DateTime at;
  final int? loadG;
  final int? reps;
  final int? durationS;
  final int? distanceM;
}

final class PersonalRecord {
  const PersonalRecord({required this.kind, required this.value, required this.at, this.atLoadG});
  final RecordKind kind;

  /// Grams, repetitions, seconds, metres or seconds per km, by [kind].
  final int value;
  final DateTime at;

  /// For [RecordKind.mostRepsAtLoad]: the load.
  final int? atLoadG;
}

enum RecordKind { highestLoad, mostRepsAtLoad, longestDuration, longestDistance, fastestPace }

/// Records for one exercise (06 S-11 rules). Never mixes exercises or units:
/// callers pass one exercise's completed sets only.
List<PersonalRecord> strengthRecords(List<SetRecordInput> sets) {
  final out = <PersonalRecord>[];
  PersonalRecord? best(
    RecordKind kind,
    Iterable<SetRecordInput> from,
    int? Function(SetRecordInput) value, {
    int? load,
  }) {
    SetRecordInput? top;
    for (final s in from) {
      final v = value(s);
      if (v == null || v <= 0) continue;
      final current = top == null ? null : value(top);
      // Ties keep the earliest, so a record is the first time it was reached.
      if (current == null || v > current || (v == current && s.at.isBefore(top!.at))) top = s;
    }
    return top == null
        ? null
        : PersonalRecord(kind: kind, value: value(top)!, at: top.at, atLoadG: load);
  }

  final withReps = sets.where((s) => (s.reps ?? 0) >= 1);
  final load = best(RecordKind.highestLoad, withReps, (s) => s.loadG);
  if (load != null) out.add(load);
  final loads = {for (final s in withReps) ?s.loadG}.toList()..sort();
  for (final l in loads.reversed) {
    final r = best(
      RecordKind.mostRepsAtLoad,
      withReps.where((s) => s.loadG == l),
      (s) => s.reps,
      load: l,
    );
    if (r != null) out.add(r);
  }
  final duration = best(RecordKind.longestDuration, sets, (s) => s.durationS);
  if (duration != null) out.add(duration);
  final distance = best(RecordKind.longestDistance, sets, (s) => s.distanceM);
  if (distance != null) out.add(distance);
  return out;
}

/// A finished walk, run or ride.
final class CardioSession {
  const CardioSession({
    required this.kind,
    required this.at,
    required this.distanceM,
    required this.durationS,
  });
  final CardioKind kind;
  final DateTime at;
  final int distanceM;
  final int durationS;
}

/// Records for one cardio kind: longest distance, longest duration, and
/// fastest pace over sessions of at least 1 km.
List<PersonalRecord> cardioRecords(CardioKind kind, List<CardioSession> sessions) {
  final mine = sessions.where((s) => s.kind == kind).toList()..sort((a, b) => a.at.compareTo(b.at));
  final out = <PersonalRecord>[];
  CardioSession? longest;
  CardioSession? longestTime;
  CardioSession? fastest;
  int? fastestPace;
  for (final s in mine) {
    if (s.distanceM > 0 && (longest == null || s.distanceM > longest.distanceM)) longest = s;
    if (s.durationS > 0 && (longestTime == null || s.durationS > longestTime.durationS)) {
      longestTime = s;
    }
    final pace = s.distanceM >= 1000
        ? paceSecondsPerKm(distanceM: s.distanceM, durationS: s.durationS)
        : null;
    if (pace != null && (fastestPace == null || pace < fastestPace)) {
      fastestPace = pace;
      fastest = s;
    }
  }
  if (longest != null) {
    out.add(
      PersonalRecord(kind: RecordKind.longestDistance, value: longest.distanceM, at: longest.at),
    );
  }
  if (longestTime != null) {
    out.add(
      PersonalRecord(
        kind: RecordKind.longestDuration,
        value: longestTime.durationS,
        at: longestTime.at,
      ),
    );
  }
  if (fastest != null) {
    out.add(PersonalRecord(kind: RecordKind.fastestPace, value: fastestPace!, at: fastest.at));
  }
  return out;
}
