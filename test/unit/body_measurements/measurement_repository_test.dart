import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/features/body_measurements/data/drift_measurement_repository.dart';
import 'package:fitbuddy/features/body_measurements/domain/measurements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftMeasurementRepository repo;

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 10, 12, 8));
    repo = DriftMeasurementRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
  });
  tearDown(() => db.close());

  test('stores centimetres in thousandths and remembers the unit typed', () async {
    final m = (await repo.add(
      type: MeasurementTypes.waist,
      valueMilli: 93500,
      entryUnit: 'in',
    )).valueOrNull!;
    expect(m.unit, 'cm');
    expect(m.entryUnit, 'in');
    expect(await outboxEntries(db), [(table: 'body_measurements', id: 'id-1')]);
  });

  test('body fat is a percentage whatever unit is passed', () async {
    final m = (await repo.add(
      type: MeasurementTypes.bodyFat,
      valueMilli: 24500,
      entryUnit: 'cm',
    )).valueOrNull!;
    expect(m.unit, 'percent');
    expect(m.entryUnit, 'percent');
  });

  test('custom types are allowed; empty names and impossible values are not', () async {
    expect(
      (await repo.add(
        type: MeasurementTypes.custom('Calf'),
        valueMilli: 38000,
        entryUnit: 'cm',
      )).isOk,
      isTrue,
    );
    expect(
      (await repo.add(type: 'custom: ', valueMilli: 38000, entryUnit: 'cm')).failureOrNull?.code,
      'invalid',
    );
    expect(
      (await repo.add(
        type: MeasurementTypes.waist,
        valueMilli: 500,
        entryUnit: 'cm',
      )).failureOrNull?.code,
      'out_of_range',
    );
    expect(
      (await repo.add(
        type: MeasurementTypes.bodyFat,
        valueMilli: 90000,
        entryUnit: 'percent',
      )).failureOrNull?.code,
      'out_of_range',
    );
  });

  test('latest per type and history per type', () async {
    await repo.add(type: MeasurementTypes.waist, valueMilli: 93500, entryUnit: 'cm');
    await repo.add(type: MeasurementTypes.chest, valueMilli: 104000, entryUnit: 'cm');
    time.now = DateTime(2026, 11, 12, 8);
    await repo.add(type: MeasurementTypes.waist, valueMilli: 92000, entryUnit: 'cm');

    final latest = await repo.watchLatestPerType().first;
    expect({for (final m in latest) m.type: m.valueMilli}, {'waist': 92000, 'chest': 104000});
    expect((await repo.watchHistory(MeasurementTypes.waist).first).map((m) => m.valueMilli), [
      93500,
      92000,
    ]);
  });

  test('edit and delete', () async {
    final m = (await repo.add(
      type: MeasurementTypes.waist,
      valueMilli: 93500,
      entryUnit: 'cm',
    )).valueOrNull!;
    await repo.update(m.id, valueMilli: 93000, notes: 'after breakfast');
    expect((await repo.watchHistory(MeasurementTypes.waist).first).single.valueMilli, 93000);
    expect((await repo.update(m.id, valueMilli: 1)).failureOrNull?.code, 'out_of_range');
    await repo.delete(m.id);
    expect(await repo.watchLatestPerType().first, isEmpty);
  });
}
