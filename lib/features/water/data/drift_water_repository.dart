import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/log_stamp.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/water.dart';

final class DriftWaterRepository implements WaterRepository {
  DriftWaterRepository(this._db, {required this.clock, required this.ids, required this.timeZone});

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final TimeZoneSource timeZone;

  WaterEntry _toDomain(WaterLogRow row) =>
      WaterEntry(id: row.id, amountMl: row.amountMl, occurredAt: row.occurredAt, localDate: row.localDate);

  @override
  Future<Result<WaterEntry>> add(int amountMl, {DateTime? at}) async {
    final failure = validateWaterMl(amountMl);
    if (failure != null) return Err(failure);
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone, at: at);
      final id = ids.newId();
      await _db.transaction(() async {
        await _db
            .into(_db.waterLogs)
            .insert(
              WaterLogsCompanion.insert(
                id: id,
                createdAt: stamp.nowUtc,
                updatedAt: stamp.nowUtc,
                amountMl: amountMl,
                occurredAt: stamp.occurredAt,
                localDate: stamp.localDate,
                tz: stamp.tz,
              ),
            );
        await _db.enqueueForSync('water_logs', id, stamp.nowUtc);
      });
      return WaterEntry(id: id, amountMl: amountMl, occurredAt: stamp.occurredAt, localDate: stamp.localDate);
    }, onError: (_) => const StorageFailure('water_write'));
  }

  @override
  Future<Result<void>> remove(String id) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final changed = await (_db.update(_db.waterLogs)..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        WaterLogsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      if (changed > 0) await _db.enqueueForSync('water_logs', id, now);
    }),
    onError: (_) => const StorageFailure('water_write'),
  );

  @override
  Stream<List<WaterEntry>> watchOn(LocalDate date) =>
      (_db.select(_db.waterLogs)
            ..where((t) => t.localDate.equalsValue(date) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch()
          .map((rows) => rows.map(_toDomain).toList());

  @override
  Stream<int> watchTotalOn(LocalDate date) =>
      watchOn(date).map((entries) => entries.fold<int>(0, (sum, e) => sum + e.amountMl));

  @override
  Future<Map<LocalDate, int>> totalsBetween(LocalDate from, LocalDate to) async {
    final rows =
        await (_db.select(_db.waterLogs)..where(
              (t) =>
                  t.localDate.isBiggerOrEqualValue(from.toString()) &
                  t.localDate.isSmallerOrEqualValue(to.toString()) &
                  t.deletedAt.isNull(),
            ))
            .get();
    final totals = <LocalDate, int>{};
    for (final row in rows) {
      totals.update(row.localDate, (v) => v + row.amountMl, ifAbsent: () => row.amountMl);
    }
    return totals;
  }
}
