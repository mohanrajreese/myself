import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/log_stamp.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/activity.dart';
import '../domain/activity_repository.dart';

final class DriftActivityRepository implements ActivityRepository {
  DriftActivityRepository(
    this._db, {
    required this.clock,
    required this.ids,
    required this.timeZone,
  });

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final TimeZoneSource timeZone;

  static const _defs = 'activity_definitions';
  static const _logs = 'activity_logs';

  LocalDate get _today => LocalDate.fromDateTime(clock.now().toLocal());

  // ------------------------------------------------------------ mapping

  static Activity _toActivity(ActivityDefinitionRow r) => Activity(
    id: r.id,
    name: r.name,
    description: r.description,
    category: r.category,
    iconKey: r.iconKey,
    trackingType: TrackingType.fromCode(r.trackingType),
    priority: ActivityPriority.fromCode(r.priority),
    targetMilli: r.targetMilli,
    targetUnit: r.targetUnit,
    schedule: ScheduleRule.fromJson((jsonDecode(r.schedule) as Map).cast<String, Object?>()),
    scheduleHistory: ScheduleChange.listFromJson(r.scheduleHistory),
    stopwatchEnabled: r.stopwatchEnabled,
    showOnDashboard: r.showOnDashboard,
    checklistItems: ChecklistItem.listFromJson(r.checklistItems),
    archived: r.status == 'archived',
    sortOrder: r.sortOrder,
  );

  static ActivityLog _toLog(ActivityLogRow r) => ActivityLog(
    id: r.id,
    activityId: r.activityDefinitionId,
    status: ActivityLogStatus.fromCode(r.status),
    occurredAt: r.occurredAt,
    localDate: r.localDate,
    source: LogSource.fromCode(r.source),
    scheduledSlot: r.scheduledSlot,
    countValue: r.countValue,
    numericValueMilli: r.numericValueMilli,
    unit: r.unit,
    durationS: r.durationS,
    checklistDone: r.checklistState == null
        ? null
        : {for (final id in jsonDecode(r.checklistState!) as List<Object?>) id! as String},
    notes: r.notes,
  );

  static String? _clean(String? text) => text == null || text.trim().isEmpty ? null : text.trim();

  ActivityDefinitionsCompanion _fields(Activity a, DateTime now) => ActivityDefinitionsCompanion(
    updatedAt: Value(now),
    name: Value(a.name.trim()),
    description: Value(_clean(a.description)),
    category: Value(a.category),
    iconKey: Value(a.iconKey),
    trackingType: Value(a.trackingType.code),
    priority: Value(a.priority.code),
    targetMilli: Value(a.targetMilli),
    targetUnit: Value(a.targetUnit),
    schedule: Value(jsonEncode(a.schedule.toJson())),
    scheduleHistory: Value(ScheduleChange.listToJson(a.scheduleHistory)),
    stopwatchEnabled: Value(a.stopwatchEnabled),
    showOnDashboard: Value(a.showOnDashboard),
    checklistItems: Value(ChecklistItem.listToJson(a.checklistItems)),
    status: Value(a.archived ? 'archived' : 'active'),
    sortOrder: Value(a.sortOrder),
  );

  Failure? _invalid(Activity a) {
    final problems = a.problems;
    return problems.isEmpty ? null : ValidationFailure('activity', problems.first);
  }

  Future<int> _nextSortOrder() async {
    final max = _db.activityDefinitions.sortOrder.max();
    final row = await (_db.selectOnly(_db.activityDefinitions)..addColumns([max])).getSingle();
    return (row.read(max) ?? -1) + 1;
  }

  Future<Activity> _insert(Activity a) async {
    final now = clock.now().toUtc();
    final id = ids.newId();
    final stored = a.copyWith(
      id: id,
      sortOrder: await _nextSortOrder(),
      scheduleHistory: [ScheduleChange(from: _today, rule: a.schedule)],
    );
    await _db
        .into(_db.activityDefinitions)
        .insert(_fields(stored, now).copyWith(id: Value(id), createdAt: Value(now)));
    await _db.enqueueForSync(_defs, id, now);
    return stored;
  }

  // ------------------------------------------------------------ definitions

  @override
  Future<Result<Activity>> create(Activity draft) async {
    final failure = _invalid(draft);
    if (failure != null) return Err(failure);
    return Result.guard(
      () => _db.transaction(() => _insert(draft.copyWith(archived: false))),
      onError: (_) => const StorageFailure('activity_write'),
    );
  }

  @override
  Future<Result<void>> update(Activity activity, {LocalDate? scheduleFrom}) async {
    final failure = _invalid(activity);
    if (failure != null) return Err(failure);
    final current = await byId(activity.id);
    if (current == null) return const Err(ValidationFailure('activity', 'not_found'));
    if (!canChangeTrackingType(
      current.trackingType,
      activity.trackingType,
      hasLogs: await hasLogs(activity.id),
    )) {
      return const Err(ValidationFailure('trackingType', 'not_allowed'));
    }
    final next = activity.schedule == current.schedule
        ? activity.copyWith(scheduleHistory: current.scheduleHistory)
        : current
              .copyWith(scheduleHistory: current.scheduleHistory)
              .rescheduled(activity.schedule, from: scheduleFrom ?? _today);
    final merged = activity.copyWith(
      schedule: next.schedule,
      scheduleHistory: next.scheduleHistory,
    );
    return Result.guard(
      () => _db.transaction(() async {
        final now = clock.now().toUtc();
        await (_db.update(
          _db.activityDefinitions,
        )..where((t) => t.id.equals(activity.id))).write(_fields(merged, now));
        await _db.enqueueForSync(_defs, activity.id, now);
      }),
      onError: (_) => const StorageFailure('activity_write'),
    );
  }

  @override
  Future<Result<Activity>> duplicate(String id, {required String name}) async {
    final source = await byId(id);
    if (source == null) return const Err(ValidationFailure('activity', 'not_found'));
    return create(source.copyWith(name: name));
  }

  Future<Result<void>> _write(
    String id,
    ActivityDefinitionsCompanion Function(DateTime now) change,
  ) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final changed = await (_db.update(
        _db.activityDefinitions,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(change(now));
      if (changed > 0) await _db.enqueueForSync(_defs, id, now);
    }),
    onError: (_) => const StorageFailure('activity_write'),
  );

  @override
  Future<Result<void>> setArchived(String id, {required bool archived}) => _write(
    id,
    (now) => ActivityDefinitionsCompanion(
      updatedAt: Value(now),
      status: Value(archived ? 'archived' : 'active'),
    ),
  );

  @override
  Future<Result<void>> delete(String id) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final logs = await (_db.select(
        _db.activityLogs,
      )..where((t) => t.activityDefinitionId.equals(id) & t.deletedAt.isNull())).get();
      for (final log in logs) {
        await (_db.update(_db.activityLogs)..where((t) => t.id.equals(log.id))).write(
          ActivityLogsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
        await _db.enqueueForSync(_logs, log.id, now);
      }
      final changed =
          await (_db.update(_db.activityDefinitions)
                ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
              .write(ActivityDefinitionsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      if (changed > 0) await _db.enqueueForSync(_defs, id, now);
    }),
    onError: (_) => const StorageFailure('activity_write'),
  );

  @override
  Future<Result<void>> reorder(List<String> orderedIds) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      for (var i = 0; i < orderedIds.length; i++) {
        final changed =
            await (_db.update(_db.activityDefinitions)
                  ..where((t) => t.id.equals(orderedIds[i]) & t.sortOrder.equals(i).not()))
                .write(ActivityDefinitionsCompanion(updatedAt: Value(now), sortOrder: Value(i)));
        if (changed > 0) await _db.enqueueForSync(_defs, orderedIds[i], now);
      }
    }),
    onError: (_) => const StorageFailure('activity_write'),
  );

  @override
  Stream<List<Activity>> watchAll() =>
      (_db.select(_db.activityDefinitions)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.createdAt),
            ]))
          .watch()
          .map((rows) => [for (final r in rows) _toActivity(r)]);

  @override
  Future<Activity?> byId(String id) async {
    final row = await (_db.select(
      _db.activityDefinitions,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toActivity(row);
  }

  // ------------------------------------------------------------ logs

  Failure? _invalidLog(LogDraft d) {
    if (d.occurredAt.isAfter(clock.now().add(const Duration(minutes: 1)))) {
      return const ValidationFailure('occurredAt', 'in_future');
    }
    if ((d.countValue ?? 0) < 0 || (d.durationS ?? 0) < 0 || (d.durationS ?? 0) > 86400) {
      return const ValidationFailure('value', 'out_of_range');
    }
    if (d.scheduledSlot != null && (d.scheduledSlot! < 0 || d.scheduledSlot! > 1439)) {
      return const ValidationFailure('scheduledSlot', 'out_of_range');
    }
    return null;
  }

  ActivityLogsCompanion _logFields(LogDraft d, LogStamp stamp) => ActivityLogsCompanion(
    updatedAt: Value(stamp.nowUtc),
    status: Value(d.status.code),
    occurredAt: Value(stamp.occurredAt),
    localDate: Value(stamp.localDate),
    tz: Value(stamp.tz),
    scheduledSlot: Value(d.scheduledSlot),
    countValue: Value(d.countValue),
    numericValueMilli: Value(d.numericValueMilli),
    unit: Value(d.unit),
    durationS: Value(d.durationS),
    checklistState: Value(
      d.checklistDone == null ? null : jsonEncode(d.checklistDone!.toList()..sort()),
    ),
    source: Value(d.source.code),
    notes: Value(_clean(d.notes)),
  );

  @override
  Future<Result<ActivityLog>> addLog(String activityId, LogDraft draft) async {
    final failure = _invalidLog(draft);
    if (failure != null) return Err(failure);
    if (await byId(activityId) == null) {
      return const Err(ValidationFailure('activity', 'not_found'));
    }
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone, at: draft.occurredAt);
      final id = ids.newId();
      await _db.transaction(() async {
        await _db
            .into(_db.activityLogs)
            .insert(
              _logFields(draft, stamp).copyWith(
                id: Value(id),
                createdAt: Value(stamp.nowUtc),
                activityDefinitionId: Value(activityId),
              ),
            );
        await _db.enqueueForSync(_logs, id, stamp.nowUtc);
      });
      final row = await (_db.select(_db.activityLogs)..where((t) => t.id.equals(id))).getSingle();
      return _toLog(row);
    }, onError: (_) => const StorageFailure('activity_log_write'));
  }

  @override
  Future<Result<void>> updateLog(String logId, LogDraft draft) async {
    final failure = _invalidLog(draft);
    if (failure != null) return Err(failure);
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone, at: draft.occurredAt);
      await _db.transaction(() async {
        final changed = await (_db.update(
          _db.activityLogs,
        )..where((t) => t.id.equals(logId) & t.deletedAt.isNull())).write(_logFields(draft, stamp));
        if (changed > 0) await _db.enqueueForSync(_logs, logId, stamp.nowUtc);
      });
    }, onError: (_) => const StorageFailure('activity_log_write'));
  }

  @override
  Future<Result<void>> deleteLog(String logId) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final changed =
          await (_db.update(_db.activityLogs)
                ..where((t) => t.id.equals(logId) & t.deletedAt.isNull()))
              .write(ActivityLogsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      if (changed > 0) await _db.enqueueForSync(_logs, logId, now);
    }),
    onError: (_) => const StorageFailure('activity_log_write'),
  );

  @override
  Stream<List<ActivityLog>> watchLogsBetween(LocalDate from, LocalDate to) =>
      (_db.select(_db.activityLogs)
            ..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.localDate.isBetweenValues(from.toString(), to.toString()),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
          .watch()
          .map((rows) => [for (final r in rows) _toLog(r)]);

  @override
  Stream<List<ActivityLog>> watchLogsFor(String activityId, {int limit = 50}) =>
      (_db.select(_db.activityLogs)
            ..where((t) => t.activityDefinitionId.equals(activityId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch()
          .map((rows) => [for (final r in rows) _toLog(r)]);

  @override
  Future<bool> hasLogs(String activityId) async {
    final row =
        await (_db.select(_db.activityLogs)
              ..where((t) => t.activityDefinitionId.equals(activityId) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }
}
