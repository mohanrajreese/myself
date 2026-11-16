import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/outbox.dart';
import '../../../core/database/unit_codes.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/units/units.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/weight_entry.dart';
import '../domain/weight_repository.dart';

final class DriftWeightRepository implements WeightRepository {
  DriftWeightRepository(
    this._db, {
    required Clock clock,
    required IdGenerator ids,
    required TimeZoneSource timeZone,
  }) : _clock = clock,
       _ids = ids,
       _timeZone = timeZone;

  final AppDatabase _db;
  final Clock _clock;
  final IdGenerator _ids;
  final TimeZoneSource _timeZone;

  @override
  Future<Result<WeightEntry>> add({
    required int weightG,
    required MassUnit entryUnit,
    String? notes,
  }) async {
    final failure = validateWeightG(weightG);
    if (failure != null) return Err(failure);
    return Result.guard(() async {
      final wallNow = _clock.now();
      final now = wallNow.toUtc();
      final entry = WeightEntry(
        id: _ids.newId(),
        weightG: weightG,
        entryUnit: entryUnit,
        occurredAt: now,
        localDate: LocalDate.fromDateTime(wallNow),
        tz: await _timeZone.currentTimeZoneId(),
        notes: notes == null || notes.trim().isEmpty ? null : notes.trim(),
      );
      await _db.transaction(() async {
        await _db
            .into(_db.weightLogs)
            .insert(
              WeightLogsCompanion.insert(
                id: entry.id,
                createdAt: now,
                updatedAt: now,
                weightG: entry.weightG,
                entryUnit: entry.entryUnit.code,
                occurredAt: entry.occurredAt,
                localDate: entry.localDate,
                tz: entry.tz,
                notes: Value(entry.notes),
              ),
            );
        await _db.enqueueForSync('weight_logs', entry.id, now);
      });
      return entry;
    }, onError: (_) => const StorageFailure('weight_write'));
  }

  SimpleSelectStatement<$WeightLogsTable, WeightLogRow> get _latestQuery => _db.select(_db.weightLogs)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
    ..limit(1);

  @override
  Future<WeightEntry?> latest() async => _toDomain(await _latestQuery.getSingleOrNull());

  @override
  Stream<WeightEntry?> watchLatest() => _latestQuery.watchSingleOrNull().map(_toDomain);

  @override
  Stream<List<WeightEntry>> watchOn(LocalDate date) => (_db.select(_db.weightLogs)
        ..where((t) => t.localDate.equalsValue(date) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
      .watch()
      .map((rows) => [for (final row in rows) _toDomain(row)!]);

  WeightEntry? _toDomain(WeightLogRow? row) => row == null
      ? null
      : WeightEntry(
          id: row.id,
          weightG: row.weightG,
          entryUnit: MassUnitCode.parse(row.entryUnit),
          occurredAt: row.occurredAt,
          localDate: row.localDate,
          tz: row.tz,
          notes: row.notes,
        );

  @override
  Future<Result<void>> delete(String id) => Result.guard(
    () => _db.transaction(() async {
      final now = _clock.now().toUtc();
      final changed =
          await (_db.update(_db.weightLogs)..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
              .write(WeightLogsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      if (changed > 0) await _db.enqueueForSync('weight_logs', id, now);
    }),
    onError: (_) => const StorageFailure('weight_write'),
  );
}
