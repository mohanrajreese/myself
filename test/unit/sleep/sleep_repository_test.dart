import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/sleep/data/drift_sleep_repository.dart';
import 'package:fitbuddy/features/sleep/domain/sleep_math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late DriftSleepRepository sleep;
  final bed = DateTime(2026, 11, 15, 23, 10);
  final wake = DateTime(2026, 11, 16, 6, 15);

  setUp(() {
    db = memoryDatabase();
    sleep = DriftSleepRepository(
      db,
      clock: MutableClock(DateTime(2026, 11, 16, 9)).clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
  });
  tearDown(() => db.close());

  Future<List<String>> listed() async => [
    for (final e in await sleep.watchBetween(LocalDate(2026, 11, 1), LocalDate(2026, 11, 30)).first)
      '${e.period.kind.name} ${e.period.wakeDate} ${e.period.duration.inMinutes}',
  ];

  test('an overnight record is stored under the wake-up day with its length', () async {
    final entry = (await sleep.add(kind: SleepKind.night, start: bed, end: wake, quality: 4)).valueOrNull!;
    expect(entry.period.duration, const Duration(hours: 7, minutes: 5));
    final row = await db.select(db.sleepLogs).getSingle();
    expect(row.localDate, LocalDate(2026, 11, 16));
    expect(row.durationS, 25500);
    expect(row.quality, 4);
    expect(await outboxEntries(db), [(table: 'sleep_logs', id: 'id-1')]);
  });

  test('naps and nights are listed newest first', () async {
    await sleep.add(kind: SleepKind.night, start: bed, end: wake);
    await sleep.add(kind: SleepKind.nap, start: DateTime(2026, 11, 15, 14, 30), end: DateTime(2026, 11, 15, 14, 55));
    expect(await listed(), ['night 2026-11-16 425', 'nap 2026-11-15 25']);
  });

  test('rejects impossible times, a future wake-up and a quality outside 1 to 5', () async {
    Future<String?> code({DateTime? start, DateTime? end, int? quality}) async => (await sleep.add(
      kind: SleepKind.night,
      start: start ?? bed,
      end: end ?? wake,
      quality: quality,
    )).failureOrNull?.code;
    expect(await code(end: bed.subtract(const Duration(hours: 1))), 'end_before_start');
    expect(await code(start: DateTime(2026, 11, 14, 20)), 'too_long');
    expect(await code(end: DateTime(2026, 11, 16, 10)), 'in_future');
    expect(await code(quality: 6), 'out_of_range');
    expect(await db.select(db.sleepLogs).get(), isEmpty);
  });

  test('editing an overnight record across dates moves it to the new wake-up day', () async {
    final entry = (await sleep.add(kind: SleepKind.night, start: bed, end: wake)).valueOrNull!;
    await sleep.update(
      entry.id,
      kind: SleepKind.night,
      start: DateTime(2026, 11, 14, 23, 30),
      end: DateTime(2026, 11, 15, 6),
      quality: 3,
      notes: ' woke once ',
    );
    final row = await db.select(db.sleepLogs).getSingle();
    expect(row.localDate, LocalDate(2026, 11, 15));
    expect(row.durationS, 23400);
    expect(row.notes, 'woke once');
    expect(await listed(), ['night 2026-11-15 390']);
  });

  test('delete removes it from the list and keeps a tombstone', () async {
    final entry = (await sleep.add(kind: SleepKind.night, start: bed, end: wake)).valueOrNull!;
    await sleep.delete(entry.id);
    expect(await listed(), isEmpty);
    expect((await db.select(db.sleepLogs).getSingle()).deletedAt, isNotNull);
  });
}
