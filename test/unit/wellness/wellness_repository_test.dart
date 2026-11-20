import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/wellness/data/drift_wellness_repository.dart';
import 'package:fitbuddy/features/wellness/domain/wellness.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftWellnessRepository wellness;
  final today = LocalDate(2026, 11, 16);
  const good = WellnessScores(energy: 4, mood: 3, stress: 2, wellness: 4);

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 8));
    wellness = DriftWellnessRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
  });
  tearDown(() => db.close());

  test('several check-ins in one day are all kept, newest first', () async {
    await wellness.add(good, notes: ' slept well ');
    time.now = DateTime(2026, 11, 16, 20);
    await wellness.add(const WellnessScores(energy: 2, mood: 3, stress: 4, wellness: 3));
    final list = await wellness.watchBetween(today, today).first;
    expect(list.map((c) => c.scores.energy), [2, 4]);
    expect(list.last.notes, 'slept well');
    expect(await outboxEntries(db), hasLength(2));
  });

  test('scores outside 1 to 5 are rejected', () async {
    final result = await wellness.add(
      const WellnessScores(energy: 0, mood: 3, stress: 2, wellness: 6),
    );
    expect(result.failureOrNull?.code, 'out_of_range');
    expect(await db.select(db.dailyHealthCheckins).get(), isEmpty);
  });

  test('daily means average the check-ins of each day', () async {
    await wellness.add(good);
    time.now = DateTime(2026, 11, 16, 20);
    await wellness.add(const WellnessScores(energy: 3, mood: 3, stress: 4, wellness: 3));
    time.now = DateTime(2026, 11, 17, 9);
    await wellness.add(const WellnessScores(energy: 5, mood: 5, stress: 1, wellness: 5));
    final means = dailyMeansTenths(
      await wellness.watchBetween(today, LocalDate(2026, 11, 17)).first,
    );
    expect(means[today], (energy: 35, mood: 30, stress: 30, wellness: 35));
    expect(means[LocalDate(2026, 11, 17)]!.energy, 50);
  });

  test('delete removes a check-in from the list', () async {
    final entry = (await wellness.add(good)).valueOrNull!;
    await wellness.delete(entry.id);
    expect(await wellness.watchBetween(today, today).first, isEmpty);
  });
}
