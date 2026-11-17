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
import '../domain/wellness.dart';

final class DriftWellnessRepository implements WellnessRepository {
  DriftWellnessRepository(
    this._db, {
    required this.clock,
    required this.ids,
    required this.timeZone,
  });

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final TimeZoneSource timeZone;

  @override
  Future<Result<WellnessCheckin>> add(WellnessScores scores, {String? notes}) async {
    final failure = scores.validate();
    if (failure != null) return Err(failure);
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone);
      final id = ids.newId();
      final note = notes == null || notes.trim().isEmpty ? null : notes.trim();
      await _db.transaction(() async {
        await _db
            .into(_db.dailyHealthCheckins)
            .insert(
              DailyHealthCheckinsCompanion.insert(
                id: id,
                createdAt: stamp.nowUtc,
                updatedAt: stamp.nowUtc,
                energy: scores.energy,
                mood: scores.mood,
                stress: scores.stress,
                wellness: scores.wellness,
                occurredAt: stamp.occurredAt,
                localDate: stamp.localDate,
                tz: stamp.tz,
                notes: Value(note),
              ),
            );
        await _db.enqueueForSync('daily_health_checkins', id, stamp.nowUtc);
      });
      return WellnessCheckin(
        id: id,
        scores: scores,
        occurredAt: stamp.occurredAt,
        localDate: stamp.localDate,
        notes: note,
      );
    }, onError: (_) => const StorageFailure('wellness_write'));
  }

  @override
  Future<Result<void>> delete(String id) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final changed =
          await (_db.update(_db.dailyHealthCheckins)
                ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
              .write(DailyHealthCheckinsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      if (changed > 0) await _db.enqueueForSync('daily_health_checkins', id, now);
    }),
    onError: (_) => const StorageFailure('wellness_write'),
  );

  @override
  Stream<List<WellnessCheckin>> watchBetween(LocalDate from, LocalDate to) =>
      (_db.select(_db.dailyHealthCheckins)
            ..where(
              (t) =>
                  t.localDate.isBiggerOrEqualValue(from.toString()) &
                  t.localDate.isSmallerOrEqualValue(to.toString()) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch()
          .map(
            (rows) => [
              for (final row in rows)
                WellnessCheckin(
                  id: row.id,
                  scores: WellnessScores(
                    energy: row.energy,
                    mood: row.mood,
                    stress: row.stress,
                    wellness: row.wellness,
                  ),
                  occurredAt: row.occurredAt,
                  localDate: row.localDate,
                  notes: row.notes,
                ),
            ],
          );
}
