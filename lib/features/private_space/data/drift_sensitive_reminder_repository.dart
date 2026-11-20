import 'package:drift/drift.dart';

import '../../../core/database/private_database.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/private_records.dart';

final class DriftSensitiveReminderRepository implements SensitiveReminderRepository {
  DriftSensitiveReminderRepository(this._db, {required this.clock, required this.ids});
  final PrivateDatabase _db;
  final Clock clock;
  final IdGenerator ids;

  static SensitiveReminder _to(SensitiveReminderRow r) => SensitiveReminder(
    id: r.id,
    ownerType: r.ownerType,
    ownerId: r.ownerId,
    title: r.title,
    ruleJson: r.schedule,
    enabled: r.enabled,
  );

  @override
  Future<Result<void>> save(SensitiveReminder r) => Result.guard(() async {
    final now = clock.now().toUtc();
    await _db
        .into(_db.localSensitiveReminders)
        .insertOnConflictUpdate(
          LocalSensitiveRemindersCompanion.insert(
            id: r.id.isEmpty ? ids.newId() : r.id,
            createdAt: now,
            updatedAt: now,
            ownerType: r.ownerType,
            ownerId: Value(r.ownerId),
            title: r.title,
            schedule: r.ruleJson,
            enabled: Value(r.enabled),
          ),
        );
  }, onError: (_) => const StorageFailure('private_write'));

  @override
  Future<Result<void>> delete(String id) => Result.guard(
    () => (_db.delete(_db.localSensitiveReminders)..where((t) => t.id.equals(id))).go(),
    onError: (_) => const StorageFailure('private_write'),
  );

  @override
  Stream<List<SensitiveReminder>> watchAll() =>
      _db.select(_db.localSensitiveReminders).watch().map((rows) => [for (final r in rows) _to(r)]);

  @override
  Future<List<SensitiveReminder>> enabled() async => [
    for (final r in await (_db.select(
      _db.localSensitiveReminders,
    )..where((t) => t.enabled.equals(true))).get())
      _to(r),
  ];
}
