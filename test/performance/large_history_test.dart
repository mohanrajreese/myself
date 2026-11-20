// Three years of daily records: report timings and query plans (Q-04).
// Timings are measured on the build machine, not a phone; the budgets are
// generous and catch regressions such as a lost index, not small changes.
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/activities/data/drift_activity_repository.dart';
import 'package:fitbuddy/features/data_export/data/export_builder.dart';
import 'package:fitbuddy/features/data_export/domain/export.dart';
import 'package:fitbuddy/features/insights/data/drift_report_repository.dart';
import 'package:fitbuddy/features/insights/domain/report.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  final start = LocalDate(2023, 11, 19);
  const days = 3 * 365;
  final timings = <String, int>{};

  setUpAll(() async {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 18, 21));
    final t = DateTime.utc(2026, 11, 18).toIso8601String();
    await db.transaction(() async {
      for (var i = 0; i < days; i++) {
        final d = start.addDays(i).toString();
        await db.customStatement(
          "INSERT INTO step_logs VALUES ('s$i', ?1, ?1, NULL, ?2, ?3, 'phone_sensor', 'UTC', NULL)",
          [t, d, 6000 + i % 5000],
        );
        await db.customStatement(
          'INSERT INTO weight_logs (id, created_at, updated_at, weight_g, entry_unit, occurred_at, local_date, tz) '
          "VALUES ('w$i', ?1, ?1, ?3, 'kg', ?1, ?2, 'UTC')",
          [t, d, 90000 + i % 2000],
        );
        await db.customStatement(
          'INSERT INTO sleep_logs (id, created_at, updated_at, kind, start_at, end_at, duration_s, local_date, tz) '
          "VALUES ('z$i', ?1, ?1, 'night', ?1, ?1, 25200, ?2, 'UTC')",
          [t, d],
        );
        for (var w = 0; w < 6; w++) {
          await db.customStatement(
            'INSERT INTO water_logs (id, created_at, updated_at, amount_ml, occurred_at, local_date, tz) '
            "VALUES ('h$i-$w', ?1, ?1, 400, ?1, ?2, 'UTC')",
            [t, d],
          );
        }
        for (var m = 0; m < 3; m++) {
          await db.customStatement(
            'INSERT INTO meal_logs (id, created_at, updated_at, meal_category, occurred_at, local_date, tz, has_photo) '
            "VALUES ('m$i-$m', ?1, ?1, 'lunch', ?1, ?2, 'UTC', 0)",
            [t, d],
          );
          for (var k = 0; k < 3; k++) {
            await db.customStatement(
              'INSERT INTO meal_food_items (id, created_at, updated_at, meal_log_id, food_name, quantity_milli, unit, '
              'energy_kcal_milli, protein_mg, carbs_mg, fat_mg, fibre_mg, sort_order) '
              "VALUES ('i$i-$m-$k', ?1, ?1, ?2, 'Food', 1000, 'serving', 250000, 10000, 30000, 8000, 3000, ?3)",
              [t, 'm$i-$m', k],
            );
          }
        }
      }
    });
  });
  tearDownAll(() async {
    // ignore: avoid_print
    print('timings (ms): $timings');
    await db.close();
  });

  Future<T> timed<T>(String name, Future<T> Function() f) async {
    final sw = Stopwatch()..start();
    final r = await f();
    timings[name] = sw.elapsedMilliseconds;
    return r;
  }

  test('a month and a year of reports load within budget', () async {
    final reports = DriftReportRepository(
      db,
      activities: DriftActivityRepository(
        db,
        clock: time.clock,
        ids: SequentialIds(),
        timeZone: const FixedTimeZone(),
      ),
      clock: time.clock,
    );
    final month = await timed(
      'report month',
      () => reports.load(periodRange(ReportPeriod.month, LocalDate(2026, 10, 1))),
    );
    expect(month.daysWith(Metric.steps), 31);
    final year = await timed(
      'report year',
      () => reports.load((from: LocalDate(2025, 11, 18), to: LocalDate(2026, 11, 17))),
    );
    expect(year.daysWith(Metric.kcalMilli), 365);
    expect(timings['report month'], lessThan(1500));
    expect(timings['report year'], lessThan(5000));
  });

  test('day and range queries on log tables use an index, never a full scan', () async {
    Future<String> plan(String sql) async => [
      for (final r in await db.customSelect('EXPLAIN QUERY PLAN $sql').get())
        r.read<String>('detail'),
    ].join(' | ');
    for (final table in [
      'weight_logs',
      'water_logs',
      'meal_logs',
      'sleep_logs',
      'daily_health_checkins',
      'activity_logs',
      'workout_sessions',
    ]) {
      final p = await plan(
        "SELECT * FROM $table WHERE local_date BETWEEN '2026-11-01' AND '2026-11-30'",
      );
      expect(p, contains('USING INDEX'), reason: '$table: $p');
    }
    expect(
      await plan("SELECT * FROM step_logs WHERE log_date BETWEEN '2026-11-01' AND '2026-11-30'"),
      contains('USING INDEX'),
    );
    final join = await plan(
      'SELECT m.local_date, sum(i.energy_kcal_milli) FROM meal_food_items i JOIN meal_logs m ON m.id = i.meal_log_id '
      "WHERE m.local_date BETWEEN '2026-11-01' AND '2026-11-30' GROUP BY m.local_date",
    );
    expect(join, isNot(contains('SCAN i')), reason: join);
  });

  test('exporting three years stays within budget', () async {
    final bytes = await timed(
      'export json',
      () => ExportBuilder(
        db: db,
        clock: time.clock,
      ).build(const ExportOptions(passphrase: 'long enough')),
    );
    expect(bytes.length, greaterThan(10000));
    expect(timings['export json'], lessThan(20000));
  });
}
