import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/log_stamp.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/measurements.dart';

final class DriftMeasurementRepository implements MeasurementRepository {
  DriftMeasurementRepository(
    this._db, {
    required this.clock,
    required this.ids,
    required this.timeZone,
  });

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final TimeZoneSource timeZone;

  static const _table = 'body_measurements';

  Measurement _toDomain(BodyMeasurementRow row) => Measurement(
    id: row.id,
    type: row.measurementType,
    valueMilli: row.valueMilli,
    unit: row.unit,
    entryUnit: row.entryUnit,
    occurredAt: row.occurredAt,
    localDate: row.localDate,
    notes: row.notes,
  );

  String? _clean(String? notes) => notes == null || notes.trim().isEmpty ? null : notes.trim();

  @override
  Future<Result<Measurement>> add({
    required String type,
    required int valueMilli,
    required String entryUnit,
    String? notes,
  }) async {
    final failure = validateMeasurement(type, valueMilli);
    if (failure != null) return Err(failure);
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone);
      final id = ids.newId();
      final percent = MeasurementTypes.isPercent(type);
      final companion = BodyMeasurementsCompanion.insert(
        id: id,
        createdAt: stamp.nowUtc,
        updatedAt: stamp.nowUtc,
        measurementType: type,
        valueMilli: valueMilli,
        unit: percent ? 'percent' : 'cm',
        entryUnit: percent ? 'percent' : entryUnit,
        occurredAt: stamp.occurredAt,
        localDate: stamp.localDate,
        tz: stamp.tz,
        notes: Value(_clean(notes)),
      );
      await _db.transaction(() async {
        await _db.into(_db.bodyMeasurements).insert(companion);
        await _db.enqueueForSync(_table, id, stamp.nowUtc);
      });
      return _toDomain(
        await (_db.select(_db.bodyMeasurements)..where((t) => t.id.equals(id))).getSingle(),
      );
    }, onError: (_) => const StorageFailure('measurement_write'));
  }

  @override
  Future<Result<void>> update(String id, {required int valueMilli, String? notes}) async {
    final existing = await (_db.select(
      _db.bodyMeasurements,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return const Err(StorageFailure('measurement_missing'));
    final failure = validateMeasurement(existing.measurementType, valueMilli);
    if (failure != null) return Err(failure);
    return Result.guard(
      () => _db.transaction(() async {
        final now = clock.now().toUtc();
        await (_db.update(_db.bodyMeasurements)..where((t) => t.id.equals(id))).write(
          BodyMeasurementsCompanion(
            valueMilli: Value(valueMilli),
            notes: Value(_clean(notes)),
            updatedAt: Value(now),
          ),
        );
        await _db.enqueueForSync(_table, id, now);
      }),
      onError: (_) => const StorageFailure('measurement_write'),
    );
  }

  @override
  Future<Result<void>> delete(String id) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final changed =
          await (_db.update(_db.bodyMeasurements)
                ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
              .write(BodyMeasurementsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      if (changed > 0) await _db.enqueueForSync(_table, id, now);
    }),
    onError: (_) => const StorageFailure('measurement_write'),
  );

  @override
  Stream<List<Measurement>> watchLatestPerType() =>
      (_db.select(_db.bodyMeasurements)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch()
          .map((rows) {
            final latest = <String, Measurement>{};
            for (final row in rows) {
              latest.putIfAbsent(row.measurementType, () => _toDomain(row));
            }
            return latest.values.toList();
          });

  @override
  Stream<List<Measurement>> watchHistory(String type) =>
      (_db.select(_db.bodyMeasurements)
            ..where((t) => t.measurementType.equals(type) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
          .watch()
          .map((rows) => rows.map(_toDomain).toList());
}
