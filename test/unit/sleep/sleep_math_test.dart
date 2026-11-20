import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/sleep/domain/sleep_math.dart';
import 'package:flutter_test/flutter_test.dart';

SleepPeriod night(DateTime bed, DateTime wake) =>
    SleepPeriod(kind: SleepKind.night, start: bed, end: wake);

void main() {
  test('an overnight sleep is measured across midnight', () {
    final sleep = night(DateTime(2026, 11, 15, 23, 10), DateTime(2026, 11, 16, 6, 15));
    expect(sleep.duration, const Duration(hours: 7, minutes: 5));
    expect(sleep.wakeDate, LocalDate(2026, 11, 16));
  });

  test('a night belongs to the day the user woke up; a nap to its own day', () {
    expect(
      night(DateTime(2026, 11, 16, 0, 5), DateTime(2026, 11, 16, 6, 35)).wakeDate,
      LocalDate(2026, 11, 16),
    );
    final nap = SleepPeriod(
      kind: SleepKind.nap,
      start: DateTime(2026, 11, 15, 14, 30),
      end: DateTime(2026, 11, 15, 14, 55),
    );
    expect(nap.wakeDate, LocalDate(2026, 11, 15));
    expect(nap.duration, const Duration(minutes: 25));
  });

  test('rejects an end before the start, a zero length, and more than 24 hours', () {
    expect(
      validateSleep(DateTime(2026, 11, 16, 7), DateTime(2026, 11, 16, 6))?.code,
      'end_before_start',
    );
    expect(
      validateSleep(DateTime(2026, 11, 16, 7), DateTime(2026, 11, 16, 7))?.code,
      'end_before_start',
    );
    expect(validateSleep(DateTime(2026, 11, 15, 6), DateTime(2026, 11, 16, 7))?.code, 'too_long');
    expect(validateSleep(DateTime(2026, 11, 15, 23), DateTime(2026, 11, 16, 6)), isNull);
  });

  test('average night length ignores naps and days without a record', () {
    final periods = [
      night(DateTime(2026, 11, 13, 23), DateTime(2026, 11, 14, 6)), // 7 h
      night(DateTime(2026, 11, 14, 23, 30), DateTime(2026, 11, 15, 6)), // 6 h 30
      SleepPeriod(
        kind: SleepKind.nap,
        start: DateTime(2026, 11, 15, 14),
        end: DateTime(2026, 11, 15, 15),
      ),
      night(DateTime(2026, 11, 15, 23), DateTime(2026, 11, 16, 6, 30)), // 7 h 30
    ];
    expect(averageNightLength(periods), const Duration(hours: 7));
    expect(averageNightLength(const []), isNull);
  });

  test('two sleeps ending on the same day are added before averaging', () {
    final periods = [
      night(DateTime(2026, 11, 15, 22), DateTime(2026, 11, 16, 2)), // 4 h
      night(DateTime(2026, 11, 16, 3), DateTime(2026, 11, 16, 6)), // 3 h, same wake day
      night(DateTime(2026, 11, 16, 23), DateTime(2026, 11, 17, 6)), // 7 h
    ];
    expect(averageNightLength(periods), const Duration(hours: 7));
  });

  test('usual bedtime averages correctly around midnight', () {
    final periods = [
      night(DateTime(2026, 11, 13, 23, 30), DateTime(2026, 11, 14, 6, 30)),
      night(DateTime(2026, 11, 15, 0, 30), DateTime(2026, 11, 15, 6, 30)),
    ];
    final habit = sleepConsistency(periods)!;
    expect(habit.usualBedtimeMinutes, 0); // midnight, not noon
    expect(habit.usualWakeMinutes, 6 * 60 + 30);
    expect(habit.bedtimeSpreadMinutes, 30);
    expect(habit.wakeSpreadMinutes, 0);
  });

  test('consistency needs at least two nights', () {
    expect(
      sleepConsistency([night(DateTime(2026, 11, 15, 23), DateTime(2026, 11, 16, 6))]),
      isNull,
    );
  });
}
