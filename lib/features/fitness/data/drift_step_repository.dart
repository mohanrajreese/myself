import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/step_attribution.dart';
import '../domain/step_repository.dart';

final class DriftStepRepository implements StepRepository {
  DriftStepRepository(
    this._db, {
    required this.clock,
    required this.ids,
    this.engine = const StepAttributionEngine(),
  });

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final StepAttributionEngine engine;

  static const _retention = Duration(days: 60);

  static StepDay _toDay(StepDailyRow r) => StepDay(
    date: r.localDate,
    sensorSteps: r.sensorSteps,
    manualAdjustment: r.manualAdjustment,
    uncertainSteps: r.uncertainSteps,
    gapCount: r.gapCount,
    lastCollectedAt: r.lastCollectedAt?.toUtc(),
  );

  static StepReading _toReading(StepReadingRow r) => StepReading(
    cumulativeSteps: r.cumulativeSteps,
    bootCount: r.bootCount,
    elapsedRealtimeMs: r.elapsedRealtimeMs,
    wallTimeUtc: r.wallTimeUtc.toUtc(),
    utcOffsetSeconds: r.utcOffsetS,
  );

  @override
  Future<Result<void>> ingest(List<RawStepReading> readings) => Result.guard(() async {
    if (readings.isEmpty) return;
    await _db.transaction(() async {
      for (final r in readings) {
        await _db
            .into(_db.localStepReadings)
            .insert(
              LocalStepReadingsCompanion.insert(
                cumulativeSteps: r.reading.cumulativeSteps,
                bootCount: r.reading.bootCount,
                elapsedRealtimeMs: r.reading.elapsedRealtimeMs,
                wallTimeUtc: r.reading.wallTimeUtc,
                tz: r.tz,
                utcOffsetS: r.reading.utcOffsetSeconds,
                source: r.source,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      final earliest = readings
          .map((r) => r.reading.wallTimeUtc)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final firstAffected = LocalDate.ofInstant(
        earliest,
        Duration(seconds: readings.first.reading.utcOffsetSeconds),
      ).addDays(-1);
      await _recompute(firstAffected, readings.last.tz);
      await (_db.delete(_db.localStepReadings)..where(
            (t) => t.wallTimeUtc.isSmallerThanValue(clock.now().toUtc().subtract(_retention)),
          ))
          .go();
    });
  }, onError: (_) => const StorageFailure('step_write'));

  /// Recomputes days from [from] on. Readings from two days earlier provide
  /// the baseline for the first period.
  Future<void> _recompute(LocalDate from, String tz) async {
    final since = DateTime.utc(from.year, from.month, from.day).subtract(const Duration(days: 2));
    final rows = await (_db.select(
      _db.localStepReadings,
    )..where((t) => t.wallTimeUtc.isBiggerOrEqualValue(since))).get();
    final days = engine.attribute(rows.map(_toReading));
    final now = clock.now().toUtc();
    for (final day in days.values) {
      if (day.date.isBefore(from)) continue;
      final existing = await (_db.select(
        _db.localStepDaily,
      )..where((t) => t.localDate.equalsValue(day.date))).getSingleOrNull();
      final adjustment = existing?.manualAdjustment ?? 0;
      await _db
          .into(_db.localStepDaily)
          .insertOnConflictUpdate(
            LocalStepDailyCompanion.insert(
              localDate: day.date,
              sensorSteps: Value(day.sensorSteps),
              manualAdjustment: Value(adjustment),
              uncertainSteps: Value(day.uncertainSteps),
              gapCount: Value(day.gaps.length),
              tz: tz,
              lastCollectedAt: Value(day.lastCollectedAt),
              computedAt: now,
            ),
          );
      await _writeLog(
        day.date,
        day.sensorSteps + adjustment,
        adjusted: adjustment != 0,
        tz: tz,
        collectedAt: day.lastCollectedAt,
      );
    }
  }

  /// One synced total per day (`step_logs`).
  Future<void> _writeLog(
    LocalDate date,
    int steps, {
    required bool adjusted,
    required String tz,
    DateTime? collectedAt,
  }) async {
    final now = clock.now().toUtc();
    final existing = await (_db.select(
      _db.stepLogs,
    )..where((t) => t.logDate.equalsValue(date))).getSingleOrNull();
    final total = steps < 0 ? 0 : steps;
    final source = adjusted ? 'phone_sensor_adjusted' : 'phone_sensor';
    if (existing != null && existing.steps == total && existing.source == source) return;
    final id = existing?.id ?? ids.newId();
    await _db
        .into(_db.stepLogs)
        .insertOnConflictUpdate(
          StepLogsCompanion.insert(
            id: id,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            logDate: date,
            steps: total,
            source: source,
            timezone: tz,
            collectedAt: Value(collectedAt),
          ),
        );
    await _db.enqueueForSync('step_logs', id, now);
  }

  @override
  Future<Result<void>> adjust(LocalDate date, int delta) async {
    if (delta == 0 || delta.abs() > 100000)
      return const Err(ValidationFailure('steps', 'out_of_range'));
    return Result.guard(
      () => _db.transaction(() async {
        final existing = await (_db.select(
          _db.localStepDaily,
        )..where((t) => t.localDate.equalsValue(date))).getSingleOrNull();
        final sensor = existing?.sensorSteps ?? 0;
        var adjustment = (existing?.manualAdjustment ?? 0) + delta;
        if (sensor + adjustment < 0) adjustment = -sensor;
        await _db
            .into(_db.localStepDaily)
            .insertOnConflictUpdate(
              LocalStepDailyCompanion.insert(
                localDate: date,
                sensorSteps: Value(sensor),
                manualAdjustment: Value(adjustment),
                uncertainSteps: Value(existing?.uncertainSteps ?? 0),
                gapCount: Value(existing?.gapCount ?? 0),
                tz: existing?.tz ?? 'UTC',
                lastCollectedAt: Value(existing?.lastCollectedAt),
                computedAt: clock.now().toUtc(),
              ),
            );
        await _writeLog(
          date,
          sensor + adjustment,
          adjusted: adjustment != 0,
          tz: existing?.tz ?? 'UTC',
          collectedAt: existing?.lastCollectedAt,
        );
      }),
      onError: (_) => const StorageFailure('step_write'),
    );
  }

  @override
  Stream<StepDay?> watchDay(LocalDate date) =>
      (_db.select(_db.localStepDaily)..where((t) => t.localDate.equalsValue(date)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : _toDay(r));

  @override
  Stream<List<StepDay>> watchRange(LocalDate from, LocalDate to) =>
      (_db.select(_db.localStepDaily)
            ..where((t) => t.localDate.isBetweenValues(from.toString(), to.toString()))
            ..orderBy([(t) => OrderingTerm(expression: t.localDate)]))
          .watch()
          .map((rows) => [for (final r in rows) _toDay(r)]);

  @override
  Future<DateTime?> lastReadingAt() async {
    final max = _db.localStepReadings.wallTimeUtc.max();
    final row = await (_db.selectOnly(_db.localStepReadings)..addColumns([max])).getSingle();
    return row.read(max)?.toUtc();
  }
}
