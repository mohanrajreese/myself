import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/errors/failure.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/fitness/data/drift_step_repository.dart';
import 'package:fitbuddy/features/fitness/domain/step_attribution.dart';
import 'package:fitbuddy/features/fitness/domain/step_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late DriftStepRepository repo;
  final boot = DateTime.utc(2026, 11, 16);
  final day = LocalDate(2026, 11, 16);

  RawStepReading r(int steps, int hour) => (
    reading: StepReading(
      cumulativeSteps: steps,
      bootCount: 1,
      elapsedRealtimeMs: hour * 3600 * 1000,
      wallTimeUtc: boot.add(Duration(hours: hour)),
      utcOffsetSeconds: 0,
    ),
    tz: 'UTC',
    source: 'worker',
  );

  setUp(() {
    db = memoryDatabase();
    repo = DriftStepRepository(
      db,
      clock: MutableClock(DateTime.utc(2026, 11, 16, 20)).clock,
      ids: SequentialIds(),
    );
  });
  tearDown(() => db.close());

  test('readings become one daily total and one synced step log', () async {
    await repo.ingest([r(100, 7), r(2100, 9)]);
    await repo.ingest([r(5100, 12), r(2100, 9)]); // duplicate ignored
    final d = (await repo.watchDay(day).first)!;
    expect(d.sensorSteps, 5000);
    expect(d.total, 5000);
    expect(d.lastCollectedAt, boot.add(const Duration(hours: 12)));
    final logs = await db.select(db.stepLogs).get();
    expect(logs.single.steps, 5000);
    expect(logs.single.source, 'phone_sensor');
    expect((await db.select(db.syncOutbox).get()).single.entityTable, 'step_logs');
    expect(await db.select(db.localStepReadings).get(), hasLength(3));
  });

  test('an adjustment is kept separately, labelled, and survives a recompute', () async {
    await repo.ingest([r(0, 7), r(3000, 9)]);
    await repo.adjust(day, 1200);
    await repo.ingest([r(4000, 11)]);
    final d = (await repo.watchDay(day).first)!;
    expect(d.sensorSteps, 4000);
    expect(d.manualAdjustment, 1200);
    expect(d.total, 5200);
    expect((await db.select(db.stepLogs).get()).single.source, 'phone_sensor_adjusted');
  });

  test('removing more than was counted stops at zero; zero is refused', () async {
    await repo.ingest([r(0, 7), r(300, 9)]);
    await repo.adjust(day, -1000);
    expect((await repo.watchDay(day).first)!.total, 0);
    expect((await repo.adjust(day, 0)).failureOrNull, isA<ValidationFailure>());
  });

  test('a range lists days in order', () async {
    await repo.ingest([r(0, 7), r(300, 9), r(800, 30)]);
    final days = await repo.watchRange(day, day.addDays(1)).first;
    expect(days.map((d) => d.date), [day, day.addDays(1)]);
  });
}
