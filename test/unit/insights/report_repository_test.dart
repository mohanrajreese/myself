import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/activities/data/drift_activity_repository.dart';
import 'package:fitbuddy/features/activities/domain/activity.dart';
import 'package:fitbuddy/features/activities/domain/activity_repository.dart';
import 'package:fitbuddy/features/insights/data/drift_report_repository.dart';
import 'package:fitbuddy/features/insights/domain/report.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftActivityRepository activities;
  late DriftReportRepository reports;
  final week = periodRange(ReportPeriod.week, LocalDate(2026, 11, 18)); // 16–22 Nov

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 18, 21));
    activities = DriftActivityRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
    reports = DriftReportRepository(db, activities: activities, clock: time.clock);
  });
  tearDown(() => db.close());

  Future<void> sql(String s, [List<Object> v = const []]) => db.customStatement(s, v);
  const stamp = '2026-11-16T09:00:00.000Z';

  test('an empty week has no series at all', () async {
    final r = await reports.load(week);
    expect(r.series, isEmpty);
    expect(r.newRecords, 0);
  });

  test('sums and picks per day from each table, ignoring deleted rows and other weeks', () async {
    await sql(
      "INSERT INTO step_logs VALUES ('s1', ?, ?, NULL, '2026-11-16', 8000, 'phone_sensor', 'UTC', NULL)",
      [stamp, stamp],
    );
    await sql(
      "INSERT INTO step_logs VALUES ('s2', ?, ?, NULL, '2026-11-15', 99999, 'phone_sensor', 'UTC', NULL)",
      [stamp, stamp],
    );
    for (final (id, ml, deleted) in [
      ('w1', 500, 'NULL'),
      ('w2', 750, 'NULL'),
      ('w3', 4000, "'$stamp'"),
    ]) {
      await sql(
        'INSERT INTO water_logs (id, created_at, updated_at, deleted_at, amount_ml, occurred_at, local_date, tz) '
        "VALUES (?, ?2, ?2, $deleted, ?, ?2, '2026-11-17', 'UTC')",
        [id, stamp, ml],
      );
    }
    final r = await reports.load(week);
    expect(r.of(Metric.steps), {LocalDate(2026, 11, 16): 8000});
    expect(r.of(Metric.waterMl), {LocalDate(2026, 11, 17): 1250});
  });

  test('meal items add up per day; junk items are counted', () async {
    await sql(
      'INSERT INTO meal_logs (id, created_at, updated_at, meal_category, occurred_at, local_date, tz, has_photo) '
      "VALUES ('m1', ?1, ?1, 'lunch', ?1, '2026-11-16', 'UTC', 0)",
      [stamp],
    );
    for (final (id, kcal, junk) in [('i1', 600000, 'NULL'), ('i2', 400000, "'sweets'")]) {
      await sql(
        'INSERT INTO meal_food_items (id, created_at, updated_at, meal_log_id, food_name, quantity_milli, unit, '
        'energy_kcal_milli, protein_mg, carbs_mg, fat_mg, fibre_mg, junk_category, sort_order) '
        "VALUES (?, ?2, ?2, 'm1', 'x', 1000, 'serving', ?, 20000, 50000, 10000, 5000, $junk, 0)",
        [id, stamp, kcal],
      );
    }
    final r = await reports.load(week);
    expect(r.of(Metric.kcalMilli), {LocalDate(2026, 11, 16): 1000000});
    expect(r.of(Metric.proteinMg)[LocalDate(2026, 11, 16)], 40000);
    expect(r.total(Metric.junkItems), 1);
  });

  test(
    'essential activities: done over occurrences that are due or past, not future ones',
    () async {
      // Created a week earlier, so its schedule covers the whole week.
      time.now = DateTime(2026, 11, 10, 9);
      final a = (await activities.create(
        Activity(
          id: '',
          name: 'Stretch',
          category: 'movement',
          iconKey: 'yoga',
          trackingType: TrackingType.boolean,
          priority: ActivityPriority.essential,
          schedule: Daily(times: [8 * 60, 22 * 60]),
          scheduleHistory: [
            ScheduleChange(
              from: LocalDate(2026, 11, 1),
              rule: Daily(times: [8 * 60, 22 * 60]),
            ),
          ],
        ),
      )).valueOrNull!;
      time.now = DateTime(2026, 11, 18, 21);
      await activities.addLog(
        a.id,
        LogDraft(
          status: ActivityLogStatus.completed,
          occurredAt: DateTime(2026, 11, 16, 8, 5),
          scheduledSlot: 480,
        ),
      );
      time.now = DateTime(2026, 11, 18, 21);
      final r = await reports.load(week);
      // 16 and 17 Nov: 2 each; 18 Nov at 21:00: 08:00 has passed, 22:00 is still due.
      expect(r.total(Metric.essentialScheduled), 5);
      expect(r.total(Metric.essentialDone), 1);
      expect(r.essentialPercent, 20);
    },
  );

  test('the report updates when a table changes', () async {
    final stream = reports.watch(week);
    final values = <int?>[];
    final sub = stream.listen((r) => values.add(r.average(Metric.steps)));
    await pumpEventQueue();
    await sql(
      "INSERT INTO step_logs VALUES ('s1', ?, ?, NULL, '2026-11-17', 6000, 'phone_sensor', 'UTC', NULL)",
      [stamp, stamp],
    );
    await db.customUpdate('UPDATE step_logs SET steps = steps', updates: {db.stepLogs});
    await pumpEventQueue();
    await sub.cancel();
    expect(values.first, isNull);
    expect(values.last, 6000);
  });
}
