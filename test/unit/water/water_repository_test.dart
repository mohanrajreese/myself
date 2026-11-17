import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/water/data/drift_water_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftWaterRepository water;
  final today = LocalDate(2026, 11, 16);

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 7, 15));
    water = DriftWaterRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
  });
  tearDown(() => db.close());

  test('quick add updates the day total at once', () async {
    final totals = <int>[];
    final sub = water.watchTotalOn(today).listen(totals.add);
    await pumpEventQueue();
    await water.add(250);
    await pumpEventQueue();
    time.now = DateTime(2026, 11, 16, 11, 40);
    await water.add(500);
    await pumpEventQueue();
    expect(totals, [0, 250, 750]);
    await sub.cancel();
  });

  test('each add is queued for sync', () async {
    await water.add(250);
    expect(await outboxEntries(db), [(table: 'water_logs', id: 'id-1')]);
  });

  test('amounts outside 1 to 5,000 ml are rejected and nothing is written', () async {
    for (final bad in [0, -250, 5001]) {
      expect((await water.add(bad)).failureOrNull?.code, 'out_of_range');
    }
    expect(await db.select(db.waterLogs).get(), isEmpty);
  });

  test('removing an entry lowers the total and leaves a tombstone', () async {
    final entry = (await water.add(250)).valueOrNull!;
    await water.add(500);
    await water.remove(entry.id);
    expect(await water.watchTotalOn(today).first, 500);
    expect((await db.select(db.waterLogs).get()).where((r) => r.deletedAt != null), hasLength(1));
  });

  test('a drink just after midnight belongs to the new day', () async {
    time.now = DateTime(2026, 11, 16, 23, 55);
    await water.add(250);
    time.now = DateTime(2026, 11, 17, 0, 5);
    await water.add(300);
    expect(await water.watchTotalOn(today).first, 250);
    expect(await water.watchTotalOn(LocalDate(2026, 11, 17)).first, 300);
  });

  test('a past time can be given; it sets the day', () async {
    await water.add(400, at: DateTime(2026, 11, 15, 21));
    expect(await water.watchTotalOn(LocalDate(2026, 11, 15)).first, 400);
    expect(await water.watchTotalOn(today).first, 0);
  });

  test('daily totals for a range skip days with nothing logged', () async {
    await water.add(250);
    await water.add(250);
    await water.add(1000, at: DateTime(2026, 11, 14, 9));
    final totals = await water.totalsBetween(LocalDate(2026, 11, 10), today);
    expect(totals, {LocalDate(2026, 11, 14): 1000, today: 500});
  });
}
