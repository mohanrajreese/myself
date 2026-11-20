import 'package:fitbuddy/features/fitness/domain/workout_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime.utc(2026, 11, 1);
  DateTime day(int n) => t.add(Duration(days: n));

  test('pace and speed', () {
    expect(paceSecondsPerKm(distanceM: 5200, durationS: 1930), 371); // 6:11 /km
    expect(speedMetresPerHour(distanceM: 5200, durationS: 1930), 9699); // 9.7 km/h
    expect(paceSecondsPerKm(distanceM: 0, durationS: 600), isNull);
    expect(speedMetresPerHour(distanceM: 1000, durationS: 0), isNull);
  });

  test('manual cardio entries are checked', () {
    expect(cardioProblems(distanceM: 5000, durationS: 1800, start: t, now: day(1)), isEmpty);
    expect(cardioProblems(distanceM: 5000, durationS: 0, start: t, now: day(1)), contains('duration_required'));
    expect(cardioProblems(distanceM: 5000, durationS: 1800, start: day(2), now: day(1)), contains('in_future'));
  });

  test('strength records: highest load needs a repetition; most reps per load; earliest wins a tie', () {
    final sets = [
      SetRecordInput(sessionId: 'a', at: day(0), loadG: 40000, reps: 12),
      SetRecordInput(sessionId: 'a', at: day(0), loadG: 40000, reps: 10),
      SetRecordInput(sessionId: 'b', at: day(3), loadG: 45000, reps: 8),
      SetRecordInput(sessionId: 'c', at: day(5), loadG: 50000, reps: 0), // failed attempt
      SetRecordInput(sessionId: 'd', at: day(7), loadG: 40000, reps: 12),
    ];
    final records = strengthRecords(sets);
    final load = records.firstWhere((r) => r.kind == RecordKind.highestLoad);
    expect(load.value, 45000);
    final at40 = records.firstWhere((r) => r.kind == RecordKind.mostRepsAtLoad && r.atLoadG == 40000);
    expect(at40.value, 12);
    expect(at40.at, day(0));
    expect(records.where((r) => r.atLoadG == 50000), isEmpty);
  });

  test('duration records for timed exercises', () {
    final records = strengthRecords([
      SetRecordInput(sessionId: 'a', at: day(0), durationS: 60),
      SetRecordInput(sessionId: 'b', at: day(2), durationS: 95),
    ]);
    expect(records.single.kind, RecordKind.longestDuration);
    expect(records.single.value, 95);
  });

  test('cardio records stay within one kind; pace needs at least 1 km', () {
    final sessions = [
      CardioSession(kind: CardioKind.run, at: day(0), distanceM: 5000, durationS: 1800),
      CardioSession(kind: CardioKind.run, at: day(2), distanceM: 800, durationS: 180), // too short for pace
      CardioSession(kind: CardioKind.run, at: day(4), distanceM: 5000, durationS: 1660),
      CardioSession(kind: CardioKind.cycle, at: day(5), distanceM: 30000, durationS: 4000),
    ];
    final run = cardioRecords(CardioKind.run, sessions);
    expect(run.firstWhere((r) => r.kind == RecordKind.longestDistance).value, 5000);
    expect(run.firstWhere((r) => r.kind == RecordKind.fastestPace).value, 332);
    expect(run.firstWhere((r) => r.kind == RecordKind.longestDistance).at, day(0));
    expect(cardioRecords(CardioKind.walk, sessions), isEmpty);
  });
}
