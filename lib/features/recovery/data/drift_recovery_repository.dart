import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/local_date.dart';
import '../domain/recovery.dart';

/// Device-only (C4): not in the sync outbox.
final class DriftRecoveryRepository implements RecoveryRepository {
  DriftRecoveryRepository(this._db, {required this.clock});
  final AppDatabase _db;
  final Clock clock;

  static RecoveryLog _to(RecoveryLogRow r) => RecoveryLog(
    date: r.localDate,
    isRestDay: r.isRestDay,
    soreness: r.soreness,
    recovery: r.recovery,
    notes: r.notes,
  );

  @override
  Future<Result<void>> save(RecoveryLog log) async {
    bool bad(int? v) => v != null && (v < 1 || v > 5);
    if (bad(log.soreness) || bad(log.recovery)) {
      return const Err(ValidationFailure('rating', 'out_of_range'));
    }
    return Result.guard(
      () => _db
          .into(_db.localRecoveryLogs)
          .insertOnConflictUpdate(
            LocalRecoveryLogsCompanion.insert(
              localDate: log.date,
              isRestDay: Value(log.isRestDay),
              soreness: Value(log.soreness),
              recovery: Value(log.recovery),
              notes: Value(log.notes?.trim().isEmpty ?? true ? null : log.notes!.trim()),
              updatedAt: clock.now().toUtc(),
            ),
          ),
      onError: (_) => const StorageFailure('recovery_write'),
    );
  }

  @override
  Stream<RecoveryLog?> watchDay(LocalDate date) => (_db.select(
    _db.localRecoveryLogs,
  )..where((t) => t.localDate.equalsValue(date))).watchSingleOrNull().map((r) => r == null ? null : _to(r));

  @override
  Stream<List<RecoveryLog>> watchRecent({int limit = 30}) =>
      (_db.select(_db.localRecoveryLogs)
            ..orderBy([(t) => OrderingTerm(expression: t.localDate, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch()
          .map((rows) => [for (final r in rows) _to(r)]);
}
