import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/fitness/domain/step_attribution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = StepAttributionEngine();
  const ist = 19800; // UTC+5:30
  // Boot 1 started at 2026-11-15 18:00 UTC (23:30 IST on the 15th).
  final boot1 = DateTime.utc(2026, 11, 15, 18);
  final boot2 = DateTime.utc(2026, 11, 16, 12);

  StepReading r(int steps, DateTime at, {int boot = 1, int offset = ist}) {
    final bootAt = boot == 1 ? boot1 : boot2;
    return StepReading(
      cumulativeSteps: steps,
      bootCount: boot,
      elapsedRealtimeMs: at.difference(bootAt).inMilliseconds,
      wallTimeUtc: at,
      utcOffsetSeconds: offset,
    );
  }

  DayStepTotal day(Map<LocalDate, DayStepTotal> m, int d) => m[LocalDate(2026, 11, d)]!;

  test('the first reading is only a baseline; differences are counted', () {
    final m = engine.attribute([
      r(1000, DateTime.utc(2026, 11, 16, 2)), // 07:30 IST
      r(1500, DateTime.utc(2026, 11, 16, 4)),
      r(2300, DateTime.utc(2026, 11, 16, 6)),
    ]);
    expect(day(m, 16).sensorSteps, 1300);
    expect(day(m, 16).uncertainSteps, 0);
    expect(day(m, 16).gaps, isEmpty);
    expect(day(m, 16).lastCollectedAt, DateTime.utc(2026, 11, 16, 6));
  });

  test('a short period across midnight is split by time, without uncertainty', () {
    // 23:55 → 00:05 IST, 100 steps.
    final m = engine.attribute([
      r(0, DateTime.utc(2026, 11, 16, 18, 25)),
      r(100, DateTime.utc(2026, 11, 16, 18, 35)),
    ]);
    expect(day(m, 16).sensorSteps, 50);
    expect(day(m, 17).sensorSteps, 50);
    expect(day(m, 16).uncertainSteps + day(m, 17).uncertainSteps, 0);
  });

  test('a long period across midnight is split by time and marked uncertain on both days', () {
    // 22:30 → 02:30 IST, 800 steps.
    final m = engine.attribute([
      r(0, DateTime.utc(2026, 11, 16, 17)),
      r(800, DateTime.utc(2026, 11, 16, 21)),
    ]);
    expect(day(m, 16).sensorSteps, 300);
    expect(day(m, 17).sensorSteps, 500);
    expect(day(m, 16).uncertainSteps, 300);
    expect(day(m, 17).uncertainSteps, 500);
  });

  test('after a reboot, steps since boot count and the time before it is a gap', () {
    final m = engine.attribute([
      r(4000, DateTime.utc(2026, 11, 16, 6)), // 11:30 IST
      r(4600, DateTime.utc(2026, 11, 16, 8)),
      r(250, DateTime.utc(2026, 11, 16, 13), boot: 2), // booted 17:30 IST
    ]);
    expect(day(m, 16).sensorSteps, 850);
    expect(day(m, 16).gaps, hasLength(1));
    expect(day(m, 16).gaps.single.start, DateTime.utc(2026, 11, 16, 8));
    expect(day(m, 16).gaps.single.end, boot2);
    expect(day(m, 16).hasGap, isTrue);
  });

  test('readings from different boots are never subtracted', () {
    final m = engine.attribute([
      r(9000, DateTime.utc(2026, 11, 16, 6)),
      r(100, DateTime.utc(2026, 11, 16, 13), boot: 2),
    ]);
    expect(day(m, 16).sensorSteps, 100);
  });

  test('a counter that goes backwards in the same boot is counted from zero and uncertain', () {
    final m = engine.attribute([
      r(5000, DateTime.utc(2026, 11, 16, 6)),
      r(300, DateTime.utc(2026, 11, 16, 7)),
    ]);
    expect(day(m, 16).sensorSteps, 300);
    expect(day(m, 16).uncertainSteps, 300);
  });

  test('an implausible rate is kept but marked uncertain', () {
    final m = engine.attribute([
      r(0, DateTime.utc(2026, 11, 16, 6)),
      r(4000, DateTime.utc(2026, 11, 16, 6, 5)), // 13 steps a second
    ]);
    expect(day(m, 16).sensorSteps, 4000);
    expect(day(m, 16).uncertainSteps, 4000);
  });

  test('each period uses the offset in force when it started (timezone change)', () {
    // In IST until 18:20 UTC (23:50 IST), then the phone moves to UTC.
    final m = engine.attribute([
      r(0, DateTime.utc(2026, 11, 16, 18)),
      r(
        200,
        DateTime.utc(2026, 11, 16, 18, 20),
        offset: 0,
      ), // forced reading at the change, now UTC
      r(500, DateTime.utc(2026, 11, 16, 19), offset: 0),
    ]);
    // First period: 23:30 → 23:50 IST, all on the 16th.
    // Second period: 18:20 → 19:00 UTC, still the 16th in UTC.
    expect(day(m, 16).sensorSteps, 500);
    expect(m.containsKey(LocalDate(2026, 11, 17)), isFalse);
  });

  test('readings arrive in any order and a duplicate changes nothing', () {
    final a = r(1000, DateTime.utc(2026, 11, 16, 2));
    final b = r(1500, DateTime.utc(2026, 11, 16, 4));
    final c = r(2300, DateTime.utc(2026, 11, 16, 6));
    expect(day(engine.attribute([c, a, b, b]), 16).sensorSteps, 1300);
  });

  test('split rounding keeps every step', () {
    final m = engine.attribute([
      r(0, DateTime.utc(2026, 11, 16, 18, 27)),
      r(7, DateTime.utc(2026, 11, 16, 18, 33)),
    ]);
    expect(day(m, 16).sensorSteps + day(m, 17).sensorSteps, 7);
  });
}
