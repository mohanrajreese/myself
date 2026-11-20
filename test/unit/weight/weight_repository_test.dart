import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/units/units.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/weight/data/drift_weight_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftWeightRepository weights;

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 23, 30));
    weights = DriftWeightRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
  });
  tearDown(() => db.close());

  test('stores grams, the entered unit, the local day and the timezone', () async {
    final result = await weights.add(weightG: 91800, entryUnit: MassUnit.kg);
    final entry = result.valueOrNull!;
    expect(entry.weightG, 91800);
    expect(entry.entryUnit, MassUnit.kg);
    expect(entry.localDate, LocalDate(2026, 11, 16));
    expect(entry.tz, 'Asia/Kolkata');
    expect(entry.occurredAt.isUtc, isTrue);
  });

  test('queues the new entry for sync in the same transaction', () async {
    await weights.add(weightG: 91800, entryUnit: MassUnit.kg);
    expect(await outboxEntries(db), [(table: 'weight_logs', id: 'id-1')]);
  });

  test('rejects weights outside 1 kg to 700 kg and writes nothing', () async {
    for (final grams in [0, 999, 700001, -5]) {
      final result = await weights.add(weightG: grams, entryUnit: MassUnit.kg);
      expect(result.failureOrNull?.code, 'out_of_range', reason: '$grams');
    }
    expect(await db.select(db.weightLogs).get(), isEmpty);
    expect(await outboxEntries(db), isEmpty);
  });

  test('latest returns the most recent entry that is not deleted', () async {
    await weights.add(weightG: 91800, entryUnit: MassUnit.kg);
    time.now = DateTime(2026, 11, 20, 7);
    final second = (await weights.add(weightG: 91200, entryUnit: MassUnit.kg)).valueOrNull!;
    expect((await weights.latest())!.weightG, 91200);

    await weights.delete(second.id);
    expect((await weights.latest())!.weightG, 91800);
  });

  test('delete leaves a tombstone and queues it for sync', () async {
    final entry = (await weights.add(weightG: 91800, entryUnit: MassUnit.kg)).valueOrNull!;
    await db.customStatement('DELETE FROM sync_outbox');
    await weights.delete(entry.id);

    final row = await db.select(db.weightLogs).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(await outboxEntries(db), [(table: 'weight_logs', id: entry.id)]);
  });

  test('editing changes value, time and note, moves the day, and queues a sync', () async {
    final entry = (await weights.add(weightG: 91800, entryUnit: MassUnit.kg)).valueOrNull!;
    await db.customStatement('DELETE FROM sync_outbox');
    final result = await weights.update(
      entry.id,
      weightG: 91500,
      occurredAt: DateTime(2026, 11, 15, 7),
      notes: ' after travel ',
    );
    expect(result.isOk, isTrue);
    final row = await db.select(db.weightLogs).getSingle();
    expect(row.weightG, 91500);
    expect(row.localDate, LocalDate(2026, 11, 15));
    expect(row.notes, 'after travel');
    expect(await outboxEntries(db), [(table: 'weight_logs', id: entry.id)]);
  });

  test('an edit cannot set an impossible weight or a future time', () async {
    final entry = (await weights.add(weightG: 91800, entryUnit: MassUnit.kg)).valueOrNull!;
    expect((await weights.update(entry.id, weightG: 5)).failureOrNull?.code, 'out_of_range');
    expect(
      (await weights.update(
        entry.id,
        weightG: 91000,
        occurredAt: DateTime(2026, 11, 18),
      )).failureOrNull?.code,
      'in_future',
    );
    expect((await db.select(db.weightLogs).getSingle()).weightG, 91800);
  });

  test('history loads in pages, newest first', () async {
    for (var day = 1; day <= 5; day++) {
      time.now = DateTime(2026, 11, day, 7);
      await weights.add(weightG: 92000 - day * 100, entryUnit: MassUnit.kg);
    }
    final first = await weights.page(limit: 2);
    expect(first.map((e) => e.localDate.day), [5, 4]);
    final second = await weights.page(limit: 2, before: first.last.occurredAt);
    expect(second.map((e) => e.localDate.day), [3, 2]);
  });

  test('a range includes the last entry before it as the baseline', () async {
    for (final day in [1, 9, 16]) {
      time.now = DateTime(2026, 11, day, 7);
      await weights.add(weightG: 92000 - day * 10, entryUnit: MassUnit.kg);
    }
    final since = await weights.watchSince(LocalDate(2026, 11, 9)).first;
    expect(since.map((e) => e.localDate.day), [1, 9, 16]);
    final recent = await weights.watchSince(LocalDate(2026, 11, 12)).first;
    expect(recent.map((e) => e.localDate.day), [9, 16]);
  });
}
