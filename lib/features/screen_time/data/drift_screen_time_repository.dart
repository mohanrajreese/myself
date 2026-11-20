import 'package:drift/drift.dart';

import '../../../core/database/private_database.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/local_date.dart';
import '../domain/screen_time.dart';

final class DriftScreenTimeRepository implements ScreenTimeRepository {
  DriftScreenTimeRepository(this._db, {required this.clock});
  final PrivateDatabase _db;
  final Clock clock;

  @override
  Future<Result<void>> store(LocalDate date, List<AppMinutes> apps, {required bool partial}) =>
      Result.guard(
        () => _db.transaction(() async {
          await (_db.delete(
            _db.localScreenTimeApps,
          )..where((t) => t.localDate.equalsValue(date))).go();
          for (final a in apps) {
            await _db
                .into(_db.localScreenTimeApps)
                .insert(
                  LocalScreenTimeAppsCompanion.insert(
                    localDate: date,
                    packageName: a.packageName,
                    appLabel: a.label,
                    foregroundMs: a.foregroundMs,
                  ),
                  mode: InsertMode.insertOrReplace,
                );
          }
          await _db
              .into(_db.localScreenTimeDaily)
              .insertOnConflictUpdate(
                LocalScreenTimeDailyCompanion.insert(
                  localDate: date,
                  totalMs: apps.fold(0, (n, a) => n + a.foregroundMs),
                  isPartial: Value(partial),
                  computedAt: clock.now().toUtc(),
                ),
              );
        }),
        onError: (_) => const StorageFailure('screen_time_write'),
      );

  @override
  Stream<List<ScreenTimeDay>> watchDays({required LocalDate from, required LocalDate to}) =>
      (_db.select(_db.localScreenTimeDaily)
            ..where((t) => t.localDate.isBetweenValues(from.toString(), to.toString()))
            ..orderBy([(t) => OrderingTerm(expression: t.localDate)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                ScreenTimeDay(date: r.localDate, totalMs: r.totalMs, isPartial: r.isPartial),
            ],
          );

  @override
  Stream<List<AppMinutes>> watchApps({required LocalDate from, required LocalDate to}) =>
      (_db.select(_db.localScreenTimeApps)
            ..where((t) => t.localDate.isBetweenValues(from.toString(), to.toString())))
          .watch()
          .map((rows) {
            final sum = <String, AppMinutes>{};
            for (final r in rows) {
              final prev = sum[r.packageName];
              sum[r.packageName] = (
                packageName: r.packageName,
                label: r.appLabel,
                foregroundMs: (prev?.foregroundMs ?? 0) + r.foregroundMs,
              );
            }
            return sum.values.toList()..sort((a, b) => b.foregroundMs.compareTo(a.foregroundMs));
          });
}
