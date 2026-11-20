import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/local_date.dart';
import '../../activities/domain/activity.dart';
import '../../activities/domain/activity_day.dart';
import '../../activities/domain/activity_repository.dart';
import '../../fitness/domain/workout_math.dart';
import '../../screen_time/domain/screen_time.dart';
import '../domain/report.dart';

/// Builds a [PeriodReport] from the main database (and screen time, which
/// stays on the phone). Read-only.
final class DriftReportRepository {
  DriftReportRepository(this._db, {required this.activities, required this.clock, this.screenTime});

  final AppDatabase _db;
  final ActivityRepository activities;
  final ScreenTimeRepository? screenTime;
  final Clock clock;

  /// The report, recomputed when any table changes.
  Stream<PeriodReport> watch(DateRange r) async* {
    yield await load(r);
    yield* _db.tableUpdates().asyncMap((_) => load(r));
  }

  Future<PeriodReport> load(DateRange r) async {
    final series = <Metric, Map<LocalDate, int>>{};
    void put(Metric m, LocalDate d, int? v) {
      if (v != null) (series[m] ??= {})[d] = v;
    }

    final from = Variable.withString(r.from.toString());
    final to = Variable.withString(r.to.toString());
    Future<List<QueryRow>> q(String sql) => _db.customSelect(sql, variables: [from, to]).get();
    LocalDate day(QueryRow row) => LocalDate.parse(row.read<String>('d'));

    for (final row in await q(
      'SELECT log_date AS d, steps AS v FROM step_logs WHERE deleted_at IS NULL AND log_date BETWEEN ?1 AND ?2',
    )) {
      put(Metric.steps, day(row), row.read<int>('v'));
    }
    for (final row in await q(
      'SELECT local_date AS d, weight_g AS v FROM weight_logs WHERE deleted_at IS NULL '
      'AND local_date BETWEEN ?1 AND ?2 ORDER BY occurred_at',
    )) {
      put(Metric.weightG, day(row), row.read<int>('v'));
    }
    for (final row in await q(
      'SELECT m.local_date AS d, sum(i.energy_kcal_milli) AS k, sum(i.protein_mg) AS p, sum(i.carbs_mg) AS c, '
      'sum(i.fat_mg) AS f, sum(i.fibre_mg) AS fi, sum(CASE WHEN i.junk_category IS NULL THEN 0 ELSE 1 END) AS j '
      'FROM meal_food_items i JOIN meal_logs m ON m.id = i.meal_log_id '
      'WHERE i.deleted_at IS NULL AND m.deleted_at IS NULL AND m.local_date BETWEEN ?1 AND ?2 GROUP BY m.local_date',
    )) {
      final d = day(row);
      put(Metric.kcalMilli, d, row.read<int>('k'));
      put(Metric.proteinMg, d, row.read<int>('p'));
      put(Metric.carbsMg, d, row.read<int>('c'));
      put(Metric.fatMg, d, row.read<int>('f'));
      put(Metric.fibreMg, d, row.read<int>('fi'));
      final j = row.read<int>('j');
      if (j > 0) put(Metric.junkItems, d, j);
    }
    for (final row in await q(
      'SELECT local_date AS d, sum(amount_ml) AS v FROM water_logs WHERE deleted_at IS NULL '
      'AND local_date BETWEEN ?1 AND ?2 GROUP BY local_date',
    )) {
      put(Metric.waterMl, day(row), row.read<int>('v'));
    }
    for (final row in await q(
      "SELECT local_date AS d, sum(duration_s) / 60 AS v FROM sleep_logs WHERE deleted_at IS NULL AND kind = 'night' "
      'AND local_date BETWEEN ?1 AND ?2 GROUP BY local_date',
    )) {
      put(Metric.sleepMin, day(row), row.read<int>('v'));
    }
    for (final row in await q(
      'SELECT local_date AS d, CAST(round(avg(mood) * 1000) AS INTEGER) AS mo, '
      'CAST(round(avg(energy) * 1000) AS INTEGER) AS en, CAST(round(avg(stress) * 1000) AS INTEGER) AS st, '
      'CAST(round(avg(wellness) * 1000) AS INTEGER) AS we FROM daily_health_checkins '
      'WHERE deleted_at IS NULL AND local_date BETWEEN ?1 AND ?2 GROUP BY local_date',
    )) {
      final d = day(row);
      put(Metric.moodMilli, d, row.read<int?>('mo'));
      put(Metric.energyMilli, d, row.read<int?>('en'));
      put(Metric.stressMilli, d, row.read<int?>('st'));
      put(Metric.wellnessMilli, d, row.read<int?>('we'));
    }
    for (final row in await q(
      'SELECT local_date AS d, kind, count(*) AS n, sum(coalesce(distance_m, 0)) AS m FROM workout_sessions '
      'WHERE deleted_at IS NULL AND ended_at IS NOT NULL AND local_date BETWEEN ?1 AND ?2 GROUP BY local_date, kind',
    )) {
      final d = day(row);
      final n = row.read<int>('n');
      final m = row.read<int>('m');
      switch (row.read<String>('kind')) {
        case 'walk':
          put(Metric.walks, d, n);
          if (m > 0) put(Metric.walkM, d, m);
        case 'run':
          put(Metric.runs, d, n);
          if (m > 0) put(Metric.runM, d, m);
        case 'cycle':
          put(Metric.rides, d, n);
          if (m > 0) put(Metric.cycleM, d, m);
        case 'gym':
          put(Metric.gymSessions, d, n);
      }
    }

    final measurements = <String, int>{};
    for (final row
        in await _db
            .customSelect(
              'SELECT measurement_type AS t, value_milli AS v FROM body_measurements '
              'WHERE deleted_at IS NULL AND local_date <= ?1 ORDER BY occurred_at',
              variables: [to],
            )
            .get()) {
      measurements[row.read<String>('t')] = row.read<int>('v');
    }

    final screen = screenTime;
    if (screen != null) {
      try {
        for (final s in await screen.watchDays(from: r.from, to: r.to).first) {
          if (s.totalMs > 0) put(Metric.screenMs, s.date, s.totalMs);
        }
      } on Object {
        // Screen time unavailable (private database closed): left out.
      }
    }

    await _activities(r, put);
    return PeriodReport(
      range: r,
      series: series,
      measurements: measurements,
      newRecords: await _newRecords(r),
    );
  }

  Future<void> _activities(DateRange r, void Function(Metric, LocalDate, int?) put) async {
    final now = clock.now();
    final today = LocalDate.fromDateTime(now);
    final all = (await activities.watchAll().first)
        .where((a) => a.priority == ActivityPriority.essential && !a.archived)
        .toList();
    if (all.isEmpty) return;
    final logs = await activities.watchLogsBetween(r.from, r.to).first;
    for (final date in r.dates) {
      if (date.isAfter(today)) break;
      var done = 0;
      var scheduled = 0;
      for (final a in all) {
        final dayLogs = [
          for (final l in logs)
            if (l.activityId == a.id && l.localDate == date) l,
        ];
        final ad = ActivityDay.of(
          a,
          date,
          dayLogs,
          now: (date: today, minute: now.hour * 60 + now.minute),
        );
        for (final s in ad.slots) {
          if (s.state == SlotState.due) continue;
          scheduled++;
          if (s.state == SlotState.done) done++;
        }
      }
      if (scheduled > 0) {
        put(Metric.essentialScheduled, date, scheduled);
        put(Metric.essentialDone, date, done);
      }
    }
  }

  Future<int> _newRecords(DateRange r) async {
    final rows = await _db
        .customSelect(
          'SELECT we.exercise_id AS e, ws.id AS s, es.completed_at AS at, es.load_g AS l, es.reps AS r, '
          'es.duration_s AS du, es.distance_m AS di FROM exercise_sets es '
          'JOIN workout_exercises we ON we.id = es.workout_exercise_id '
          'JOIN workout_sessions ws ON ws.id = we.session_id '
          'WHERE es.completed_at IS NOT NULL AND es.deleted_at IS NULL AND we.deleted_at IS NULL '
          'AND ws.deleted_at IS NULL AND ws.local_date <= ?1 ORDER BY es.completed_at',
          variables: [Variable.withString(r.to.toString())],
        )
        .get();
    final byExercise = <String, List<SetRecordInput>>{};
    for (final row in rows) {
      (byExercise[row.read<String>('e')] ??= []).add(
        SetRecordInput(
          sessionId: row.read<String>('s'),
          at: DateTime.parse(row.read<String>('at')),
          loadG: row.read<int?>('l'),
          reps: row.read<int?>('r'),
          durationS: row.read<int?>('du'),
          distanceM: row.read<int?>('di'),
        ),
      );
    }
    var n = 0;
    for (final sets in byExercise.values) {
      for (final rec in strengthRecords(sets)) {
        if (r.contains(LocalDate.fromDateTime(rec.at.toLocal()))) n++;
      }
    }
    return n;
  }
}
