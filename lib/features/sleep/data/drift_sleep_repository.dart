import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/sleep_math.dart';
import '../domain/sleep_repository.dart';

final class DriftSleepRepository implements SleepRepository {
  DriftSleepRepository(this._db, {required this.clock, required this.ids, required this.timeZone});

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final TimeZoneSource timeZone;

  Failure? _validate(DateTime start, DateTime end, int? quality) {
    final failure = validateSleep(start, end);
    if (failure != null) return failure;
    if (quality != null && (quality < 1 || quality > 5)) {
      return const ValidationFailure('quality', 'out_of_range');
    }
    if (end.isAfter(clock.now())) return const ValidationFailure('endAt', 'in_future');
    return null;
  }

  String? _clean(String? notes) => notes == null || notes.trim().isEmpty ? null : notes.trim();

  @override
  Future<Result<SleepEntry>> add({
    required SleepKind kind,
    required DateTime start,
    required DateTime end,
    int? quality,
    String? notes,
  }) async {
    final failure = _validate(start, end, quality);
    if (failure != null) return Err(failure);
    return Result.guard(() async {
      final now = clock.now().toUtc();
      final period = SleepPeriod(kind: kind, start: start, end: end);
      final id = ids.newId();
      final tz = await timeZone.currentTimeZoneId();
      await _db.transaction(() async {
        await _db
            .into(_db.sleepLogs)
            .insert(
              SleepLogsCompanion.insert(
                id: id,
                createdAt: now,
                updatedAt: now,
                kind: kind.code,
                startAt: start.toUtc(),
                endAt: end.toUtc(),
                durationS: period.duration.inSeconds,
                quality: Value(quality),
                notes: Value(_clean(notes)),
                localDate: period.wakeDate,
                tz: tz,
              ),
            );
        await _db.enqueueForSync('sleep_logs', id, now);
      });
      return SleepEntry(id: id, period: period, quality: quality, notes: _clean(notes));
    }, onError: (_) => const StorageFailure('sleep_write'));
  }

  @override
  Future<Result<void>> update(
    String id, {
    required SleepKind kind,
    required DateTime start,
    required DateTime end,
    int? quality,
    String? notes,
  }) async {
    final failure = _validate(start, end, quality);
    if (failure != null) return Err(failure);
    return Result.guard(
      () => _db.transaction(() async {
        final now = clock.now().toUtc();
        final period = SleepPeriod(kind: kind, start: start, end: end);
        final changed =
            await (_db.update(
              _db.sleepLogs,
            )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
              SleepLogsCompanion(
                updatedAt: Value(now),
                kind: Value(kind.code),
                startAt: Value(start.toUtc()),
                endAt: Value(end.toUtc()),
                durationS: Value(period.duration.inSeconds),
                quality: Value(quality),
                notes: Value(_clean(notes)),
                localDate: Value(period.wakeDate),
              ),
            );
        if (changed > 0) await _db.enqueueForSync('sleep_logs', id, now);
      }),
      onError: (_) => const StorageFailure('sleep_write'),
    );
  }

  @override
  Future<Result<void>> delete(String id) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final changed =
          await (_db.update(_db.sleepLogs)..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
              .write(SleepLogsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      if (changed > 0) await _db.enqueueForSync('sleep_logs', id, now);
    }),
    onError: (_) => const StorageFailure('sleep_write'),
  );

  @override
  Stream<List<SleepEntry>> watchBetween(LocalDate from, LocalDate to) =>
      (_db.select(_db.sleepLogs)
            ..where(
              (t) =>
                  t.localDate.isBiggerOrEqualValue(from.toString()) &
                  t.localDate.isSmallerOrEqualValue(to.toString()) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.endAt)]))
          .watch()
          .map(
            (rows) => [
              for (final row in rows)
                SleepEntry(
                  id: row.id,
                  period: SleepPeriod(
                    kind: SleepKind.fromCode(row.kind),
                    start: row.startAt.toLocal(),
                    end: row.endAt.toLocal(),
                  ),
                  quality: row.quality,
                  notes: row.notes,
                ),
            ],
          );
}
