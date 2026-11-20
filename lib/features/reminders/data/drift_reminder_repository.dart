import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/scheduling/reminder_planner.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/reminder.dart';
import '../domain/reminder_repository.dart';

final class DriftReminderRepository implements ReminderRepository {
  DriftReminderRepository(this._db, {required this.clock, required this.ids});

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;

  static const _table = 'reminders';

  static Reminder _toReminder(ReminderRow r) => Reminder(
    id: r.id,
    kind: ReminderKind.fromCode(r.kind),
    title: r.title,
    description: r.description,
    activityId: r.activityDefinitionId,
    rule: ScheduleRule.fromJson((jsonDecode(r.schedule) as Map).cast<String, Object?>()),
    onlyIfIncomplete: r.condition == 'if_incomplete',
    soundKey: r.soundKey,
    vibrate: r.vibrate,
    snoozeMinutes: r.snoozeDefaultMin,
    alarm: r.priority == 'alarm',
    quietBehaviour: QuietBehaviour.fromCode(r.quietHoursBehaviour),
    enabled: r.enabled,
    startDate: r.startDate,
    endDate: r.endDate,
  );

  static String? _clean(String? text) => text == null || text.trim().isEmpty ? null : text.trim();

  RemindersCompanion _fields(Reminder r, DateTime now) => RemindersCompanion(
    updatedAt: Value(now),
    kind: Value(r.kind.code),
    title: Value(r.title.trim()),
    description: Value(_clean(r.description)),
    activityDefinitionId: Value(r.activityId),
    schedule: Value(jsonEncode(r.rule.toJson())),
    condition: Value(r.onlyIfIncomplete ? 'if_incomplete' : 'always'),
    channelKey: Value(r.channel.code),
    soundKey: Value(r.soundKey),
    vibrate: Value(r.vibrate),
    snoozeDefaultMin: Value(r.snoozeMinutes),
    priority: Value(r.alarm ? 'alarm' : 'normal'),
    quietHoursBehaviour: Value(r.quietBehaviour.code),
    exact: Value(r.alarm),
    enabled: Value(r.enabled),
    startDate: Value(r.startDate),
    endDate: Value(r.endDate),
  );

  Failure? _invalid(Reminder r) => r.problems.isEmpty ? null : ValidationFailure('reminder', r.problems.first);

  @override
  Future<Result<Reminder>> create(Reminder draft) async {
    final failure = _invalid(draft);
    if (failure != null) return Err(failure);
    return Result.guard(() async {
      final now = clock.now().toUtc();
      final stored = draft.copyWith(id: ids.newId());
      await _db.transaction(() async {
        await _db
            .into(_db.reminders)
            .insert(_fields(stored, now).copyWith(id: Value(stored.id), createdAt: Value(now)));
        await _db.enqueueForSync(_table, stored.id, now);
      });
      return stored;
    }, onError: (_) => const StorageFailure('reminder_write'));
  }

  Future<Result<void>> _write(String id, RemindersCompanion Function(DateTime now) change) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final changed = await (_db.update(
        _db.reminders,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(change(now));
      if (changed > 0) await _db.enqueueForSync(_table, id, now);
    }),
    onError: (_) => const StorageFailure('reminder_write'),
  );

  @override
  Future<Result<void>> update(Reminder reminder) async {
    final failure = _invalid(reminder);
    if (failure != null) return Err(failure);
    return _write(reminder.id, (now) => _fields(reminder, now));
  }

  @override
  Future<Result<void>> setEnabled(String id, {required bool enabled}) =>
      _write(id, (now) => RemindersCompanion(updatedAt: Value(now), enabled: Value(enabled)));

  @override
  Future<Result<void>> delete(String id) =>
      _write(id, (now) => RemindersCompanion(updatedAt: Value(now), deletedAt: Value(now)));

  SimpleSelectStatement<$RemindersTable, ReminderRow> get _live => _db.select(_db.reminders)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);

  @override
  Stream<List<Reminder>> watchAll() => _live.watch().map((rows) => [for (final r in rows) _toReminder(r)]);

  @override
  Future<List<Reminder>> enabled() async => [
    for (final r in await _live.get())
      if (r.enabled) _toReminder(r),
  ];

  @override
  Future<Reminder?> byId(String id) async {
    final row = await (_db.select(
      _db.reminders,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toReminder(row);
  }
}
